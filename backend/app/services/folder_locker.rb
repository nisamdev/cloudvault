# frozen_string_literal: true

# Moves a folder into the private section, or back out of it.
#
# Locking encrypts every file inside; unlocking decrypts them. Both walk the
# whole subtree, because a folder inside a private folder is private too and
# nobody would expect otherwise.
class FolderLocker
  class Error < StandardError; end

  Result = Struct.new(:folders, :files, :failed, keyword_init: true)

  def initialize(folder, vault_key)
    @folder = folder
    @vault_key = vault_key
  end

  def lock! = apply(locked: true)
  def unlock! = apply(locked: false)

  private

  def apply(locked:)
    folders = subtree
    files = StoredFile.active.where(folder_id: folders.map(&:id))
    failed = []

    files.find_each do |file|
      move(file, locked: locked)
    rescue VaultCipher::WrongKey, VaultStorage::TooLarge, StandardError => e
      # One file that cannot be encrypted must not leave the rest half-done and
      # the folder claiming to be private.
      Rails.logger.error("[vault] #{file.id} could not be moved: #{e.class}: #{e.message}")
      failed << file.name
    end

    raise Error, "#{failed.first} could not be moved, so nothing was changed." if failed.any?

    Folder.where(id: folders.map(&:id)).update_all(locked: locked, updated_at: Time.current)

    Result.new(folders: folders.size, files: files.size, failed: failed)
  end

  # A file already in the state it is being moved to is left alone, so running
  # this twice costs nothing and cannot double-encrypt.
  def move(file, locked:)
    if locked
      return if file.encrypted?

      # Resize while plaintext is still readable — after encrypt the job can
      # only see ciphertext and would leave the gallery tile blank forever.
      ensure_thumbnail!(file)

      VaultStorage.encrypt!(file, :attachment, @vault_key)
      VaultStorage.encrypt!(file, :thumbnail, @vault_key)
      file.update!(locked: true, encrypted: true)
    else
      return unless file.encrypted?

      VaultStorage.decrypt!(file, :attachment, @vault_key)
      VaultStorage.decrypt!(file, :thumbnail, @vault_key)
      file.update!(locked: false, encrypted: false)
      # Files locked before they ever got a thumb still need one once open.
      ensure_thumbnail!(file) if file.picture? && !file.thumbnail.attached?
    end
  end

  def ensure_thumbnail!(file)
    return unless file.picture?
    return if file.thumbnail.attached?

    ProcessImageJob.perform_now(file.id)
    file.reload
  end

  def subtree
    found = [ @folder ]
    frontier = [ @folder.id ]

    until frontier.empty?
      children = Folder.active.where(parent_id: frontier).to_a
      found.concat(children)
      frontier = children.map(&:id)
    end

    found
  end
end
