class Firm < ApplicationRecord
  # Public: what FirmSerializer shows. `owner` is admin-only — it leads to the owner's phone.
  ransack_tiers public: %w[ id name description phone whatsapp address working_hours status
                            category_id owner_id created_at ],
                admin: %w[ updated_at deleted_at ],
                public_associations: %w[ category ],
                admin_associations: %w[ owner ]

  # pending   -> submitted (or edited) by an owner who cannot publish directly, waiting for review
  # active    -> approved, or created by someone who can publish directly
  # suspended -> hidden by a super admin (moderation), or rejected in review (rejection_reason set)
  # Note: every active firm is public, whoever owns it. A subscription buys publishing without
  # review and the plan's firm quota, not visibility.
  acts_as_paranoid

  enum :status, { pending: 0, active: 1, suspended: 2 }, default: :pending, validate: true

  belongs_to :category
  belongs_to :owner, class_name: "User", inverse_of: :firms, with_deleted: true
  belongs_to :reviewed_by, class_name: "User", optional: true, with_deleted: true

  scope :search, ->(term) { where("firms.name ILIKE ?", "%#{sanitize_sql_like(term)}%") }

  # Public listing: every approved firm. Keep reading through this scope rather than `active`, so the
  # rule stays in one place. To tie visibility to the owner's subscription again:
  #   active.where(owner_id: Subscription.current.select(:user_id))
  #         .or(active.where(owner_id: User.reviewers.select(:id)))
  scope :visible, -> { active }

  validates :name, presence: true, length: { maximum: 150 }
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true

  def rejected?
    suspended? && rejection_reason.present?
  end

  def self.ransackable_scopes(auth_object = nil)
    %w[ visible ]
  end
end
