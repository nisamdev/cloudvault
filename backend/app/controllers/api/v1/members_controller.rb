# frozen_string_literal: true

module Api
  module V1
    # Changing what someone in the family may do, or removing them.
    class MembersController < BaseController
      before_action :set_family
      before_action :authorize_manage!

      # PATCH /api/v1/families/:family_id/members/:id
      def update
        member = @family.family_members.find(params[:id])

        # Two separate decisions, and a request may carry either or both: what
        # somebody may do with the family's things, and whether they reach them
        # at all.
        set_vault_access(member) if params.key?(:can_use_vault)
        return if performed?

        if params.key?(:role)
          role = params[:role].to_s

          return render_role_error("That is not a role.") unless FamilyMember::ROLES.include?(role)
          # Ownership is not a role you hand out; it decides who the family
          # belongs to, and the model only permits one.
          if role == "owner" || member.owner?
            return render_role_error("Ownership cannot be reassigned here.")
          end

          member.role = role
        end

        member.save!
        render json: { member: serialize(member) }
      end

      # DELETE /api/v1/families/:family_id/members/:id
      def destroy
        member = @family.family_members.find(params[:id])

        return render_role_error("The owner cannot be removed from the family.") if member.owner?

        # What they shared stays with the family and becomes the owner's: a
        # departing person must not take the passports they scanned, and must
        # not keep the keys to them either.
        summary = FamilyDeparture.new(member).call

        render json: { kept: summary.to_h }
      end

      private

      def set_family
        @family = Family.find(params[:family_id])
      end

      def authorize_manage!
        return if PermissionChecker.can_manage_family?(current_user, @family)

        render_error(
          message: "Only a family admin can manage members.",
          code: "forbidden",
          status: :forbidden
        )
      end

      def render_role_error(message)
        render_error(message: message, code: "invalid_role", status: :unprocessable_content)
      end

      # The owner is the one person who cannot be shut out: somebody has to be
      # able to open the door again.
      def set_vault_access(member)
        if member.owner?
          render_role_error("The owner always has the family's things.")
          return
        end

        member.can_use_vault = ActiveModel::Type::Boolean.new.cast(params[:can_use_vault])
        member.vault_note = params[:vault_note].to_s.strip.presence if params.key?(:vault_note)
      end

      def serialize(member)
        {
          id: member.id,
          role: member.role,
          can_use_vault: member.can_use_vault?,
          vault_access_decided: member.vault_access_decided?,
          vault_note: member.vault_note,
          joined_at: member.joined_at,
          user: {
            id: member.user_id,
            email: member.user.email,
            full_name: member.user.full_name,
            avatar_url: member.user.avatar_url
          }
        }
      end
    end
  end
end
