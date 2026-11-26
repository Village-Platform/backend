# Single-use codes a reviewer keeps for a lost phone. Only an HMAC of each code is stored: the codes
# are random enough (about 50 bits) that a keyed hash is safe without bcrypt's slowness, and the
# plaintext is shown exactly once, right after enrollment.
class RecoveryCode < ApplicationRecord
  COUNT = 10
  LENGTH = 10
  ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze # no 0/O or 1/I look-alikes
  FORMAT = /\A[#{ALPHABET.join}]{#{LENGTH}}\z/

  belongs_to :user

  # Replaces the user's codes and returns the new plaintext codes, formatted for display.
  def self.regenerate!(user)
    codes = Array.new(COUNT) { Array.new(LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join }
    transaction do
      where(user:).delete_all
      now = Time.current
      insert_all!(codes.map { { user_id: user.id, code_digest: digest(user, _1), created_at: now, updated_at: now } })
    end
    codes.map { _1.scan(/.{5}/).join("-") }
  end

  # Uses up the code if it is one of the user's unused codes. One UPDATE, so a code cannot be spent twice.
  def self.consume(user, input)
    code = normalize(input)
    return false unless code.match?(FORMAT)

    where(user:, code_digest: digest(user, code), used_at: nil).update_all(used_at: Time.current) == 1
  end

  def self.remaining(user) = where(user:, used_at: nil).count

  def self.normalize(input) = input.to_s.upcase.gsub(/[\s-]/, "")

  def self.digest(user, code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "recovery-code:#{user.id}:#{code}")
  end
end
