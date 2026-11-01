# A guest's inbox: campaign rows addressed to an install instead of a user. Exactly one of the two,
# enforced by the database, as in topic_subscriptions. A deleted install takes its inbox with it
# (Devices::Register deletes a stale install with delete_all, which a restricting key would block).
class AddDeviceToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_reference :notifications, :device, foreign_key: { on_delete: :cascade }, index: false
    change_column_null :notifications, :user_id, true
    add_check_constraint :notifications, "num_nonnulls(user_id, device_id) = 1", name: "notifications_one_recipient"
    add_index :notifications, %i[ device_id created_at ], where: "device_id IS NOT NULL"
  end
end
