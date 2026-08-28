# frozen_string_literal: true

module Api
  module V1
    class FoldersController < BaseController
      include ZipKit::RailsStreaming

      # The ZIP is opened as a plain browser navigation, which cannot carry an
      # Authorization header; a short-lived scoped token stands in for it.
      allow_unauthenticated :download

      before_action :set_folder, only: %i[show update destroy download_url]
      before_action :set_folder_for_download, only: %i[download]

      # GET /api/v1/folders
      # Returns the whole tree in one call — a family vault is small enough that
      # this beats a request per level, and the sidebar needs all of it anyway.
      def index
        # The private section is asked for by name; the ordinary tree never
        # contains it, open or not.
        scope = visible_folders.active
        scope = params[:locked] == "true" ? only_locked(scope) : hide_locked(scope)
        # Albums and document folders are two cabinets, and each screen asks
        # only for its own. Anything not asking gets the documents, as before.
        scope = scope.of_kind(params[:kind])
        # A gallery that has never been opened has nowhere to put a photograph
        # yet, so asking for the albums is what brings the first one into being.
        Folder.default_for(current_user, kind: "photo", family: current_family) if params[:kind] == "photo"
        folders = scope.reload.order(is_default: :desc, name: :asc)

        render json: {
          folders: folders.map { |folder| serialize(folder) },
          tree: build_tree(folders)
        }
      end

      # GET /api/v1/folders/:id
      def show
        render json: {
          folder: serialize(@folder),
          # Root first, so the UI can render breadcrumbs directly.
          breadcrumbs: @folder.ancestors.map { |f| { id: f.id, name: f.name } },
          children: @folder.children.where(trashed_at: nil).order(:name).map { |f| serialize(f) }
        }
      end

      # POST /api/v1/folders
      def create
        folder = Folder.new(folder_params)
        folder.user = current_user
        # A folder inside a family folder stays in the family.
        folder.family = folder.parent&.family || (folder_params[:family].presence && current_family)
        folder.family ||= current_family if params[:shared] == "true"

        authorize_parent!(folder.parent) or return

        folder.save!
        inherit_lock(folder)

        # A folder created from the private section with no locked parent still
        # needs to be sealed — inherit_lock only covers "made inside one".
        if ActiveModel::Type::Boolean.new.cast(params[:locked])
          unless vault_unlocked?
            return render_error(message: "Unlock the private section before creating a private folder.",
                                code: "vault_locked", status: :forbidden)
          end
          folder.update_columns(locked: true, updated_at: Time.current) unless folder.locked?
        end

        render json: { folder: serialize(folder.reload) }, status: :created
      end

      # PATCH /api/v1/folders/:id  — rename, or move to another parent
      def update
        attrs = folder_params

        if attrs.key?(:parent_id)
          new_parent = attrs[:parent_id].present? ? visible_folders.find(attrs[:parent_id]) : nil
          authorize_parent!(new_parent) or return
        end

        @folder.update!(attrs)

        # Dragging a folder under a private one must seal it the same way a
        # brand-new child would be.
        inherit_lock(@folder.reload) if attrs.key?(:parent_id)

        render json: { folder: serialize(@folder) }
      end

      # DELETE /api/v1/folders/:id
      # Soft-deletes the folder and everything under it, so Trash can restore
      # the whole branch rather than leaving orphaned files behind.
      def destroy
        now = Time.current
        ids = [ @folder.id ] + descendant_ids(@folder)

        Folder.transaction do
          Folder.where(id: ids).update_all(trashed_at: now, updated_at: now)
          StoredFile.where(folder_id: ids, trashed_at: nil).update_all(trashed_at: now, updated_at: now)
        end

        head :no_content
      end

      # GET /api/v1/folders/trashed
      # Folders sitting in the trash, for the Trash screen.
      def trashed
        folders = visible_folders.where.not(trashed_at: nil).order(trashed_at: :desc)

        render json: { folders: folders.map { |folder| serialize(folder).merge(
          trashed_at: folder.trashed_at,
          purge_after: folder.trashed_at + retention_days.days
        ) } }
      end

      # POST /api/v1/folders/:id/restore
      # Brings the folder back, along with the files that went down with it.
      def restore
        folder = visible_folders.find_by(id: params[:id])
        return render_error(message: "We couldn't find what you were looking for.",
                            code: "not_found", status: :not_found) if folder.nil?

        Folder.transaction do
          # A parent that is still in the trash would leave this folder
          # unreachable, so it comes back at the top level instead.
          folder.parent = nil if folder.parent&.trashed_at
          folder.update!(trashed_at: nil)

          StoredFile.where(folder_id: folder.id)
                    .where.not(trashed_at: nil)
                    .update_all(trashed_at: nil, updated_at: Time.current)
        end

        render json: { folder: serialize(folder) }
      end

      # POST /api/v1/folders/:id/download_url
      # Hands back a short-lived URL the browser can navigate to.
      def download_url
        archiver = FolderArchiver.new(folder: @folder, user: current_user)

        if archiver.entries.empty?
          return render_error(message: "That folder has no files to download.",
                              code: "folder_empty", status: :unprocessable_content)
        end

        token = JwtService.encode_download(user_id: current_user.id, scope: "folder:#{@folder.id}")

        render json: {
          url: "#{Rails.configuration.x.api_url}/api/v1/folders/#{@folder.id}/download?token=#{CGI.escape(token)}",
          filename: archiver.filename,
          file_count: archiver.entries.size,
          total_size: archiver.total_size
        }
      end

      # GET /api/v1/folders/:id/download?token=...
      # Streams a ZIP of the folder, built entry by entry so neither the server
      # nor the client waits for the whole archive to exist first.
      def download
        archiver = FolderArchiver.new(folder: @folder, user: @download_user)

        zip_kit_stream(filename: archiver.filename) do |zip|
          archiver.empty_directories.each do |dir|
            # zip_kit appends the trailing slash itself; passing one produces a
            # "folder//" entry that some extractors show as a stray directory.
            zip.add_empty_directory(dirname: dir.chomp("/")) if zip.respond_to?(:add_empty_directory)
          end

          archiver.entries.each do |entry|
            file = entry.stored_file
            next unless file.attachment.attached?

            # Images, PDFs and archives are already compressed; deflating them
            # again costs CPU for nothing.
            writer = precompressed?(file) ? :write_stored_file : :write_deflated_file

            zip.public_send(writer, entry.path) do |sink|
              file.attachment.blob.download { |chunk| sink << chunk }
            end
          rescue StandardError => e
            # One unreadable blob must not abort an otherwise good archive.
            Rails.logger.error("[folder-zip] #{file.id}: #{e.class}: #{e.message}")
          end
        end
      end

      # POST /api/v1/folders/:id/lock — move it into the private section
      #
      # Everything inside is encrypted, including anything in folders below it:
      # a folder inside a private folder is private, and nobody would expect
      # otherwise.
      #
      # Optional folder_id nests it under an existing private folder. Blank
      # parent (folder_id="") puts it at the top of Private.
      def lock
        return unless require_vault!

        folder = hide_locked(visible_folders.active).find_by(id: params[:id])
        return render_error(message: "We couldn't find that folder.", code: "not_found", status: :not_found) if folder.nil?

        if params.key?(:folder_id)
          if params[:folder_id].present?
            parent = Folder.active.find_by(id: params[:folder_id], user_id: current_user.id, locked: true)
            unless parent
              return render_error(message: "We couldn't find that private folder.",
                                  code: "folder_not_found", status: :not_found)
            end
            # Cannot nest a folder under itself or its own descendant.
            if parent.id == folder.id || descendant_ids(folder).include?(parent.id)
              return render_error(message: "That folder cannot go inside itself.",
                                  code: "invalid_parent", status: :unprocessable_content)
            end
            folder.update!(parent_id: parent.id)
          else
            folder.update!(parent_id: nil)
          end
        end

        result = FolderLocker.new(folder, vault_key).lock!

        render json: { folder: serialize(folder.reload), files: result.files, folders: result.folders }
      rescue FolderLocker::Error => e
        render_error(message: e.message, code: "lock_failed", status: :unprocessable_content)
      end

      # DELETE /api/v1/folders/:id/lock — bring it back out
      def unlock
        return unless require_vault!

        folder = visible_folders.active.where(locked: true).find_by(id: params[:id])
        return render_error(message: "We couldn't find that folder.", code: "not_found", status: :not_found) if folder.nil?

        result = FolderLocker.new(folder, vault_key).unlock!

        render json: { folder: serialize(folder.reload), files: result.files, folders: result.folders }
      rescue FolderLocker::Error => e
        render_error(message: e.message, code: "unlock_failed", status: :unprocessable_content)
      end

      private

      def retention_days
        ENV.fetch("TRASH_RETENTION_DAYS", 30).to_i
      end

      PRECOMPRESSED_TYPES = %w[image/ video/ audio/].freeze
      PRECOMPRESSED_EXACT = %w[application/zip application/gzip application/pdf].freeze

      def precompressed?(file)
        mime = file.mime_type.to_s
        PRECOMPRESSED_EXACT.include?(mime) || PRECOMPRESSED_TYPES.any? { |p| mime.start_with?(p) }
      end

      # Authenticates the ZIP request from the query-string token rather than a
      # bearer header, then re-checks that the user can still see the folder.
      def set_folder_for_download
        payload = JwtService.decode_download(params[:token], expected_scope: "folder:#{params[:id]}")
        @download_user = User.find_by(id: payload["sub"])
        raise JwtService::InvalidToken, "unknown user" if @download_user.nil?

        @folder = folders_visible_to(@download_user).find_by(id: params[:id])
        raise ActiveRecord::RecordNotFound if @folder.nil?
      rescue JwtService::InvalidToken
        render_error(message: "This download link has expired.",
                     code: "invalid_download_token", status: :unauthorized)
      end

      def folders_visible_to(user)
        family_id = user.primary_membership&.family_id

        if family_id
          Folder.where(user_id: user.id).or(Folder.where(family_id: family_id))
        else
          Folder.where(user_id: user.id)
        end
      end

      def set_folder
        scope = vault_unlocked? ? visible_folders : hide_locked(visible_folders)
        @folder = scope.find_by(id: params[:id])

        return if @folder

        render_error(message: "We couldn't find what you were looking for.",
                     code: "not_found", status: :not_found)
      end

      # A user sees their own folders plus the family's shared ones.
      def visible_folders
        family_id = current_membership&.family_id

        if family_id
          Folder.where(user_id: current_user.id).or(Folder.where(family_id: family_id))
        else
          Folder.where(user_id: current_user.id)
        end
      end

      def authorize_parent!(parent)
        return true if parent.nil?

        # Adding to a shared folder is an edit of family content.
        if parent.family_id && !PermissionChecker.can_upload_to_family?(current_user, parent.family)
          render_error(message: "You don't have permission to add to that folder.",
                       code: "forbidden", status: :forbidden)
          return false
        end

        true
      end

      def descendant_ids(folder)
        ids = []
        queue = Folder.where(parent_id: folder.id).pluck(:id)

        until queue.empty?
          ids.concat(queue)
          queue = Folder.where(parent_id: queue).pluck(:id)
        end

        ids
      end

      def folder_params
        params.require(:folder).permit(:name, :parent_id, :family, :kind)
      end

      # A folder made inside a private one is private from the moment it exists,
      # so nothing is ever briefly in the open.
      def inherit_lock(folder)
        parent = folder.parent
        return unless parent&.locked?

        folder.update_columns(locked: true, updated_at: Time.current)
      end

      def serialize(folder)
        {
          id: folder.id,
          name: folder.name,
          parent_id: folder.parent_id,
          shared: folder.family_id.present?,
          locked: folder.locked?,
          kind: folder.kind,
          is_default: folder.is_default,
          file_count: StoredFile.where(folder_id: folder.id, trashed_at: nil).count,
          created_at: folder.created_at
        }
      end

      # Nests the flat list into parent/child form for the sidebar tree.
      def build_tree(folders)
        by_parent = folders.group_by(&:parent_id)

        build = lambda do |parent_id|
          (by_parent[parent_id] || []).map do |folder|
            serialize(folder).merge(children: build.call(folder.id))
          end
        end

        build.call(nil)
      end
    end
  end
end
