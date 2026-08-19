# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # A row deleted between enqueue and perform is normal, not a failure.
  discard_on ActiveJob::DeserializationError
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
end
