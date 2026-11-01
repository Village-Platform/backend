module Firms
  # Edits a firm, and decides whether the edit needs review:
  # - an edit of an approved (active) firm by an owner who cannot publish directly sends it back:
  #   it turns pending, drops out of the public lists and returns once a reviewer approves it, so a
  #   firm cannot change its name or phone after approval unseen;
  # - an owner's edit of a rejected firm resubmits it (pending again, the old reason cleared).
  # Edits by reviewers, by subscribed firm admins of their active firms, edits of pending or
  # moderation-suspended firms, and saves that change nothing keep the status. A firm that turns
  # pending notifies the reviewers.
  class Update
    def self.call(firm:, editor:, attributes:) = new(firm:, editor:, attributes:).call

    def initialize(firm:, editor:, attributes:)
      @firm = firm
      @editor = editor
      @attributes = attributes
    end

    def call
      submitted = false
      # with_lock reloads the row, so the attributes are assigned inside it: an approval saved at
      # the same moment is either seen here or waits for this save, never overwritten.
      @firm.with_lock do
        @firm.assign_attributes(@attributes)
        if (submitted = needs_review?)
          @firm.status = :pending
          @firm.rejection_reason = nil
        end
        @firm.save!
      end
      notify_reviewers if submitted
      @firm
    end

    private

    def needs_review?
      return false if @editor.reviewer? || !@firm.changed?

      @firm.rejected? || (@firm.active? && !@editor.can_publish_directly?)
    end

    def notify_reviewers
      Submissions::NotifyReviewers.call(record: @firm, kind: :firm_submitted, screen: "firm", author: @firm.owner, name: @firm.name)
    end
  end
end
