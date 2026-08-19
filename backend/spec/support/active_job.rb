# The app uses Sidekiq in every real environment; specs use the test adapter so
# jobs are captured and asserted on rather than actually pushed to Redis.
RSpec.configure do |config|
  config.before do
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
  end
end
