# Reads the signed-in reviewer (super admin or admin) from the cookie session used by the dashboard.
# Admin::BaseController then limits admins to the review pages.
#
# With two-factor sign-in on (ReviewerMfa), a correct password only starts a short pending step;
# the reviewer is signed in once the authenticator code is checked (Admin::SecondFactorsController).
module AdminSession
  TTL = 12.hours
  # Long enough to install an authenticator app and scan the QR code during a first setup.
  PENDING_TTL = 10.minutes

  def self.sign_in(session, user, second_factor: false)
    session[:admin_user_id] = user.id
    session[:admin_signed_in_at] = Time.current.to_i
    session[:admin_second_factor] = second_factor
    remember_token_version(session, user)
  end

  # Keeps this session valid after the admin changes their own password from it, without extending
  # its TTL. Every other session of theirs, and every API token, is still revoked.
  def self.remember_token_version(session, user)
    session[:admin_token_version] = user.token_version
  end

  # Returns the reviewer, or nil when missing, expired, revoked, no longer a reviewer, or signed in
  # without the code their sign-in now requires (e.g. they set up an authenticator since).
  def self.find_admin(session)
    user_id = session[:admin_user_id]
    signed_in_at = session[:admin_signed_in_at]
    return nil if user_id.blank? || signed_in_at.blank?
    return nil if Time.zone.at(signed_in_at.to_i) < TTL.ago

    user = User.reviewers.find_by(id: user_id)
    return nil unless user&.token_version_current?(session_version(session))
    return nil if ReviewerMfa.required_for?(user) && !session[:admin_second_factor]

    user
  end

  # nil for a session signed in before versions existed.
  def self.session_version(session)
    session[:admin_token_version]
  end

  # The password was right; the code step comes next.
  def self.begin_second_factor(session, user)
    session[:admin_pending_user_id] = user.id
    session[:admin_pending_at] = Time.current.to_i
    session[:admin_pending_version] = user.token_version
  end

  # The reviewer who passed the password step in the last PENDING_TTL, or nil.
  def self.pending_reviewer(session)
    user_id = session[:admin_pending_user_id]
    started_at = session[:admin_pending_at]
    return nil if user_id.blank? || started_at.blank?
    return nil if Time.zone.at(started_at.to_i) < PENDING_TTL.ago

    user = User.reviewers.find_by(id: user_id)
    user if user&.token_version_current?(session[:admin_pending_version])
  end
end
