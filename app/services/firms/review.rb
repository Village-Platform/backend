module Firms
  # A reviewer's decision on a firm. Approving makes it active (from pending or rejected; lifting a
  # moderation suspension takes a super admin); rejecting a pending firm suspends it with a reason the owner sees. Both record who
  # decided and tell the owner, after the commit: a failed notification never undoes a decision.
  #
  # Approval does not make a firm public on its own: Firm.visible still needs the owner's current
  # subscription (or a reviewer owner).
  class Review
    def self.approve(firm:, reviewer:) = new(firm:, reviewer:).approve
    def self.reject(firm:, reviewer:, reason:) = new(firm:, reviewer:).reject(reason)

    def initialize(firm:, reviewer:)
      @firm = firm
      @reviewer = reviewer
    end

    def approve
      decide(:active, rejection_reason: nil) do
        raise Submissions::ReviewError, "Firm is already active" if @firm.active?
        if @firm.suspended? && !@firm.rejected? && !@reviewer.super_admin?
          raise Submissions::ReviewError, "Only a super admin lifts a suspension"
        end
      end
      notify_owner(:firm_approved)
    end

    def reject(reason)
      decide(:suspended, rejection_reason: reason) do
        raise Submissions::ReviewError, "Firm is not pending" unless @firm.pending?
      end
      notify_owner(:firm_rejected, reason:)
    end

    private

    def decide(status, rejection_reason:)
      @firm.with_lock do
        yield
        @firm.update!(status:, rejection_reason:, reviewed_by: @reviewer, reviewed_at: Time.current)
      end
      Observability::Metrics.increment(:submissions_reviewed, type: "firm", outcome: status == :active ? "approved" : "rejected")
    end

    def notify_owner(kind, **interpolations)
      return @firm if @firm.owner_id == @reviewer.id

      Notifier.notify(
        user: @firm.owner,
        kind:,
        dedupe_key: "firm:#{@firm.id}:#{kind}:#{@firm.reviewed_at.to_i}",
        data: { firm_id: @firm.id },
        destination: Notifications::Destination.new(screen: "firm", id: @firm.id),
        name: @firm.name,
        **interpolations
      )
      @firm
    rescue StandardError => e
      Rails.logger.error("[Firms::Review] notification failed firm_id=#{@firm.id} #{e.class}: #{e.message}")
      @firm
    end
  end
end
