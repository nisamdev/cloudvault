# frozen_string_literal: true

module Api
  module V1
    # Reveal one secret at a time — never bundled into a listing.
    class RecordSecretsController < BaseController
      before_action :set_record
      before_action :set_secret, only: %i[reveal history reveal_version]

      # GET /api/v1/records/:record_id/secrets/:key/reveal
      def reveal
        return unless require_vault!
        return unless authorize_reveal!

        value = RecordSecretSealer.open(
          sealed: @secret.sealed,
          kdf: @secret.kdf,
          vault_key: vault_key
        )

        render json: {
          key: @secret.key,
          value: value,
          updated_at: @secret.updated_at
        }
      end

      # GET /api/v1/records/:record_id/secrets/:key/history
      def history
        return unless require_vault!
        return unless authorize_reveal!

        render json: {
          key: @secret.key,
          versions: @secret.secret_versions.recent_first.map { |version| serialize_version(version) }
        }
      end

      # GET /api/v1/records/:record_id/secrets/:key/history/:version_id/reveal
      def reveal_version
        return unless require_vault!
        return unless authorize_reveal!

        version = @secret.secret_versions.find(params[:version_id])
        value = RecordSecretSealer.open(
          sealed: version.sealed,
          kdf: @secret.kdf,
          vault_key: vault_key
        )

        render json: {
          key: @secret.key,
          value: value,
          replaced_at: version.replaced_at
        }
      end

      private

      def set_record
        record = visible_records.find_by(id: params[:record_id])
        if record.nil? || (record.locked? && !vault_unlocked?) ||
           !RecordPermissions.can_view?(current_user, record)
          render_error(message: "We couldn't find what you were looking for.",
                       code: "not_found", status: :not_found)
          return
        end

        @record = record
      end

      def set_secret
        return unless @record

        @secret = @record.record_secrets.find_by(key: params[:key])
        return if @secret

        render_error(message: "We couldn't find what you were looking for.",
                     code: "not_found", status: :not_found)
      end

      def authorize_reveal!
        return true if RecordPermissions.can_edit?(current_user, @record)

        render_error(message: "You don't have permission to read this secret.",
                     code: "forbidden", status: :forbidden)
        false
      end

      def visible_records
        own = VaultRecord.where(user_id: current_user.id)
        return own unless current_family

        own.or(VaultRecord.where(family_id: current_family.id, visibility: "family"))
      end

      def serialize_version(version)
        {
          id: version.id,
          replaced_at: version.replaced_at
        }
      end
    end
  end
end
