module Authentication
  extend ActiveSupport::Concern

  # Guest tokens (POST /api/v1/auth/guest) carry this "typ" and no "sub"; user tokens carry no typ.
  GUEST_TOKEN_TYPE = "guest".freeze

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = user_from_token
  end

  def authenticate_user!
    render_error(:unauthorized, "unauthorized") unless current_user
  end

  # Every API call carries a token: a user's, or a guest's. Enforced only when API_TOKEN_REQUIRED
  # is set, so app versions that predate guest tokens keep working until the switch is flipped;
  # until then tokenless calls are counted, which is how you know when it is safe to flip.
  def require_api_token!
    return if current_user || guest_token?

    enforced = Rails.configuration.x.api_token_required
    Observability::Metrics.increment(:tokenless_api_requests, result: enforced ? "rejected" : "allowed")
    render_error(:unauthorized, "unauthorized") if enforced
  end

  def guest_token?
    token_payload&.dig("typ") == GUEST_TOKEN_TYPE
  end

  def token_payload
    return @token_payload if defined?(@token_payload)

    scheme, token = request.authorization.to_s.split(" ", 2)
    @token_payload = scheme&.casecmp?("Bearer") ? JsonWebToken.decode(token) : nil
  end

  # Only an untyped token names a user. Without this check a guest token would reach find_by, and
  # PostgreSQL casts a string such as "12abc" to the id 12.
  def user_from_token
    payload = token_payload
    return nil if payload.nil? || payload.key?("typ")

    User.not_deleted.find_by(id: payload["sub"])
  end

  def issue_token_for(user)
    JsonWebToken.encode({ sub: user.id })
  end

  def issue_guest_token
    JsonWebToken.encode({ typ: GUEST_TOKEN_TYPE })
  end
end
