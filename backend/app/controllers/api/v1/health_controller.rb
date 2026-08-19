# frozen_string_literal: true

module Api
  module V1
    # Dependency-aware health check.
    #
    # /up (Rails' built-in) only proves the process booted. This endpoint proves
    # the process can still reach Postgres, Redis and object storage, which is
    # what actually breaks in a multi-service deploy.
    class HealthController < ApplicationController
      def show
        checks = {
          database: check { ActiveRecord::Base.connection.execute("SELECT 1") },
          redis: check { Sidekiq.redis(&:ping) },
          storage: check { ActiveStorage::Blob.service.present? }
        }

        healthy = checks.values.all? { |c| c[:ok] }

        render json: {
          status: healthy ? "ok" : "degraded",
          version: ENV.fetch("APP_VERSION", "dev"),
          environment: Rails.env,
          checks: checks
        }, status: healthy ? :ok : :service_unavailable
      end

      private

      def check
        yield
        { ok: true }
      rescue StandardError => e
        # The message can carry connection strings; log it, don't return it.
        Rails.logger.error("[health] #{e.class}: #{e.message}")
        { ok: false, error: e.class.name }
      end
    end
  end
end
