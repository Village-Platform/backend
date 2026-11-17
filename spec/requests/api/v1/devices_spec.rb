require "rails_helper"

RSpec.describe "Devices API", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  def register(installation_id = "install-1", token: "token-1", headers: {}, **attrs)
    put "/api/v1/devices/#{installation_id}", params: { token:, **attrs }, headers:, as: :json
  end

  it "registers a guest device" do
    expect { register(app_version: "2.4.0", locale: "ar") }.to have_enqueued_job(SyncDeviceTopicsJob)

    expect(response).to have_http_status(:ok)
    device = Device.sole
    expect(device).to have_attributes(installation_id: "install-1", token: "token-1", user: nil, app_version: "2.4.0", locale: "ar")
    expect(device.last_seen_at).to be_present
  end

  it "attaches the device to the signed-in user" do
    register(headers: auth_headers(user))

    expect(Device.sole.user).to eq(user)
    expect(json.dig("data", "user_attached")).to be(true)
  end

  it "updates the token on rotation without a new row" do
    register
    expect { register(token: "token-2") }.to have_enqueued_job(SyncDeviceTopicsJob)

    expect(Device.sole.token).to eq("token-2")
  end

  it "does not resync when nothing changed" do
    register
    expect { register }.not_to have_enqueued_job(SyncDeviceTopicsJob)
  end

  it "moves a token that another installation held" do
    register("install-a", token: "shared")
    register("install-b", token: "shared")

    expect(response).to have_http_status(:ok)
    expect(Device.pluck(:installation_id)).to eq(%w[ install-b ])
  end

  it "refuses an anonymous change to a user's device" do
    register(headers: auth_headers(user))
    register(token: "attacker")

    expect(response).to have_http_status(:forbidden)
    expect(Device.sole.token).to eq("token-1")
  end

  it "refuses the web platform: browsers register through the dashboard" do
    register(platform: "web")

    expect(response).to have_http_status(:unprocessable_content)
    expect(Device.count).to eq(0)
  end

  it "refuses to take over a dashboard browser, even signed in" do
    browser = create(:device, installation_id: "web-1", platform: "web", user: create(:user, :super_admin))
    register("web-1", token: "attacker", headers: auth_headers(user))

    expect(response).to have_http_status(:forbidden)
    expect(browser.reload).to have_attributes(token: browser.token, user_id: browser.user_id)
  end

  it "lets the install itself recover its device without a bearer" do
    topic = create(:topic, key: "owners")
    TopicSubscription.create!(topic:, user:)
    register(headers: auth_headers(user)) # then the JWT expires or the account is deleted

    expect { register(token: "token-1") }
      .to have_enqueued_job(SyncDeviceTopicsJob).with(Device.sole.id, topic_ids: [ topic.id ])
    expect(response).to have_http_status(:ok)
    expect(Device.sole.user).to be_nil
  end

  it "unsubscribes a moved token from the old user's topics" do
    topic = create(:topic, key: "owners")
    TopicSubscription.create!(topic:, user:)
    register("install-a", token: "shared", headers: auth_headers(user))

    register("install-b", token: "shared")

    expect(SyncDeviceTopicsJob).to have_been_enqueued.with(Device.sole.id, topic_ids: [ topic.id ])
  end

  it "moves the device to a new user on login" do
    other = create(:user)
    topic = create(:topic, key: "owners")
    TopicSubscription.create!(topic:, user:)
    register(headers: auth_headers(user))

    expect { register(headers: auth_headers(other)) }
      .to have_enqueued_job(SyncDeviceTopicsJob).with(Device.sole.id, topic_ids: [ topic.id ])
    expect(Device.sole.user).to eq(other)
  end

  it "detaches on logout" do
    register(headers: auth_headers(user))
    post "/api/v1/devices/install-1/detach", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(Device.sole.user).to be_nil
  end

  it "refuses to detach someone else's device" do
    register(headers: auth_headers(user))
    post "/api/v1/devices/install-1/detach", headers: auth_headers(create(:user))

    expect(response).to have_http_status(:forbidden)
    expect(Device.sole.user).to eq(user)
  end

  it "requires a sign-in to detach" do
    register
    post "/api/v1/devices/install-1/detach"
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a missing token" do
    put "/api/v1/devices/install-1", params: {}, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "never returns the installation id or token" do
    register
    expect(json["data"].keys).not_to include("installation_id", "token")
  end

  it "rate limits registration" do
    store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails.cache).to receive(:increment) { |*args, **opts| store.increment(*args, **opts) }

    30.times { |i| register("install-#{i}", token: "t-#{i}") }
    expect(response).to have_http_status(:ok)
    register("install-x", token: "t-x")

    expect(response).to have_http_status(:too_many_requests)
    expect(json.dig("error", "code")).to eq("rate_limited")
  end
end
