require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  config.action_controller.perform_caching = false
  config.cache_store = :memory_store

  config.active_storage.service = :local

  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.active_record.query_log_tags_enabled = true
  config.active_job.verbose_enqueue_logs = true
  # Same adapter as production; jobs run when the server starts with SOLID_QUEUE_IN_PUMA=1 (or bin/jobs).
  config.active_job.queue_adapter = :solid_queue

  config.action_controller.raise_on_missing_callback_actions = true

  # Throwaway Active Record Encryption keys (public, never used in production).
  config.active_record.encryption.primary_key = "village-development-primary-key-not-secret"
  config.active_record.encryption.deterministic_key = "village-development-deterministic-key-not-secret"
  config.active_record.encryption.key_derivation_salt = "village-development-key-derivation-salt-not-secret"
end
