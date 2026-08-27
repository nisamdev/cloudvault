# frozen_string_literal: true

module Api
  module V1
    # Sharing one file or folder with one person, or with a family.
    #
    # Separate from SharesController, which makes public links for people with
    # no account. This is access for someone the vault already knows.
    class GrantsController < BaseController
      before_action :set_resource
      before_action :authorize_share!

      # GET /api/v1/files/:file_id/grants
      def index
        render json: { grants: grants_for(@resource).map { |g| serialize(g) } }
      end

      # POST /api/v1/files/:file_id/grants
      def create
        # Sharing with a person means they can read it, and they have no way to:
        # only the owner's passphrase opens the private section.
        if @resource.respond_to?(:locked?) && @resource.locked?
          return render_error(
            message: "That is in your private section. Take it out before sharing it with anyone.",
            code: "resource_locked", status: :unprocessable_content
          )
        end

        subject = resolve_subject
        return if performed?

        if subject.is_a?(User) && subject.id == @resource.user_id
          return render_error(message: "They already own this.",
                              code: "already_owner", status: :unprocessable_content)
        end

        grant = AccessGrant.find_or_initialize_by(resource: @resource, subject: subject)
        grant.granted_by = current_user
        grant.role = params[:role].presence || "viewer"
        grant.expires_at = params[:expires_at].presence

        unless grant.save
          return render_error(message: grant.errors.full_messages.to_sentence,
                              code: "invalid_grant", status: :unprocessable_content)
        end

        render json: { grant: serialize(grant) }, status: :created
      end

      # PATCH /api/v1/grants/:id
      def update
        @grant.update!(role: params[:role], expires_at: params[:expires_at].presence)
        render json: { grant: serialize(@grant) }
      rescue ActiveRecord::RecordInvalid => e
        render_error(message: e.record.errors.full_messages.to_sentence,
                     code: "invalid_grant", status: :unprocessable_content)
      end

      # DELETE /api/v1/grants/:id
      def destroy
        @grant.destroy!
        head :no_content
      end

      private

      # Nested under a file or a folder for index/create; addressed by its own id
      # for update/destroy, where the resource comes from the grant.
      def set_resource
        if params[:id].present?
          @grant = AccessGrant.find(params[:id])
          @resource = @grant.resource
        elsif params[:file_id].present?
          @resource = StoredFile.find(params[:file_id])
        else
          @resource = Folder.find(params[:folder_id])
        end
      end

      # Handing out access is the owner's call, or a family admin's. Somebody
      # who was merely granted edit cannot pass that on.
      def authorize_share!
        return if may_share?(@resource)

        render_error(message: "You don't have permission to share this.",
                     code: "forbidden", status: :forbidden)
      end

      def may_share?(resource)
        return PermissionChecker.can_share?(current_user, resource) if resource.is_a?(StoredFile)

        resource.user_id == current_user.id ||
          PermissionChecker.can_manage_family?(current_user, resource.family)
      end

      # Who to share with: an existing account by email, or one of the caller's
      # families by id.
      def resolve_subject
        if params[:family_id].present?
          family = current_user.families.find_by(id: params[:family_id])
          return family if family

          render_error(message: "We couldn't find that family.",
                       code: "family_not_found", status: :not_found)
          return nil
        end

        email = params[:email].to_s.strip.downcase
        user = User.find_by(email: email)
        return user if user

        # Deliberately not an invitation: a grant needs somebody to point at.
        # Inviting a stranger to the vault is a different, heavier decision.
        render_error(
          message: "Nobody here uses #{email}. Invite them to the family first, or send a public link.",
          code: "user_not_found",
          status: :not_found
        )
        nil
      end

      def grants_for(resource)
        AccessGrant.where(resource: resource).includes(:subject).order(created_at: :desc)
      end

      def serialize(grant)
        {
          id: grant.id,
          role: grant.role,
          expires_at: grant.expires_at,
          expired: grant.expired?,
          created_at: grant.created_at,
          subject: serialize_subject(grant.subject)
        }
      end

      def serialize_subject(subject)
        if subject.is_a?(Family)
          { type: "family", id: subject.id, name: subject.name, member_count: subject.family_members.count }
        else
          { type: "user", id: subject.id, name: subject.full_name.presence || subject.email, email: subject.email }
        end
      end
    end
  end
end
