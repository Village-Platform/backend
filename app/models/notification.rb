# In-app notification. Addressed to a user, or to a guest install (campaigns only); exactly one of
# the two, enforced by the database.
class Notification < ApplicationRecord
  # Public rows are the caller's own (policy scope).
  ransack_tiers public: %w[ id kind title body read_at created_at ],
                admin: %w[ user_id updated_at ],
                admin_associations: %w[ user ]

  enum :kind, {
    subscription_approved: 0,
    subscription_rejected: 1,
    subscription_expiring: 2,
    subscription_expired: 3,
    system_announcement: 4
  }, validate: true

  belongs_to :user, optional: true
  belongs_to :device, optional: true
  belongs_to :campaign, class_name: "NotificationCampaign", optional: true

  scope :unread, -> { where(read_at: nil) }
  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  validates :title, :body, presence: true
  validate :one_recipient

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end

  private

  def one_recipient
    errors.add(:base, "must belong to a user or a device, not both") unless user_id.present? ^ device_id.present?
  end
end
