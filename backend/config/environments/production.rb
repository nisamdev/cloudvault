require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  # Storage service comes from ACTIVE_STORAGE_SERVICE (see config/application.rb).

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # Railway terminates TLS at the edge and forwards X-Forwarded-Proto, so this
  # stays on. FORCE_SSL=false is the escape hatch for a plain-HTTP deploy.
  config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"

  # Railway's health checks and private-network calls arrive over plain HTTP.
  # Redirecting them to HTTPS would fail every deploy.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  # config.active_job.queue_adapter = :resque

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  # Invite/share emails must link to the SPA, not the API.
  config.action_mailer.default_url_options = begin
    uri = URI.parse(ENV.fetch("APP_URL", "https://localhost"))
    { host: uri.host, port: uri.port, protocol: uri.scheme }.compact
  end
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_deliveries = ENV.fetch("PERFORM_DELIVERIES", "true") == "true"

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # DNS rebinding / Host header protection.
  # ALLOWED_HOSTS is comma-separated; leave it unset to accept any Host (the
  # Rails default). On Railway set it to your API domain, e.g.
  #   cloudvault-api.up.railway.app,api.yourdomain.com
  allowed_hosts = ENV.fetch("ALLOWED_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
  if allowed_hosts.any?
    config.hosts = allowed_hosts + [ /.*\.railway\.internal/ ]
    # Health checks hit the container by internal address, not by domain.
    config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  end
end
