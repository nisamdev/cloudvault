# frozen_string_literal: true

module Api
  module V1
    # The trash bin as a whole — emptying it in one go, rather than purging
    # each file the SPA happens to have loaded on the current page.
    class TrashController < BaseController
      # DELETE /api/v1/trash
      def destroy
        purged_files = 0
        purged_folders = 0

        hide_locked(visible_files.trashed)
          .or(visible_files.trashed.where(user_id: current_user.id, locked: true))
          .find_each do |file|
          next unless PermissionChecker.can_delete?(current_user, file)

          FilePurger.new(file).call
          purged_files += 1
        end

        # Deepest folders first so a parent is not removed while a child still
        # points at it.
        trashed_folders_for(current_user).order(id: :desc).find_each do |folder|
          folder.destroy!
          purged_folders += 1
        end

        render json: { files: purged_files, folders: purged_folders }
      end

      private

      def visible_files
        mine = StoredFile.where(user_id: current_user.id)

        family_ids = current_user.family_ids
        if family_ids.any?
          mine = mine.or(StoredFile.where(family_id: family_ids, visibility: %w[family shared_link]))
        end

        granted = GrantedResources.new(current_user)
        return mine if granted.empty?

        mine.or(StoredFile.where(id: granted.file_ids))
            .or(StoredFile.where(folder_id: granted.folder_ids))
      end

      def trashed_folders_for(user)
        scope = Folder.where.not(trashed_at: nil).where(user_id: user.id)
        family_ids = user.family_ids
        return scope if family_ids.empty?

        scope.or(Folder.where.not(trashed_at: nil).where(family_id: family_ids))
      end
    end
  end
end
