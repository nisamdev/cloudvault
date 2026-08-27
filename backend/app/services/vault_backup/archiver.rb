# frozen_string_literal: true

require "zip_kit"

module VaultBackup
  # Builds the inner ZIP: manifest, pg_dump output, and document blobs.
  class Archiver
    def initialize(output_path:, database_dump_path:, file_entries:, inner_manifest:)
      @output_path = output_path
      @database_dump_path = database_dump_path
      @file_entries = file_entries
      @inner_manifest = inner_manifest
    end

    def call
      FileUtils.mkdir_p(File.dirname(@output_path))

      # The File must be opened with a block of its own. ZipKit writes the
      # central directory when its block ends, but it does not own the IO it was
      # handed and will not close it — so those last bytes sat in Ruby's buffer
      # and every archive came out truncated. A backup that cannot be opened is
      # not a backup, and nothing says so until the day you need it.
      File.open(@output_path, "wb") do |io|
        ZipKit::Streamer.open(io) do |zip|
          zip.write_deflated_file(Format::INNER_MANIFEST) do |sink|
            sink << JSON.pretty_generate(@inner_manifest)
          end

          zip.write_stored_file(Format::DATABASE_DUMP) do |sink|
            stream_file(@database_dump_path, sink)
          end

          @file_entries.each do |entry|
            next unless entry.blob

            zip.write_stored_file(entry.path) do |sink|
              entry.blob.download { |chunk| sink << chunk }
            end
          rescue StandardError => e
            Rails.logger.error("[vault-backup] skip #{entry.path}: #{e.class}: #{e.message}")
          end
        end
      end

      @output_path
    end

    private

    def stream_file(path, sink)
      File.open(path, "rb") do |io|
        while (chunk = io.read(1_048_576))
          sink << chunk
        end
      end
    end
  end
end
