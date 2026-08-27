# frozen_string_literal: true

module VaultBackup
  # Orchestrates pg_dump, document blobs, and encryption into one `.vault` file.
  class Builder
    class Error < StandardError; end

    BACKUP_TYPES = {
      documents: "documents",
      images: "images"
    }.freeze

    def initialize(passphrase:, backup_type: :documents, output_dir: nil)
      @passphrase = passphrase
      @backup_type = backup_type.to_sym
      @output_dir = output_dir || ENV.fetch("BACKUP_OUTPUT_DIR", Rails.root.join("tmp/backups").to_s)
    end

    def call
      raise Error, "Unknown backup type: #{@backup_type}" unless BACKUP_TYPES.key?(@backup_type)
      raise Error, "vault:backup:images is not implemented yet." if @backup_type == :images

      FileUtils.mkdir_p(@output_dir)
      stamp = Time.current.strftime("%Y-%m-%d-%H%M%S")
      final_path = File.join(@output_dir, "cloudvault-#{BACKUP_TYPES[@backup_type]}-#{stamp}.vault")

      db_dump = Tempfile.new([ "vault-db", ".dump" ], binmode: true)
      inner_zip = Tempfile.new([ "vault-inner", ".zip" ], binmode: true)

      begin
        DatabaseDumper.new(output_path: db_dump.path).call
        collector = document_collector
        inner_manifest = {
          format_version: 1,
          backup_type: BACKUP_TYPES[@backup_type],
          created_at: Time.current.iso8601,
          pg_dump_format: "custom",
          stored_files: collector.entries.map { |e| e.path[%r{^files/(\d+)/}, 1] }.compact.uniq.size,
          blob_entries: collector.entries.size,
          blob_bytes: collector.total_bytes,
          # Files are archived under a path a person can read — files/12/deed.pdf
          # rather than files/<random key> — so somebody opening the archive by
          # hand can find what they are looking for. That leaves the restore
          # with no way to match a file back to its blob, so the mapping is
          # written down here.
          entries: collector.entries.map do |entry|
            { path: entry.path, key: entry.blob.key, byte_size: entry.byte_size }
          end
        }

        Archiver.new(
          output_path: inner_zip.path,
          database_dump_path: db_dump.path,
          file_entries: collector.entries,
          inner_manifest: inner_manifest
        ).call

        Encryptor.new(
          input_path: inner_zip.path,
          output_path: final_path,
          passphrase: @passphrase,
          backup_type: BACKUP_TYPES[@backup_type]
        ).call

        Result.new(
          path: final_path,
          stored_files: inner_manifest[:stored_files],
          blob_entries: inner_manifest[:blob_entries],
          blob_bytes: inner_manifest[:blob_bytes]
        )
      ensure
        db_dump.close!
        inner_zip.close!
      end
    end

    Result = Struct.new(:path, :stored_files, :blob_entries, :blob_bytes, keyword_init: true)

    private

    def document_collector
      FileCollector.new(scope: StoredFile.files)
    end
  end
end
