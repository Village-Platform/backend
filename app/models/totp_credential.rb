# A reviewer's authenticator app (RFC 6238: 6 digits, 30-second steps, SHA-1, as every authenticator
# app expects). The secret is encrypted at rest; anyone who reads it can mint codes.
#
# Each code works once: #verify advances last_used_timestep with a compare-and-set UPDATE, so two
# requests racing with the same code cannot both pass. Wrong codes count up to a lock that only an
# operator reset clears (lib/tasks/totp.rake). Rails rate_limit is not enough on its own: it lives
# in a per-process memory cache that every deploy empties.
class TotpCredential < ApplicationRecord
  ISSUER = "AghourServices".freeze # ASCII: some authenticator apps render RTL issuers badly
  STEP = 30
  MAX_FAILED_ATTEMPTS = 10
  # An enrollment page reloaded within this window keeps its QR code, so a phone that already
  # scanned it still matches.
  ENROLLMENT_REUSE = 30.minutes

  belongs_to :user

  encrypts :otp_secret
  self.filter_attributes += [ :otp_secret ]

  scope :confirmed, -> { where.not(confirmed_at: nil) }

  # The unconfirmed credential an enrollment page shows. Raises for a user who already has a
  # confirmed one: replacing a device goes through an operator reset.
  def self.enrollment_for!(user)
    transaction do
      credential = lock.find_by(user:)
      raise ArgumentError, "User already has a confirmed authenticator" if credential&.confirmed?

      if credential.nil? || credential.created_at <= ENROLLMENT_REUSE.ago
        credential&.destroy!
        credential = create!(user:, otp_secret: ROTP::Base32.random)
      end
      credential
    end
  end

  def confirmed? = confirmed_at.present?
  def locked? = locked_at.present?

  # otpauth:// URI the QR code carries. The label is the user's name, not their phone number, so the
  # phone keeps no contact details in its account list.
  def provisioning_uri
    totp.provisioning_uri(user.name)
  end

  # :ok, :invalid, :replayed (a valid code that was already used), or :locked.
  def verify(code, at: Time.current)
    return :locked if locked?

    matched_at = code.to_s.match?(/\A\d{6}\z/) && totp.verify(code.to_s, drift_behind: STEP, at:)
    return register_failure unless matched_at

    step = matched_at.to_i / STEP
    advanced = self.class.where(id:, locked_at: nil)
                         .where("last_used_timestep IS NULL OR last_used_timestep < ?", step)
                         .update_all(last_used_timestep: step, failed_attempts: 0, updated_at: Time.current)
    return register_failure(:replayed) if advanced.zero?

    reload
    :ok
  end

  def confirm!
    update!(confirmed_at: Time.current)
  end

  # Counts a wrong code in one UPDATE, locking at MAX_FAILED_ATTEMPTS. An unconfirmed credential never
  # locks: it is still being set up, and starting over replaces it anyway.
  def register_failure(result = :invalid)
    lock_sql = confirmed? ? "CASE WHEN failed_attempts + 1 >= :max THEN :now ELSE locked_at END" : "locked_at"
    self.class.where(id:).update_all(
      [ "failed_attempts = failed_attempts + 1, locked_at = #{lock_sql}, updated_at = :now",
        { max: MAX_FAILED_ATTEMPTS, now: Time.current } ]
    )
    reload
    locked? ? :locked : result
  end

  private

  def totp
    ROTP::TOTP.new(otp_secret, issuer: ISSUER, interval: STEP)
  end
end
