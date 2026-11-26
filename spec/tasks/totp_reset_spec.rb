require "rails_helper"
require "rake"

RSpec.describe "totp:reset" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { _1.name == "totp:reset" } }

  let(:task) { Rake::Task["totp:reset"] }
  let(:admin) { create(:user, :admin) }

  after { task.reenable }

  it "removes the authenticator and recovery codes and revokes every session and token" do
    create(:totp_credential, :confirmed, user: admin, locked_at: Time.current)
    RecoveryCode.regenerate!(admin)

    expect { task.invoke(admin.id.to_s, "ops-person") }.to output(/reset for user #{admin.id}/).to_stdout

    expect(TotpCredential.where(user: admin)).to be_empty
    expect(RecoveryCode.where(user: admin)).to be_empty
    expect(admin.reload.token_version).to eq(1)
  end

  it "refuses to run without an operator name" do
    expect { task.invoke(admin.id.to_s) }.to raise_error(SystemExit)
  end
end
