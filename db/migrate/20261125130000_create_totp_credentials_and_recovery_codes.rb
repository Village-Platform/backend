# Reviewer two-factor sign-in (docs/reviewer-totp-design.md). Both tables start empty, so their
# indexes need no concurrent build.
class CreateTotpCredentialsAndRecoveryCodes < ActiveRecord::Migration[8.1]
  def change
    # One authenticator per user. An unconfirmed row is an enrollment whose first code has not been
    # entered yet; only a confirmed one counts at sign-in.
    create_table :totp_credentials do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :otp_secret, null: false # Active Record Encryption ciphertext
      t.datetime :confirmed_at
      t.bigint :last_used_timestep # replay guard: the 30-second step of the last accepted code
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :locked_at # too many wrong codes; cleared only by bin/rails "totp:reset[USER_ID]"
      t.timestamps
    end

    # Single-use codes for a lost phone, stored as HMAC digests only.
    create_table :recovery_codes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :code_digest, null: false, index: { unique: true }
      t.datetime :used_at
      t.timestamps
    end
  end
end
