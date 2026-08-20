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
        role = params[:role].to_s

        return render_role_error("That is not a role.") unless FamilyMember::ROLES.include?(role)
        # Ownership is not a role you hand out; it decides who the family
        # belongs to, and the model only permits one.
        return render_role_error("Ownership cannot be reassigned here.") if role == "owner" || member.owner?

        member.update!(role: role)
        render json: { member: serialize(member) }
      end

      # DELETE /api/v1/families/:family_id/members/:id
      def destroy
        member = @family.family_members.find(params[:id])

        return render_role_error("The owner cannot be removed from the family.") if member.owner?

        # Their files stay: they belong to the family, and removing a person
        # should not silently delete the passports they scanned. What changes is
        # that they can no longer reach them.
        member.destroy!
        head :no_content
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

      def serialize(member)
        {
          id: member.id,
          role: member.role,
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
