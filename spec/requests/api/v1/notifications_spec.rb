require "rails_helper"

RSpec.describe "Notifications API", type: :request do
  let(:user) { create(:user) }

  def notify(target = user, key: nil)
    Notifier.notify(user: target, kind: :subscription_rejected, dedupe_key: key, reason: "x")
  end

  it "lists only my notifications with an unread count" do
    notify
    notify.mark_as_read!
    notify(create(:user))

    get "/api/v1/notifications", headers: auth_headers(user)

    expect(json["data"].size).to eq(2)
    expect(json.dig("meta", "unread_count")).to eq(1)
  end

  it "filters unread" do
    notify
    notify.mark_as_read!

    get "/api/v1/notifications", params: { unread: true }, headers: auth_headers(user)

    expect(json["data"].size).to eq(1)
  end

  it "marks one as read and cannot touch others' notifications" do
    mine = notify
    other = notify(create(:user))

    patch "/api/v1/notifications/#{mine.id}/read", headers: auth_headers(user)
    expect(json.dig("data", "read")).to be(true)

    patch "/api/v1/notifications/#{other.id}/read", headers: auth_headers(user)
    expect(response).to have_http_status(:not_found)
  end

  it "marks all as read" do
    2.times { notify }

    patch "/api/v1/notifications/read_all", headers: auth_headers(user)

    expect(response).to have_http_status(:no_content)
    expect(user.notifications.unread.count).to eq(0)
  end

  it "does not create duplicates for the same dedupe key" do
    notify(key: "same")
    notify(key: "same")

    expect(user.notifications.count).to eq(1)
  end

  describe "a guest" do
    let(:device) { create(:device, installation_id: "guest-install") }
    let(:guest_headers) do
      { "Authorization" => "Bearer #{JsonWebToken.encode({ typ: 'guest' })}", "X-Installation-Id" => "guest-install" }
    end

    def broadcast(to = device, read: false)
      Notification.create!(device: to, kind: :system_announcement, title: "إعلان", body: "نص",
                           read_at: (Time.current if read))
    end

    it "lists its install's inbox with an unread count" do
      broadcast
      broadcast(read: true)
      broadcast(create(:device))
      notify # a user's row, never a guest's

      get "/api/v1/notifications", headers: guest_headers

      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(2)
      expect(json.dig("meta", "unread_count")).to eq(1)
      expect(json["data"].first.keys).to match_array(%w[ id kind title body data read read_at created_at ])
    end

    it "receives a campaign sent to everyone in its inbox" do
      put "/api/v1/devices/guest-install", params: { token: "fcm-guest" }, headers: guest_headers, as: :json
      campaign = create(:notification_campaign, topics: [ Topic.everyone ])
      DeliverCampaignJob.perform_now(campaign.id, campaign.scheduled_at.iso8601(6))

      get "/api/v1/notifications", headers: guest_headers

      expect(json["data"].sole).to include("kind" => "system_announcement", "title" => campaign.title, "read" => false)
      expect(json.dig("meta", "unread_count")).to eq(1)
    end

    it "gets an empty inbox for an install the server has not registered yet" do
      get "/api/v1/notifications", headers: guest_headers.merge("X-Installation-Id" => "not-registered")

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to eq([])
      expect(json.dig("meta", "unread_count")).to eq(0)
    end

    it "marks one as read and cannot touch another install's or a user's rows" do
      mine = broadcast
      other_install = broadcast(create(:device))
      users = notify

      patch "/api/v1/notifications/#{mine.id}/read", headers: guest_headers
      expect(json.dig("data", "read")).to be(true)

      [ other_install, users ].each do |row|
        patch "/api/v1/notifications/#{row.id}/read", headers: guest_headers
        expect(response).to have_http_status(:not_found)
      end
    end

    it "marks all as read in its install only" do
      2.times { broadcast }
      other_install = broadcast(create(:device))

      patch "/api/v1/notifications/read_all", headers: guest_headers

      expect(response).to have_http_status(:no_content)
      expect(device.notifications.unread.count).to eq(0)
      expect(other_install.reload).not_to be_read
    end

    it "needs both the guest token and the header, as old app versions send neither" do
      get "/api/v1/notifications", headers: guest_headers.except("X-Installation-Id")
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/notifications", headers: guest_headers.except("Authorization")
      expect(response).to have_http_status(:unauthorized)
    end

    it "is refused for an install that is signed in" do
      device.update!(user:)

      get "/api/v1/notifications", headers: guest_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "keeps the guest inbox through a sign-in and shows it again after logout" do
      row = broadcast
      put "/api/v1/devices/guest-install", params: { token: device.token }, headers: auth_headers(user)

      get "/api/v1/notifications", headers: auth_headers(user).merge("X-Installation-Id" => "guest-install")
      expect(json["data"]).to eq([]) # signed in: the user's inbox, never the install's

      post "/api/v1/devices/guest-install/detach", headers: auth_headers(user)
      get "/api/v1/notifications", headers: guest_headers
      expect(json["data"].pluck("id")).to eq([ row.id ])
    end

    it "loses its inbox with its install when a new install takes over the token" do
      broadcast
      put "/api/v1/devices/new-install", params: { token: device.token }, headers: guest_headers.except("X-Installation-Id")

      expect(Device.exists?(device.id)).to be(false)
      expect(Notification.where(device_id: device.id)).to be_empty
    end
  end

  describe "push" do
    include ActiveJob::TestHelper

    it "enqueues one push per device of the user when notified" do
      devices = create_list(:device, 2, user:)
      create(:device) # someone else's phone

      expect { notify }.to have_enqueued_job(PushNotificationJob).exactly(2).times
      expect(PushNotificationJob).to have_been_enqueued.with(Notification.last.id, devices.first.id)
    end

    it "pushes nothing for a duplicate" do
      create(:device, user:)
      notify(key: "same")
      expect { notify(key: "same") }.not_to have_enqueued_job(PushNotificationJob)
    end

    it "adds the destination to data and keeps subscription_id" do
      subscription = create(:subscription, user:)
      Subscriptions::Reject.call(subscription:, reviewer: create(:user, :super_admin), reason: "صورة غير واضحة")

      data = user.notifications.last.data
      expect(data).to include("subscription_id" => subscription.id, "screen" => "subscription", "id" => subscription.id.to_s)
    end
  end
end
