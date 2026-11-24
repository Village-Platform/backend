module Admin
  # Login page for the dashboard. Super admins and admins (reviewers) can sign in.
  class SessionsController < ActionController::Base
    layout "admin_auth"

    rate_limit to: 10, within: 3.minutes, only: :create,
               with: -> {
                 Observability::Metrics.increment(:logins, surface: "admin", result: "rate_limited")
                 redirect_to admin_login_path, alert: I18n.t("admin.sessions.too_many_attempts")
               }

    around_action :use_arabic

    def new
      redirect_to admin_root_path if AdminSession.find_admin(session)
    end

    def create
      user = User.find_by(phone: User.normalize_value_for(:phone, params[:phone].to_s))

      if user&.reviewer? && user.authenticate(params[:password].to_s)
        reset_session # prevent session fixation
        if ReviewerMfa.required_for?(user)
          # The password alone signs nobody in: the authenticator code (or its setup) comes next.
          Observability::Metrics.increment(:logins, surface: "admin", result: "mfa_required")
          AdminSession.begin_second_factor(session, user)
          redirect_to user.totp_enabled? ? new_admin_second_factor_path : new_admin_authenticator_path
        else
          Observability::Metrics.increment(:logins, surface: "admin", result: "success")
          AdminSession.sign_in(session, user)
          redirect_to admin_root_path
        end
      else
        Observability::Metrics.increment(:logins, surface: "admin", result: "invalid_credentials")
        flash.now[:alert] = I18n.t("admin.sessions.invalid")
        render :new, status: :unprocessable_content
      end
    end

    def destroy
      reset_session
      redirect_to admin_login_path, notice: I18n.t("admin.sessions.signed_out")
    end

    private

    def use_arabic(&action)
      I18n.with_locale(:ar, &action)
    end
  end
end
