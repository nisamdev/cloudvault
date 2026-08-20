# frozen_string_literal: true

module Api
  module V1
    # Every device currently able to stay signed in.
    #
    # A refresh token *is* a session: the access token is fifteen minutes of
    # memory, but the refresh token in the cookie is what keeps a device alive
    # for days. Revoking one here is what a lost phone needs.
    class SessionsController < BaseController
      # GET /api/v1/sessions
      def index
        current = current_refresh_token

        sessions = current_user.refresh_tokens.active.order(created_at: :desc).map do |token|
          serialize(token, current: token.id == current&.id)
        end

        render json: { sessions: sessions }
      end

      # DELETE /api/v1/sessions/:id
      def destroy
        token = current_user.refresh_tokens.active.find(params[:id])
        token.revoke!

        head :no_content
      end

      # DELETE /api/v1/sessions
      #
      # Everything except the browser asking, which would otherwise sign itself
      # out and make the button feel like a mistake.
      def destroy_all
        current = current_refresh_token

        scope = current_user.refresh_tokens.active
        scope = scope.where.not(id: current.id) if current
        ended = scope.each(&:revoke!).size

        render json: { sessions_ended: ended }
      end

      private

      def current_refresh_token
        RefreshToken.find_by_raw_token(cookies.encrypted[AuthController::REFRESH_COOKIE])
      end

      def serialize(token, current:)
        {
          id: token.id,
          current: current,
          ip_address: token.ip_address,
          device: DeviceName.for(token.user_agent),
          user_agent: token.user_agent,
          last_used_at: token.last_used_at,
          created_at: token.created_at,
          expires_at: token.expires_at
        }
      end
    end
  end
end
