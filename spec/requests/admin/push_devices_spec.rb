require "rails_helper"

RSpec.describe "Admin web push", type: :request do
  include ActiveJob::TestHelper

  let(:fcm) { Fcm.client }
  let(:firebase_env) do
    { "FIREBASE_WEB_API_KEY" => "api-key", "FIREBASE_PROJECT_ID" => "village", "FIREBASE_MESSAGING_SENDER_ID" => "123",
      "FIREBASE_WEB_APP_ID" => "1:123:web:abc", "FIREBASE_VAPID_KEY" => "vapid" }
  end

  def register_browser(installation_id: "web-1", token: "web-token")
    post "/admin/push_device", params: { installation_id:, token: }, as: :json
  end

  def stub_firebase_env(values)
    allow(ENV).to receive(:[]).and_call_original
    values.each { |name, value| allow(ENV).to receive(:[]).with(name).and_return(value) }
  end

  describe "registering a browser" do
    it "stores it as a web device of the signed-in admin, outside every topic" do
      admin = sign_in_admin

      expect { register_browser }.not_to change { fcm.subscribed.values.flatten.size }
      perform_enqueued_jobs

      expect(response).to have_http_status(:no_content)
      expect(Device.sole).to have_attributes(installation_id: "web-1", token: "web-token", platform: "web", user: admin)
      expect(fcm.subscribed.values.flatten).to be_empty
    end

    it "updates the same row when the token rotates" do
      sign_in_admin
      register_browser
      register_browser(token: "web-token-2")

      expect(Device.sole.token).to eq("web-token-2")
    end

    it "is open to admins (reviewers) too" do
      sign_in_admin(create(:user, :admin, password: "password123"))
      register_browser

      expect(response).to have_http_status(:no_content)
    end

    it "requires a dashboard session" do
      register_browser

      expect(response).to redirect_to(admin_login_path)
      expect(Device.count).to eq(0)
    end

    it "refuses an installation that belongs to the app" do
      create(:device, installation_id: "web-1", platform: "android")
      sign_in_admin
      register_browser

      expect(response).to have_http_status(:forbidden)
    end
  end

  it "forgets the browser at logout" do
    sign_in_admin
    register_browser
    delete "/admin/logout"

    expect(Device.count).to eq(0)
  end

  it "pushes the admin's notifications to the browser with the page to open" do
    admin = sign_in_admin
    register_browser
    firm = create(:firm)

    Notifier.notify(user: admin, kind: :system_announcement, title: "عنوان", body: "نص",
                    destination: Notifications::Destination.new(screen: "firm", id: firm.id))
    perform_enqueued_jobs

    expect(fcm.deliveries.sole).to include(token: "web-token")
    expect(fcm.deliveries.sole[:data]).to include("screen" => "firm", "admin_path" => "/admin/firms/#{firm.id}")
  end

  it "keeps admin_path out of the app's pushes" do
    user = create(:user)
    create(:device, user:, token: "app-token")

    Notifier.notify(user:, kind: :system_announcement, title: "عنوان", body: "نص")
    perform_enqueued_jobs

    expect(fcm.deliveries.sole[:data]).not_to have_key("admin_path")
  end

  it "leaves a browser without a user out of campaigns" do
    create(:device, platform: "web", user: nil)

    expect(Topic.recipient_guest_device_ids([ Topic.everyone ])).to be_empty
  end

  describe "the enable button" do
    it "is offered once Firebase is configured" do
      stub_firebase_env(firebase_env)
      sign_in_admin
      get "/admin"

      expect(response.body).to include("data-push-toggle", admin_push_device_path, "admin_push")
    end

    it "is hidden while any Firebase value is missing" do
      stub_firebase_env(firebase_env.merge("FIREBASE_VAPID_KEY" => nil))
      sign_in_admin
      get "/admin"

      expect(response.body).not_to include("data-push-toggle")
    end
  end
end
