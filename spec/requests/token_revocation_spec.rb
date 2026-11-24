require "rails_helper"

# Every bearer token and dashboard session records the user's token_version when it was issued.
# Bumping the version revokes all of them at once.
RSpec.describe "Token revocation", type: :request do
  let(:user) { create(:user, phone: "01011112222", password: "password123") }

  def bearer(token) = { "Authorization" => "Bearer #{token}" }

  def login_token(phone: user.phone, password: "password123")
    post "/api/v1/auth/login", params: { phone:, password: }, as: :json
    json.dig("data", "token")
  end

  describe "API tokens" do
    it "issues tokens that carry the current version" do
      token = login_token

      expect(JsonWebToken.decode(token)).to include("sub" => user.id, "ver" => 0)
      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:ok)
    end

    it "keeps accepting tokens issued before versions existed while the version is 0" do
      get "/api/v1/me", headers: bearer(JsonWebToken.encode({ sub: user.id }))

      expect(response).to have_http_status(:ok)
    end

    it "refuses a token from an older version" do
      token = login_token
      user.increment!(:token_version)

      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a token whose version is not an integer" do
      get "/api/v1/me", headers: bearer(JsonWebToken.encode({ sub: user.id, ver: "0" }))

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "changing the password through the API" do
    let(:params) { { user: { password: "newpass456", password_confirmation: "newpass456" } } }

    it "revokes every other token and hands back a new one for this device" do
      other_device = login_token
      this_device = login_token

      patch "/api/v1/me", params:, headers: bearer(this_device), as: :json

      expect(response).to have_http_status(:ok)
      fresh = json.dig("meta", "token")
      expect(JsonWebToken.decode(fresh)).to include("sub" => user.id, "ver" => 1)

      get "/api/v1/me", headers: bearer(other_device)
      expect(response).to have_http_status(:unauthorized)
      get "/api/v1/me", headers: bearer(this_device)
      expect(response).to have_http_status(:unauthorized)
      get "/api/v1/me", headers: bearer(fresh)
      expect(response).to have_http_status(:ok)
    end

    it "keeps tokens and returns no new one when the password is not changed" do
      token = login_token

      patch "/api/v1/me", params: { user: { name: "New Name" } }, headers: bearer(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(json["meta"]).to be_nil
      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "other ways a user's access ends" do
    it "does not revoke on a role change, since roles are read from the database on every request" do
      token = login_token
      user.update!(role: :firm_admin)

      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:ok)
    end

    it "revokes when an admin sets a new password on the dashboard" do
      token = login_token
      sign_in_admin

      patch "/admin/users/#{user.id}", params: { user: { password: "newpass456" } }

      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "keeps old tokens dead when an admin restores a soft-deleted user" do
      token = login_token
      user.destroy!
      user.recover

      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.token_version).to eq(1)
    end

    it "keeps old tokens dead when a deleted account is restored" do
      token = login_token
      Users::DeleteAccount.call(user:)
      user.recover

      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "dashboard sessions" do
    let(:admin) { create(:user, :super_admin, password: "password123") }

    it "ends the session when the admin's password is changed elsewhere" do
      sign_in_admin(admin)
      admin.update!(password: "newpass456")

      get "/admin"
      expect(response).to redirect_to("/admin/login")
    end

    it "keeps the admin signed in after changing their own password on the dashboard" do
      sign_in_admin(admin)

      patch "/admin/users/#{admin.id}", params: { user: { password: "newpass456" } }

      get "/admin"
      expect(response).to have_http_status(:ok)
    end

    it "keeps sessions signed in before versions existed while the version is 0" do
      sign_in_admin(admin)
      # A cookie written before this change has no version key.
      allow(AdminSession).to receive(:session_version).and_return(nil)

      get "/admin"
      expect(response).to have_http_status(:ok)
    end
  end
end
