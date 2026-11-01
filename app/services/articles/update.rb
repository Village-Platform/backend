module Articles
  # Edits an article, with the same review rule as Firms::Update: an approved article edited by an
  # author who cannot publish directly goes back to pending, and an author's edit of a rejected
  # article resubmits it. Reviewers' edits keep the review status. The push campaign follows the
  # article (Articles::SyncPushCampaign cancels it while the article is not approved).
  class Update
    def self.call(article:, editor:, attributes:) = new(article:, editor:, attributes:).call

    def initialize(article:, editor:, attributes:)
      @article = article
      @editor = editor
      @attributes = attributes
    end

    def call
      submitted = false
      @article.with_lock do
        @article.assign_attributes(@attributes)
        if (submitted = needs_review?)
          @article.review_status = :pending
          @article.rejection_reason = nil
        end
        @article.save!
      end
      Articles::SyncPushCampaign.call(@article)
      notify_reviewers if submitted
      @article
    end

    private

    def needs_review?
      return false if @editor.reviewer? || !@article.changed?

      @article.rejected? || (@article.approved? && !@editor.can_publish_directly?)
    end

    def notify_reviewers
      Submissions::NotifyReviewers.call(record: @article, kind: :article_submitted, screen: "article",
                                        author: @article.author, name: @article.title)
    end
  end
end
