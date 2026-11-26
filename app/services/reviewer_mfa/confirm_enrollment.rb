module ReviewerMfa
  # Finishes setting up an authenticator: its first code proves the phone holds the secret. Returns
  # the new recovery codes (plaintext, to show once), or nil when the code is wrong.
  class ConfirmEnrollment
    def self.call(credential:, input:) = new(credential:, input:).call

    def initialize(credential:, input:)
      @credential = credential
      @input = input
    end

    def call
      return nil unless @credential.verify(@input) == :ok

      TotpCredential.transaction do
        @credential.confirm!
        RecoveryCode.regenerate!(@credential.user)
      end
    end
  end
end
