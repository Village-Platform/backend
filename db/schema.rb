# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_01_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "articles", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.integer "kind", default: 0, null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.bigint "notify_topic_id"
    t.index "lower((title)::text) gin_trgm_ops", name: "index_articles_on_title_trigram", using: :gin
    t.index ["author_id"], name: "index_articles_on_author_id"
    t.index ["kind", "published_at"], name: "index_articles_on_kind_and_published_at"
    t.index ["notify_topic_id"], name: "index_articles_on_notify_topic_id"
    t.index ["published_at"], name: "index_articles_on_published_at"
  end

  create_table "campaign_topics", force: :cascade do |t|
    t.bigint "notification_campaign_id", null: false
    t.bigint "topic_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["notification_campaign_id", "topic_id"], name: "index_campaign_topics_on_notification_campaign_id_and_topic_id", unique: true
    t.index ["topic_id"], name: "index_campaign_topics_on_topic_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "icon"
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text) gin_trgm_ops", name: "index_categories_on_name_trigram", using: :gin
    t.index ["active", "position"], name: "index_categories_on_active_and_position"
    t.index ["name"], name: "index_categories_on_name", unique: true
  end

  create_table "devices", force: :cascade do |t|
    t.string "installation_id", null: false
    t.string "token", null: false
    t.bigint "user_id"
    t.string "platform", default: "android", null: false
    t.string "locale"
    t.string "app_version"
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["installation_id"], name: "index_devices_on_installation_id", unique: true
    t.index ["token"], name: "index_devices_on_token", unique: true
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "feature_flags", force: :cascade do |t|
    t.string "key", null: false
    t.boolean "enabled", default: false, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_feature_flags_on_key", unique: true
    t.check_constraint "key::text ~ '^[a-z][a-z0-9_]*$'::text", name: "feature_flags_key_format"
  end

  create_table "firms", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.bigint "owner_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "phone"
    t.string "whatsapp"
    t.string "address"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "working_hours"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index "lower((address)::text) gin_trgm_ops", name: "index_firms_on_address_trigram", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_firms_on_name_trigram", using: :gin
    t.index "lower((phone)::text) gin_trgm_ops", name: "index_firms_on_phone_trigram", using: :gin
    t.index ["category_id", "status"], name: "index_firms_on_category_id_and_status"
    t.index ["category_id"], name: "index_firms_on_category_id"
    t.index ["owner_id"], name: "index_firms_on_owner_id"
    t.index ["status"], name: "index_firms_on_status"
  end

  create_table "notification_campaigns", force: :cascade do |t|
    t.string "title", null: false
    t.text "body", null: false
    t.string "screen", default: "none", null: false
    t.bigint "target_id"
    t.integer "status", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "sent_at"
    t.integer "recipients_count"
    t.string "fcm_message_name"
    t.text "last_error"
    t.bigint "created_by_id"
    t.bigint "article_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id"], name: "index_notification_campaigns_on_article_id", unique: true, where: "(article_id IS NOT NULL)"
    t.index ["created_by_id"], name: "index_notification_campaigns_on_created_by_id"
    t.index ["status", "scheduled_at"], name: "index_notification_campaigns_on_status_and_scheduled_at"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id"
    t.integer "kind", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "read_at"
    t.string "dedupe_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "campaign_id"
    t.bigint "device_id"
    t.index ["campaign_id"], name: "index_notifications_on_campaign_id"
    t.index ["dedupe_key"], name: "index_notifications_on_dedupe_key", unique: true, where: "(dedupe_key IS NOT NULL)"
    t.index ["device_id", "created_at"], name: "index_notifications_on_device_id_and_created_at", where: "(device_id IS NOT NULL)"
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_notifications_unread_by_user", where: "(read_at IS NULL)"
    t.check_constraint "num_nonnulls(user_id, device_id) = 1", name: "notifications_one_recipient"
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.string "description"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_failure"
    t.text "metadata"
    t.integer "total_jobs", default: 0, null: false
    t.integer "completed_jobs", default: 0, null: false
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "batch_id"
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "stored_files", force: :cascade do |t|
    t.string "key", null: false
    t.binary "data", null: false
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_stored_files_on_key", unique: true
  end

  create_table "subscription_plans", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "price_cents", null: false
    t.integer "duration_days", null: false
    t.integer "max_firms", default: 1, null: false
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text) gin_trgm_ops", name: "index_subscription_plans_on_name_trigram", using: :gin
    t.index ["name"], name: "index_subscription_plans_on_name", unique: true
    t.check_constraint "duration_days > 0", name: "subscription_plans_duration_positive"
    t.check_constraint "max_firms > 0", name: "subscription_plans_max_firms_positive"
    t.check_constraint "price_cents >= 0", name: "subscription_plans_price_non_negative"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "subscription_plan_id", null: false
    t.bigint "reviewed_by_id"
    t.integer "status", default: 0, null: false
    t.integer "payment_method", null: false
    t.integer "amount_cents", null: false
    t.string "transaction_reference", null: false
    t.string "payer_phone"
    t.text "notes"
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.datetime "reviewed_at"
    t.text "rejection_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((payer_phone)::text) gin_trgm_ops", name: "index_subscriptions_on_payer_phone_trigram", using: :gin
    t.index "lower((transaction_reference)::text) gin_trgm_ops", name: "index_subscriptions_on_transaction_reference_trigram", using: :gin
    t.index ["payment_method", "transaction_reference"], name: "index_subscriptions_on_payment_reference", unique: true
    t.index ["reviewed_by_id"], name: "index_subscriptions_on_reviewed_by_id"
    t.index ["status", "ends_at"], name: "index_subscriptions_on_status_and_ends_at"
    t.index ["subscription_plan_id"], name: "index_subscriptions_on_subscription_plan_id"
    t.index ["user_id", "status", "ends_at"], name: "index_subscriptions_on_user_id_and_status_and_ends_at"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
    t.index ["user_id"], name: "index_subscriptions_one_pending_per_user", unique: true, where: "(status = 0)"
  end

  create_table "topic_subscriptions", force: :cascade do |t|
    t.bigint "topic_id", null: false
    t.bigint "user_id"
    t.bigint "device_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_topic_subscriptions_on_device_id"
    t.index ["topic_id", "device_id"], name: "index_topic_subscriptions_on_topic_id_and_device_id", unique: true, where: "(device_id IS NOT NULL)"
    t.index ["topic_id", "user_id"], name: "index_topic_subscriptions_on_topic_id_and_user_id", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["user_id"], name: "index_topic_subscriptions_on_user_id"
    t.check_constraint "num_nonnulls(user_id, device_id) = 1", name: "topic_subscriptions_one_subscriber"
  end

  create_table "topics", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.boolean "public", default: false, null: false
    t.boolean "system", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_topics_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "phone", null: false
    t.string "email"
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index "lower((email)::text) gin_trgm_ops", name: "index_users_on_email_trigram", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_users_on_name_trigram", using: :gin
    t.index "lower((phone)::text) gin_trgm_ops", name: "index_users_on_phone_trigram", using: :gin
    t.index ["email"], name: "index_users_on_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["phone"], name: "index_users_on_phone", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "articles", "topics", column: "notify_topic_id", on_delete: :nullify
  add_foreign_key "articles", "users", column: "author_id"
  add_foreign_key "campaign_topics", "notification_campaigns", on_delete: :cascade
  add_foreign_key "campaign_topics", "topics"
  add_foreign_key "devices", "users"
  add_foreign_key "firms", "categories"
  add_foreign_key "firms", "users", column: "owner_id"
  add_foreign_key "notification_campaigns", "articles"
  add_foreign_key "notification_campaigns", "users", column: "created_by_id"
  add_foreign_key "notifications", "devices", on_delete: :cascade
  add_foreign_key "notifications", "notification_campaigns", column: "campaign_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "subscriptions", "subscription_plans"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "subscriptions", "users", column: "reviewed_by_id"
  add_foreign_key "topic_subscriptions", "devices", on_delete: :cascade
  add_foreign_key "topic_subscriptions", "topics"
  add_foreign_key "topic_subscriptions", "users"
end
