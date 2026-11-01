module Observability
  # The only place the app touches the OpenTelemetry metrics API. The Ruby metrics SDK is pre-1.0,
  # so if it changes or misbehaves, this file is what gets rewritten (e.g. onto prometheus-client).
  #
  #   Observability::Metrics.increment(:api_errors, code: "not_found", status: 404)
  #   Observability::Metrics.record(:subscription_review_wait, 3600, outcome: "approved")
  #
  # Every instrument is declared in DEFINITIONS with the attribute keys it may carry. Each attribute
  # combination becomes a time series, so values must come from closed sets (enums, routes, i18n
  # codes) — never ids, phones, paths or messages. An undeclared key raises outside production and
  # is dropped in production.
  #
  # Until install! runs (no collector configured, or a spec without :metrics) every call is a no-op
  # apart from that check. Recording never raises in production: telemetry must not fail a request.
  module Metrics
    Definition = Data.define(:kind, :name, :unit, :description, :attributes, :buckets, :zero) do
      def initialize(attributes: [], buckets: nil, zero: [], **)
        super(attributes: attributes.map(&:to_s), buckets:, zero:, **)
      end
    end

    LATENCY_BUCKETS = [ 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10 ].freeze

    DEFINITIONS = {
      http_request_duration: Definition.new(
        kind: :histogram, name: "http.server.request.duration", unit: "s",
        description: "Controller actions, by route (controller#action)",
        attributes: %w[ http.route http.request.method http.response.status_code app.surface ],
        buckets: LATENCY_BUCKETS
      ),
      api_errors: Definition.new(
        kind: :counter, name: "aghour.api.errors", unit: "{error}",
        description: "Error responses by errors.api.* code", attributes: %i[ code status ]
      ),
      client_requests: Definition.new(
        kind: :counter, name: "aghour.api.client_requests", unit: "{request}",
        description: "API requests by client platform and app version (X-App-Platform / X-App-Version)",
        attributes: %w[ client.platform client.app_version ]
      ),
      logins: Definition.new(
        kind: :counter, name: "aghour.auth.logins", unit: "{login}",
        description: "Login attempts", attributes: %i[ surface result ],
        zero: [ { surface: "api", result: "success" }, { surface: "api", result: "invalid_credentials" },
                { surface: "admin", result: "success" }, { surface: "admin", result: "invalid_credentials" },
                { surface: "admin", result: "rate_limited" } ]
      ),
      tokenless_api_requests: Definition.new(
        kind: :counter, name: "aghour.auth.tokenless_requests", unit: "{request}",
        description: "API calls with neither a user nor a guest token; allowed until API_TOKEN_REQUIRED=1",
        attributes: %i[ result ], zero: [ { result: "allowed" }, { result: "rejected" } ]
      ),
      registrations: Definition.new(
        kind: :counter, name: "aghour.auth.registrations", unit: "{user}", description: "New accounts",
        zero: [ {} ]
      ),
      subscriptions_requested: Definition.new(
        kind: :counter, name: "aghour.subscriptions.requested", unit: "{subscription}",
        description: "Subscription requests submitted by owners", attributes: %i[ payment_method plan ]
      ),
      subscriptions_reviewed: Definition.new(
        kind: :counter, name: "aghour.subscriptions.reviewed", unit: "{subscription}",
        description: "Subscriptions approved or rejected", attributes: %i[ outcome ],
        zero: [ { outcome: "approved" }, { outcome: "rejected" } ]
      ),
      subscription_review_wait: Definition.new(
        kind: :histogram, name: "aghour.subscription.review.wait", unit: "s",
        description: "Time from request to review", attributes: %i[ outcome ],
        buckets: [ 5.minutes, 15.minutes, 30.minutes, 1.hour, 2.hours, 4.hours, 8.hours, 12.hours,
                   1.day, 2.days, 3.days, 7.days ].map(&:to_i)
      ),
      payment_screenshot_size: Definition.new(
        kind: :histogram, name: "aghour.payment_screenshots.uploaded.size", unit: "By",
        description: "Payment screenshot sizes", attributes: %i[ content_type ],
        buckets: [ 100_000, 250_000, 500_000, 1_000_000, 2_000_000, 3_000_000, 4_000_000 ]
      ),
      notifications_created: Definition.new(
        kind: :counter, name: "aghour.notifications.created", unit: "{notification}",
        description: "In-app notifications created", attributes: %i[ kind ]
      ),
      notifications_deduplicated: Definition.new(
        kind: :counter, name: "aghour.notifications.deduplicated", unit: "{notification}",
        description: "Notifications skipped because their dedupe_key already existed", attributes: %i[ kind ]
      ),
      # Started at 0 so increase() sees the first run even when the pod restarts afterwards: the
      # "reminders did not run" alert is built on this counter.
      reminder_runs: Definition.new(
        kind: :counter, name: "aghour.reminders.runs", unit: "{run}",
        description: "SubscriptionExpiryRemindersJob runs", attributes: %i[ result ],
        zero: [ { result: "success" }, { result: "failure" } ]
      ),
      devices_registered: Definition.new(
        kind: :counter, name: "aghour.push.devices_registered", unit: "{device}",
        description: "Device registrations; changed = new install, new token or new user", attributes: %i[ result ]
      ),
      push_sent: Definition.new(
        kind: :counter, name: "aghour.push.sent", unit: "{message}",
        description: "FCM sends by source (system / campaign) and result (ok, invalid, unregistered, auth_error, retry, failed)",
        attributes: %i[ source result ],
        zero: [ { source: "system", result: "ok" }, { source: "system", result: "auth_error" },
                { source: "campaign", result: "ok" }, { source: "campaign", result: "auth_error" } ]
      ),
      campaigns_delivered: Definition.new(
        kind: :counter, name: "aghour.push.campaigns", unit: "{campaign}",
        description: "Campaign deliveries by outcome", attributes: %i[ result ],
        zero: [ { result: "sent" }, { result: "failed" }, { result: "canceled" } ]
      ),
      push_tokens_pruned: Definition.new(
        kind: :counter, name: "aghour.push.tokens_pruned", unit: "{device}",
        description: "Devices deleted because FCM reported their token unregistered or invalid", zero: [ {} ]
      ),
      reminders_sent: Definition.new(
        kind: :counter, name: "aghour.reminders.sent", unit: "{notification}",
        description: "Reminder notifications sent by the daily job", zero: [ {} ]
      )
    }.freeze

    @mutex = Mutex.new
    @instruments = {}

    class << self
      # Creates the instruments on meter_provider. Views first: the SDK matches them when an
      # instrument is created, and it ignores the explicit_bucket_boundaries advisory.
      # observe: also registers the observable gauges (DB counts, Puma, pool, Ruby) — only in the
      # web server, so rake tasks and consoles don't poll the database.
      def install!(meter_provider, observe: false)
        @mutex.synchronize do
          DEFINITIONS.each_value do |definition|
            next unless definition.buckets

            meter_provider.add_view(
              definition.name,
              aggregation: OpenTelemetry::SDK::Metrics::Aggregation::ExplicitBucketHistogram.new(boundaries: definition.buckets)
            )
          end

          meter = meter_provider.meter("aghour-api")
          @instruments = DEFINITIONS.to_h { |key, definition| [ key, build(meter, definition) ] }
          DEFINITIONS.each { |key, definition| definition.zero.each { |attrs| @instruments[key].add(0, attributes: stringify(attrs)) } }
          Gauges.register(meter) if observe
        end
      end

      def uninstall!
        @mutex.synchronize { @instruments = {} }
      end

      def increment(key, by = 1, **attributes)
        emit(key, :add, by, attributes)
      end

      def record(key, value, **attributes)
        emit(key, :record, value, attributes)
      end

      private

      def build(meter, definition)
        meter.public_send("create_#{definition.kind}", definition.name, unit: definition.unit, description: definition.description)
      end

      def emit(key, method, value, attributes)
        definition = DEFINITIONS[key]
        return programming_error("unknown metric #{key.inspect}") unless definition

        attrs = stringify(attributes)
        unknown = attrs.keys - definition.attributes
        if unknown.any?
          programming_error("#{definition.name} does not allow attributes #{unknown.inspect}")
          attrs = attrs.slice(*definition.attributes)
        end

        begin
          @instruments[key]&.public_send(method, value, attributes: attrs)
        rescue StandardError => e
          Rails.logger.warn("[Observability::Metrics] #{definition.name} not recorded: #{e.class}: #{e.message}")
        end
        nil
      end

      def programming_error(message)
        raise ArgumentError, message unless Rails.env.production?

        Rails.logger.warn("[Observability::Metrics] #{message}")
        nil
      end

      # A new, unfrozen hash every time: when a view applies, the SDK merge!s into it.
      def stringify(attributes)
        attributes.each_with_object({}) { |(k, v), h| h[k.to_s] = v.is_a?(Symbol) ? v.to_s : v }
      end
    end
  end
end
