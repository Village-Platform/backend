module Admin
  # Second sign-in step: the code from the reviewer's authenticator app, or one of their recovery
  # codes. Reached only from a password step finished in the last few minutes (AdminSession).
  # Sits outside BaseController for the same reason SessionsController does: nobody is signed in yet.
  class SecondFactorsController < ActionController::Base
    layout "admin_auth"

    rate_limit to: 10, within: 3.minutes, only: :create,
               with: -> {
                 Observability::Metrics.increment(:logins, surface: "admin", result: "rate_limited")
                 redirect_to new_admin_second_factor_path, alert: I18n.t("admin.sessions.too_many_attempts")
               }

    # A form from a session that has since ended (signed out, timed out) fails the CSRF check.
    # Start the sign-in over rather than showing an error page.
    rescue_from ActionController::InvalidAuthenticityToken do
      reset_session
      redirect_to admin_login_path, alert: I18n.t("admin.second_factors.expired")
    end

    around_action :use_arabic
    before_action :set_reviewer
    before_action :set_credential

    # GET /admin/second_factor/new
    def new; end

    # POST /admin/second_factor
    def create
      result = ReviewerMfa::CheckCode.call(credential: @credential, input: params[:otp])

      if result.in?(%i[ ok recovery_code ])
        Observability::Metrics.increment(:logins, surface: "admin", result: result == :ok ? "mfa_success" : "recovery_code_used")
        reset_session # a new session id for the signed-in state
        AdminSession.sign_in(session, @reviewer, second_factor: true)
        redirect_to admin_root_path, notice: recovery_notice(result)
      else
        Observability::Metrics.increment(:logins, surface: "admin", result: "mfa_#{result}")
        flash.now[:alert] = I18n.t(result == :locked ? "admin.second_factors.locked" : "admin.second_factors.invalid")
        render :new, status: :unprocessable_content
      end
    end

    private

    def set_reviewer
      @reviewer = AdminSession.pending_reviewer(session)
      return if @reviewer

      reset_session
      redirect_to admin_login_path, alert: I18n.t("admin.second_factors.expired")
    end

    # A reviewer without a finished setup belongs on the setup page, not here.
    def set_credential
      @credential = TotpCredential.confirmed.find_by(user: @reviewer)
      redirect_to new_admin_authenticator_path unless @credential
    end

    def recovery_notice(result)
      return unless result == :recovery_code

      I18n.t("admin.second_factors.recovery_code_used", count: RecoveryCode.remaining(@reviewer))
    end

    def use_arabic(&action)
      I18n.with_locale(:ar, &action)
    end
  end
end
