# Traces and metrics through OpenTelemetry, exported over OTLP to the collector in the cluster
# (deploy/observability). Off unless OTEL_EXPORTER_OTLP_ENDPOINT is set, so development and test
# run without a collector, and Observability::Metrics records nothing.
#
# Standard OTEL_* variables are read by the SDK: OTEL_SERVICE_NAME, OTEL_TRACES_SAMPLER(_ARG),
# OTEL_METRIC_EXPORT_INTERVAL, OTEL_SDK_DISABLED.

# Always subscribed: without an installed meter provider, recording is a no-op.
ActiveSupport::Notifications.subscribe("process_action.action_controller") do |event|
  Observability::Requests.record(event)
end

otel_enabled = !Rails.env.test? &&
               ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present? &&
               ENV["OTEL_SDK_DISABLED"] != "true"

if otel_enabled
  # Configured here rather than after boot: the Rack and Action Pack instrumentations insert their
  # middleware, which has to happen before Rails builds the stack.
  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "aghour-api")
    c.service_version = ENV.fetch("APP_REVISION", "unknown")
    c.resource = OpenTelemetry::SDK::Resources::Resource.create("deployment.environment.name" => Rails.env.to_s)
    c.logger = Rails.logger
    c.use_all(
      # Probes hit /up every few seconds; tracing them would bury real requests.
      "OpenTelemetry::Instrumentation::Rack" => { untraced_endpoints: [ "/up" ] },
      # Queries carry phone numbers: export the statement shape only, never the values.
      "OpenTelemetry::Instrumentation::PG" => { db_statement: :obfuscate }
    )
  end

  Rails.application.config.after_initialize do
    # Gauges poll the database, so only the web server registers them, not rake tasks or consoles.
    server = defined?(Rails::Server) || $PROGRAM_NAME.match?(/\bpuma\b/)
    Observability::Metrics.install!(OpenTelemetry.meter_provider, observe: server)
  end

  # Puma exits normally on SIGTERM (raise_exception_on_sigterm false), so this flushes the last batch.
  at_exit do
    OpenTelemetry.meter_provider.shutdown(timeout: 5)
    OpenTelemetry.tracer_provider.shutdown(timeout: 5)
  end
end
