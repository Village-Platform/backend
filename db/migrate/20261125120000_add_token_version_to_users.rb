# Revocation for bearer tokens and dashboard sessions: each one records the version it was issued
# at, and bumping the column revokes them all. A constant default is metadata-only in PostgreSQL 11+,
# so this adds the column without rewriting the table.
class AddTokenVersionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :token_version, :integer, null: false, default: 0
  end
end
