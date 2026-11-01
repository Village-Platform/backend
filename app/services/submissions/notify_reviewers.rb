module Submissions
  # Tells the super admins that a firm or article waits for review: an inbox row and a push that
  # opens the record. Admins review too, but are not notified: they work from the dashboard's
  # pending counters. Super admins can open pending records (their policy scope is all rows), so the
  # firm / article screens already work on old app versions.
  #
  # Runs after the submission has committed, and never raises: a failed notification must not undo
  # or fail the submission. The dedupe key carries updated_at, so a resubmission notifies again
  # while a retried call does not.
  module NotifyReviewers
    def self.call(record:, kind:, screen:, author:, name:)
      destination = Notifications::Destination.new(screen:, id: record.id)
      User.super_admin.where.not(id: author.id).find_each do |reviewer|
        Notifier.notify(
          user: reviewer,
          kind:,
          dedupe_key: "#{screen}:#{record.id}:submitted:#{record.updated_at.to_i}:#{reviewer.id}",
          data: { "#{screen}_id": record.id },
          destination:,
          author: author.name,
          name:
        )
      rescue StandardError => e
        Rails.logger.error("[Submissions::NotifyReviewers] #{screen}_id=#{record.id} reviewer_id=#{reviewer.id} #{e.class}: #{e.message}")
      end
    end
  end
end
