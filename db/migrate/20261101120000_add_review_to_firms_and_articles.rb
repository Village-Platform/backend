# Review of user submissions. Firms already have `pending`; a rejected firm becomes `suspended` with
# a rejection_reason, so old apps never meet a new status string. Articles gain their own review
# state beside published_at: existing rows default to approved and stay live (a constant default is
# a metadata-only change in PostgreSQL 11+, no table rewrite).
class AddReviewToFirmsAndArticles < ActiveRecord::Migration[8.1]
  def change
    change_table :firms, bulk: true do |t|
      t.text :rejection_reason
      t.references :reviewed_by, foreign_key: { to_table: :users }, index: false
      t.datetime :reviewed_at
    end

    change_table :articles, bulk: true do |t|
      t.integer :review_status, null: false, default: 1
      t.text :rejection_reason
      t.references :reviewed_by, foreign_key: { to_table: :users }, index: false
      t.datetime :reviewed_at
    end

    # The review queue and the sidebar counter read only the pending rows.
    add_index :articles, :created_at, where: "review_status = 0", name: "index_articles_pending_review"
  end
end
