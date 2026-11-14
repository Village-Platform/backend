require "rails_helper"

RSpec.describe "Admin user firms", type: :request do
  let(:owner) { create(:user, :subscribed) }
  let!(:firm) { create(:firm, owner:) }

  describe "without a session" do
    it "will not move a firm" do
      target = create(:user, :subscribed)

      post "/admin/users/#{target.id}/firms", params: { firm_id: firm.id }

      expect(response).to redirect_to("/admin/login")
      expect(firm.reload.owner).to eq(owner)
    end
  end

  describe "signed in" do
    before { sign_in_admin }

    it "attaches an existing firm to the user" do
      target = create(:user, :subscribed)

      post "/admin/users/#{target.id}/firms", params: { firm_id: firm.id }

      expect(firm.reload.owner).to eq(target)
      expect(flash[:notice]).to be_present
    end

    it "moves a firm away to another owner" do
      target = create(:user, :subscribed)

      delete "/admin/users/#{owner.id}/firms/#{firm.id}", params: { new_owner_id: target.id }

      expect(firm.reload.owner).to eq(target)
    end

    # firms.owner_id is NOT NULL: a firm can never be ownerless, so "remove" has to say
    # where it goes rather than detach.
    it "refuses to leave a firm without an owner" do
      delete "/admin/users/#{owner.id}/firms/#{firm.id}"

      expect(firm.reload.owner).to eq(owner)
      expect(flash[:alert]).to be_present
    end

    it "refuses an owner who cannot manage firms" do
      resident = create(:user)

      delete "/admin/users/#{owner.id}/firms/#{firm.id}", params: { new_owner_id: resident.id }

      expect(firm.reload.owner).to eq(owner)
      expect(flash[:alert]).to be_present
    end

    it "only moves firms that belong to the user in the URL" do
      other_owner = create(:user, :subscribed)
      target = create(:user, :subscribed)

      delete "/admin/users/#{other_owner.id}/firms/#{firm.id}", params: { new_owner_id: target.id }

      expect(firm.reload.owner).to eq(owner)
    end

    # Visibility does not depend on the owner, so a reassignment never hides a firm.
    it "keeps the firm in the public listing when the new owner is not subscribed" do
      unsubscribed = create(:user, :firm_admin)

      post "/admin/users/#{unsubscribed.id}/firms", params: { firm_id: firm.id }

      expect(firm.reload.owner).to eq(unsubscribed)
      expect(Firm.visible).to include(firm)
    end

    it "prefills the owner when creating a firm for this user" do
      get "/admin/firms/new", params: { owner_id: owner.id }

      selected = Nokogiri::HTML(response.body).at_css("select[name='firm[owner_id]'] option[selected]")
      expect(selected).to be_present
      expect(selected["value"]).to eq(owner.id.to_s)
    end
  end
end
