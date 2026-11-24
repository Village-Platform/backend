module ReviewerMfa
  # Checks what a reviewer typed at the code step: a 6-digit authenticator code, or one of their
  # recovery codes. Wrong recovery codes count toward the same lock as wrong authenticator codes.
  #
  # Returns :ok, :recovery_code (a recovery code was used up), :invalid, :replayed or :locked.
  class CheckCode
    def self.call(credential:, input:) = new(credential:, input:).call

    def initialize(credential:, input:)
      @credential = credential
      @input = input.to_s.strip
    end

    def call
      return :locked if @credential.locked?
      return @credential.verify(@input) if @input.match?(/\A\d{6}\z/)
      return :recovery_code if RecoveryCode.consume(@credential.user, @input)

      @credential.register_failure
    end
  end
end
