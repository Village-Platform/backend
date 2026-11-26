# File bodies for the "database" Active Storage service (lib/active_storage/service/database_service.rb).
# Used on hosts without a persistent disk. The blob metadata stays in active_storage_blobs.
class CreateStoredFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :stored_files do |t|
      t.string :key, null: false
      t.binary :data, null: false
      t.datetime :created_at, null: false
    end
    add_index :stored_files, :key, unique: true
  end
end
