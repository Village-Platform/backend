require "rails_helper"

RSpec.describe "Firms API", type: :request do
  let(:category) { create(:category) }
  let(:owner) { create(:user, :subscribed) }
  let(:super_admin) { create(:user, :super_admin) }

  describe "GET /api/v1/firms" do
    it "shows only active firms to the public" do
      create(:firm, name: "Visible", category:)
      create(:firm, :pending, name: "Pending", category:)

      get "/api/v1/firms"

      expect(json["data"].map { _1["name"] }).to eq([ "Visible" ])
    end

    it "lets owners see their own pending firms" do
      create(:firm, :pending, name: "Mine", owner:, category:)

      get "/api/v1/firms", params: { mine: true }, headers: auth_headers(owner)

      expect(json["data"].map { _1["name"] }).to eq([ "Mine" ])
    end

    it "lists only active firms to owners and super admins too" do
      create(:firm, name: "Visible", category:)
      create(:firm, :pending, name: "Own pending", owner:, category:)
      create(:firm, name: "Suspended", status: :suspended, category:)

      [ owner, super_admin ].each do |user|
        get "/api/v1/firms", headers: auth_headers(user)
        expect(json["data"].map { _1["name"] }).to eq([ "Visible" ])

        get "/api/v1/categories/#{category.id}/firms", headers: auth_headers(user)
        expect(json["data"].map { _1["name"] }).to eq([ "Visible" ])
      end
    end

    it "still lets the super admin open a pending firm" do
      firm = create(:firm, :pending, category:)
      get "/api/v1/firms/#{firm.id}", headers: auth_headers(super_admin)
      expect(response).to have_http_status(:ok)
    end

    it "filters by category through the nested route and searches by name" do
      other = create(:category)
      create(:firm, name: "Pharmacy Nour", category:)
      create(:firm, name: "Clinic", category:)
      create(:firm, name: "Pharmacy Other", category: other)

      get "/api/v1/categories/#{category.id}/firms", params: { q: "pharm" }

      expect(json["data"].map { _1["name"] }).to eq([ "Pharmacy Nour" ])
    end

    it "hides pending firms from other users on show" do
      firm = create(:firm, :pending, category:)
      get "/api/v1/firms/#{firm.id}", headers: auth_headers(create(:user))
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/firms" do
    let(:params) { { firm: { name: "صيدلية النور", category_id: category.id, status: "active" } } }

    it "lets a subscribed firm admin publish directly (status is not assignable by owners)" do
      post "/api/v1/firms", params: { firm: params[:firm].merge(status: "suspended") }, headers: auth_headers(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "status")).to eq("active")
      expect(json.dig("data", "owner_id")).to eq(owner.id)
    end

    it "submits the firm for review when the firm admin's subscription expired" do
      unsubscribed = create(:user, :firm_admin)
      create(:subscription, :expired, user: unsubscribed)

      post "/api/v1/firms", params:, headers: auth_headers(unsubscribed), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "status")).to eq("pending")
    end

    it "enforces the plan's max_firms" do
      create(:firm, owner:, category:) # plan allows 1

      post "/api/v1/firms", params:, headers: auth_headers(owner), as: :json

      expect(json.dig("error", "code")).to eq("subscription_required")
    end
  end

  describe "visibility after subscription expiry" do
    it "hides active firms whose owner subscription expired" do
      firm = create(:firm, name: "Expired owner", category:)
      firm.owner.subscriptions.update_all(ends_at: 1.minute.ago)

      get "/api/v1/firms"

      expect(json["data"]).to be_empty
    end
  end

  describe "PATCH /api/v1/firms/:id" do
    let(:firm) { create(:firm, :pending, owner:, category:) }

    it "lets super admins approve a firm" do
      patch "/api/v1/firms/#{firm.id}", params: { firm: { status: "active" } },
                                        headers: auth_headers(super_admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(firm.reload).to be_active
    end

    it "forbids another firm admin from editing it" do
      other_owner = create(:user, :firm_admin)
      firm.update!(status: :active)

      patch "/api/v1/firms/#{firm.id}", params: { firm: { name: "Hacked" } },
                                        headers: auth_headers(other_owner), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(firm.reload.name).not_to eq("Hacked")
    end

    it "sends an unsubscribed owner's edit of an active firm back for review" do
      firm.update!(status: :active)
      owner.subscriptions.update_all(ends_at: 1.minute.ago)

      patch "/api/v1/firms/#{firm.id}", params: { firm: { phone: "01099999999" } },
                                        headers: auth_headers(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "status")).to eq("pending")
      expect(firm.reload).to be_pending
      expect(firm.phone).to eq("01099999999")
    end

    it "keeps a subscribed owner's edit of an active firm live (they publish directly)" do
      firm.update!(status: :active)

      patch "/api/v1/firms/#{firm.id}", params: { firm: { phone: "01099999999" } },
                                        headers: auth_headers(owner), as: :json

      expect(firm.reload).to be_active
      expect(firm.phone).to eq("01099999999")
    end

    it "keeps an active firm active when the owner saves without changes" do
      firm.update!(status: :active)

      patch "/api/v1/firms/#{firm.id}", params: { firm: { name: firm.name } },
                                        headers: auth_headers(owner), as: :json

      expect(firm.reload).to be_active
    end

    it "keeps a suspended firm suspended when its owner edits it" do
      firm.update!(status: :suspended)

      patch "/api/v1/firms/#{firm.id}", params: { firm: { name: "New name" } },
                                        headers: auth_headers(owner), as: :json

      expect(firm.reload).to be_suspended
    end

    it "keeps the status when the super admin edits an active firm" do
      firm.update!(status: :active)

      patch "/api/v1/firms/#{firm.id}", params: { firm: { name: "Fixed typo" } },
                                        headers: auth_headers(super_admin), as: :json

      expect(firm.reload).to be_active
    end
  end

  describe "permissions in the response (can)" do
    let!(:firm) { create(:firm, owner:, category:) }

    def can_for(headers = {})
      get "/api/v1/firms/#{firm.id}", headers: headers
      json.dig("data", "can")
    end

    it "tells each viewer what they may do" do
      expect(can_for).to eq("update" => false, "destroy" => false, "moderate" => false, "review" => false)
      expect(can_for(auth_headers(create(:user)))).to eq("update" => false, "destroy" => false, "moderate" => false, "review" => false)
      expect(can_for(auth_headers(owner))).to eq("update" => true, "destroy" => true, "moderate" => false, "review" => false)
      expect(can_for(auth_headers(create(:user, :admin)))).to eq("update" => false, "destroy" => false, "moderate" => false, "review" => true)
      expect(can_for(auth_headers(super_admin))).to eq("update" => true, "destroy" => true, "moderate" => true, "review" => true)
    end

    it "is included in lists too" do
      get "/api/v1/firms", headers: auth_headers(owner)

      expect(json["data"].first["can"]).to include("update" => true)
    end
  end
end
