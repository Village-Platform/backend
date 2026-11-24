# Fail at boot, not at a reviewer's first sign-in, when the TOTP setup is incomplete.
# The list repeats ReviewerMfa::MODES: app/ constants cannot be autoloaded while initializers run.
mode = Rails.configuration.x.reviewer_mfa_mode
unless %w[ off optional required ].include?(mode)
  raise ArgumentError, "REVIEWER_MFA_MODE must be off, optional or required, got #{mode.inspect}"
end

if mode != "off"
  encryption = Rails.configuration.active_record.encryption
  missing = %i[ primary_key deterministic_key key_derivation_salt ].select { encryption.public_send(_1).blank? }
  if missing.any?
    raise "REVIEWER_MFA_MODE=#{mode} needs Active Record Encryption keys (missing: #{missing.join(', ')}). " \
          "Generate them with bin/rails db:encryption:init."
  end
end
