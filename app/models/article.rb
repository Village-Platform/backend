class Article < ApplicationRecord
  acts_as_paranoid
  # `author` is admin-only: it leads to a User, and through it to a phone number.
  ransack_tiers public: %w[ id title kind published_at ],
                admin: %w[ body author_id created_at updated_at deleted_at ],
                admin_associations: %w[ author ]

  enum :kind, { news: 0, article: 1, announcement: 2 }, default: :news, validate: true
  # Review of an author's submission, beside published_at (when it goes live). Only an approved
  # article is ever public; authors who can publish directly create approved ones.
  enum :review_status, { pending: 0, approved: 1, rejected: 2 }, default: :approved, validate: true

  belongs_to :author, class_name: "User", inverse_of: :articles
  belongs_to :reviewed_by, class_name: "User", optional: true, with_deleted: true
  # Pushed to this topic when the article goes live (Articles::SyncPushCampaign).
  belongs_to :notify_topic, class_name: "Topic", optional: true
  has_one :push_campaign, class_name: "NotificationCampaign", dependent: :nullify

  scope :published, -> { approved.where(published_at: ..Time.current) }
  scope :latest_first, -> { order(published_at: :desc, id: :desc) }

  validates :title, presence: true, length: { maximum: 200 }
  validates :body, presence: true

  def published?
    approved? && published_at.present? && published_at <= Time.current
  end

  def self.ransackable_scopes(auth_object = nil)
    %w[ published ]
  end
end
