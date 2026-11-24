module ReviewerMfaHelpers
  def with_reviewer_mfa_mode(mode)
    previous = Rails.configuration.x.reviewer_mfa_mode
    Rails.configuration.x.reviewer_mfa_mode = mode
    yield
  ensure
    Rails.configuration.x.reviewer_mfa_mode = previous
  end

  def totp_code(credential, at: Time.current)
    ROTP::TOTP.new(credential.otp_secret).at(at)
  end
end

RSpec.configure do |config|
  config.include ReviewerMfaHelpers
  config.around(:each, :reviewer_mfa) do |example|
    with_reviewer_mfa_mode(example.metadata[:reviewer_mfa]) { example.run }
  end
end
