# An FCM topic whose membership this database owns. FCM cannot list a topic's members, so FCM holds
# a mirror kept in step by SyncDeviceTopicsJob; drift is repaired by re-syncing, never by reading FCM.
class Topic < ApplicationRecord
  EVERYONE_KEY = "all"

  # The key is the FCM topic name and the apps' contract: renaming it would orphan every subscriber.
  attr_readonly :key

  has_many :topic_subscriptions, dependent: :delete_all # membership, not history
  has_many :campaign_topics, dependent: :restrict_with_error # campaign history keeps its topics

  scope :ordered, -> { order(:name) }
  scope :listed, -> { where(public: true, system: false) }

  validates :key, presence: true, uniqueness: true, length: { maximum: 50 },
                  format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :name, presence: true, length: { maximum: 100 }

  before_destroy :keep_system_topic

  # Seeds run only on an empty production database, so the topic is created here when missing.
  def self.everyone
    create_with(name: "الجميع", system: true).find_or_create_by!(key: EVERYONE_KEY)
  end

  # Non-deleted users who get an inbox row when a campaign targets these topics.
  def self.recipient_user_ids(topics)
    users = User.not_deleted
    return users.ids if topics.any?(&:system?)

    subscriptions = TopicSubscription.where(topic_id: topics.map(&:id))
    via_devices = Device.where(id: subscriptions.select(:device_id)).select(:user_id)
    users.where(id: subscriptions.select(:user_id)).or(users.where(id: via_devices)).ids
  end

  # Guest installs that get an inbox row when a campaign targets these topics. A signed-in device is
  # left out: its user gets the row.
  def self.recipient_guest_device_ids(topics)
    devices = Device.where(user_id: nil)
    return devices.ids if topics.any?(&:system?)

    devices.where(id: TopicSubscription.where(topic_id: topics.map(&:id)).select(:device_id)).ids
  end

  def devices
    return Device.all if system?

    subscriptions = topic_subscriptions
    Device.where(id: subscriptions.select(:device_id)).or(Device.where(user_id: subscriptions.select(:user_id)))
  end

  private

  def keep_system_topic
    return unless system?

    errors.add(:base, "لا يمكن حذف موضوع النظام.")
    throw :abort
  end
end
