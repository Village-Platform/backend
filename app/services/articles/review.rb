module Articles
  # A reviewer's decision on an article. Approving makes it live at its published_at (now, if the
  # author left it empty) and lets its push campaign be scheduled; rejecting a pending article keeps
  # it hidden with a reason the author sees. Both record who decided and tell the author, after the
  # commit: a failed notification never undoes a decision.
  class Review
    def self.approve(article:, reviewer:) = new(article:, reviewer:).approve
    def self.reject(article:, reviewer:, reason:) = new(article:, reviewer:).reject(reason)

    def initialize(article:, reviewer:)
      @article = article
      @reviewer = reviewer
    end

    def approve
      decide(:approved, rejection_reason: nil) do
        raise Submissions::ReviewError, "Article is already approved" if @article.approved?

        @article.published_at ||= Time.current
      end
      Articles::SyncPushCampaign.call(@article)
      notify_author(:article_approved)
    end

    def reject(reason)
      decide(:rejected, rejection_reason: reason) do
        raise Submissions::ReviewError, "Article is not pending" unless @article.pending?
      end
      notify_author(:article_rejected, reason:)
    end

    private

    def decide(review_status, rejection_reason:)
      @article.with_lock do
        yield
        @article.update!(review_status:, rejection_reason:, reviewed_by: @reviewer, reviewed_at: Time.current)
      end
      Observability::Metrics.increment(:submissions_reviewed, type: "article", outcome: review_status.to_s)
    end

    def notify_author(kind, **interpolations)
      return @article if @article.author_id == @reviewer.id

      Notifier.notify(
        user: @article.author,
        kind:,
        dedupe_key: "article:#{@article.id}:#{kind}:#{@article.reviewed_at.to_i}",
        data: { article_id: @article.id },
        destination: Notifications::Destination.new(screen: "article", id: @article.id),
        name: @article.title,
        **interpolations
      )
      @article
    rescue StandardError => e
      Rails.logger.error("[Articles::Review] notification failed article_id=#{@article.id} #{e.class}: #{e.message}")
      @article
    end
  end
end
