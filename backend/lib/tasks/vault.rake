# frozen_string_literal: true

namespace :vault do
  def self.backup_passphrase
    if ENV["BACKUP_PASSPHRASE"].present?
      return ENV["BACKUP_PASSPHRASE"]
    end

    unless $stdin.tty?
      abort "[vault] Set BACKUP_PASSPHRASE — no TTY to prompt for one."
    end

    require "io/console"
    pass = $stdin.getpass("Backup passphrase (min 8 chars): ")
    abort "[vault] Passphrase too short." if pass.length < 8
    pass
  end

  desc "Encrypted backup: database + documents (no photos). Set BACKUP_PASSPHRASE or you'll be prompted."
  task backup: :environment do
    result = VaultBackup::Builder.new(passphrase: backup_passphrase, backup_type: :documents).call

    puts "[vault] wrote #{result.path}"
    puts "[vault] #{result.stored_files} document(s), #{result.blob_entries} blob(s), #{result.blob_bytes} bytes"
  rescue VaultBackup::Builder::Error, VaultBackup::DatabaseDumper::Error,
         VaultBackup::Encryptor::Error => e
    abort "[vault] #{e.message}"
  end

  desc "Show what is inside a backup without changing anything. FILE=path"
  task inspect: :environment do
    path = ENV["FILE"] or abort "[vault] Set FILE=/path/to/backup.vault"

    result = VaultBackup::Restorer.new(
      path: path, passphrase: backup_passphrase, inspect_only: true
    ).call
    m = result.manifest

    puts "[vault] #{path}"
    puts "[vault] taken #{m['created_at']} from #{m['rails_env'] || 'unknown'}"
    puts "[vault] #{m['stored_files'] || m['documents'] || '?'} document(s), #{m['blob_entries'] || '?'} blob(s)"
    puts "[vault] the passphrase opens it"
  rescue VaultBackup::Restorer::Error, VaultBackup::Encryptor::Error => e
    abort "[vault] #{e.message}"
  end

  desc "Restore a backup. FILE=path, FORCE=1 to overwrite a database that has data in it."
  task restore: :environment do
    path = ENV["FILE"] or abort "[vault] Set FILE=/path/to/backup.vault"
    force = ENV["FORCE"].present?

    result = VaultBackup::Restorer.new(
      path: path, passphrase: backup_passphrase, force: force
    ).call

    puts "[vault] restored from #{path}"
    puts "[vault] #{result.tables} table(s), #{result.restored_blobs} blob(s) put back"
    puts "[vault] #{result.missing_blobs} blob(s) had no bytes in the archive" if result.missing_blobs.positive?
    puts "[vault] note: photos are not in this archive — restore them separately." \
      if result.manifest["backup_type"].to_s == "documents"
  rescue VaultBackup::Restorer::WouldOverwrite => e
    abort "[vault] #{e.message}"
  rescue VaultBackup::Restorer::Error, VaultBackup::Encryptor::Error => e
    abort "[vault] #{e.message}"
  end

  namespace :backup do
    desc "Encrypted backup: photo library only (step 13 — not yet implemented)"
    task images: :environment do
      abort "[vault] vault:backup:images is not implemented yet."
    end
  end
end
