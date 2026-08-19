# frozen_string_literal: true

module Api
  module V1
    class FilesController < BaseController
      before_action :set_file, only: %i[show update destroy download restore preview purge]

      # GET /api/v1/files
      # Params: folder_id, file_type (file|image), trashed, q, page, per_page
      def index
        scope = visible_files
        scope = params[:trashed] == "true" ? scope.trashed : scope.active
        scope = scope.where(file_type: params[:file_type]) if StoredFile::FILE_TYPES.include?(params[:file_type])
        # folder_id=<id> scopes to that folder; folder_id= (blank) means the root.
        # Omitting the parameter searches across all folders, which is what a
        # search should do.
        scope = scope.where(folder_id: params[:folder_id].presence) if params.key?(:folder_id)

        scope = scope.with_labels(params[:label_ids]) if params[:label_ids].present?
        scope = scope.search(params[:q]) if params[:q].present?

        # Gallery filters. Each is a no-op when its parameter is absent.
        scope = scope.by_owner(params[:owner_id])
        scope = scope.with_visibility(params[:visibility])
        scope = scope.with_orientation(params[:orientation])
        scope = scope.uploaded_between(*date_range)
        scope = scope.with_location if params[:has_location] == "true"

        pagy, records = pagy(
          scope.sorted_by(params[:sort]).includes(:user, :folder, :labels, attachment_attachment: :blob),
          limit: per_page
        )
        pagination_headers(pagy)

        render json: { files: records.map { |f| serialize(f) } }
      end

      # GET /api/v1/files/:id
      def show
        render json: {
          file: serialize(@file, detailed: true),
          details: details_for(@file),
          versions: @file.file_versions.newest_first.map { |v| serialize_version(v) }
        }
      end

      # POST /api/v1/files
      def create
        upload = params[:file]
        return render_error(message: "No file was uploaded.", code: "file_missing", status: :bad_request) if upload.blank?

        visibility = params[:visibility].presence || "private"
        folder = find_folder(params[:folder_id])

        if visibility == "family"
          unless PermissionChecker.can_upload_to_family?(current_user, current_family)
            return render_error(
              message: "You don't have permission to add files to the family vault.",
              code: "forbidden",
              status: :forbidden
            )
          end
        end

        # Uploading a file whose name already exists in the same folder creates a
        # new version instead of a duplicate entry.
        existing = visible_files.active
                                .where(folder_id: folder&.id, name: File.basename(upload.original_filename.to_s))
                                .first
        replaces = existing if existing && PermissionChecker.can_edit?(current_user, existing)

        stored_file = FileUploader
          .new(user: current_user, family: current_family)
          .call(upload, folder: folder, visibility: visibility, replaces: replaces)

        render json: { file: serialize(stored_file, detailed: true) },
               status: replaces ? :ok : :created
      rescue FileUploader::QuotaExceeded => e
        render_error(message: e.message, code: "quota_exceeded", status: :content_too_large)
      rescue FileUploader::FileTooLarge => e
        render_error(message: e.message, code: "file_too_large", status: :content_too_large)
      rescue FileUploader::UnsupportedType => e
        render_error(message: e.message, code: "unsupported_type", status: :unsupported_media_type)
      end

      # PATCH /api/v1/files/:id
      def update
        authorize!(:edit) or return

        attrs = file_params.to_h
        # Visibility is not a plain attribute: it moves the file in and out of
        # the family vault and shifts the storage accounting with it.
        visibility = attrs.delete("visibility")

        # A move must land somewhere the caller can reach. Blank means the root.
        if attrs.key?("folder_id") && attrs["folder_id"].present?
          target = find_folder(attrs["folder_id"])

          unless target
            return render_error(message: "We couldn't find that folder.",
                                code: "folder_not_found", status: :not_found)
          end

          attrs["folder_id"] = target.id
        end

        StoredFile.transaction do
          @file.update!(attrs) if attrs.any?
          FileVisibilityUpdater.new(file: @file, user: current_user).call(visibility) if visibility
          assign_labels! if params.key?(:label_ids)
        end

        render json: { file: serialize(@file, detailed: true) }
      rescue FileVisibilityUpdater::Forbidden => e
        render_error(message: e.message, code: "forbidden", status: :forbidden)
      rescue FileVisibilityUpdater::QuotaExceeded => e
        render_error(message: e.message, code: "quota_exceeded", status: :content_too_large)
      rescue FileVisibilityUpdater::Error => e
        render_error(message: e.message, code: "invalid_visibility", status: :unprocessable_content)
      end

      # DELETE /api/v1/files/:id  — soft delete, recoverable from Trash
      def destroy
        authorize!(:delete) or return

        @file.trash!
        head :no_content
      end

      # POST /api/v1/files/:id/restore
      def restore
        authorize!(:delete) or return

        # A file whose folder was trashed alongside it would come back into a
        # folder the user cannot navigate to, so it returns to the root.
        @file.folder = nil if @file.folder&.trashed_at
        @file.restore!

        render json: { file: serialize(@file) }
      end

      # DELETE /api/v1/files/:id/purge — permanent, releases the storage
      def purge
        authorize!(:delete) or return

        unless @file.trashed?
          return render_error(
            message: "Move the file to trash before deleting it permanently.",
            code: "not_trashed",
            status: :unprocessable_content
          )
        end

        FilePurger.new(@file).call
        head :no_content
      end

      # GET /api/v1/files/:id/download
      def download
        unless @file.attachment.attached?
          return render_error(message: "That file has no contents.", code: "not_found", status: :not_found)
        end

        @file.update_column(:last_accessed_at, Time.current)

        # Returns the presigned URL rather than redirecting to it.
        #
        # The SPA has to send a bearer token to reach this endpoint, which a
        # plain <a href> cannot do, and following a redirect through XHR would
        # drag CORS preflight into the storage request. Handing back the URL lets
        # the browser navigate straight to object storage — the bytes never pass
        # through Puma either way. Signed for the public endpoint (StorageUrl).
        render json: {
          url: StorageUrl.for(
            @file.attachment,
            expires_in: 5.minutes,
            disposition: "attachment",
            filename: @file.name
          ),
          expires_in: 300,
          filename: @file.name
        }
      end

      # GET /api/v1/files/:id/preview
      #
      # Describes how the file can be shown in the browser and hands back what
      # is needed to show it.
      #
      # Media gets an inline presigned URL the browser loads directly. Text is
      # returned in the body instead: reading it with fetch() would need CORS
      # configured on the storage bucket, which is one more thing to get wrong
      # in every environment.
      def preview
        unless @file.attachment.attached?
          return render json: { kind: "none", reason: "empty" }
        end

        kind = preview_kind(@file)

        payload = { kind: kind, name: @file.name, mime_type: @file.mime_type, size: @file.size }

        case kind
        when "text"
          text = @file.attachment.blob.download.byteslice(0, TEXT_PREVIEW_LIMIT)
          payload[:text] = text.force_encoding("UTF-8").scrub("?")
          payload[:truncated] = @file.size.to_i > TEXT_PREVIEW_LIMIT
        when "image", "pdf", "video", "audio"
          payload[:url] =
            if kind == "image" && needs_conversion?(@file)
              # No browser but Safari renders HEIC, so hand back a JPEG rendition
              # instead of the original. Active Storage keeps the processed
              # variant, so this cost is paid once per photo.
              converted_preview_url(@file)
            else
              StorageUrl.for(@file.attachment, expires_in: 15.minutes, disposition: "inline")
            end

          if kind == "image"
            payload[:width] = @file.image_width
            payload[:height] = @file.image_height
            payload[:converted] = needs_conversion?(@file)
          end
        end

        render json: payload
      end

      private

      TEXT_PREVIEW_LIMIT = 512 * 1024 # 512 KB is plenty to read; more just hangs the tab.

      # Formats no mainstream browser can display inline. AVIF is deliberately
      # absent: Chrome, Firefox and Safari all render it.
      UNDISPLAYABLE_IMAGE_TYPES = %w[image/heic image/heif image/tiff image/x-tiff].freeze

      PREVIEW_LIMIT = [ 2048, 2048 ].freeze

      def needs_conversion?(file)
        UNDISPLAYABLE_IMAGE_TYPES.include?(file.mime_type.to_s.downcase)
      end

      # Renders the photo to JPEG once and serves that. Falls back to the
      # original if conversion fails, so the client still gets something.
      def converted_preview_url(file)
        variant = file.attachment.variant(
          resize_to_limit: PREVIEW_LIMIT,
          format: :jpeg,
          saver: { quality: 85 }
        ).processed

        StorageUrl.for_blob(variant.image.blob, expires_in: 15.minutes, disposition: "inline")
      rescue StandardError => e
        Rails.logger.error("[preview] conversion failed for #{file.id}: #{e.class}: #{e.message}")
        StorageUrl.for(file.attachment, expires_in: 15.minutes, disposition: "inline")
      end

      TEXT_MIME_TYPES = %w[
        application/json application/xml application/javascript
        application/x-yaml application/yaml application/sql
      ].freeze

      def preview_kind(file)
        mime = file.mime_type.to_s

        return "image" if mime.start_with?("image/") && !mime.include?("svg")
        return "pdf" if mime == "application/pdf"
        return "video" if mime.start_with?("video/")
        return "audio" if mime.start_with?("audio/")
        # SVG renders as an image but can carry script, so it is shown as text.
        return "text" if mime.start_with?("text/") || TEXT_MIME_TYPES.include?(mime) || mime.include?("svg")

        "none"
      end

      def set_file
        @file = StoredFile.find(params[:id])

        return if PermissionChecker.can_view?(current_user, @file)

        # 404 rather than 403: a file you cannot see should not be confirmed to exist.
        render_error(message: "We couldn't find what you were looking for.",
                     code: "not_found", status: :not_found)
      end

      def authorize!(action)
        permitted =
          case action
          when :edit then PermissionChecker.can_edit?(current_user, @file)
          when :delete then PermissionChecker.can_delete?(current_user, @file)
          else false
          end

        return true if permitted

        render_error(
          message: "You don't have permission to do that.",
          code: "forbidden",
          status: :forbidden
        )
        false
      end

      # Everything the current user is allowed to see: their own files plus the
      # family's shared ones.
      def visible_files
        family_id = current_membership&.family_id

        if family_id
          StoredFile.where(user_id: current_user.id)
                    .or(StoredFile.where(family_id: family_id, visibility: %w[family shared_link]))
        else
          StoredFile.where(user_id: current_user.id)
        end
      end

      # Resolves a folder the caller is actually allowed to put files in.
      #
      # The family branch is guarded: with no membership, `family_id: nil` would
      # match every other user's personal folders.
      def find_folder(folder_id)
        return nil if folder_id.blank?

        own = Folder.active.find_by(id: folder_id, user_id: current_user.id)
        return own if own

        family_id = current_membership&.family_id
        return nil if family_id.nil?

        Folder.active.find_by(id: folder_id, family_id: family_id)
      end

      # Everything we know about a file, for the details panel. Kept out of the
      # list serializer: it costs extra queries and nothing in a list shows it.
      def details_for(file)
        blob = file.attachment.attached? ? file.attachment.blob : nil

        {
          uploaded_at: file.created_at,
          updated_at: file.updated_at,
          taken_at: file.taken_at,
          last_accessed_at: file.last_accessed_at,
          trashed_at: file.trashed_at,
          purge_after: file.purge_after,
          mime_type: file.mime_type,
          size: file.size,
          checksum: blob&.checksum,
          version_number: file.version_number,
          version_count: file.file_versions.count,
          visibility: file.visibility,
          owner: { id: file.user_id, name: file.user.full_name || file.user.email },
          family: file.family && { id: file.family_id, name: file.family.name },
          folder: file.folder && { id: file.folder_id, name: file.folder.name, path: file.folder.path },
          labels: file.labels.map { |l| { id: l.id, name: l.name, color: l.color } },
          active_share_links: file.shared_links.active.count,
          image: file.image? ? image_details(file) : nil
        }
      end

      def image_details(file)
        {
          width: file.image_width,
          height: file.image_height,
          megapixels: image_megapixels(file),
          camera: file.camera,
          camera_make: file.camera_make,
          camera_model: file.camera_model,
          location: file.location? ? { latitude: file.latitude.to_f, longitude: file.longitude.to_f } : nil
        }
      end

      def image_megapixels(file)
        return nil if file.image_width.blank? || file.image_height.blank?

        ((file.image_width * file.image_height) / 1_000_000.0).round(1)
      end

      # Replaces the file's labels wholesale with the given set. Ids the caller
      # cannot see are silently dropped rather than erroring — they may belong
      # to another family.
      def assign_labels!
        allowed = Label.for_user(current_user).where(id: Array(params[:label_ids])).pluck(:id)

        @file.file_labels.where.not(label_id: allowed).destroy_all
        (allowed - @file.file_labels.pluck(:label_id)).each do |label_id|
          @file.file_labels.create!(label_id: label_id)
        end
        @file.reload
      end

      def file_params
        # Accepts either a flat body ({ "visibility": "family" }) or a nested
        # one under file_attributes.
        source = params[:file_attributes].presence || params
        source.permit(:name, :visibility, :folder_id)
      end

      # Resolves date_from/date_to into a time range in the viewer's timezone.
      #
      # The gallery groups photos under "Today" using the browser's clock, so
      # the filter has to agree with it. Interpreting the dates in UTC would put
      # this evening's uploads outside "today" for anyone east of Greenwich.
      def date_range
        zone = ActiveSupport::TimeZone[current_user.timezone.to_s] || Time.zone

        from = parse_date(params[:date_from])&.in_time_zone(zone)&.beginning_of_day
        to = parse_date(params[:date_to])&.in_time_zone(zone)&.end_of_day

        [ from, to ]
      end

      # A malformed date filters nothing rather than erroring the whole listing.
      def parse_date(value)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue Date::Error
        nil
      end

      def per_page
        [ params.fetch(:per_page, 25).to_i, 100 ].min
      end

      def serialize(file, detailed: false)
        payload = {
          id: file.id,
          name: file.name,
          mime_type: file.mime_type,
          size: file.size,
          file_type: file.file_type,
          visibility: file.visibility,
          folder_id: file.folder_id,
          version_number: file.version_number,
          trashed_at: file.trashed_at,
          purge_after: file.purge_after,
          created_at: file.created_at,
          updated_at: file.updated_at,
          owner: { id: file.user_id, name: file.user.full_name || file.user.email },
          folder: file.folder && { id: file.folder_id, name: file.folder.name },
          labels: file.labels.map { |l| { id: l.id, name: l.name, color: l.color } },
          # Lets the SPA hide controls the API would reject anyway.
          permissions: {
            can_edit: PermissionChecker.can_edit?(current_user, file),
            can_delete: PermissionChecker.can_delete?(current_user, file),
            can_share: PermissionChecker.can_share?(current_user, file)
          }
        }

        if file.image?
          payload[:image] = {
            width: file.image_width,
            height: file.image_height,
            thumbnail_url: thumbnail_url_for(file),
            # When the shutter fired, if the file said so.
            taken_at: file.taken_at,
            camera: file.camera,
            location: file.location? ? { latitude: file.latitude.to_f, longitude: file.longitude.to_f } : nil
          }
          # What the gallery groups and sorts by.
          payload[:captured_at] = file.captured_at
        end

        payload[:download_url] = "#{Rails.configuration.x.api_url}/api/v1/files/#{file.id}/download" if detailed
        payload
      end

      def thumbnail_url_for(file)
        return nil unless file.thumbnail.attached?

        StorageUrl.for(file.thumbnail, expires_in: 15.minutes)
      rescue StandardError => e
        Rails.logger.warn("[files] thumbnail url failed for #{file.id}: #{e.class}")
        nil
      end

      def serialize_version(version)
        {
          id: version.id,
          version_number: version.version_number,
          size: version.size,
          created_at: version.created_at,
          created_by: version.created_by_id
        }
      end
    end
  end
end
