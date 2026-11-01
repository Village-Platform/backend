# Sends a campaign: one FCM message to its topics, then an inbox row per signed-in recipient and
# per guest install.
#
# Idempotent. The job only proceeds while the campaign is scheduled (or sending, on a retry) and
# still scheduled for the time it was queued with, so a canceled or rescheduled campaign makes the
# old job a no-op. The FCM message name is saved right after the send and a retry that finds it
# skips the send. The one gap: a crash between FCM accepting the message and that save re-sends it
# on retry (at-least-once; FCM has no idempotency key). Inbox rows are deduplicated by dedupe_key.
class DeliverCampaignJob < ApplicationJob
  include FcmRetries

  queue_as :default

  # Two jobs for one campaign never run at once (a reschedule to the same time, a manual retry):
  # the second waits, then finds the campaign sent.
  limits_concurrency to: 1, key: ->(campaign_id, *) { campaign_id }, duration: 15.minutes

  INBOX_BATCH = 1000

  def perform(campaign_id, scheduled_at_iso)
    campaign = claim(campaign_id, scheduled_at_iso)
    return unless campaign

    destination = campaign.destination
    unless destination.live?
      return finish(campaign, :canceled, error: destination.error || "المقال لم يُنشر بعد.")
    end

    push(campaign, destination) unless campaign.fcm_message_name
    recipients = write_inbox(campaign, destination)
    finish(campaign, :sent, recipients_count: recipients)
  rescue Fcm::AuthError, Fcm::InvalidArgument => e
    record_push(e.is_a?(Fcm::AuthError) ? "auth_error" : "invalid")
    finish(campaign, :failed, error: e.message)
  rescue Fcm::Retryable
    raise # FcmRetries schedules the retry
  rescue StandardError => e
    # Anything else must not leave the campaign in "sending", where nobody can cancel or retry it.
    finish(campaign, :failed, error: "#{e.class}: #{e.message}") if campaign
    raise
  end

  private

  def claim(campaign_id, scheduled_at_iso)
    campaign = NotificationCampaign.find_by(id: campaign_id)
    return unless campaign

    campaign.with_lock do
      next unless campaign.scheduled? || campaign.sending?
      next unless campaign.scheduled_at.iso8601(6) == scheduled_at_iso

      campaign.sending! unless campaign.sending?
      campaign
    end
  end

  def push(campaign, destination)
    payload = Fcm::Message.payload(
      title: campaign.title,
      body: campaign.body,
      data: destination.to_data.merge("campaign_id" => campaign.id)
    )
    campaign.update!(fcm_message_name: Fcm.client.send_to_topics(campaign.topics.pluck(:key), payload))
    record_push("ok")
  end

  # One row per signed-in recipient and one per guest install. Returns how many were addressed.
  def write_inbox(campaign, destination)
    topics = campaign.topics.to_a
    common = {
      campaign_id: campaign.id, kind: Notification.kinds[:system_announcement],
      title: campaign.title, body: campaign.body, data: destination.to_data
    }
    user_ids = Topic.recipient_user_ids(topics)
    device_ids = Topic.recipient_guest_device_ids(topics)
    insert_inbox(user_ids, common) { |id| { user_id: id, dedupe_key: "campaign:#{campaign.id}:user:#{id}" } }
    insert_inbox(device_ids, common) { |id| { device_id: id, dedupe_key: "campaign:#{campaign.id}:device:#{id}" } }
    user_ids.size + device_ids.size
  end

  # ON CONFLICT DO NOTHING: a retry skips rows already written. A guest install can be deleted
  # between reading its id and inserting (its token moved to a new install): the batch then fails
  # its foreign key, so it is retried once with only the installs that still exist.
  def insert_inbox(ids, common)
    now = Time.current
    ids.each_slice(INBOX_BATCH) do |batch|
      retried = false
      begin
        next if batch.empty?

        rows = batch.map { |id| { **common, **yield(id), created_at: now, updated_at: now } }
        # A savepoint, so the failed insert does not abort a transaction this runs inside.
        Notification.transaction(requires_new: true) { Notification.insert_all(rows) }
      rescue ActiveRecord::InvalidForeignKey
        raise if retried

        retried = true
        batch = Device.where(id: batch).ids
        retry
      end
    end
  end

  def finish(campaign, status, error: nil, recipients_count: nil)
    attributes = { status:, last_error: error }
    attributes.merge!(sent_at: Time.current, recipients_count:) if status == :sent
    campaign.update_columns(**attributes, updated_at: Time.current)
    Observability::Metrics.increment(:campaigns_delivered, result: status.to_s)
  end

  # Called by FcmRetries when the last attempt still failed.
  def fcm_gave_up(error)
    campaign = NotificationCampaign.find_by(id: arguments.first)
    finish(campaign, :failed, error: error.message) if campaign
  end

  def push_source = "campaign"
end
