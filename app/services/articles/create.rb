module Articles
  # Creates an article for its author. Reviewers and subscribed firm admins publish directly
  # (approved: live at published_at); everyone else submits it for review (pending), at most
  # User::MAX_PENDING_SUBMISSIONS at a time, and the reviewers are notified.
  class Create
    def self.call(author:, attributes:) = new(author:, attributes:).call

    def initialize(author:, attributes:)
      @author = author
      @attributes = attributes
    end

    def call
      article = Article.transaction do
        @author.lock! # the pending cap counts this author's rows; parallel creates wait here
        build.tap(&:save!)
      end
      notify_reviewers(article) if article.pending?
      article
    end

    private

    def build
      article = @author.articles.build(@attributes)
      if @author.can_publish_directly?
        article.review_status = :approved
      else
        raise Submissions::LimitError, "too_many_pending" if @author.articles.pending.count >= User::MAX_PENDING_SUBMISSIONS

        article.review_status = :pending
      end
      article
    end

    def notify_reviewers(article)
      Submissions::NotifyReviewers.call(record: article, kind: :article_submitted, screen: "article", author: @author, name: article.title)
    end
  end
end
