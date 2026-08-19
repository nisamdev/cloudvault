# frozen_string_literal: true

module Api
  module V1
    class FamiliesController < BaseController
      before_action :set_family, only: %i[show update]

      # POST /api/v1/families
      def create
        if current_user.primary_membership.present?
          return render_error(
            message: "You already belong to a family.",
            code: "family_exists",
            status: :conflict
          )
        end

        family = Family.new(family_params.merge(owner: current_user))
        family.family_storage_quota = ENV.fetch("FAMILY_STORAGE_QUOTA_BYTES", 2_147_483_648).to_i
        family.save!

        render json: { family: serialize_family(family, current_user) }, status: :created
      end

      # GET /api/v1/families/:id
      def show
        render json: {
          family: serialize_family(@family, current_user),
          members: @family.family_members.includes(:user).map { |m| serialize_member(m) },
          invitations: @family.family_invitations.pending.map { |i| serialize_invitation(i) }
        }
      end

      # PATCH /api/v1/families/:id
      def update
        authorize_manage!(@family) or return

        @family.update!(family_params)
        render json: { family: serialize_family(@family, current_user) }
      end

      private

      def set_family
        @family = Family.find(params[:id])

        # Membership is the gate: a family is invisible to everyone outside it,
        # and we return 404 rather than 403 so its existence isn't confirmed.
        return if @family.family_members.exists?(user_id: current_user.id)

        render_error(
          message: "We couldn't find what you were looking for.",
          code: "not_found",
          status: :not_found
        )
      end

      def authorize_manage!(family)
        return true if PermissionChecker.can_manage_family?(current_user, family)

        render_error(
          message: "Only family owners and admins can do that.",
          code: "forbidden",
          status: :forbidden
        )
        false
      end

      def family_params
        params.require(:family).permit(:name, :description)
      end

      def serialize_family(family, user)
        membership = family.family_members.find_by(user_id: user.id)

        {
          id: family.id,
          name: family.name,
          description: family.description,
          role: membership&.role,
          storage_quota: family.family_storage_quota,
          storage_used: family.family_storage_used,
          storage_percent_used: family.storage_percent_used,
          member_count: family.family_members.count,
          created_at: family.created_at
        }
      end

      def serialize_member(member)
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

      def serialize_invitation(invitation)
        {
          id: invitation.id,
          email: invitation.email,
          role: invitation.role,
          expires_at: invitation.expires_at,
          created_at: invitation.created_at
        }
      end
    end
  end
end
