# frozen_string_literal: true

module Api
  module V1
    # The private section: setting it up, opening it, and closing it again.
    #
    # Nothing here ever returns the vault key. Unlocking hands back a token that
    # is only half of it — see VaultSession for why.
    class VaultsController < BaseController
      # GET /api/v1/vault
      def show
        render json: status_payload
      end

      # POST /api/v1/vault — set one up
      def create
        if vault
          return render_error(message: "You already have a private section.",
                              code: "vault_exists", status: :unprocessable_content)
        end

        created, recovery_key = PrivateVault.open_for(current_user, params[:passphrase])

        render json: status_payload(created, unlocked: true).merge(
          # The only time this exists anywhere. It is not stored, and asking for
          # it again is not possible.
          recovery_key: recovery_key,
          token: VaultSession.open(user: current_user, vault_key: created.unlock(params[:passphrase]))
        ), status: :created
      rescue PrivateVault::WrongPassphrase => e
        render_error(message: e.message, code: "weak_passphrase", status: :unprocessable_content)
      end

      # POST /api/v1/vault/unlock
      def unlock
        return no_vault unless vault

        key = vault.unlock(params[:passphrase])
        vault.update(unlocked_at: Time.current)

        render json: status_payload(unlocked: true).merge(
          token: VaultSession.open(user: current_user, vault_key: key)
        )
      rescue PrivateVault::WrongPassphrase => e
        # Deliberately slow and deliberately vague, and rate-limited by
        # Rack::Attack alongside the login endpoints.
        render_error(message: e.message, code: "wrong_passphrase", status: :unauthorized)
      end

      # DELETE /api/v1/vault/unlock — lock it again
      def lock
        VaultSession.close(request.headers[VaultAccess::HEADER])

        render json: status_payload(unlocked: false)
      end

      # PATCH /api/v1/vault/passphrase
      def change_passphrase
        return no_vault unless vault

        vault.change_passphrase(current: params[:current_passphrase], to: params[:passphrase])

        render json: status_payload(unlocked: true).merge(
          token: VaultSession.open(user: current_user, vault_key: vault.unlock(params[:passphrase]))
        )
      rescue PrivateVault::WrongPassphrase => e
        render_error(message: e.message, code: "wrong_passphrase", status: :unauthorized)
      end

      # POST /api/v1/vault/recover — the way back in when the passphrase is gone
      def recover
        return no_vault unless vault

        recovery_key = vault.reset_with_recovery(
          recovery_key: params[:recovery_key], passphrase: params[:passphrase]
        )

        render json: status_payload(unlocked: true).merge(
          recovery_key: recovery_key,
          token: VaultSession.open(user: current_user, vault_key: vault.unlock(params[:passphrase]))
        )
      rescue PrivateVault::WrongPassphrase => e
        render_error(message: e.message, code: "wrong_recovery_key", status: :unauthorized)
      end

      # POST /api/v1/vault/recovery_key_seen — stop nagging about writing it down
      def recovery_key_seen
        return no_vault unless vault

        vault.update!(recovery_key_shown_at: Time.current)
        render json: status_payload
      end

      private

      def vault
        @vault ||= PrivateVault.find_by(user_id: current_user.id)
      end

      def no_vault
        render_error(message: "You haven't set up a private section yet.",
                     code: "no_vault", status: :not_found)
      end

      def status_payload(record = vault, unlocked: nil)
        {
          exists: record.present?,
          # A response that is handing back a token is describing an unlocked
          # section, whatever this particular request carried.
          unlocked: unlocked.nil? ? vault_unlocked? : unlocked,
          recovery_key_acknowledged: record&.recovery_key_shown_at.present?,
          locked_files: current_user.stored_files.active.where(locked: true).count,
          locked_folders: current_user.folders.active.where(locked: true).count,
          # Records can be locked too. Counting only files made the locked
          # screen say "0 files, 0 folders" over a section that had things in it.
          locked_records: VaultRecord.active.where(user_id: current_user.id, locked: true).count
        }
      end
    end
  end
end
