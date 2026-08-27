# frozen_string_literal: true

module VaultBackup
  # Document blobs only — `file_type: file`, not the photo gallery.
  #
  # Includes trashed rows and encrypted ciphertext as stored; restoring needs
  # the database half of the backup, not a decrypted export.
  class FileCollector
    Entry = Struct.new(:path, :blob, :byte_size, keyword_init: true)

    def initialize(scope: StoredFile.files)
      @scope = scope
    end

    def entries
      @entries ||= build_entries
    end

    def total_bytes
      entries.sum(&:byte_size)
    end

    private

    def build_entries
      list = []

      @scope.includes(:file_versions, attachment_attachment: :blob,
                      file_versions: { attachment_attachment: :blob }).find_each do |file|
        add_attachment(list, file.attachment, "#{file.id}/#{sanitize(file.name)}")
        file.file_versions.sort_by(&:version_number).each do |version|
          add_attachment(list, version.attachment,
                         "#{file.id}/versions/v#{version.version_number}/#{sanitize(file.name)}")
        end
      end

      list
    end

    def add_attachment(list, attachment, suffix)
      return unless attachment.attached?

      blob = attachment.blob
      list << Entry.new(
        path: "#{Format::FILES_PREFIX}#{suffix}",
        blob: blob,
        byte_size: blob.byte_size.to_i
      )
    end

    def sanitize(name)
      cleaned = name.to_s.tr("/\\", "_").gsub("..", "_").strip
      cleaned = "_#{cleaned}" if cleaned.start_with?(".")
      cleaned.presence || "untitled"
    end
  end
end
