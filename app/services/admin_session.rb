# Reads the signed-in reviewer (super admin or admin) from the cookie session used by the dashboard.
# Admin::BaseController then limits admins to the review pages.
module AdminSession
  TTL = 12.hours

  def self.sign_in(session, user)
    session[:admin_user_id] = user.id
    session[:admin_signed_in_at] = Time.current.to_i
  end

  # Returns the reviewer, or nil when missing, expired, or no longer a reviewer.
  def self.find_admin(session)
    user_id = session[:admin_user_id]
    signed_in_at = session[:admin_signed_in_at]
    return nil if user_id.blank? || signed_in_at.blank?
    return nil if Time.zone.at(signed_in_at.to_i) < TTL.ago

    User.reviewers.find_by(id: user_id)
  end
end
