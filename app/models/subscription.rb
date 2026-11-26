# A firm owner's paid access period.
#
# Flow: owner pays via InstaPay / Vodafone Cash -> submits the transfer reference
#       (+ optional screenshot) -> pending -> super admin approves (active) or rejects (rejected).
# Expiry is time-based: an active subscription is "current" only while starts_at <= now < ends_at.
class Subscription < ApplicationRecord
  # Public rows are already limited to the caller's own by the policy scope, so their own payment
  # fields are safe to filter on. `user` and `reviewed_by` lead to other people and are admin-only.
  ransack_tiers public: %w[ id status payment_method amount_cents transaction_reference payer_phone
                            notes starts_at ends_at reviewed_at rejection_reason
                            subscription_plan_id created_at ],
                admin: %w[ user_id reviewed_by_id updated_at amount_egp ],
                public_associations: %w[ subscription_plan ],
                admin_associations: %w[ user reviewed_by ]

  # Money is stored in piasters; filtering in pounds stops "500" meaning 5 EGP.
  ransacker :amount_egp do
    Arel.sql("(subscriptions.amount_cents / 100.0)")
  end

  SCREENSHOT_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  SCREENSHOT_MAX_SIZE = 4.megabytes # Kept from the old 4.5MB request cap; clients may rely on it

  enum :status, { pending: 0, active: 1, rejected: 2 }, default: :pending, validate: true
  enum :payment_method, { instapay: 0, vodafone_cash: 1 }, validate: true

  belongs_to :user, with_deleted: true
  belongs_to :subscription_plan
  belongs_to :reviewed_by, class_name: "User", optional: true, with_deleted: true

  has_one_attached :payment_screenshot

  scope :current, -> { active.where(starts_at: ..Time.current).where("subscriptions.ends_at > ?", Time.current) }
  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  normalizes :transaction_reference, with: ->(ref) { ref.strip }
  normalizes :payer_phone, with: ->(phone) { phone.to_s.gsub(/[^\d+]/, "").presence }

  before_validation :snapshot_price, on: :create

  validates :transaction_reference, presence: true, length: { maximum: 100 },
                                    uniqueness: { scope: :payment_method }
  validates :payer_phone, format: { with: /\A\+?\d{8,15}\z/ }, allow_nil: true
  validates :notes, length: { maximum: 500 }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :one_pending_per_user, on: :create
  validate :plan_is_available, on: :create
  validate :payment_screenshot_is_valid

  # Human-friendly state for the app: pending / rejected / scheduled / current / expired
  def state
    return status unless active?

    now = Time.current
    if starts_at > now then "scheduled"
    elsif ends_at > now then "current"
    else "expired"
    end
  end

  def days_left
    return nil unless active? && ends_at > Time.current

    ((ends_at - Time.current) / 1.day).ceil
  end

  # True when another approved period starts right after this one (stacked renewal).
  def renewed?
    Subscription.active.where(user_id: user_id).where.not(id: id)
                .where(starts_at: (ends_at - 1.minute)..).exists?
  end

  def self.ransackable_scopes(auth_object = nil)
    %w[ current ]
  end

  private

  def snapshot_price
    self.amount_cents ||= subscription_plan&.price_cents
  end

  def one_pending_per_user
    return unless user && Subscription.pending.exists?(user_id: user.id)

    errors.add(:base, :pending_exists, message: I18n.t("errors.api.pending_subscription_exists"))
  end

  def plan_is_available
    errors.add(:subscription_plan, :inactive) if subscription_plan && !subscription_plan.active?
  end

  def payment_screenshot_is_valid
    return unless payment_screenshot.attached?

    blob = payment_screenshot.blob
    unless SCREENSHOT_CONTENT_TYPES.include?(blob.content_type)
      errors.add(:payment_screenshot, I18n.t("errors.api.invalid_image_type"))
    end
    if blob.byte_size > SCREENSHOT_MAX_SIZE
      errors.add(:payment_screenshot, I18n.t("errors.api.file_too_large", size: "4MB"))
    end
  end
end
