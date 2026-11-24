require "rails_helper"

# The test environment turns forgery protection off; these examples turn it back on, because the
# two-factor pages depend on the session (and with it the CSRF token) surviving between steps.
RSpec.describe "Dashboard two-factor sign-in with CSRF protection", type: :request, reviewer_mfa: "required" do
  let(:admin) { create(:user, :super_admin, password: "password123") }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  def form_token
    response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  def sign_in_with_password
    get "/admin/login"
    post "/admin/login", params: { phone: admin.phone, password: "password123", authenticity_token: form_token }
  end

  it "keeps the setup step when another tab opens the dashboard meanwhile" do
    sign_in_with_password
    get "/admin/authenticator/new"
    token = form_token
    credential = TotpCredential.find_by!(user: admin)

    get "/admin" # e.g. a bookmark opened in a second tab
    expect(response).to redirect_to("/admin/authenticator/new")

    post "/admin/authenticator", params: { otp: totp_code(credential), authenticity_token: token }
    expect(response).to have_http_status(:ok)
    expect(credential.reload).to be_confirmed
  end

  it "keeps the code step when another tab opens the dashboard meanwhile" do
    credential = create(:totp_credential, :confirmed, user: admin)
    sign_in_with_password
    get "/admin/second_factor/new"
    token = form_token

    get "/admin"
    expect(response).to redirect_to("/admin/second_factor/new")

    post "/admin/second_factor", params: { otp: totp_code(credential), authenticity_token: token }
    expect(response).to redirect_to("/admin")
  end

  it "sends a stale form back to the login page instead of an error page" do
    sign_in_with_password
    get "/admin/authenticator/new"

    post "/admin/authenticator", params: { otp: "123456", authenticity_token: "stale" }

    expect(response).to redirect_to("/admin/login")
    expect(flash[:alert]).to eq(I18n.t("admin.second_factors.expired"))
  end
end
