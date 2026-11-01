require "rails_helper"

# Who publishes directly and who submits for review, for firms and articles, and the review itself.
RSpec.describe "Submissions and review", type: :request do
  let(:category) { create(:category) }
  let(:user) { create(:user) }
  let(:firm_admin) { create(:user, :subscribed) }
  let(:admin) { create(:user, :admin) }
  let(:super_admin) { create(:user, :super_admin) }

  let(:firm_params) { { firm: { name: "صيدلية النور", category_id: category.id } } }
  let(:article_params) { { article: { title: "خبر", body: "تفاصيل" } } }

  def create_firm(as:)
    post "/api/v1/firms", params: firm_params, headers: auth_headers(as), as: :json
  end

  def create_article(as:, params: article_params)
    post "/api/v1/articles", params:, headers: auth_headers(as), as: :json
  end

  describe "creating, per role" do
    it "refuses a guest" do
      post "/api/v1/firms", params: firm_params, as: :json
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/articles", params: article_params, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "submits a normal user's firm and article for review and notifies only the super admins" do
      admin
      super_admin

      expect { create_firm(as: user) }.to change(Notification, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json.dig("data", "status")).to eq("pending")
      firm_id = json.dig("data", "id")

      expect { create_article(as: user) }.to change(Notification, :count).by(1)
      expect(json.dig("data", "review_status")).to eq("pending")

      inbox = Notification.where(user: [ admin, super_admin ], kind: :firm_submitted)
      expect(inbox.map(&:user)).to eq([ super_admin ])
      expect(Notification.where(user: admin)).to be_empty
      expect(inbox.first.data).to include("screen" => "firm", "id" => firm_id.to_s)
      expect(inbox.first.body).to include(user.name, "صيدلية النور")
      expect(Notification.where(kind: :article_submitted).first.data).to include("screen" => "article")
    end

    it "pushes the review notification to the super admins' devices" do
      create(:device, user: super_admin)

      expect { create_firm(as: user) }.to have_enqueued_job(PushNotificationJob)
    end

    it "keeps a normal user's submissions out of public lists, but in their own" do
      create_firm(as: user)
      create_article(as: user)

      get "/api/v1/firms"
      expect(json["data"]).to be_empty
      get "/api/v1/articles"
      expect(json["data"]).to be_empty

      get "/api/v1/firms", params: { mine: true }, headers: auth_headers(user)
      expect(json["data"].size).to eq(1)
      get "/api/v1/articles", params: { mine: true }, headers: auth_headers(user)
      expect(json["data"].map { _1["review_status"] }).to eq([ "pending" ])
      get "/api/v1/articles", headers: auth_headers(user)
      expect(json["data"]).to be_empty
    end

    it "caps a user's submissions waiting for review" do
      User::MAX_PENDING_SUBMISSIONS.times { create(:firm, :pending, owner: user, category:) }
      User::MAX_PENDING_SUBMISSIONS.times { create(:article, :pending, author: user) }

      create_firm(as: user)
      expect(response).to have_http_status(:forbidden)
      expect(json.dig("error", "code")).to eq("too_many_pending")
      expect(json.dig("error", "message")).to be_present

      create_article(as: user)
      expect(json.dig("error", "code")).to eq("too_many_pending")
    end

    it "lets a subscribed firm admin publish directly, without notifying reviewers" do
      admin

      expect { create_firm(as: firm_admin) }.not_to change(Notification, :count)
      expect(json.dig("data", "status")).to eq("active")

      create_article(as: firm_admin, params: { article: { title: "خبر", body: "...", published_at: 1.minute.ago } })
      expect(json.dig("data", "review_status")).to eq("approved")

      get "/api/v1/articles"
      expect(json["data"].map { _1["title"] }).to eq([ "خبر" ])
      get "/api/v1/firms"
      expect(json["data"].map { _1["name"] }).to eq([ "صيدلية النور" ])
    end

    it "lets an admin publish directly with no subscription and no quota, and shows their firms" do
      2.times { create_firm(as: admin) }
      expect(json.dig("data", "status")).to eq("active")

      create_article(as: admin, params: { article: { title: "إعلان", body: "...", published_at: 1.minute.ago } })
      expect(json.dig("data", "review_status")).to eq("approved")

      get "/api/v1/firms"
      expect(json["data"].size).to eq(2)
    end

    it "lets the super admin publish directly and still choose a firm's status" do
      post "/api/v1/firms", params: { firm: firm_params[:firm].merge(status: "pending") },
                            headers: auth_headers(super_admin), as: :json
      expect(json.dig("data", "status")).to eq("pending")

      create_firm(as: super_admin)
      expect(json.dig("data", "status")).to eq("active")
    end
  end

  describe "reviewing" do
    let(:firm) { create(:firm, :pending, owner: user, category:) }
    let(:article) { create(:article, :pending, author: user, published_at: nil) }

    it "lists what waits for review, to reviewers only" do
      firm
      article
      create(:firm, category:)

      get "/api/v1/firms", params: { review: "pending" }, headers: auth_headers(admin)
      expect(json["data"].map { _1["id"] }).to eq([ firm.id ])
      get "/api/v1/articles", params: { review: "pending" }, headers: auth_headers(admin)
      expect(json["data"].map { _1["id"] }).to eq([ article.id ])

      get "/api/v1/firms", params: { review: "pending" }, headers: auth_headers(user)
      expect(json["data"].map { _1["id"] }).not_to include(firm.id)
    end

    it "lets an admin open a pending submission" do
      get "/api/v1/firms/#{firm.id}", headers: auth_headers(admin)
      expect(json.dig("data", "can", "review")).to be(true)

      get "/api/v1/articles/#{article.id}", headers: auth_headers(admin)
      expect(json.dig("data", "can", "review")).to be(true)
    end

    [ :admin, :super_admin ].each do |role|
      it "lets a #{role} approve a firm and tells the owner" do
        reviewer = public_send(role)

        expect {
          patch "/api/v1/firms/#{firm.id}/approve", headers: auth_headers(reviewer)
        }.to change { Notification.where(user:, kind: :firm_approved).count }.by(1)

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "status")).to eq("active")
        expect(firm.reload.reviewed_by).to eq(reviewer)
        expect(Notification.find_by(user:, kind: :firm_approved).data).to include("screen" => "firm", "id" => firm.id.to_s)
      end
    end

    it "keeps an approved firm of a user without a subscription out of the public list" do
      patch "/api/v1/firms/#{firm.id}/approve", headers: auth_headers(admin)

      get "/api/v1/firms"
      expect(json["data"]).to be_empty

      create(:subscription, :current, user:)
      get "/api/v1/firms"
      expect(json["data"].map { _1["id"] }).to eq([ firm.id ])
    end

    it "rejects a firm with a reason the owner sees" do
      patch "/api/v1/firms/#{firm.id}/reject", params: { reason: "العنوان ناقص" }, headers: auth_headers(admin), as: :json

      expect(json.dig("data", "status")).to eq("suspended")
      expect(json.dig("data", "rejection_reason")).to eq("العنوان ناقص")
      expect(Notification.find_by(user:, kind: :firm_rejected).body).to include("العنوان ناقص")

      get "/api/v1/firms/#{firm.id}", headers: auth_headers(user)
      expect(json.dig("data", "rejection_reason")).to eq("العنوان ناقص")
    end

    it "requires a reason to reject" do
      patch "/api/v1/firms/#{firm.id}/reject", headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:bad_request)
      expect(firm.reload).to be_pending
    end

    it "refuses a second review" do
      patch "/api/v1/firms/#{firm.id}/approve", headers: auth_headers(admin)
      patch "/api/v1/firms/#{firm.id}/approve", headers: auth_headers(super_admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("already_reviewed")

      patch "/api/v1/firms/#{firm.id}/reject", params: { reason: "x" }, headers: auth_headers(admin), as: :json
      expect(json.dig("error", "code")).to eq("already_reviewed")
    end

    it "forbids a firm admin or the owner from reviewing" do
      patch "/api/v1/firms/#{firm.id}/approve", headers: auth_headers(user)
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/articles/#{article.id}/approve", headers: auth_headers(firm_admin)
      expect(response).to have_http_status(:not_found) # not in their scope at all
      expect(article.reload).to be_pending
    end

    it "approves an article: it goes live now and the author is told" do
      patch "/api/v1/articles/#{article.id}/approve", headers: auth_headers(admin)

      expect(json.dig("data", "review_status")).to eq("approved")
      expect(article.reload.published_at).to be_within(5.seconds).of(Time.current)
      expect(Notification.find_by(user:, kind: :article_approved).data).to include("screen" => "article")

      get "/api/v1/articles"
      expect(json["data"].map { _1["id"] }).to eq([ article.id ])
    end

    it "rejects an article with a reason; the author still sees it" do
      patch "/api/v1/articles/#{article.id}/reject", params: { reason: "مكرر" }, headers: auth_headers(super_admin), as: :json

      expect(json.dig("data", "review_status")).to eq("rejected")
      expect(Notification.find_by(user:, kind: :article_rejected).body).to include("مكرر")

      get "/api/v1/articles/#{article.id}", headers: auth_headers(user)
      expect(json.dig("data", "rejection_reason")).to eq("مكرر")
      get "/api/v1/articles"
      expect(json["data"]).to be_empty
    end
  end

  describe "editing after review" do
    it "resubmits a rejected firm when its owner edits it, and notifies the super admins again" do
      firm = create(:firm, :rejected, owner: user, category:)
      super_admin

      expect {
        patch "/api/v1/firms/#{firm.id}", params: { firm: { address: "شارع المدرسة" } }, headers: auth_headers(user), as: :json
      }.to change { Notification.where(user: super_admin, kind: :firm_submitted).count }.by(1)

      expect(json.dig("data", "status")).to eq("pending")
      expect(json.dig("data", "rejection_reason")).to be_nil
    end

    it "keeps a moderation suspension when the owner edits" do
      firm = create(:firm, status: :suspended, owner: user, category:)

      patch "/api/v1/firms/#{firm.id}", params: { firm: { name: "اسم جديد" } }, headers: auth_headers(user), as: :json

      expect(firm.reload).to be_suspended
    end

    it "sends a normal user's edit of an approved article back for review" do
      article = create(:article, author: user)
      super_admin

      expect {
        patch "/api/v1/articles/#{article.id}", params: { article: { body: "نص معدل" } }, headers: auth_headers(user), as: :json
      }.to change { Notification.where(user: super_admin, kind: :article_submitted).count }.by(1)

      expect(article.reload).to be_pending
      get "/api/v1/articles"
      expect(json["data"]).to be_empty
    end

    it "keeps a subscribed firm admin's article approved when they edit it" do
      article = create(:article, author: firm_admin)

      patch "/api/v1/articles/#{article.id}", params: { article: { body: "نص معدل" } }, headers: auth_headers(firm_admin), as: :json

      expect(article.reload).to be_approved
    end

    it "forbids editing someone else's article" do
      article = create(:article, author: firm_admin)

      patch "/api/v1/articles/#{article.id}", params: { article: { body: "x" } }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
