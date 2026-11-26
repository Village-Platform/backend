require "rails_helper"

RSpec.describe TotpCredential do
  let(:credential) { create(:totp_credential, :confirmed) }
  let(:now) { Time.zone.parse("2026-11-25 10:00:15") }

  describe "#verify" do
    it "accepts the current code" do
      expect(credential.verify(totp_code(credential, at: now), at: now)).to eq(:ok)
    end

    it "accepts the previous step's code, for slow typing and small clock drift" do
      expect(credential.verify(totp_code(credential, at: now - 30), at: now)).to eq(:ok)
    end

    it "refuses a code two steps old or one step ahead" do
      expect(credential.verify(totp_code(credential, at: now - 60), at: now)).to eq(:invalid)
      expect(credential.verify(totp_code(credential, at: now + 30), at: now)).to eq(:invalid)
    end

    it "refuses malformed input" do
      [ nil, "", "12345", "1234567", "abcdef", 123_456 ].each do |input|
        expect(credential.verify(input, at: now)).to eq(:invalid)
      end
    end

    it "accepts a code only once" do
      code = totp_code(credential, at: now)

      expect(credential.verify(code, at: now)).to eq(:ok)
      expect(credential.verify(code, at: now + 5)).to eq(:replayed)
    end

    it "refuses an earlier step's code once a later one was used" do
      expect(credential.verify(totp_code(credential, at: now), at: now)).to eq(:ok)
      expect(credential.verify(totp_code(credential, at: now - 30), at: now)).to eq(:replayed)
    end

    it "locks after ten wrong codes and then refuses even the right one" do
      9.times { expect(credential.verify("000000", at: now)).to eq(:invalid) }
      expect(credential.verify("000000", at: now)).to eq(:locked)

      expect(credential.verify(totp_code(credential, at: now), at: now)).to eq(:locked)
      expect(credential.reload).to be_locked
    end

    it "resets the failure count on success" do
      5.times { credential.verify("000000", at: now) }
      credential.verify(totp_code(credential, at: now), at: now)

      expect(credential.reload.failed_attempts).to eq(0)
    end

    it "never locks a credential that is still being set up" do
      unconfirmed = create(:totp_credential)
      12.times { unconfirmed.verify("000000", at: now) }

      expect(unconfirmed.reload).not_to be_locked
    end

    # Two requests load the row before either writes. The guard is the UPDATE condition, not the
    # in-memory value, so the second one loses even though its copy still says the code is unused.
    it "lets only one of two requests holding stale copies use the same code" do
      code = totp_code(credential, at: now)
      copies = Array.new(2) { TotpCredential.find(credential.id) }

      results = copies.map { _1.verify(code, at: now) }

      expect(results).to contain_exactly(:ok, :replayed)
    end
  end

  describe ".enrollment_for!" do
    let(:user) { create(:user, :admin) }

    it "keeps the same secret when the page is reloaded soon after" do
      first = described_class.enrollment_for!(user)

      expect(described_class.enrollment_for!(user).otp_secret).to eq(first.otp_secret)
    end

    it "starts over with a new secret after the reuse window" do
      first = described_class.enrollment_for!(user)

      travel 31.minutes do
        expect(described_class.enrollment_for!(user).otp_secret).not_to eq(first.otp_secret)
      end
      expect(described_class.where(user:).count).to eq(1)
    end

    it "refuses to replace a confirmed authenticator" do
      create(:totp_credential, :confirmed, user:)

      expect { described_class.enrollment_for!(user) }.to raise_error(ArgumentError)
    end
  end

  it "stores the secret encrypted" do
    raw = described_class.connection.select_value("SELECT otp_secret FROM totp_credentials WHERE id = #{credential.id}")

    expect(raw).not_to include(credential.otp_secret)
  end

  it "labels the authenticator entry with the user's name, not their phone" do
    uri = credential.provisioning_uri

    expect(uri).to start_with("otpauth://totp/")
    expect(uri).to include("issuer=AghourServices")
    expect(uri).not_to include(credential.user.phone)
  end
end
