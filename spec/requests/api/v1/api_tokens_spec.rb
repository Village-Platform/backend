require "rails_helper"

RSpec.describe "API tokens", type: :request do
  let(:guest_headers) { { "Authorization" => "Bearer #{JsonWebToken.encode({ typ: 'guest' })}" } }

  describe "POST /api/v1/auth/guest" do
    it "issues a guest token without credentials" do
      post "/api/v1/auth/guest"

      expect(response).to have_http_status(:created)
      expect(JsonWebToken.decode(json.dig("data", "token"))).to include("typ" => "guest")
    end

    it "is rate limited per IP" do
      store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails.cache).to receive(:increment) { |*args, **opts| store.increment(*args, **opts) }

      30.times { post "/api/v1/auth/guest" }
      expect(response).to have_http_status(:created)
      post "/api/v1/auth/guest"

      expect(response).to have_http_status(:too_many_requests)
      expect(json.dig("error", "code")).to eq("rate_limited")
    end
  end

  describe "a guest token" do
    it "never names a user, even one whose id a typed token's sub would cast to" do
      user = create(:user)
      token = JsonWebToken.encode({ typ: "guest", sub: "#{user.id}abc" })

      get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "is refused where a user is required" do
      get "/api/v1/notifications", headers: guest_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "when API_TOKEN_REQUIRED is on" do
    around do |example|
      Rails.configuration.x.api_token_required = true
      example.run
    ensure
      Rails.configuration.x.api_token_required = false
    end

    it "refuses a call without a token" do
      get "/api/v1/categories"

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("unauthorized")
    end

    it "refuses an invalid or expired token" do
      expired = JsonWebToken.encode({ typ: "guest" }, expires_at: 1.minute.ago)

      get "/api/v1/categories", headers: { "Authorization" => "Bearer #{expired}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "serves a guest token" do
      get "/api/v1/categories", headers: guest_headers

      expect(response).to have_http_status(:ok)
    end

    it "serves a user token" do
      get "/api/v1/firms", headers: auth_headers(create(:user))

      expect(response).to have_http_status(:ok)
    end

    it "keeps the ways to get a token open" do
      post "/api/v1/auth/guest"
      expect(response).to have_http_status(:created)

      create(:user, phone: "01099999999", password: "password123")
      post "/api/v1/auth/login", params: { phone: "01099999999", password: "password123" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "keeps app_config open" do
      get "/api/v1/app_config"

      expect(response).to have_http_status(:ok)
    end

    it "keeps category icons open, since image loaders send no headers" do
      category = create(:category)
      category.icon_image.attach(io: file_fixture("receipt.png").open, filename: "receipt.png", content_type: "image/png")

      get "/api/v1/categories/#{category.id}/icon"

      expect(response).to have_http_status(:ok)
    end
  end

  context "when API_TOKEN_REQUIRED is off (the default)" do
    it "still serves a call without a token, for app versions that predate guest tokens" do
      get "/api/v1/categories"

      expect(response).to have_http_status(:ok)
    end
  end
end
