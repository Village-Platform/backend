Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?

  config.consider_all_requests_local = true
  config.cache_store = :null_store

  config.active_storage.service = :test

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  config.active_support.deprecation = :stderr
  config.action_controller.raise_on_missing_callback_actions = true

  # Specs turn two-factor sign-in on per example (spec/support/reviewer_mfa_helpers.rb), never from .env.
  config.x.reviewer_mfa_mode = "off"

  # Throwaway Active Record Encryption keys (public, never used in production).
  config.active_record.encryption.primary_key = "village-test-primary-key-not-secret"
  config.active_record.encryption.deterministic_key = "village-test-deterministic-key-not-secret"
  config.active_record.encryption.key_derivation_salt = "village-test-key-derivation-salt-not-secret"
end
