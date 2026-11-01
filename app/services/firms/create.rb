module Firms
  # Creates a firm for its author. Who the author is decides where it starts: reviewers and
  # subscribed firm admins publish directly (active), within the plan's firm quota; everyone else
  # submits it for review (pending), at most User::MAX_PENDING_SUBMISSIONS at a time, and the
  # reviewers are notified.
  class Create
    def self.call(author:, attributes:) = new(author:, attributes:).call

    def initialize(author:, attributes:)
      @author = author
      @attributes = attributes
    end

    def call
      firm = Firm.transaction do
        # Both limits count this author's rows; the lock stops two parallel creates passing them.
        @author.lock!
        build.tap(&:save!)
      end
      notify_reviewers(firm) if firm.pending?
      firm
    end

    private

    def build
      firm = @author.firms.build(@attributes)
      if @author.can_publish_directly?
        raise Submissions::LimitError, "subscription_required" unless @author.can_add_firm?

        # A super admin may pick the status (FirmPolicy#permitted_attributes); otherwise it is live.
        firm.status = :active unless @attributes.key?(:status)
      else
        raise Submissions::LimitError, "too_many_pending" if @author.firms.pending.count >= User::MAX_PENDING_SUBMISSIONS

        firm.status = :pending
      end
      firm
    end

    def notify_reviewers(firm)
      Submissions::NotifyReviewers.call(record: firm, kind: :firm_submitted, screen: "firm", author: @author, name: firm.name)
    end
  end
end
