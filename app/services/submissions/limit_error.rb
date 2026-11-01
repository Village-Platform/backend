module Submissions
  # A create refused before it reaches the database. `code` is the API error code
  # (errors.api.<code>): subscription_required for the firm quota, too_many_pending for the cap on
  # submissions waiting for review.
  class LimitError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super("Submission refused: #{code}")
    end
  end
end
