require "rails_helper"

RSpec.describe "Admin review of firm and article submissions", type: :request do
  let(:author) { create(:user) }
  let(:firm) { create(:firm, :pending, owner: author) }
  let(:article) { create(:article, :pending, author:, published_at: nil) }

  context "as a super admin" do
    let!(:reviewer) { sign_in_admin }

    it "approves a firm through the review service and tells the owner" do
      patch "/admin/firms/#{firm.id}/approve"

      expect(firm.reload).to be_active
      expect(firm.reviewed_by).to eq(reviewer)
      expect(Notification.where(user: author, kind: :firm_approved).count).to eq(1)
    end

    it "still lifts a moderation suspension" do
      suspended = create(:firm, status: :suspended)

      patch "/admin/firms/#{suspended.id}/approve"

      expect(suspended.reload).to be_active
    end

    it "rejects a firm with a reason, and requires one" do
      patch "/admin/firms/#{firm.id}/reject", params: { reason: " " }
      expect(firm.reload).to be_pending
      expect(flash[:alert]).to be_present

      patch "/admin/firms/#{firm.id}/reject", params: { reason: "بيانات ناقصة" }
      expect(firm.reload).to be_rejected
      expect(firm.rejection_reason).to eq("بيانات ناقصة")
      expect(Notification.where(user: author, kind: :firm_rejected).count).to eq(1)
    end

    it "approves an article: published now, author told" do
      patch "/admin/articles/#{article.id}/approve"

      expect(article.reload).to be_approved
      expect(article).to be_published
      expect(Notification.where(user: author, kind: :article_approved).count).to eq(1)
    end

    it "rejects an article once" do
      patch "/admin/articles/#{article.id}/reject", params: { reason: "مكرر" }
      expect(article.reload).to be_rejected

      patch "/admin/articles/#{article.id}/reject", params: { reason: "مكرر" }
      expect(flash[:alert]).to be_present
    end

    it "shows the review form and the pending counters" do
      firm
      article

      get "/admin/firms/#{firm.id}"
      expect(response.body).to include("سبب الرفض", "مراجعة النشاط")

      get "/admin/articles/#{article.id}"
      expect(response.body).to include("مراجعة الخبر", "اعتماد ونشر")

      get "/admin/articles", params: { review_status: "pending" }
      expect(response.body).to include(article.title)
      expect(response.body).to include(%(<span class="nav-count">1</span>))
    end

    it "does not schedule a push for an article until it is approved" do
      article.update!(notify_topic: create(:topic), published_at: 1.hour.from_now)
      Articles::SyncPushCampaign.call(article)
      expect(article.reload.push_campaign).to be_nil

      patch "/admin/articles/#{article.id}/approve"
      expect(article.reload.push_campaign).to be_scheduled
    end
  end

  context "as an admin (reviewer)" do
    let!(:reviewer) { sign_in_admin(create(:user, :admin, password: "password123")) }

    it "can sign in and lands on the firms waiting for review" do
      get "/admin"

      expect(response).to redirect_to("/admin/firms?status=pending")
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("مراجعة المحتوى")
      expect(response.body).not_to include("/admin/users")
    end

    it "reviews firms and articles" do
      patch "/admin/firms/#{firm.id}/approve"
      expect(firm.reload).to be_active
      expect(firm.reviewed_by).to eq(reviewer)

      patch "/admin/articles/#{article.id}/reject", params: { reason: "غير موثق" }
      expect(article.reload).to be_rejected

      get "/admin/firms/#{firm.id}"
      expect(response).to have_http_status(:ok)
      get "/admin/articles/#{article.id}"
      expect(response).to have_http_status(:ok)
    end

    it "cannot lift a moderation suspension" do
      suspended = create(:firm, status: :suspended)

      patch "/admin/firms/#{suspended.id}/approve"

      expect(suspended.reload).to be_suspended
      expect(flash[:alert]).to be_present
    end

    it "is kept out of every other dashboard page and action" do
      [
        -> { get "/admin/users" },
        -> { get "/admin/subscriptions" },
        -> { get "/admin/firms/#{firm.id}/edit" },
        -> { patch "/admin/firms/#{firm.id}/suspend" },
        -> { delete "/admin/firms/#{firm.id}" },
        -> { delete "/admin/articles/#{article.id}" },
        -> { get "/admin/search", params: { q: "x" } }
      ].each do |request|
        request.call
        expect(response).to redirect_to("/admin/firms?status=pending")
      end

      expect(firm.reload).to be_pending
      expect(Firm.exists?(firm.id)).to be(true)
      expect(Article.exists?(article.id)).to be(true)
    end
  end

  it "refuses a firm admin at the dashboard login" do
    owner = create(:user, :subscribed, password: "password123")

    post "/admin/login", params: { phone: owner.phone, password: "password123" }

    expect(response).to have_http_status(:unprocessable_content)
  end
end
