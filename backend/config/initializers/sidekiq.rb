# frozen_string_literal: true

# Sidekiq points at REDIS_URL — compose supplies the redis service, Railway
# supplies ${{Redis.REDIS_URL}}.

redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  # Railway's Redis can drop idle connections; reconnect rather than fail a job.
  network_timeout: 5,
  reconnect_attempts: 3
}

Sidekiq.configure_server do |config|
  config.redis = redis_config
  config.concurrency = ENV.fetch("SIDEKIQ_CONCURRENCY", 5).to_i
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
