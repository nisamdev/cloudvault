# frozen_string_literal: true

module Api
  module V1
    class FamiliesController < BaseController
      before_action :set_family, only: %i[show update]

      # GET /api/v1/families — every family this account belongs to
      def index
        families = current_user.families.includes(:family_members).order(:created_at)

        render json: {
          families: families.map { |f| serialize_family(f, current_user) },
          current_family_id: current_user.current_membership&.family_id
        }
      end

      # POST /api/v1/families
      #
      # A family is something you create when you want one, and you can have
      # more than one — "Family", "Parents' house", "Tax stuff". Nothing about
      # an account requires any.
      def create
        family = Family.new(family_params.merge(owner: current_user))
        family.family_storage_quota = ENV.fetch("FAMILY_STORAGE_QUOTA_BYTES", 2_147_483_648).to_i
        family.save!

        # A newly created family is the one you meant to be working in.
        current_user.update!(current_family_id: family.id)

        render json: { family: serialize_family(family, current_user) }, status: :created
      end

      # POST /api/v1/families/:id/select — which family the app is showing
      def select
        membership = current_user.family_memberships.find_by(family_id: params[:id])

        unless membership
          return render_error(message: "We couldn't find that family.",
                              code: "not_found", status: :not_found)
        end

        current_user.update!(current_family_id: membership.family_id)
        render json: { family: serialize_family(membership.family, current_user) }
      end

      # DELETE /api/v1/families/:id/leave
      def leave
        membership = current_user.family_memberships.find_by(family_id: params[:id])

        unless membership
          return render_error(message: "We couldn't find that family.",
                              code: "not_found", status: :not_found)
        end

        # The owner cannot walk away and leave it ownerless; they delete it or
        # hand it on, neither of which is a one-click action.
        if membership.owner?
          return render_error(
            message: "You own this family, so you can't leave it.",
            code: "owner_cannot_leave",
            status: :unprocessable_content
          )
        end

        # Their files stay where they are — they belong to the family — but the
        # personal ones come with them.
        membership.destroy!
        current_user.update!(current_family_id: current_user.family_memberships.first&.family_id)

        head :no_content
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
          can_use_vault: membership.nil? || membership.can_use_vault?,
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
