require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = ENV["ASSUME_SSL"].present?
  config.force_ssl = ENV["FORCE_SSL"].present?
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  config.log_tags = [ :request_id, ->(request) { Observability.log_tag(request) } ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"

  config.active_support.report_deprecations = false

  # Swap to Redis / Solid Cache when needed.
  config.cache_store = :memory_store
  # Jobs are rows in the primary database (see CreateSolidQueueTables), run by the Solid Queue
  # plugin inside Puma when SOLID_QUEUE_IN_PUMA is set. They survive restarts, unlike :async.
  config.active_job.queue_adapter = :solid_queue
  # Delete a job's row when it finishes, so no recurring cleanup (and no scheduler process) is needed.
  config.solid_queue.preserve_finished_jobs = false

  # Uploaded files (payment screenshots). "database" keeps them in PostgreSQL, which works on
  # hosts without a persistent disk. Use "local" with a mounted volume, or S3 later.
  config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "database").to_sym

  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]
end
