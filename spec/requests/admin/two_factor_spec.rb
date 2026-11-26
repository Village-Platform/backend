require "rails_helper"

RSpec.describe "Dashboard two-factor sign-in", type: :request do
  let(:admin) { create(:user, :super_admin, password: "password123") }

  def sign_in_with_password(user = admin)
    post "/admin/login", params: { phone: user.phone, password: "password123" }
  end

  def enroll(user = admin)
    create(:totp_credential, :confirmed, user:)
  end

  context "when off" do
    it "signs in with the password alone, even with an authenticator set up", reviewer_mfa: "off" do
      enroll
      sign_in_with_password

      expect(response).to redirect_to("/admin")
    end
  end

  context "when optional", reviewer_mfa: "optional" do
    it "lets a reviewer without an authenticator in with the password" do
      sign_in_with_password

      expect(response).to redirect_to("/admin")
      get "/admin"
      expect(response).to have_http_status(:ok)
    end

    it "asks an enrolled reviewer for a code before the dashboard opens" do
      credential = enroll
      sign_in_with_password

      expect(response).to redirect_to("/admin/second_factor/new")
      get "/admin"
      expect(response).to redirect_to("/admin/second_factor/new")

      post "/admin/second_factor", params: { otp: totp_code(credential) }
      expect(response).to redirect_to("/admin")
      get "/admin"
      expect(response).to have_http_status(:ok)
    end

    it "lets a signed-in reviewer set up an authenticator from the dashboard and stay signed in" do
      sign_in_with_password
      get "/admin/authenticator/new"
      expect(response).to have_http_status(:ok)

      credential = TotpCredential.find_by!(user: admin)
      post "/admin/authenticator", params: { otp: totp_code(credential) }

      expect(response).to have_http_status(:ok)
      expect(credential.reload).to be_confirmed
      get "/admin"
      expect(response).to have_http_status(:ok)
    end

    it "ends password-only sessions once the reviewer has an authenticator" do
      sign_in_with_password
      enroll

      get "/admin"
      expect(response).to redirect_to("/admin/login")
    end
  end

  context "when required", reviewer_mfa: "required" do
    it "sends a reviewer without an authenticator to set one up, showing the QR code" do
      sign_in_with_password
      expect(response).to redirect_to("/admin/authenticator/new")

      get "/admin/authenticator/new"
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).to include("<svg")
      credential = TotpCredential.find_by!(user: admin)
      expect(response.body).to include(credential.otp_secret.scan(/.{1,4}/).join(" "))

      # Mid-sign-in is not signed in: the dashboard sends the reviewer back to the setup step.
      get "/admin"
      expect(response).to redirect_to("/admin/authenticator/new")
    end

    it "confirms the authenticator with its first code, shows the recovery codes once and signs in" do
      sign_in_with_password
      get "/admin/authenticator/new"
      credential = TotpCredential.find_by!(user: admin)

      post "/admin/authenticator", params: { otp: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(credential.reload).not_to be_confirmed

      post "/admin/authenticator", params: { otp: totp_code(credential) }
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body.scan(/[A-Z2-9]{5}-[A-Z2-9]{5}/).uniq.size).to eq(10)
      expect(response.body).to include("data-recovery-download", "aghour-recovery-codes-#{Date.current.iso8601}.txt")
      expect(response.body).to include(CGI.escapeHTML(admin.name))
      expect(credential.reload).to be_confirmed
      expect(RecoveryCode.remaining(admin)).to eq(10)

      get "/admin"
      expect(response).to have_http_status(:ok)
    end

    it "refuses a wrong code and keeps the dashboard closed" do
      enroll
      sign_in_with_password
      post "/admin/second_factor", params: { otp: "000000" }

      expect(response).to have_http_status(:unprocessable_content)
      get "/admin"
      expect(response).to redirect_to("/admin/second_factor/new")
    end

    it "refuses a code that was already used" do
      credential = enroll
      code = totp_code(credential)
      sign_in_with_password
      post "/admin/second_factor", params: { otp: code }
      delete "/admin/logout"

      sign_in_with_password
      post "/admin/second_factor", params: { otp: code }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "accepts a recovery code once" do
      enroll
      recovery = RecoveryCode.regenerate!(admin).first

      sign_in_with_password
      post "/admin/second_factor", params: { otp: recovery }
      expect(response).to redirect_to("/admin")
      delete "/admin/logout"

      sign_in_with_password
      post "/admin/second_factor", params: { otp: recovery }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "locks the authenticator after ten wrong codes" do
      credential = enroll
      sign_in_with_password
      10.times { post "/admin/second_factor", params: { otp: "000000" } }

      expect(response.body).to include(I18n.t("admin.second_factors.locked"))
      post "/admin/second_factor", params: { otp: totp_code(credential) }
      expect(response).to have_http_status(:unprocessable_content)
      expect(credential.reload).to be_locked
    end

    it "forgets a password step that was not finished within ten minutes" do
      credential = enroll
      sign_in_with_password

      travel 11.minutes do
        post "/admin/second_factor", params: { otp: totp_code(credential) }
        expect(response).to redirect_to("/admin/login")
      end
    end

    it "does not show the code page without a password step" do
      get "/admin/second_factor/new"

      expect(response).to redirect_to("/admin/login")
    end

    it "never offers a second device to a reviewer who already has one" do
      enroll
      sign_in_with_password

      get "/admin/authenticator/new"
      expect(response).to redirect_to("/admin/login")
      expect(TotpCredential.where(user: admin).count).to eq(1)
    end
  end
end
