# frozen_string_literal: true

module Api
  module V1
    # Public share links.
    #
    # Two audiences: the owner managing links (authenticated), and anyone
    # holding a link (not authenticated — the token is the credential).
    class SharesController < BaseController
      allow_unauthenticated :show, :download

      before_action :set_file, only: %i[index create]
      before_action :set_link_by_token, only: %i[show download]

      # GET /api/v1/shares — every link I have out, across all my files
      def mine
        links = SharedLink.active
                          .where(user_id: current_user.id)
                          .includes(:stored_file)
                          .order(created_at: :desc)

        # A link to a trashed file is dead weight; do not list it as live.
        links = links.reject { |link| link.stored_file.nil? || link.stored_file.trashed? }

        render json: {
          shares: links.map do |link|
            serialize(link).merge(
              file: {
                id: link.stored_file_id,
                name: link.stored_file.name,
                mime_type: link.stored_file.mime_type,
                file_type: link.stored_file.file_type
              },
              status: link.usable? ? "active" : link.unusable_reason
            )
          end
        }
      end

      # GET /api/v1/files/:file_id/shares
      def index
        authorize_share! or return

        links = @file.shared_links.active.order(created_at: :desc)
        render json: { shares: links.map { |link| serialize(link) } }
      end

      # POST /api/v1/files/:file_id/shares
      def create
        authorize_share! or return

        link = @file.shared_links.new(
          user: current_user,
          expires_at: parse_expiry,
          max_downloads: params[:max_downloads].presence
        )
        # has_secure_password with validations disabled: assign only when given.
        link.password = params[:password] if params[:password].present?
        link.save!

        # The raw token is returned exactly once — it is never recoverable later.
        render json: { share: serialize(link, include_url: true) }, status: :created
      end

      # DELETE /api/v1/shares/:id
      def destroy
        link = SharedLink.find(params[:id])

        unless PermissionChecker.can_share?(current_user, link.stored_file)
          return render_error(message: "You don't have permission to do that.",
                              code: "forbidden", status: :forbidden)
        end

        link.revoke!
        head :no_content
      end

      # GET /api/v1/shares/:token — public metadata for the share landing page
      def show
        return render_unusable if @link.nil? || !@link.usable?

        file = @link.stored_file
        # A trashed file must not stay reachable through an old link.
        return render_unusable if file.trashed?

        render json: {
          share: {
            requires_password: @link.password_protected?,
            expires_at: @link.expires_at,
            file: {
              name: file.name,
              size: file.size,
              mime_type: file.mime_type,
              file_type: file.file_type,
              shared_by: file.user.full_name || file.user.email
            }
          }
        }
      end

      # POST /api/v1/shares/:token/download
      def download
        return render_unusable if @link.nil? || !@link.usable?

        file = @link.stored_file
        return render_unusable if file.trashed?

        if @link.password_protected? && !@link.authenticate_password(params[:password].to_s)
          return render_error(
            message: "That password is incorrect.",
            code: "invalid_share_password",
            status: :unauthorized
          )
        end

        unless file.attachment.attached?
          return render_error(message: "That file has no contents.", code: "not_found", status: :not_found)
        end

        @link.record_download!

        render json: serve(file)
      end

      private

      def set_file
        @file = StoredFile.find(params[:file_id])

        return if PermissionChecker.can_view?(current_user, @file)

        render_error(message: "We couldn't find what you were looking for.",
                     code: "not_found", status: :not_found)
      end

      def set_link_by_token
        @link = SharedLink.find_by_raw_token(params[:token])
      end

      def authorize_share!
        return true if PermissionChecker.can_share?(current_user, @file)

        render_error(
          message: "You don't have permission to share this file.",
          code: "forbidden",
          status: :forbidden
        )
        false
      end

      # One message for every unusable state: an attacker probing tokens learns
      # nothing about whether a link ever existed.
      # A public link has left the family, so a photo going down it is cleaned of
      # where it was taken first. Family members still get the original, with the
      # metadata the app shows them.
      def serve(file)
        blob = file.attachment.blob

        unless MetadataStripper.strippable?(blob.content_type)
          return {
            url: StorageUrl.for(file.attachment, expires_in: 5.minutes,
                                disposition: "attachment", filename: file.name),
            filename: file.name
          }
        end

        name = served_name(file, blob)

        {
          url: StorageUrl.stripped(blob, expires_in: 5.minutes,
                                   disposition: "attachment", filename: name),
          filename: name,
          metadata_removed: true
        }
      end

      # HEIC cannot be written back out here, so a cleaned copy is a JPEG and the
      # name has to say so rather than lying about what was downloaded.
      def served_name(file, blob)
        extension = MetadataStripper.output_for(blob.content_type)[:extension]
        return file.name if extension.nil?

        "#{File.basename(file.name, '.*')}#{extension}"
      end

      def render_unusable
        render_error(
          message: "This link is no longer available.",
          code: "share_unavailable",
          status: :not_found
        )
      end

      def parse_expiry
        case params[:expires_in]
        when "1h" then 1.hour.from_now
        when "24h", "1d" then 1.day.from_now
        when "7d" then 7.days.from_now
        when "30d" then 30.days.from_now
        when "never", "", nil then nil
        else
          Time.zone.parse(params[:expires_in].to_s) rescue nil
        end
      end

      def serialize(link, include_url: false)
        payload = {
          id: link.id,
          expires_at: link.expires_at,
          password_protected: link.password_protected?,
          download_count: link.download_count,
          max_downloads: link.max_downloads,
          last_accessed_at: link.last_accessed_at,
          created_at: link.created_at
        }
        # Only ever populated on creation; the token cannot be recovered after.
        # Built from the origin the browser used, so a link created through a
        # tunnel is reachable by whoever it is sent to.
        payload[:url] = link.url(frontend_origin) if include_url
        payload
      end
    end
  end
end
