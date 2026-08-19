# frozen_string_literal: true

module Api
  module V1
    class InvitationsController < BaseController
      # Accepting an invite is how a brand-new user joins, so it must be
      # reachable while signed out; the token is the credential.
      allow_unauthenticated :show

      before_action :set_family, only: %i[create destroy]

      # POST /api/v1/families/:family_id/invitations
      def create
        authorize_manage! or return

        email = params[:email].to_s.strip.downcase

        if @family.family_members.joins(:user).exists?(users: { email: email })
          return render_error(
            message: "That person is already in your family.",
            code: "already_member",
            status: :conflict
          )
        end

        # Re-inviting replaces any outstanding invite rather than colliding with
        # the partial unique index on pending invitations.
        @family.family_invitations.pending.where(email: email).update_all(revoked_at: Time.current)

        invitation = @family.family_invitations.create!(
          email: email,
          role: params[:role].presence || "viewer",
          invited_by: current_user
        )

        FamilyInvitationMailer.invite(invitation, invitation.raw_token).deliver_later

        render json: { invitation: serialize(invitation) }, status: :created
      end

      # GET /api/v1/invitations/:token
      # Lets the accept screen show who invited you before you sign up.
      def show
        invitation = FamilyInvitation.find_by_raw_token(params[:token])

        unless invitation&.pending?
          return render_error(
            message: "This invitation is no longer valid.",
            code: "invalid_invitation",
            status: :not_found
          )
        end

        render json: {
          invitation: {
            email: invitation.email,
            role: invitation.role,
            family_name: invitation.family.name,
            invited_by: invitation.invited_by.full_name || invitation.invited_by.email,
            expires_at: invitation.expires_at
          }
        }
      end

      # POST /api/v1/invitations/:token/accept
      def accept
        invitation = FamilyInvitation.find_by_raw_token(params[:token])

        unless invitation&.pending?
          return render_error(
            message: "This invitation is no longer valid.",
            code: "invalid_invitation",
            status: :not_found
          )
        end

        # An invitation is addressed to one mailbox; accepting from a different
        # account would let a forwarded email leak family access.
        unless invitation.email == current_user.email
          return render_error(
            message: "This invitation was sent to #{invitation.email}.",
            code: "invitation_email_mismatch",
            status: :forbidden
          )
        end

        if current_user.primary_membership.present?
          return render_error(
            message: "You already belong to a family.",
            code: "family_exists",
            status: :conflict
          )
        end

        member = nil
        ActiveRecord::Base.transaction do
          member = invitation.family.family_members.create!(
            user: current_user,
            role: invitation.role,
            joined_at: Time.current
          )
          invitation.update!(accepted_at: Time.current)
        end

        render json: {
          family: {
            id: invitation.family_id,
            name: invitation.family.name,
            role: member.role
          }
        }, status: :created
      end

      # DELETE /api/v1/families/:family_id/invitations/:id
      def destroy
        authorize_manage! or return

        invitation = @family.family_invitations.find(params[:id])
        invitation.update!(revoked_at: Time.current)

        head :no_content
      end

      private

      def set_family
        @family = Family.find(params[:family_id])

        return if @family.family_members.exists?(user_id: current_user.id)

        render_error(message: "We couldn't find what you were looking for.",
                     code: "not_found", status: :not_found)
      end

      def authorize_manage!
        return true if PermissionChecker.can_manage_family?(current_user, @family)

        render_error(
          message: "Only family owners and admins can invite people.",
          code: "forbidden",
          status: :forbidden
        )
        false
      end

      def serialize(invitation)
        {
          id: invitation.id,
          email: invitation.email,
          role: invitation.role,
          expires_at: invitation.expires_at
        }
      end
    end
  end
end
