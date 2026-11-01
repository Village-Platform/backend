module ErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound do
      render_error(:not_found, "not_found")
    end

    rescue_from ActiveRecord::RecordInvalid do |e|
      render_error(:unprocessable_content, "validation_failed", details: e.record.errors.to_hash(true))
    end

    # Race on a unique index (e.g. same transfer reference submitted twice at once).
    rescue_from ActiveRecord::RecordNotUnique do
      render_error(:conflict, "duplicate")
    end

    rescue_from Subscriptions::ReviewError do
      render_error(:unprocessable_content, "invalid_state")
    end

    rescue_from Submissions::ReviewError do
      render_error(:unprocessable_content, "already_reviewed")
    end

    # Firm quota (subscription_required) or the cap on submissions waiting for review.
    rescue_from Submissions::LimitError do |e|
      render_error(:forbidden, e.code)
    end

    rescue_from ActionController::ParameterMissing do |e|
      render_error(:bad_request, "bad_request", details: { param: e.param })
    end

    rescue_from Devices::OwnershipError do
      render_error(:forbidden, "forbidden")
    end

    rescue_from Pundit::NotAuthorizedError do
      current_user ? render_error(:forbidden, "forbidden") : render_error(:unauthorized, "unauthorized")
    end
  end

  private

  # Consistent error shape:
  # { "error": { "code": "not_found", "message": "...", "details": {...} } }
  def render_error(status, code, details: nil)
    Observability::Metrics.increment(:api_errors, code:, status: Rack::Utils.status_code(status))
    body = { code:, message: I18n.t("errors.api.#{code}") }
    body[:details] = details if details.present?
    render json: { error: body }, status:
  end
end
