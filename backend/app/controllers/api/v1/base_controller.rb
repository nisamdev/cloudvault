# frozen_string_literal: true

module Api
  module V1
    # Shared behaviour for every v1 endpoint: authentication, a single error
    # envelope, and pagination headers.
    class BaseController < ApplicationController
      include Authenticable
      include VaultAccess
      include Pagy::Backend

      # Order matters: Rails matches rescue_from handlers bottom-up, so the most
      # specific must be declared last.
      rescue_from StandardError, with: :handle_internal_error
      rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
      rescue_from ActiveRecord::RecordInvalid, with: :handle_validation_error
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # Storage URLs are built deep inside serializers that never see the
      # request, but whether they can be reached depends on how this browser
      # reached us. Stash it where StorageUrl can find it.
      before_action { Current.request_origin = frontend_origin }

      private

      # Where the browser actually reached us — a cloudflared tunnel, a LAN IP,
      # or localhost. Links handed back to that browser (a QR code to open on a
      # phone, a share URL to send to someone) must use the same origin, or they
      # point somewhere the recipient cannot reach.
      #
      # Falls back to APP_URL, which is all a mailer has to work with.
      def frontend_origin
        raw = request.headers["Origin"].presence || request.headers["Referer"].presence
        return Rails.configuration.x.app_url if raw.blank?

        uri = URI.parse(raw)
        return Rails.configuration.x.app_url unless uri.scheme&.start_with?("http") && uri.host.present?

        default_port = uri.scheme == "https" ? 443 : 80
        port = uri.port && uri.port != default_port ? ":#{uri.port}" : ""

        "#{uri.scheme}://#{uri.host}#{port}"
      rescue URI::InvalidURIError
        Rails.configuration.x.app_url
      end

      # Every failure the client sees has this shape, so the SPA has exactly one
      # error path to render (see frontend/src/api/client.js).
      def render_error(message:, code:, status:, details: {})
        render json: {
          error: { message: message, code: code, details: details }
        }, status: status
      end

      def handle_not_found(_error)
        render_error(
          message: "We couldn't find what you were looking for.",
          code: "not_found",
          status: :not_found
        )
      end

      def handle_validation_error(error)
        render_error(
          message: error.record.errors.full_messages.to_sentence,
          code: "validation_failed",
          status: :unprocessable_content,
          # Keyed by field so the form can show messages inline.
          details: error.record.errors.to_hash(true).transform_values(&:first)
        )
      end

      def handle_parameter_missing(error)
        render_error(
          message: "Required parameter missing: #{error.param}",
          code: "parameter_missing",
          status: :bad_request
        )
      end

      def handle_internal_error(error)
        # Never leak an exception message to the client; log it with the request
        # id so it can be found later.
        Rails.logger.error("[#{request.request_id}] #{error.class}: #{error.message}")
        Rails.logger.error(error.backtrace&.first(20)&.join("\n"))

        raise error if Rails.env.local?

        render_error(
          message: "Something went wrong on our end. Please try again.",
          code: "internal_error",
          status: :internal_server_error
        )
      end

      def pagination_headers(pagy)
        response.headers["X-Total-Count"] = pagy.count.to_s
        response.headers["X-Total-Pages"] = pagy.pages.to_s
        response.headers["X-Page"] = pagy.page.to_s
      end
    end
  end
end
