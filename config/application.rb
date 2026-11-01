require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"     # enable later for live notifications

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Lets Active Storage find the custom "Database" service in lib/active_storage/service/.
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

module AghourServices
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks active_storage])

    config.time_zone = "Cairo"

    # Arabic first, English as fallback. Clients choose via the Accept-Language header.
    config.i18n.available_locales = %i[ar]
    config.i18n.default_locale = :ar
    config.i18n.fallbacks = [ :ar ]

    # The JSON API controllers inherit ActionController::API, but the app is not api_only,
    # because the admin dashboard (/admin) needs cookies, sessions, flash and assets.
    config.api_only = false

    # 1 = every /api/v1 call needs a user or guest token (Api::V1::BaseController). Off by default so
    # app versions without guest tokens keep working; flip it once tokenless traffic has died down.
    config.x.api_token_required = ENV["API_TOKEN_REQUIRED"] == "1"

    # Image variants (thumbnails) with libvips (installed in Dockerfile.vercel).
    config.active_storage.variant_processor = :vips

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, dir: "spec/factories"
    end
  end
end
