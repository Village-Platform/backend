module Admin
  # Setting up a reviewer's authenticator app: a QR code to scan, then its first code to confirm.
  # Open to a reviewer in the middle of signing in (REVIEWER_MFA_MODE=required and no device yet) or
  # to a signed-in reviewer setting one up by choice (optional). Each reviewer sets up one device;
  # replacing it is an operator reset (lib/tasks/totp.rake), so a stolen session cannot swap phones.
  class AuthenticatorsController < ActionController::Base
    layout "admin_auth"

    rate_limit to: 10, within: 3.minutes, only: :create,
               with: -> { redirect_to new_admin_authenticator_path, alert: I18n.t("admin.sessions.too_many_attempts") }

    # A form from a session that has since ended (signed out, timed out) fails the CSRF check.
    # Start the sign-in over rather than showing an error page.
    rescue_from ActionController::InvalidAuthenticityToken do
      reset_session
      redirect_to admin_login_path, alert: I18n.t("admin.second_factors.expired")
    end

    around_action :use_arabic
    before_action :no_store # the page carries the secret, and later the recovery codes
    before_action :set_reviewer

    # GET /admin/authenticator/new
    def new
      @credential = TotpCredential.enrollment_for!(@reviewer)
    end

    # POST /admin/authenticator
    def create
      @credential = TotpCredential.find_by(user: @reviewer, confirmed_at: nil)
      return redirect_to(new_admin_authenticator_path) unless @credential

      @recovery_codes = ReviewerMfa::ConfirmEnrollment.call(credential: @credential, input: params[:otp])
      if @recovery_codes
        Observability::Metrics.increment(:logins, surface: "admin", result: "mfa_enrolled")
        reset_session
        AdminSession.sign_in(session, @reviewer, second_factor: true)
      else
        flash.now[:alert] = I18n.t("admin.authenticators.invalid")
        render :new, status: :unprocessable_content
      end
    end

    private

    def set_reviewer
      @reviewer = AdminSession.find_admin(session) || AdminSession.pending_reviewer(session)
      return if @reviewer && ReviewerMfa.may_enroll?(@reviewer)

      redirect_to(AdminSession.find_admin(session) ? admin_root_path : admin_login_path)
    end

    def use_arabic(&action)
      I18n.with_locale(:ar, &action)
    end
  end
end
