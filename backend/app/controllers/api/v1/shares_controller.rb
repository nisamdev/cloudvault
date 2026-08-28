# frozen_string_literal: true

module Api
  module V1
    # Public share links.
    #
    # Two audiences: the owner managing links (authenticated), and anyone
    # holding a link (not authenticated — the token is the credential).
    class SharesController < BaseController
      allow_unauthenticated :show, :download

      before_action :set_subject, only: %i[index create]
      before_action :set_link_by_token, only: %i[show download]

      # GET /api/v1/shares — every link I have out, across all my files
      def mine
        links = SharedLink.active
                          .where(user_id: current_user.id)
                          .includes(:stored_file, :vault_record)
                          .order(created_at: :desc)

        # A link to something trashed is dead weight; do not list it as live.
        links = links.reject(&:subject_gone?)

        render json: {
          shares: links.map do |link|
            serialize(link).merge(
              subject_summary(link),
              status: link.usable? ? "active" : link.unusable_reason
            )
          end
        }
      end

      # GET /api/v1/files/:file_id/shares — or /records/:record_id/shares
      def index
        authorize_share! or return

        links = SharedLink.active.where(subject_key => @subject.id).order(created_at: :desc)
        render json: { shares: links.map { |link| serialize(link) } }
      end

      # POST /api/v1/files/:file_id/shares — or /records/:record_id/shares
      def create
        authorize_share! or return

        # A public link to an encrypted file would have to hand out the key with
        # it, which is the opposite of what putting it in the private section
        # was for.
        if @subject.is_a?(StoredFile) && @subject.locked?
          return render_error(
            message: "#{@subject.name} is in your private section. Take it out before sharing a link to it.",
            code: "file_locked", status: :unprocessable_content
          )
        end

        link = SharedLink.new(
          subject_key => @subject.id,
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

        unless may_share?(link.subject)
          return render_error(message: "You don't have permission to do that.",
                              code: "forbidden", status: :forbidden)
        end

        link.revoke!
        head :no_content
      end

      # GET /api/v1/shares/:token — public metadata for the share landing page
      def show
        # A trashed file or an archived record must not stay reachable through
        # an old link.
        return render_unusable if @link.nil? || !@link.usable? || @link.subject_gone?

        render json: { share: public_share(@link) }
      end

      # POST /api/v1/shares/:token/download
      def download
        return render_unusable if @link.nil? || !@link.usable? || @link.subject_gone?

        if @link.password_protected? && !@link.authenticate_password(params[:password].to_s)
          return render_error(
            message: "That password is incorrect.",
            code: "invalid_share_password",
            status: :unauthorized
          )
        end

        file = shared_file
        return if performed?

        unless file.attachment.attached?
          return render_error(message: "That file has no contents.", code: "not_found", status: :not_found)
        end

        @link.record_download!

        render json: serve(file)
      end

      private

      # A share hangs off a file or off a record, and everything after this
      # point treats the two the same way.
      def set_subject
        @subject =
          if params[:record_id].present?
            VaultRecord.active.find(params[:record_id])
          elsif params[:folder_id].present?
            Folder.active.find(params[:folder_id])
          else
            StoredFile.find(params[:file_id])
          end

        return if may_view?(@subject)

        render_error(message: "We couldn't find what you were looking for.",
                     code: "not_found", status: :not_found)
      end

      def subject_key
        case @subject
        when VaultRecord then :vault_record_id
        when Folder then :folder_id
        else :stored_file_id
        end
      end

      def may_view?(subject)
        return RecordPermissions.can_view?(current_user, subject) if subject.is_a?(VaultRecord)
        return PermissionChecker.can_view_folder?(current_user, subject) if subject.is_a?(Folder)

        PermissionChecker.can_view?(current_user, subject)
      end

      # Sharing a record is the owner's call, or an editor's — the same people
      # who could change it.
      def may_share?(subject)
        return false if subject.nil?
        return RecordPermissions.can_edit?(current_user, subject) if subject.is_a?(VaultRecord)
        # An album is somebody's own, so sharing it is theirs to decide.
        return subject.user_id == current_user.id if subject.is_a?(Folder)

        PermissionChecker.can_share?(current_user, subject)
      end

      # The file a public visitor is asking for. For a file share there is only
      # one; for a record share it must be one of that record's own documents,
      # or the link becomes a way to read the whole vault.
      def shared_file
        if @link.for_album?
          photo = @link.album_photos.find_by(id: params[:file_id])
          if photo.nil?
            render_error(message: "That photo is not part of this album.",
                         code: "not_found", status: :not_found)
            return nil
          end

          return photo
        end

        return @link.stored_file unless @link.for_record?

        file = @link.vault_record.stored_files.find_by(id: params[:file_id])
        if file.nil? || file.trashed?
          render_error(message: "That document is not part of this share.",
                       code: "not_found", status: :not_found)
          return nil
        end

        file
      end

      # What anybody holding the link is shown. Never a secret: a record's
      # passwords are encrypted under a passphrase this link does not have.
      def public_share(link)
        base = {
          requires_password: link.password_protected?,
          expires_at: link.expires_at,
          kind: if link.for_record? then "record"
                elsif link.for_album? then "album"
                else "file"
                end
        }

        return base.merge(record: shared_record(link.vault_record)) if link.for_record?
        return base.merge(album: shared_album(link)) if link.for_album?

        base.merge(file: shared_file_summary(link.stored_file))
      end

      # An album and the photographs in it, as anybody holding the link sees it.
      def shared_album(link)
        photos = link.album_photos

        {
          name: link.folder.name,
          shared_by: link.folder.user.full_name || link.folder.user.email,
          count: photos.size,
          photos: photos.map do |photo|
            {
              id: photo.id,
              name: photo.name,
              size: photo.size,
              taken_at: photo.taken_at,
              place_name: photo.place_name,
              width: photo.image_width,
              height: photo.image_height
            }
          end
        }
      end

      def shared_record(record)
        template = record.template

        {
          title: record.title,
          type_label: template&.label || record.record_type,
          shared_by: record.user.full_name || record.user.email,
          # Only fields the template knows and the record filled in, in the
          # order the form shows them. Nothing invented, nothing encrypted.
          details: (template&.fields || []).reject(&:secret?).filter_map do |field|
            value = record.data[field.key]
            { label: field.label, value: value, kind: field.kind } if value.present?
          end,
          documents: record.stored_files.reject(&:trashed?).map do |file|
            { id: file.id, name: file.name, size: file.size, mime_type: file.mime_type }
          end
        }
      end

      def shared_file_summary(file)
        {
          name: file.name,
          size: file.size,
          mime_type: file.mime_type,
          file_type: file.file_type,
          shared_by: file.user.full_name || file.user.email
        }
      end

      # One row in "links I have out", whichever kind it is.
      def subject_summary(link)
        if link.for_album?
          return { album: { id: link.folder_id, name: link.folder.name,
                            count: link.album_photos.size } }
        end

        return { file: shared_file_summary(link.stored_file).merge(id: link.stored_file_id) } unless link.for_record?

        record = link.vault_record
        { record: { id: record.id, title: record.title, record_type: record.record_type,
                    document_count: record.stored_files.reject(&:trashed?).size } }
      end

      def set_link_by_token
        @link = SharedLink.find_by_raw_token(params[:token])
      end

      def authorize_share!
        return true if may_share?(@subject)

        render_error(
          message: "You don't have permission to share this.",
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
