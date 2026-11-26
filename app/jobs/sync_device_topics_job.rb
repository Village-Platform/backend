# Makes FCM's topic membership for one device match this database: subscribes the token to the
# topics the device belongs to and unsubscribes it from the others among topic_ids. Reconciliation,
# so running it twice, or after a missed run, is harmless.
class SyncDeviceTopicsJob < ApplicationJob
  include FcmRetries # a retry re-runs the whole reconciliation, which is safe

  queue_as :default

  def perform(device_id, topic_ids: nil)
    device = Device.find_by(id: device_id)
    # A dashboard browser never joins topics: they carry campaigns meant for the apps (Device).
    return if device.nil? || device.web?

    keys = device.topic_keys
    topics = topic_ids ? Topic.where(id: topic_ids).pluck(:key) : keys
    rejected = topics.flat_map do |key|
      keys.include?(key) ? Fcm.client.subscribe(key, [ device.token ]) : Fcm.client.unsubscribe(key, [ device.token ])
    end

    prune(device) if rejected.include?(device.token)
  end

  private

  def prune(device)
    device.destroy
    Observability::Metrics.increment(:push_tokens_pruned)
  end

  def push_source = "topics"
end
