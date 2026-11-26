module Users
  # Deletes a user's account at their request (Google Play account-deletion policy).
  #
  # The users row is kept as an anonymised tombstone: subscriptions are payment records the
  # platform keeps for reconciliation, and they hold a NOT NULL user_id. Everything personal is
  # removed: firms, notifications, payment screenshots, payer phone and notes, and the user's own
  # name / phone / email / password. Their phones become guests and leave the user's push topics.
  # Authentication refuses any user with `deleted_at` set.
  class DeleteAccount
    DELETED_NAME = "حساب محذوف".freeze

    def self.call(user:) = new(user:).call

    def initialize(user:)
      @user = user
    end

    def call
      raise ArgumentError, "Super admins cannot delete their own account" if @user.super_admin?

      @user.with_lock do
        # Firm is soft-deletable: destroy would only hide the rows, and the default scope would skip
        # firms the owner had already deleted. Both kinds hold the user's contact details.
        @user.firms.with_deleted.find_each(&:destroy_fully!)
        @user.notifications.delete_all
        @user.devices.each { |device| Devices::Detach.call(device:) }
        @user.topic_subscriptions.delete_all
        TotpCredential.where(user: @user).delete_all
        RecoveryCode.where(user: @user).delete_all
        @user.subscriptions.find_each do |subscription|
          subscription.payment_screenshot.purge if subscription.payment_screenshot.attached?
          subscription.update_columns(payer_phone: nil, notes: nil)
        end

        @user.update_columns(
          name: DELETED_NAME,
          phone: tombstone_phone,
          email: nil,
          password_digest: BCrypt::Password.create(SecureRandom.base58(32)),
          # update_columns skips the model's revocation callbacks, so revoke here: a restored
          # tombstone must not revive the old tokens.
          token_version: @user.token_version + 1,
          role: User.roles[:user],
          deleted_at: Time.current,
          updated_at: Time.current
        )
      end

      @user
    end

    private

    # Unique per user, unchanged by phone normalization, and longer than the 15 digits a real
    # phone may have, so it can never collide with a number someone registers later.
    def tombstone_phone
      "+#{'0' * 16}#{@user.id}"
    end
  end
end
