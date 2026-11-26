require "rails_helper"

RSpec.describe "Me API", type: :request do
  describe "PATCH /api/v1/me" do
    let(:user) { create(:user, name: "Khaled Elabady", phone: "01012345678", email: "k@example.com", password: "password123") }

    def update_me(attrs)
      patch "/api/v1/me", params: { user: attrs }, headers: auth_headers(user), as: :json
    end

    it "updates the name, email and phone" do
      update_me(name: "Khaled Ali", email: "New@Example.com", phone: "0119 876 5432", current_password: "password123")

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("name" => "Khaled Ali", "email" => "new@example.com", "phone" => "01198765432")
    end

    it "removes the email when it is sent empty" do
      update_me(email: "")

      expect(response).to have_http_status(:ok)
      expect(user.reload.email).to be_nil
    end

    it "rejects a malformed email" do
      update_me(email: "khaled@gmail")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_failed")
      expect(json.dig("error", "details")).to have_key("email")
    end

    it "rejects a phone that is not an Egyptian mobile number" do
      %w[ 0101234 01312345678 +201012345678 ].each do |phone|
        update_me(phone:, current_password: "password123")

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details")).to have_key("phone")
      end
      expect(user.reload.phone).to eq("01012345678")
    end

    it "keeps an old-format phone valid when the phone is not changed" do
      user.update_columns(phone: "+201012345678")
      update_me(name: "Khaled")

      expect(response).to have_http_status(:ok)
    end

    it "answers phone_taken for a phone another account holds, with every field's errors" do
      create(:user, phone: "01198765432")
      update_me(phone: "01198765432", email: "bad", current_password: "password123")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("phone_taken")
      expect(json.dig("error", "details").keys).to contain_exactly("phone", "email")
      expect(user.reload.phone).to eq("01012345678")
    end

    it "lets the user log in with the new phone" do
      update_me(phone: "01598765432", current_password: "password123")

      post "/api/v1/auth/login", params: { phone: "01598765432", password: "password123" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "requires the current password to change the phone" do
      [ {}, { current_password: "wrong-pass" } ].each do |extra|
        update_me(phone: "01198765432", **extra)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("invalid_password")
      end
      expect(user.reload.phone).to eq("01012345678")
    end

    it "requires the current password to change the password" do
      update_me(password: "new-password1", password_confirmation: "new-password1", current_password: "wrong-pass")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("invalid_password")
      expect(user.reload.authenticate("password123")).to be_truthy
    end

    it "requires the current password for a whitespace-only new password" do
      update_me(password: " " * 8, password_confirmation: " " * 8)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("invalid_password")
      expect(user.reload.authenticate("password123")).to be_truthy
    end

    it "answers phone_taken when another account takes the phone between the check and the save" do
      create(:user, phone: "01198765432")
      allow_any_instance_of(ActiveRecord::Validations::UniquenessValidator).to receive(:validate_each)

      update_me(phone: "01198765432", current_password: "password123")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("phone_taken")
      expect(json.dig("error", "details")).to have_key("phone")
    end

    it "changes the password with the current one" do
      update_me(password: "new-password1", password_confirmation: "new-password1", current_password: "password123")

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("new-password1")).to be_truthy
    end

    it "needs no password for the name, the email, or resending the same phone" do
      update_me(name: "Khaled Ali", email: "", phone: "010 1234 5678")

      expect(response).to have_http_status(:ok)
      expect(user.reload.name).to eq("Khaled Ali")
    end

    it "does not let the user change their role" do
      update_me(role: "super_admin")
      expect(user.reload).to be_user
    end
  end

  describe "DELETE /api/v1/me" do
    let(:user) { create(:user, password: "password123") }

    it "turns the account's phones into guests and drops its topics" do
      device = create(:device, user:)
      TopicSubscription.create!(topic: create(:topic), user:)

      delete "/api/v1/me", params: { password: "password123" }, headers: auth_headers(user), as: :json

      expect(device.reload.user).to be_nil
      expect(TopicSubscription.count).to eq(0)
    end

    it "deletes the account and revokes the token" do
      delete "/api/v1/me", params: { password: "password123" }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:no_content)
      expect(user.reload).to be_deleted

      get "/api/v1/me", headers: auth_headers(user)
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a wrong password with 422, not 401, so the app keeps the session" do
      delete "/api/v1/me", params: { password: "wrong-pass" }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("invalid_password")
      expect(user.reload).not_to be_deleted
    end

    it "requires the password" do
      delete "/api/v1/me", headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      delete "/api/v1/me", params: { password: "password123" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses super admins" do
      admin = create(:user, :super_admin, password: "password123")
      delete "/api/v1/me", params: { password: "password123" }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(admin.reload).not_to be_deleted
    end
  end
end
