source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "bootsnap", require: false
gem "propshaft" # asset pipeline for the admin dashboard CSS
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "image_processing", "~> 1.2"

group :production do
  gem "ruby-vips"
end

group :development do
  gem "actual_db_schema"
end

# Soft Deletion
gem "acts_as_paranoid", "~> 0.11.0"

# Auth & authorization
gem "bcrypt", "~> 3.1.7"
gem "jwt", "~> 3.1"
gem "pundit", "~> 2.5"
# Reviewer two-factor sign-in: RFC 6238 codes and the setup QR (rendered as inline SVG).
gem "rotp", "~> 6.3"
gem "rqrcode", "~> 3.1"

# API helpers
gem "rack-cors"
gem "rails-i18n", "~> 8.0"
gem "dotenv-rails"

# Observability (config/initializers/opentelemetry.rb). Off unless OTEL_EXPORTER_OTLP_ENDPOINT is set.
# The metrics gems are pre-1.0 and only reached through Observability::Metrics: keep them pinned.
gem "opentelemetry-sdk", "~> 1.13"
gem "opentelemetry-exporter-otlp", "~> 0.37"
# Only what this app uses (instrumentation-all brings ~60 gems: AWS, Mongo, GraphQL, ...).
gem "opentelemetry-instrumentation-rails" # Rack, Action Pack/View, Active Record/Job/Support
gem "opentelemetry-instrumentation-pg"
gem "opentelemetry-instrumentation-net_http"
gem "opentelemetry-metrics-sdk", "0.22.0"
gem "opentelemetry-exporter-otlp-metrics", "0.15.0"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

gem "tailwindcss-rails", "~> 4.7"

# Search and filtering for Active Record models
gem "ransack", "~> 6.0"
gem "pagy", "~> 43.8"

gem "solid_queue", "~> 1.7"

gem "googleauth", "~> 1.17"

gem "fcm", "~> 2.0"
