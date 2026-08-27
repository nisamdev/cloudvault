# frozen_string_literal: true

require "zip"

module VaultBackup
  # Puts a backup back.
  #
  # The half that makes the other half worth having. An encrypted archive nobody
  # has ever restored is a guess, not a backup — and this project has already
  # lost a database once, so the restore path is not theoretical.
  #
  # Deliberately loud and deliberately reversible in the only way that matters:
  # it refuses to touch a database that has anything in it unless the caller
  # says so out loud.
  class Restorer
    class Error < StandardError; end
    class WouldOverwrite < Error; end

    Result = Struct.new(:manifest, :restored_blobs, :missing_blobs, :tables, keyword_init: true)

    # @param inspect_only [Boolean] read the manifest and stop — the dry run
    #   that tells you whether the passphrase is right before anything changes
    def initialize(path:, passphrase:, force: false, inspect_only: false)
      @path = path
      @passphrase = passphrase
      @force = force
      @inspect_only = inspect_only
    end

    def call
      raise Error, "No such backup: #{@path}" unless File.exist?(@path)

      archive = decrypt
      begin
        inner = archive.path
        manifest = read_manifest(inner)
        return Result.new(manifest: manifest, restored_blobs: 0, missing_blobs: 0, tables: 0) if @inspect_only

        guard_existing_data!
        restore_database(inner)
        restored, missing = restore_blobs(inner, manifest)

        Result.new(
          manifest: manifest,
          restored_blobs: restored,
          missing_blobs: missing,
          tables: table_count
        )
      ensure
        # close! closes and unlinks; the object stayed referenced until here so
        # nothing could collect it out from under the restore.
        archive.close!
      end
    end

    private

    def decrypt
      Encryptor.decrypt(input_path: @path, passphrase: @passphrase)
    rescue VaultCipher::WrongKey
      # The one error worth being precise about: everything else is a broken
      # file, this is a typo.
      raise Error, "That passphrase does not open this backup."
    rescue Encryptor::Error => e
      raise Error, e.message
    end

    def read_manifest(inner)
      Zip::File.open(inner) do |zip|
        entry = zip.find_entry(Format::INNER_MANIFEST)
        raise Error, "The backup has no manifest — it may be truncated." if entry.nil?

        JSON.parse(entry.get_input_stream.read)
      end
    rescue Zip::Error => e
      raise Error, "The backup could not be opened: #{e.message}"
    end

    # Restoring over a database that already holds records is how somebody
    # loses the thing they were trying to protect.
    #
    # An empty or brand-new database is the ordinary case and must not trip this
    # — there is nothing there to overwrite, and the tables do not exist yet.
    def guard_existing_data!
      return if @force

      existing = begin
        User.count
      rescue ActiveRecord::StatementInvalid
        0
      end
      return if existing.zero?

      raise WouldOverwrite,
            "This database already has #{existing} user(s). Restoring replaces all of it. " \
            "Re-run with FORCE=1 if that is what you want."
    end

    def restore_database(inner)
      dump = extract(inner, Format::DATABASE_DUMP)

      begin
        url = DatabaseDumper.new(output_path: "/dev/null").send(:database_url)
        raise Error, "DATABASE_URL is not set." if url.blank?

        # --clean --if-exists so the restore replaces rather than collides;
        # --no-owner because the roles on the machine restoring are rarely the
        # roles on the machine that dumped.
        success = system(
          "pg_restore", "--clean", "--if-exists", "--no-owner", "--no-acl",
          "-d", url, dump, exception: false
        )
        # pg_restore reports failure for harmless "does not exist" notices on a
        # clean database, so the check that matters is whether the data arrived.
        restored_any = begin
          User.count.positive?
        rescue ActiveRecord::StatementInvalid
          false
        end
        raise Error, "pg_restore failed and the database is still empty." if !success && !restored_any
      ensure
        FileUtils.rm_f(dump)
      end

      ActiveRecord::Base.connection.reconnect!
    end

    # The bytes go back into whatever storage this machine is configured with,
    # under the keys the freshly restored database now expects.
    #
    # Driven by the manifest rather than by walking the blobs: the archive is
    # laid out for a human, so only the manifest knows which file is which blob.
    def restore_blobs(inner, manifest)
      entries = manifest["entries"]

      if entries.blank?
        Rails.logger.warn("[vault-restore] archive has no file map; nothing to put back")
        return [ 0, ActiveStorage::Blob.count ]
      end

      restored = 0
      missing = 0
      service = ActiveStorage::Blob.service

      Zip::File.open(inner) do |zip|
        entries.each do |mapped|
          archived = zip.find_entry(mapped["path"])

          if archived.nil?
            missing += 1
            next
          end

          service.upload(mapped["key"], StringIO.new(archived.get_input_stream.read))
          restored += 1
        rescue StandardError => e
          Rails.logger.error("[vault-restore] #{mapped['path']}: #{e.class}: #{e.message}")
          missing += 1
        end
      end

      [ restored, missing ]
    end

    def extract(inner, name)
      Zip::File.open(inner) do |zip|
        entry = zip.find_entry(name)
        raise Error, "The backup is missing #{name}." if entry.nil?

        temp = Tempfile.new([ "vault-restore", File.extname(name) ], binmode: true)
        entry.get_input_stream { |io| IO.copy_stream(io, temp) }
        temp.close
        return temp.path
      end
    end

    def table_count
      ActiveRecord::Base.connection.tables.size
    end
  end
end
