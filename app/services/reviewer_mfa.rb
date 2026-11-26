# Who needs an authenticator code to reach the dashboard, per REVIEWER_MFA_MODE
# (config/application.rb). Only reviewers sign in to the dashboard, so only they are asked.
module ReviewerMfa
  MODES = %w[ off optional required ].freeze

  def self.mode = Rails.configuration.x.reviewer_mfa_mode
  def self.enabled? = mode != "off"

  # Whether a password alone is not enough for this reviewer.
  def self.required_for?(user)
    case mode
    when "required" then true
    when "optional" then user.totp_enabled?
    else false
    end
  end

  # Whether this reviewer may set up an authenticator now: only while the feature is on, and only
  # once. A second device replaces the first through an operator reset, never from the dashboard,
  # so a stolen session cannot swap in the thief's phone.
  def self.may_enroll?(user)
    enabled? && !user.totp_enabled?
  end
end
