module Api
  module V1
    class AuthController < BaseController
      # These are how a caller gets a token in the first place.
      skip_before_action :require_api_token!

      # An unauthenticated mint: limit it per IP. An install asks once per token lifetime, so
      # carrier-grade NAT (many phones behind one IP) stays well under this.
      rate_limit to: 30, within: 1.minute, only: :guest,
                 with: -> { render_error(:too_many_requests, "rate_limited") }

      # POST /api/v1/auth/guest -> { data: { token } }
      # For browsing without an account. It names no user: endpoints that need one still answer 401.
      def guest
        render json: { data: { token: issue_guest_token } }, status: :created
      end

      # POST /api/v1/auth/register
      # { "user": { "name", "phone", "email", "password", "password_confirmation" } }
      # Everyone registers as a normal user; roles are granted by a super admin.
      def register
        user = User.create!(register_params)
        Observability::Metrics.increment(:registrations)
        render json: auth_payload(user), status: :created
      end

      # POST /api/v1/auth/login
      # { "phone": "...", "password": "..." }
      def login
        phone = User.normalize_value_for(:phone, params.require(:phone))
        user = User.not_deleted.find_by(phone:)

        if user&.authenticate(params.require(:password))
          Observability::Metrics.increment(:logins, surface: "api", result: "success")
          render json: auth_payload(user)
        else
          Observability::Metrics.increment(:logins, surface: "api", result: "invalid_credentials")
          render_error(:unauthorized, "invalid_credentials")
        end
      end

      private

      def register_params
        params.require(:user).permit(:name, :phone, :email, :password, :password_confirmation)
      end

      def auth_payload(user)
        { data: { token: issue_token_for(user), user: UserSerializer.render(user) } }
      end
    end
  end
end
