# frozen_string_literal: true

# Empties the trash of anything past the retention window.
#
# Runs on the maintenance queue. Without it, deleted files keep consuming quota
# forever and "30 days" in the UI would be a lie.
class PurgeTrashJob < ApplicationJob
  queue_as :maintenance

  def perform
    cutoff = ENV.fetch("TRASH_RETENTION_DAYS", 30).to_i.days.ago

    files = StoredFile.trashed.where(trashed_at: ..cutoff)
    count = files.count

    files.find_each { |file| FilePurger.new(file).call }

    # Folders are only removed once nothing is left pointing at them.
    empty_folders = Folder.where.not(trashed_at: nil).where(trashed_at: ..cutoff)
    folder_count = empty_folders.count
    empty_folders.find_each do |folder|
      folder.destroy! unless StoredFile.exists?(folder_id: folder.id)
    end

    Rails.logger.info("[purge-trash] removed #{count} files and up to #{folder_count} folders older than #{cutoff}")
  end
end
