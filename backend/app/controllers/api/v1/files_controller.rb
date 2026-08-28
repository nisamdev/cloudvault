# frozen_string_literal: true

module Api
  module V1
    class FilesController < BaseController
      include ZipKit::RailsStreaming

      # Browser navigations cannot send Authorization; the ZIP URL carries its
      # own short-lived token, same pattern as folder downloads.
      allow_unauthenticated :zip

      before_action :set_file,
                    only: %i[show update destroy download restore preview purge pages rearrange
                             text split content sign lock unlock reprocess]
      before_action :set_zip_download, only: %i[zip]

      # GET /api/v1/files
      # Params: folder_id, file_type (file|image), trashed, q, page, per_page
      def index
        # Two separate places, not one list with a filter on it: `locked=true`
        # is the private section, everything else is the rest of the vault.
        # Trash is the exception: the owner's private deletions must still show
        # up there, or Empty trash can never reclaim them.
        scope =
          if params[:trashed] == "true"
            trash_scope(visible_files)
          elsif params[:locked] == "true"
            only_locked(visible_files).active
          else
            hide_locked(visible_files).active
          end
        scope = scope.where(file_type: params[:file_type]) if StoredFile::FILE_TYPES.include?(params[:file_type])
        # folder_id=<id> scopes to that folder; folder_id= (blank) means the root.
        # Omitting the parameter searches across all folders, which is what a
        # search should do.
        scope = scope.where(folder_id: params[:folder_id].presence) if params.key?(:folder_id)

        # Anything reaching me from somebody else: what my families share, and
        # what has been granted to me by name or through a family. My own files
        # are not "shared with me", so they are excluded.
        if params[:shared_with_me] == "true"
          granted = GrantedResources.new(current_user)
          from_others = scope.where(visibility: "family")
          unless granted.empty?
            from_others = from_others.or(scope.where(id: granted.file_ids))
                                     .or(scope.where(folder_id: granted.folder_ids))
          end

          scope = from_others.where.not(user_id: current_user.id)
        end

        scope = scope.with_labels(params[:label_ids]) if params[:label_ids].present?
        scope = scope.search(params[:q]) if params[:q].present?

        # Gallery filters. Each is a no-op when its parameter is absent.
        scope = scope.by_owner(params[:owner_id])
        scope = scope.with_visibility(params[:visibility])
        scope = scope.with_orientation(params[:orientation])
        scope = scope.uploaded_between(*date_range)
        scope = scope.with_location if params[:has_location] == "true"
        scope = scope.taken_at_place(params[:place]) if params[:place].present?

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

        # A file put into a private folder has to arrive encrypted, not be
        # encrypted a moment later — there must be no window where the bytes are
        # sitting in storage in the open.
        if folder&.locked? && !vault_unlocked?
          return render_error(message: "The private section is locked.",
                              code: "vault_locked", status: :forbidden)
        end

        stored_file = FileUploader
          .new(user: current_user, family: current_family)
          .call(
            upload,
            folder: folder,
            visibility: visibility,
            replaces: replaces,
            last_modified: params[:last_modified]
          )

        lock_into_vault(stored_file) if folder&.locked?

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

        # Neither is file_type. It normally follows the mime type, which files
        # every JPEG under Photos — including photographs *of documents*. Saying
        # otherwise is a decision, so it is recorded as one.
        if attrs.key?("file_type")
          chosen = attrs.delete("file_type")

          unless StoredFile::FILE_TYPES.include?(chosen)
            return render_error(message: "A file is either a document or a photo.",
                                code: "invalid_file_type", status: :unprocessable_content)
          end

          if chosen == "image" && !@file.picture?
            return render_error(message: "#{@file.name} isn't a picture, so it can't live in Photos.",
                                code: "not_a_picture", status: :unprocessable_content)
          end

          attrs["file_type"] = chosen
          attrs["file_type_pinned"] = true
          # Albums and document folders are separate trees, and a file that has
          # changed sides can no longer be in the one it was in: Photos would
          # not list it, and My Files would not show the folder holding it, so
          # it would be reachable from nowhere at all. It comes out of the
          # folder, which is the one place both sections can see.
          attrs["folder_id"] = nil if leaving_its_tree?(chosen)
        end

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

        # Crossing the boundary of the private section is the one move that
        # changes the bytes as well as the row.
        follow_folder_lock or return

        # Filing a picture back into Photos should still produce a thumbnail if
        # the original upload never got one (or the job ran while it was a doc).
        if @file.picture? && !@file.thumbnail.attached?
          ProcessImageJob.perform_later(@file.id)
        end

        render json: { file: serialize(@file.reload, detailed: true) }
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

      # POST /api/v1/files/:id/lock — move one file into the private section
      #
      # Folders are locked as a tree; a lone file still needs a locked folder to
      # live in. Prefer an explicit folder_id from the picker; otherwise land in
      # the dedicated "Private" catch-all (never a random locked folder).
      def lock
        return unless require_vault!
        authorize!(:edit) or return

        return render json: { file: serialize(@file) } if @file.locked?

        destination = private_destination_folder(params[:folder_id])
        return if performed?

        StoredFile.transaction do
          @file.update!(folder_id: destination.id)
          lock_into_vault(@file)
        end

        render json: { file: serialize(@file.reload) }
      rescue VaultCipher::WrongKey, VaultStorage::TooLarge => e
        render_error(message: e.message.presence || "That file could not be moved.",
                     code: "lock_failed", status: :unprocessable_content)
      end

      # DELETE /api/v1/files/:id/lock — bring one file back out
      def unlock
        return unless require_vault!
        authorize!(:edit) or return

        return render json: { file: serialize(@file) } unless @file.locked?

        VaultStorage.decrypt!(@file, :attachment, vault_key)
        VaultStorage.decrypt!(@file, :thumbnail, vault_key)
        # Back to the root of My Files / Photos — its private folder may still
        # hold other things, and leaving it there would re-encrypt on the next
        # listing refresh via follow_folder_lock.
        @file.update!(locked: false, encrypted: false, folder_id: nil)
        ensure_thumbnail!(@file)

        render json: { file: serialize(@file.reload) }
      rescue VaultCipher::WrongKey, VaultStorage::TooLarge => e
        render_error(message: e.message.presence || "That file could not be moved.",
                     code: "unlock_failed", status: :unprocessable_content)
      end

      # POST /api/v1/files/:id/reprocess — rebuild a missing gallery thumbnail
      def reprocess
        authorize!(:edit) or return

        unless @file.picture?
          return render_error(message: "Only pictures have thumbnails.",
                              code: "not_a_picture", status: :unprocessable_content)
        end

        ProcessImageJob.perform_later(@file.id, force: true)
        render json: { queued: true }
      end

      # POST /api/v1/files/zip_url — multi-select download as one ZIP
      def zip_url
        ids = Array(params[:file_ids]).map(&:to_s).uniq.first(FilesArchiver::MAX_ENTRIES)
        if ids.empty?
          return render_error(message: "Pick at least one file to download.",
                              code: "empty_selection", status: :unprocessable_content)
        end

        files = hide_locked(visible_files.active).where(id: ids).includes(attachment_attachment: :blob)
        archiver = FilesArchiver.new(files: files, user: current_user)

        if archiver.entries.empty?
          return render_error(message: "None of those files can be downloaded.",
                              code: "nothing_to_download", status: :unprocessable_content)
        end

        token = JwtService.encode_download(
          user_id: current_user.id,
          scope: "files:zip",
          file_ids: archiver.entries.map { |e| e.stored_file.id }
        )

        render json: {
          url: "#{Rails.configuration.x.api_url}/api/v1/files/zip?token=#{CGI.escape(token)}",
          filename: archiver.filename,
          file_count: archiver.entries.size,
          total_size: archiver.total_size
        }
      end

      # GET /api/v1/files/zip?token=...
      def zip
        zip_kit_stream(filename: @zip_archiver.filename) do |zip|
          @zip_archiver.entries.each do |entry|
            file = entry.stored_file
            next unless file.attachment.attached?

            writer = zip_precompressed?(file) ? :write_stored_file : :write_deflated_file
            zip.public_send(writer, entry.path) do |sink|
              file.attachment.blob.download { |chunk| sink << chunk }
            end
          rescue StandardError => e
            Rails.logger.error("[files-zip] #{file.id}: #{e.class}: #{e.message}")
          end
        end
      end

      # GET /api/v1/files/:id/download
      def download
        unless @file.attachment.attached?
          return render_error(message: "That file has no contents.", code: "not_found", status: :not_found)
        end

        # A locked file has no URL anybody else could follow: its bytes are
        # ciphertext, and only this process holds the key.
        if @file.encrypted?
          return render json: { via: "api", url: nil, filename: @file.name }
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
      #
      # via=proxy asks for a URL on our own origin instead. Showing an image
      # needs no such thing, but *reading its pixels back* does: a canvas that
      # has drawn a cross-origin image is tainted, and the scanner has to read
      # the pixels to crop and enhance them.
      def preview
        unless @file.attachment.attached?
          return render json: { kind: "none", reason: "empty" }
        end

        kind = preview_kind(@file)

        payload = { kind: kind, name: @file.name, mime_type: @file.mime_type, size: @file.size }

        # Same again: no URL, because there is nothing anybody else could fetch.
        # The SPA reads /content with the unlock token and makes its own.
        if @file.encrypted?
          payload[:via] = "api"
          payload[:width] = @file.image_width if kind == "image"
          payload[:height] = @file.image_height if kind == "image"
          return render json: payload
        end

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
              converted_preview_url(@file, proxy: same_origin_bytes?)
            elsif same_origin_bytes?
              StorageUrl.proxy_url(
                @file.attachment.blob,
                expires_in: 15.minutes, disposition: "inline", filename: @file.name
              )
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

      # GET /api/v1/files/:id/pages
      #
      # Page images, so the browser needs no PDF renderer. The signing editor
      # wants them big enough to place a signature on; the page arranger wants
      # thumbnails, and wants them for a whole document rather than the first
      # screenful — hence `size` and `from`.
      def pages
        unless pdf?(@file)
          return render_error(message: "That file is not a PDF.",
                              code: "not_a_pdf", status: :unprocessable_content)
        end

        thumbnails = params[:size] == "thumb"
        # "read" is for cropping and OCR, where the small print has to survive.
        reading = params[:size] == "read"
        renderer = PdfPageRenderer.new(
          @file.attachment.download,
          width: page_render_width(thumbnails, reading),
          format: reading ? :jpeg : :png
        )
        rendered = renderer.pages(
          limit: thumbnails ? PdfPageRenderer::MAX_THUMBS : PdfPageRenderer::MAX_PAGES,
          from: params[:from].presence || 1
        )

        render json: {
          page_count: renderer.page_count,
          # Whether the PDF carries real text or is a picture of one. A reader
          # should take a born-digital PDF at its word and treat a scanned one
          # as the photograph it is — which means letting it be cropped first.
          has_text_layer: PdfTextExtractor.new(@file.attachment.download).call.any_text?,
          pages: rendered.map do |page|
            {
              number: page[:number],
              width: page[:width],
              height: page[:height],
              # Inline data rather than a URL: an <img> cannot send the bearer
              # token, and these are throwaway renders not worth storing.
              image: "data:#{page[:content_type]};base64,#{Base64.strict_encode64(page[:png])}"
            }
          end
        }
      end

      # POST /api/v1/files/:id/split
      #
      # Pulls a run of pages out as a document of its own.
      #
      # Unlike rearranging, this writes a *new* file and leaves the original
      # exactly as it was: taking one statement out of a year of them is not an
      # edit to the year.
      def split
        authorize!(:edit) or return

        unless pdf?(@file)
          return render_error(message: "That file is not a PDF.",
                              code: "not_a_pdf", status: :unprocessable_content)
        end

        original = @file.attachment.download
        numbers = (params[:from].to_i..params[:to].to_i).to_a

        if numbers.empty?
          return render_error(message: "The last page has to come after the first.",
                              code: "empty_range", status: :unprocessable_content)
        end

        bytes = PdfPageArranger.new(original).call(numbers.map { |n| { number: n, rotation: 0 } })

        stored = FileUploader
                 .new(user: current_user, family: current_family)
                 .call(pdf_upload(bytes, split_name(numbers)),
                       folder: @file.folder, visibility: "private")

        render json: { file: serialize(stored, detailed: true) }, status: :created
      rescue PdfPageArranger::Error => e
        render_error(message: e.message, code: "split_failed", status: :unprocessable_content)
      rescue FileUploader::QuotaExceeded => e
        render_error(message: e.message, code: "quota_exceeded", status: :content_too_large)
      end

      # GET /api/v1/files/:id/content
      #
      # The file itself, through the API rather than from object storage.
      #
      # This is how a locked file is read: its bytes in storage are ciphertext,
      # so only this process can turn them back into a document, and only while
      # the private section is open. The unlock token travels in a header and
      # never in the URL — which is why the SPA fetches this and makes a blob URL
      # rather than pointing the browser at it.
      def content
        unless @file.attachment.attached?
          return render_error(message: "That file has no contents.", code: "not_found", status: :not_found)
        end

        bytes =
          if @file.encrypted?
            return unless require_vault!

            begin
              VaultStorage.read(@file.attachment, vault_key)
            rescue VaultCipher::WrongKey
              return render_error(message: "That file could not be opened.",
                                  code: "vault_locked", status: :forbidden)
            end
          else
            @file.attachment.download
          end

        @file.update_column(:last_accessed_at, Time.current)

        send_data bytes,
                  type: @file.mime_type,
                  disposition: params[:disposition] == "attachment" ? "attachment" : "inline",
                  filename: @file.name
      end

      # GET /api/v1/files/:id/text
      #
      # The text inside a PDF, and the handful of things in it worth reading.
      #
      # A PDF built from photographs has no text layer. When that happens we
      # fall back to OCR (tesseract) so a scan is still readable. `source`
      # tells the SPA which path produced the words.
      def text
        unless pdf?(@file)
          return render_error(message: "That file is not a PDF.",
                              code: "not_a_pdf", status: :unprocessable_content)
        end

        bytes = @file.attachment.download
        extracted = PdfTextExtractor.new(bytes).call
        source = "text_layer"

        unless extracted.any_text?
          ocr = PdfOcr.new(bytes).call
          if ocr.any_text?
            extracted = ocr
            source = "ocr"
          else
            source = "none"
          end
        end

        details = KeyDetails.new(extracted.pages).call

        render json: {
          has_text: extracted.any_text?,
          source: source,
          page_count: extracted.page_count,
          truncated: extracted.truncated,
          title: details[:title],
          details: details[:details],
          found: details[:found],
          lines: details[:lines],
          pages: extracted.pages
        }
      end

      # PATCH /api/v1/files/:id/pages
      #
      # Reorders, turns and drops pages. The result replaces the file as a new
      # version rather than becoming a second file: this is an edit to a
      # document, and the one thing that must not happen is losing the original.
      def rearrange
        authorize!(:edit) or return

        unless pdf?(@file)
          return render_error(message: "That file is not a PDF.",
                              code: "not_a_pdf", status: :unprocessable_content)
        end

        layout = Array(params[:pages]).map do |page|
          { number: page[:number].to_i, rotation: page[:rotation].to_i }
        end

        original = @file.attachment.download

        if unchanged?(layout, original)
          return render_error(message: "Nothing about the pages has changed.",
                              code: "no_changes", status: :unprocessable_content)
        end

        bytes = PdfPageArranger.new(original).call(layout)

        FileUploader
          .new(user: current_user, family: current_family)
          .call(pdf_upload(bytes, @file.name), replaces: @file)

        render json: { file: serialize(@file.reload, detailed: true) }
      rescue PdfPageArranger::Error => e
        render_error(message: e.message, code: "rearrange_failed", status: :unprocessable_content)
      rescue FileUploader::QuotaExceeded => e
        render_error(message: e.message, code: "quota_exceeded", status: :content_too_large)
      end

      # POST /api/v1/files/:id/sign
      #
      # Flattens the editor's fields onto the PDF, keeping the unfilled original
      # as a version — a signed document you cannot un-sign is a trap.
      def sign
        authorize!(:edit) or return

        unless pdf?(@file)
          return render_error(message: "That file is not a PDF.",
                              code: "not_a_pdf", status: :unprocessable_content)
        end

        fields = build_fields.select { |field| filled?(field) }
        if fields.empty?
          return render_error(message: "Nothing was placed on the document.",
                              code: "no_fields", status: :unprocessable_content)
        end

        images = signature_images(fields)
        missing = fields.select { |f| signature_field?(f) && !images.key?(f.value.to_s) && !inline?(f.value) }

        # Silently dropping an unknown signature would leave someone believing
        # they had signed when the page is blank.
        if missing.any?
          return render_error(message: "We couldn't find that signature.",
                              code: "signature_not_found", status: :not_found)
        end

        stamped = PdfFieldStamper.new(@file.attachment.download, images: images).call(fields)

        FileUploader
          .new(user: current_user, family: current_family)
          .call(pdf_upload(stamped, @file.name), replaces: @file)

        render json: { file: serialize(@file.reload, detailed: true) }
      rescue PdfFieldStamper::Error => e
        render_error(message: e.message, code: "signing_failed", status: :unprocessable_content)
      end

      private

      def pdf?(file)
        file.mime_type == "application/pdf" && file.attachment.attached?
      end

      def build_fields
        Array(params[:fields]).map do |field|
          PdfFieldStamper::Field.new(
            type: field[:type],
            page: field[:page].to_i,
            x: field[:x].to_f,
            y: field[:y].to_f,
            width: field[:width].to_f,
            height: field[:height].to_f,
            value: field[:value],
            font_size: field[:font_size],
            bold: field[:bold].to_s == "true",
            italic: field[:italic].to_s == "true",
            align: field[:align],
            color: field[:color]
          )
        end
      end

      def signature_field?(field)
        %w[signature initials].include?(field.type.to_s)
      end

      def inline?(value)
        value.to_s.start_with?("data:image/")
      end

      # An empty text box is a field the user placed and never filled; stamping
      # it would create a new version that changes nothing.
      def filled?(field)
        return field.value.to_s == "true" if field.type.to_s == "checkbox"

        field.value.to_s.strip.present?
      end

      # Signature fields carry a saved signature's id; resolve those to bytes
      # once, here, so the stamper never touches the database.
      def signature_images(fields)
        ids = fields.select { |f| %w[signature initials].include?(f.type.to_s) }
                    .map(&:value)
                    .select { |v| v.to_s.match?(/\A\d+\z/) }

        current_user.signatures.where(id: ids).each_with_object({}) do |signature, images|
          images[signature.id.to_s] = signature.image.download if signature.image.attached?
        end
      end

      # A document is unchanged when every page is still there, still in order
      # and still the way up it started. Rebuilding it anyway would spend a
      # version and a copy of the bytes to produce the same file.
      def unchanged?(layout, bytes)
        layout.each_with_index.all? { |page, index| page[:number] == index + 1 && page[:rotation].zero? } &&
          layout.size == PdfPageRenderer.new(bytes).page_count
      end

      # Encrypts a file that has just landed in a private folder, and its
      # thumbnail with it — a thumbnail of a passport is still a passport.
      def lock_into_vault(file)
        # Thumbnails must exist before the bytes are sealed: ProcessImageJob
        # cannot resize ciphertext, and preview-via-decrypt cannot help <img>.
        ensure_thumbnail!(file)
        VaultStorage.encrypt!(file, :attachment, vault_key)
        VaultStorage.encrypt!(file, :thumbnail, vault_key)
        file.update!(locked: true, encrypted: true)
      end

      def ensure_thumbnail!(file)
        return unless file.picture?
        return if file.thumbnail.attached?

        ProcessImageJob.perform_now(file.id)
        file.reload
      end

      # A locked folder the caller picked, or the dedicated "Private" catch-all.
      # Never "whichever locked folder was created first" — that made newly
      # created private folders silently become the dump target.
      def private_destination_folder(folder_id)
        if folder_id.present?
          folder = Folder.active.find_by(id: folder_id, user_id: current_user.id, locked: true)
          unless folder
            render_error(message: "We couldn't find that private folder.",
                         code: "folder_not_found", status: :not_found)
            return nil
          end
          return folder
        end

        catch_all_private_folder
      end

      # Dedicated inbox for one-off locks when the SPA did not pick a folder.
      # Always the folder named "Private", creating it if needed — not the
      # oldest/newest locked folder the user happens to have.
      def catch_all_private_folder
        existing = Folder.active.find_by(user_id: current_user.id, locked: true, name: "Private")
        return existing if existing

        Folder.create!(user: current_user, name: unused_private_folder_name, locked: true)
      end

      def unused_private_folder_name
        scope = Folder.active.where(user_id: current_user.id, parent_id: nil, family_id: nil)
        base = "Private"
        return base unless scope.exists?([ "LOWER(name) = ?", base.downcase ])

        n = 2
        n += 1 while scope.exists?([ "LOWER(name) = ?", "private #{n}" ])
        "Private #{n}"
      end

      # After a move, the file has to match the folder it is now in. Going in
      # encrypts it; coming out decrypts it; staying on the same side is free.
      def follow_folder_lock
        should_be_locked = @file.folder&.locked? || false
        return true if should_be_locked == @file.encrypted?

        unless vault_unlocked?
          render_error(message: "Unlock the private section before moving files in or out of it.",
                       code: "vault_locked", status: :forbidden)
          return false
        end

        if should_be_locked
          lock_into_vault(@file)
        else
          VaultStorage.decrypt!(@file, :attachment, vault_key)
          VaultStorage.decrypt!(@file, :thumbnail, vault_key)
          @file.update!(locked: false, encrypted: false)
          ensure_thumbnail!(@file)
        end

        true
      rescue VaultCipher::WrongKey, VaultStorage::TooLarge => e
        render_error(message: e.message.presence || "That file could not be moved.",
                     code: "vault_move_failed", status: :unprocessable_content)
        false
      end

      # Named after where the pages came from, so a folder full of these still
      # says which is which.
      def split_name(numbers)
        base = File.basename(@file.name, ".*")
        span = numbers.size == 1 ? "page #{numbers.first}" : "pages #{numbers.first}-#{numbers.last}"

        "#{base} (#{span}).pdf"
      end

      # A PDF built in memory; FileUploader expects an upload.
      def pdf_upload(bytes, filename)
        tempfile = Tempfile.new([ "signed", ".pdf" ], binmode: true)
        tempfile.write(bytes)
        tempfile.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile: tempfile, filename: filename, type: "application/pdf"
        )
      end

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
      def converted_preview_url(file, proxy: false)
        variant = file.attachment.variant(
          resize_to_limit: PREVIEW_LIMIT,
          format: :jpeg,
          saver: { quality: 85 }
        ).processed

        blob = variant.image.blob
        if proxy
          StorageUrl.proxy_url(blob, expires_in: 15.minutes, disposition: "inline", filename: file.name)
        else
          StorageUrl.for_blob(blob, expires_in: 15.minutes, disposition: "inline")
        end
      rescue StandardError => e
        Rails.logger.error("[preview] conversion failed for #{file.id}: #{e.class}: #{e.message}")
        StorageUrl.for(file.attachment, expires_in: 15.minutes, disposition: "inline")
      end

      def same_origin_bytes?
        params[:via] == "proxy"
      end

      TEXT_MIME_TYPES = %w[
        application/json application/xml application/javascript
        application/x-yaml application/yaml application/sql
      ].freeze

      def page_render_width(thumbnails, reading)
        return PdfPageRenderer::THUMB_WIDTH if thumbnails
        return PdfPageRenderer::READ_WIDTH if reading

        PdfPageRenderer::RENDER_WIDTH
      end

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

        # A locked file does not exist until the private section is open. 404
        # rather than 403 for the same reason as everywhere else here: the
        # answer must not confirm that there is something to find.
        #
        # Exception: the owner can restore or permanently delete their own
        # private trash without unlocking — those paths never read plaintext.
        if @file.locked? && !vault_unlocked?
          trash_housekeeping = @file.trashed? &&
            @file.user_id == current_user.id &&
            %w[restore purge].include?(action_name)

          unless trash_housekeeping
            return render_error(message: "We couldn't find what you were looking for.",
                                code: "not_found", status: :not_found)
          end
        end

        return if PermissionChecker.can_view?(current_user, @file)

        # 404 rather than 403: a file you cannot see should not be confirmed to exist.
        render_error(message: "We couldn't find what you were looking for.",
                     code: "not_found", status: :not_found)
      end

      def set_zip_download
        payload = JwtService.decode_download(params[:token], expected_scope: "files:zip")
        user = User.find_by(id: payload["sub"])
        raise JwtService::InvalidToken, "unknown user" if user.nil?

        ids = Array(payload["file_ids"]).map(&:to_i)
        files = StoredFile.active.where(id: ids, locked: false)
                          .includes(attachment_attachment: :blob)
                          .select { |file| PermissionChecker.can_view?(user, file) }

        @zip_archiver = FilesArchiver.new(files: files, user: user)
        if @zip_archiver.entries.empty?
          return render_error(message: "None of those files can be downloaded.",
                              code: "nothing_to_download", status: :unprocessable_content)
        end
      rescue JwtService::InvalidToken
        render_error(message: "This download link has expired.",
                     code: "invalid_download_token", status: :unauthorized)
      end

      ZIP_PRECOMPRESSED_TYPES = %w[image/ video/ audio/].freeze
      ZIP_PRECOMPRESSED_EXACT = %w[application/zip application/gzip application/pdf].freeze

      def zip_precompressed?(file)
        mime = file.mime_type.to_s
        ZIP_PRECOMPRESSED_EXACT.include?(mime) || ZIP_PRECOMPRESSED_TYPES.any? { |p| mime.start_with?(p) }
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
      # Everything the caller can reach: their own, whatever their families
      # share, and anything granted to them by name or through a family.
      #
      # This mirrors PermissionChecker, which stays the authority for a single
      # file; the two must not drift, so any rule added there belongs here too.
      def visible_files
        mine = StoredFile.where(user_id: current_user.id)

        family_ids = current_user.vault_family_ids
        if family_ids.any?
          mine = mine.or(StoredFile.where(family_id: family_ids, visibility: %w[family shared_link]))
        end

        granted = GrantedResources.new(current_user)
        return mine if granted.empty?

        mine.or(StoredFile.where(id: granted.file_ids))
            .or(StoredFile.where(folder_id: granted.folder_ids))
      end

      # Ordinary trash + the owner's own private deletions. Ciphertext can be
      # listed and purged without the passphrase; other people's locked files
      # stay invisible.
      def trash_scope(files)
        base = files.trashed
        open = hide_locked(base)
        mine_private = base.where(user_id: current_user.id, locked: true)
        open.or(mine_private)
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
        source.permit(:name, :visibility, :folder_id, :file_type,
                      :place_name, :latitude, :longitude)
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
          locked: file.locked?,
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

        # `picture?`, not `image?`: a certificate filed under My Files is still a
        # JPEG, and its row should still show what it looks like.
        if file.picture?
          payload[:image] = {
            width: file.image_width,
            height: file.image_height,
            thumbnail_url: thumbnail_url_for(file),
            # When the shutter fired, if the file said so.
            taken_at: file.taken_at,
            camera: file.camera,
            location: file.location? ? { latitude: file.latitude.to_f, longitude: file.longitude.to_f } : nil,
            # Where somebody said it was taken. Almost never in the EXIF, so
            # almost always this or nothing.
            place_name: file.place_name
          }
          # What the gallery groups and sorts by.
          payload[:captured_at] = file.captured_at
        end

        # Only worth saying for a picture, where the two can differ.
        payload[:filed_as_document] = file.picture? && !file.image?

        payload[:download_url] = "#{Rails.configuration.x.api_url}/api/v1/files/#{file.id}/download" if detailed
        payload
      end

      # Whether this file's folder belongs to the other section now.
      def leaving_its_tree?(chosen)
        return false if @file.folder_id.blank?

        wanted = chosen == "image" ? "photo" : "file"
        Folder.where(id: @file.folder_id).where.not(kind: wanted).exists?
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
