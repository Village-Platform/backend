require "rails_helper"

RSpec.describe "Internal cron", type: :request do
  let(:path) { "/internal/cron/subscription_reminders" }

  around do |example|
    previous = ENV["CRON_SECRET"]
    ENV["CRON_SECRET"] = "test-cron-secret"
    example.run
  ensure
    ENV["CRON_SECRET"] = previous
  end

  it "runs the reminders with the right secret" do
    allow(SubscriptionExpiryRemindersJob).to receive(:perform_now).and_return(2)

    get path, headers: { "Authorization" => "Bearer test-cron-secret" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("sent" => 2)
  end

  it "rejects a wrong or missing secret" do
    expect(SubscriptionExpiryRemindersJob).not_to receive(:perform_now)

    get path, headers: { "Authorization" => "Bearer nope" }
    expect(response).to have_http_status(:unauthorized)

    get path
    expect(response).to have_http_status(:unauthorized)
  end

  it "is closed when CRON_SECRET is not set" do
    ENV["CRON_SECRET"] = nil

    get path, headers: { "Authorization" => "Bearer " }

    expect(response).to have_http_status(:unauthorized)
  end
end
