require "rails_helper"

RSpec.describe DeliverCampaignJob do
  include ActiveJob::TestHelper

  let(:fcm) { Fcm.client }
  let(:news) { create(:topic, :listed, key: "news") }
  let(:owners) { create(:topic, key: "owners") }
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }

  let(:guest) { create(:device) }

  before do
    TopicSubscription.create!(topic: news, user: alice)
    TopicSubscription.create!(topic: news, device: create(:device, user: bob))
    TopicSubscription.create!(topic: news, device: guest)
  end

  def campaign(**attrs) = create(:notification_campaign, topics: [ news ], **attrs)

  def deliver(campaign, at: campaign.scheduled_at)
    described_class.perform_now(campaign.id, at.iso8601(6))
  end

  it "sends one topic push and writes inbox rows" do
    article = create(:article)
    record = campaign(screen: "article", target_id: article.id)
    deliver(record)

    message = fcm.deliveries.sole
    expect(message[:topic]).to eq("news")
    expect(message[:data]).to eq("screen" => "article", "id" => article.id.to_s, "campaign_id" => record.id.to_s)
    expect(record.reload).to have_attributes(status: "sent", recipients_count: 3, fcm_message_name: "projects/test/messages/1")
    expect(record.sent_at).to be_present
    expect(Notification.where(campaign_id: record.id).pluck(:user_id, :device_id))
      .to contain_exactly([ alice.id, nil ], [ bob.id, nil ], [ nil, guest.id ])
    expect(alice.notifications.sole).to have_attributes(kind: "system_announcement", title: "عرض جديد",
                                                        data: { "screen" => "article", "id" => article.id.to_s })
  end

  it "uses a condition for several topics" do
    deliver(create(:notification_campaign, topics: [ news, owners ]))
    expect(fcm.deliveries.sole[:condition]).to eq("'news' in topics || 'owners' in topics")
  end

  it "reaches every user through the everyone topic" do
    record = create(:notification_campaign, topics: [ Topic.everyone ])
    deliver(record)
    expect(fcm.deliveries.sole[:topic]).to eq("all")
    expect(record.reload.recipients_count).to eq(User.not_deleted.count + 1) # + the guest install
  end

  it "writes a guest install's inbox row with the campaign's content" do
    article = create(:article)
    record = campaign(screen: "article", target_id: article.id)
    deliver(record)

    expect(guest.notifications.sole).to have_attributes(
      kind: "system_announcement", title: "عرض جديد", user_id: nil, campaign_id: record.id,
      data: { "screen" => "article", "id" => article.id.to_s }, dedupe_key: "campaign:#{record.id}:device:#{guest.id}"
    )
  end

  it "reaches every guest install, and no signed-in one, through the everyone topic" do
    unsubscribed_guest = create(:device)
    signed_in = create(:device, user: create(:user))

    deliver(create(:notification_campaign, topics: [ Topic.everyone ]))

    expect(Notification.where.not(device_id: nil).pluck(:device_id)).to contain_exactly(guest.id, unsubscribed_guest.id)
    expect(signed_in.notifications).to be_empty
  end

  it "skips a guest install deleted while its batch was being written" do
    gone = create(:device)
    TopicSubscription.create!(topic: news, device: gone)
    allow(Topic).to receive(:recipient_guest_device_ids).and_wrap_original do |original, *args|
      original.call(*args).tap { gone.delete } # the install disappears after its id was read
    end

    record = campaign
    deliver(record)

    expect(record.reload).to be_sent
    expect(Notification.where.not(device_id: nil).pluck(:device_id)).to eq([ guest.id ])
  end

  it "is a no-op when run twice" do
    record = campaign
    2.times { deliver(record) }
    expect(fcm.deliveries.size).to eq(1)
    expect(Notification.count).to eq(3)
  end

  it "skips a canceled campaign" do
    record = campaign(scheduled_at: 1.hour.from_now)
    record.cancel!
    deliver(record)
    expect(fcm.deliveries).to be_empty
  end

  it "ignores a stale job after reschedule" do
    record = campaign(scheduled_at: 1.hour.from_now)
    first = record.scheduled_at
    record.update!(scheduled_at: 2.hours.from_now)

    deliver(record, at: first)

    expect(fcm.deliveries).to be_empty
    expect(record.reload).to be_scheduled
  end

  it "does not resend when the message name is saved" do
    record = campaign
    record.update_columns(status: NotificationCampaign.statuses[:sending], fcm_message_name: "projects/test/messages/9")

    deliver(record)

    expect(fcm.deliveries).to be_empty
    expect(Notification.count).to eq(3)
    expect(record.reload).to be_sent
  end

  it "cancels when the destination disappeared" do
    article = create(:article)
    record = campaign(screen: "article", target_id: article.id)
    article.destroy

    deliver(record)

    expect(fcm.deliveries).to be_empty
    expect(record.reload).to be_canceled
    expect(record.last_error).to be_present
  end

  it "cancels instead of linking to an article that is not live yet" do
    article = create(:article, published_at: 2.days.from_now)
    record = campaign(screen: "article", target_id: article.id)

    deliver(record)

    expect(fcm.deliveries).to be_empty
    expect(record.reload).to be_canceled
  end

  it "skips soft-deleted users" do
    record = campaign
    alice.destroy
    deliver(record)
    expect(Notification.where.not(user_id: nil).pluck(:user_id)).to eq([ bob.id ])
  end

  it "marks failed on AuthError", :metrics do
    fcm.fail_next_with(Fcm::AuthError.new("FCM 401"))
    record = campaign
    deliver(record)

    expect(record.reload).to be_failed
    expect(record.last_error).to include("401")
    expect(metric_value("aghour.push.campaigns", result: "failed")).to eq(1)
  end

  it "retries on Retryable and stays sending" do
    fcm.fail_next_with(Fcm::Retryable.new(retry_after: 10))
    record = campaign
    expect { deliver(record) }.to have_enqueued_job(described_class)
    expect(record.reload).to be_sending
  end

  it "marks failed on an unexpected error and still raises it" do
    fcm.fail_next_with(Fcm::Error.new("FCM 404"))
    record = campaign

    expect { deliver(record) }.to raise_error(Fcm::Error)
    expect(record.reload).to be_failed
    expect(record.last_error).to include("404")
  end

  it "marks failed when retries run out" do
    record = campaign
    job = described_class.new(record.id, record.scheduled_at.iso8601(6))
    job.executions = FcmRetries::MAX_ATTEMPTS
    fcm.fail_next_with(Fcm::Retryable.new)

    expect { job.perform_now }.to raise_error(Fcm::Retryable)
    expect(record.reload).to be_failed
  end

  describe Campaigns::Schedule do
    it "enqueues delivery at the scheduled time" do
      record = build(:notification_campaign, topics: [ news ], scheduled_at: 2.hours.from_now)
      expect { Campaigns::Schedule.call(campaign: record) }
        .to have_enqueued_job(DeliverCampaignJob).at(record.scheduled_at)
      expect(DeliverCampaignJob).to have_been_enqueued.with(record.id, record.scheduled_at.iso8601(6))
      expect(record).to be_persisted.and be_scheduled
    end

    it "sends now when no time is given" do
      record = build(:notification_campaign, topics: [ news ], scheduled_at: nil)
      freeze_time do
        Campaigns::Schedule.call(campaign: record)
        expect(record.scheduled_at).to eq(Time.current)
      end
    end
  end

  describe NotificationCampaign do
    it "rejects six topics and an unknown destination" do
      record = build(:notification_campaign, topics: create_list(:topic, 6), screen: "article", target_id: 0)
      expect(record).not_to be_valid
      expect(record.errors[:topics]).to be_present
      expect(record.errors[:target_id]).to be_present
    end

    it "cannot cancel a sent campaign" do
      record = campaign
      record.update_columns(status: NotificationCampaign.statuses[:sent])
      expect { record.cancel! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
