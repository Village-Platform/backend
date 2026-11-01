# An app install that can receive pushes. Guests have no user.
class Device < ApplicationRecord
  PLATFORMS = %w[ android ].freeze

  belongs_to :user, optional: true
  has_many :topic_subscriptions, dependent: :delete_all
  # The guest inbox. Kept while the device is signed in (the app shows the user's inbox then) and
  # shown again after logout.
  has_many :notifications, dependent: :delete_all

  validates :installation_id, presence: true, length: { maximum: 200 }
  validates :token, presence: true, length: { maximum: 4096 }
  validates :platform, inclusion: { in: PLATFORMS }

  # Topics the device belongs to, directly or through its user. The everyone topic is implicit.
  def topics
    user_topics = TopicSubscription.where(user_id: user_id).select(:topic_id) if user_id
    scope = Topic.where(id: TopicSubscription.where(device_id: id).select(:topic_id))
    scope = scope.or(Topic.where(id: user_topics)) if user_topics
    scope.where(system: false)
  end

  def topic_keys
    [ Topic::EVERYONE_KEY, *topics.order(:key).pluck(:key) ]
  end
end
