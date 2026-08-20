# frozen_string_literal: true

module Api
  module V1
    # The signed-in user's own account: who they are, what they are using, and
    # changing their password.
    class AccountController < BaseController
      # GET /api/v1/account
      def show
        render json: { account: serialize_account, storage: storage_breakdown }
      end

      # PATCH /api/v1/account
      def update
        current_user.update!(account_params)
        render json: { account: serialize_account }
      end

      # PATCH /api/v1/account/password
      def update_password
        unless current_user.authenticate(params[:current_password].to_s)
          return render_error(
            message: "That is not your current password.",
            code: "invalid_password",
            status: :unauthorized
          )
        end

        if params[:password].to_s.length < 8
          return render_error(
            message: "Your new password needs at least 8 characters.",
            code: "password_too_short",
            status: :unprocessable_content
          )
        end

        current_user.update!(password: params[:password])

        # A password change is what you do when you think somebody else has it,
        # so every other session ends — otherwise the change achieves nothing.
        ended = revoke_other_sessions

        render json: { ok: true, sessions_ended: ended }
      end

      private

      def account_params
        params.permit(:full_name, :timezone)
      end

      def revoke_other_sessions
        current = RefreshToken.find_by_raw_token(cookies.encrypted[AuthController::REFRESH_COOKIE])

        scope = current_user.refresh_tokens.active
        scope = scope.where.not(id: current.id) if current
        scope.each(&:revoke!).size
      end

      def serialize_account
        {
          id: current_user.id,
          email: current_user.email,
          full_name: current_user.full_name,
          avatar_url: current_user.avatar_url,
          timezone: current_user.timezone,
          two_factor_enabled: current_user.two_factor_enabled,
          last_signed_in_at: current_user.last_signed_in_at,
          created_at: current_user.created_at
        }
      end

      # What the quota is actually being spent on. Counts live files only —
      # trashed files still occupy the quota, so they get their own line rather
      # than being folded into a type and looking like something you cannot
      # reclaim.
      def storage_breakdown
        files = current_user.stored_files.where(trashed_at: nil)

        {
          used: current_user.storage_used,
          quota: current_user.storage_quota,
          percent_used: current_user.storage_percent_used,
          by_type: files.group(:file_type).sum(:size),
          counts: files.group(:file_type).count,
          trashed: {
            size: current_user.stored_files.where.not(trashed_at: nil).sum(:size),
            count: current_user.stored_files.where.not(trashed_at: nil).count
          },
          versions: {
            size: FileVersion.joins(:stored_file)
                             .where(stored_files: { user_id: current_user.id }).sum(:size),
            count: FileVersion.joins(:stored_file)
                              .where(stored_files: { user_id: current_user.id }).count
          }
        }
      end
    end
  end
end
