module Admin
  # One queue for everything waiting on a reviewer. Approve / reject stay on the firm and article
  # controllers (and their Review services); this page only gathers the links.
  class ReviewsController < BaseController
    allow_reviewers :index

    def index
      @firms = Firm.pending.includes(:category, :owner).order(:created_at).limit(50)
      @articles = Article.pending.includes(:author).order(:created_at).limit(50)
    end
  end
end
