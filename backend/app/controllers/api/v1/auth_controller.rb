# frozen_string_literal: true

module Api
  module V1
    # Session lifecycle: register, login, refresh, logout.
    #
    # Token model (from PHASE1_IMPLEMENTATION_GUIDE.md, hardened):
    #   access token  — JWT, ~15 min, returned in the body, held in memory by the SPA
    #   refresh token — opaque, 7 days, httpOnly cookie, rotated on every use
    #
    # The guide's example stores the access token in localStorage. We don't: any
    # XSS would be able to read it. Keeping it in memory and putting the refresh
    # token in an httpOnly cookie means script on the page can steal neither.
    class AuthController < BaseController
      # Logout is deliberately unauthenticated: a user whose access token has
      # already expired must still be able to end the session and clear the
      # cookie. It only ever revokes the refresh token the caller presents.
      allow_unauthenticated :register, :login, :refresh, :logout

      REFRESH_COOKIE = :cloudvault_refresh_token

      # POST /api/v1/auth/register
      def register
        user = User.new(registration_params)
        user.storage_quota = ENV.fetch("USER_STORAGE_QUOTA_BYTES", 268_435_456).to_i
        user.save!

        issue_session(user, status: :created)
      end

      # POST /api/v1/auth/login
      def login
        user = User.find_by(email: params[:email].to_s.strip.downcase)

        # authenticate returns false for a nil digest (OAuth-only accounts), so
        # both "no such user" and "wrong password" land here with one message —
        # revealing which it was would enumerate accounts.
        unless user&.authenticate(params[:password].to_s)
          return render_error(
            message: "That email or password is incorrect.",
            code: "invalid_credentials",
            status: :unauthorized
          )
        end

        user.update_column(:last_signed_in_at, Time.current)
        issue_session(user, status: :ok)
      end

      # POST /api/v1/auth/refresh
      def refresh
        token = cookies.encrypted[REFRESH_COOKIE] || params[:refresh_token]
        record = RefreshToken.find_by_raw_token(token)

        if record.nil?
          return render_error(
            message: "Your session has expired. Please sign in again.",
            code: "invalid_refresh_token",
            status: :unauthorized
          )
        end

        # A token that was already rotated is being replayed — assume theft and
        # end every session this user has.
        if record.detect_replay!
          Rails.logger.warn("[auth] refresh token replay for user #{record.user_id}")
          clear_refresh_cookie
          return render_error(
            message: "Your session was ended for security reasons. Please sign in again.",
            code: "refresh_token_replayed",
            status: :unauthorized
          )
        end

        unless record.active?
          clear_refresh_cookie
          return render_error(
            message: "Your session has expired. Please sign in again.",
            code: "expired_refresh_token",
            status: :unauthorized
          )
        end

        issue_session(record.user, rotating: record, status: :ok)
      end

      # POST /api/v1/auth/logout
      def logout
        token = cookies.encrypted[REFRESH_COOKIE]
        RefreshToken.find_by_raw_token(token)&.revoke!
        clear_refresh_cookie

        head :no_content
      end

      # GET /api/v1/auth/me
      def me
        render json: session_payload(current_user, access_token: nil).except(:access_token)
      end

      private

      def registration_params
        params.permit(:email, :password, :full_name, :timezone)
      end

      def issue_session(user, status:, rotating: nil)
        new_refresh = nil

        ActiveRecord::Base.transaction do
          new_refresh = user.refresh_tokens.create!(
            user_agent: request.user_agent&.truncate(255),
            ip_address: request.remote_ip
          )

          # Point the old token at its successor so a later replay is detectable.
          rotating&.update!(replaced_by: new_refresh, revoked_at: Time.current, last_used_at: Time.current)
        end

        set_refresh_cookie(new_refresh)

        access_token = JwtService.encode({ sub: user.id, email: user.email })
        render json: session_payload(user, access_token: access_token), status: status
      end

      def session_payload(user, access_token:)
        membership = user.primary_membership

        {
          access_token: access_token,
          expires_in: JwtService.access_ttl.to_i,
          user: {
            id: user.id,
            email: user.email,
            full_name: user.full_name,
            avatar_url: user.avatar_url,
            timezone: user.timezone,
            storage_quota: user.storage_quota,
            storage_used: user.storage_used,
            storage_percent_used: user.storage_percent_used
          },
          family: membership && {
            id: membership.family_id,
            name: membership.family.name,
            role: membership.role,
            # Being in a family whose things are shut to you is a real state,
            # and one the screen has to be able to explain. Without this it
            # simply shows nothing and says nothing about why.
            can_use_vault: membership.can_use_vault?,
            storage_quota: membership.family.family_storage_quota,
            storage_used: membership.family.family_storage_used
          },
          # All of them, so the app can offer a switcher. An account may belong
          # to several families, or to none — neither is a broken state.
          families: user.family_memberships.includes(:family).map do |m|
            { id: m.family_id, name: m.family.name, role: m.role, can_use_vault: m.can_use_vault? }
          end
        }
      end

      def set_refresh_cookie(refresh_token)
        cookies.encrypted[REFRESH_COOKIE] = {
          value: refresh_token.raw_token,
          httponly: true,
          secure: cookie_secure?,
          # The SPA and API are same-origin in dev (via the Vite proxy) but may
          # be different subdomains in production, which needs SameSite=None.
          same_site: cookie_same_site,
          expires: refresh_token.expires_at,
          path: "/"
        }
      end

      def clear_refresh_cookie
        cookies.delete(REFRESH_COOKIE, path: "/", same_site: cookie_same_site, secure: cookie_secure?)
      end

      def cookie_secure?
        ENV.fetch("COOKIE_SECURE", Rails.env.production?.to_s) == "true"
      end

      def cookie_same_site
        ENV.fetch("COOKIE_SAME_SITE", Rails.env.production? ? "none" : "lax").to_sym
      end
    end
  end
end
