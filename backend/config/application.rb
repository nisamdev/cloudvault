require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module CloudVault
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # API mode omits cookie middleware, but the refresh token lives in an
    # httpOnly cookie — the SPA must never be able to read it from script.
    config.middleware.use ActionDispatch::Cookies

    config.time_zone = "UTC"

    # Background jobs run through Sidekiq (see config/sidekiq.yml).
    config.active_job.queue_adapter = :sidekiq

    # Object storage. Overridden to :test in the test environment.
    # Active Storage reads this during framework init, which is why it lives
    # here rather than in an initializer.
    config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "s3").to_sym

    # Direct browser -> storage uploads need the presigned URL to outlive a slow
    # connection on a large file.
    config.active_storage.service_urls_expire_in = 15.minutes

    # Mail goes to Mailpit locally and a real SMTP provider in production; both
    # are configured entirely from the environment.
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV.fetch("SMTP_ADDRESS", "localhost"),
      port: ENV.fetch("SMTP_PORT", 1025).to_i,
      user_name: ENV["SMTP_USER_NAME"].presence,
      password: ENV["SMTP_PASSWORD"].presence,
      authentication: ENV["SMTP_AUTHENTICATION"].presence,
      # Mailpit speaks plaintext SMTP; hosted providers need STARTTLS.
      enable_starttls_auto: ENV.fetch("SMTP_STARTTLS", "false") == "true"
    }.compact

    # Invite and share links must point at the SPA, not the API.
    config.x.app_url = ENV.fetch("APP_URL", "http://localhost:5173")
    config.x.api_url = ENV.fetch("API_URL", "http://localhost:3000")
    config.x.mail_from = ENV.fetch("MAIL_FROM", "no-reply@cloudvault.local")
  end
end
