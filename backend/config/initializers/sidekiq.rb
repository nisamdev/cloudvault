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

# Recurring jobs are registered by the worker only. Registering from the web
# process too would have both racing to write the same schedule on every boot.
Sidekiq.configure_server do |config|
  config.on(:startup) do
    schedule_file = Rails.root.join("config/schedule.yml")
    next unless schedule_file.exist?

    require "sidekiq/cron"
    Sidekiq::Cron::Job.load_from_hash!(YAML.load_file(schedule_file))
  rescue StandardError => e
    # A bad schedule must not stop the worker from processing normal jobs.
    Rails.logger.error("[sidekiq-cron] failed to load schedule: #{e.class}: #{e.message}")
  end
end
