require "rails_helper"

RSpec.describe RecoveryCode do
  let(:user) { create(:user, :admin) }

  it "issues ten formatted codes and stores only digests" do
    codes = described_class.regenerate!(user)

    expect(codes.size).to eq(10)
    expect(codes).to all(match(/\A[A-Z2-9]{5}-[A-Z2-9]{5}\z/))
    stored = described_class.where(user:).pluck(:code_digest)
    expect(stored.size).to eq(10)
    expect(stored & codes.map { described_class.normalize(_1) }).to be_empty
  end

  it "replaces the previous codes" do
    old = described_class.regenerate!(user)
    described_class.regenerate!(user)

    expect(described_class.consume(user, old.first)).to be(false)
  end

  it "accepts each code once, in any case and with or without the dash or spaces" do
    code = described_class.regenerate!(user).first

    expect(described_class.consume(user, " #{code.downcase.delete('-')} ")).to be(true)
    expect(described_class.consume(user, code)).to be(false)
    expect(described_class.remaining(user)).to eq(9)
  end

  it "does not accept another user's code" do
    code = described_class.regenerate!(create(:user, :admin)).first

    expect(described_class.consume(user, code)).to be(false)
  end
end
