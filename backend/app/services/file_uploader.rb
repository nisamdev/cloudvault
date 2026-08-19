# frozen_string_literal: true

# Takes an uploaded file and turns it into a StoredFile, enforcing quota and
# type rules and keeping storage accounting correct.
#
# Uploading over an existing file creates a version rather than overwriting, so
# nothing is ever silently lost.
class FileUploader
  class Error < StandardError; end
  class QuotaExceeded < Error; end
  class FileTooLarge < Error; end
  class UnsupportedType < Error; end

  # Deny-list of types that browsers or servers may execute. An allow-list would
  # be safer still, but a family vault has to accept arbitrary documents.
  BLOCKED_MIME_TYPES = %w[
    application/x-msdownload
    application/x-msdos-program
    application/x-sh
    text/x-shellscript
  ].freeze

  BLOCKED_EXTENSIONS = %w[.exe .bat .cmd .com .scr .msi .sh .ps1].freeze

  def initialize(user:, family: nil)
    @user = user
    @family = family
  end

  # @param upload [ActionDispatch::Http::UploadedFile]
  # @return [StoredFile]
  def call(upload, folder: nil, visibility: "private", replaces: nil)
    # A re-upload inherits the existing file's visibility.
    effective_visibility = replaces ? replaces.visibility : visibility
    validate!(upload, family_visible: effective_visibility == "family")

    stored_file = replaces ? add_version(upload, replaces) : create_file(upload, folder, visibility)

    # Quota accounting must not drift if a later step raises, so it happens in
    # the same transaction as the record write.
    stored_file
  end

  private

  attr_reader :user, :family

  def validate!(upload, family_visible:)
    size = upload.size.to_i

    raise FileTooLarge, "That file is larger than the #{max_upload_mb} MB limit." if size > max_upload_bytes

    extension = File.extname(upload.original_filename.to_s).downcase
    if BLOCKED_MIME_TYPES.include?(upload.content_type) || BLOCKED_EXTENSIONS.include?(extension)
      raise UnsupportedType, "That file type isn't allowed."
    end

    raise QuotaExceeded, "You don't have enough storage space left." if user.storage_remaining < size

    # Only a file that actually lands in the family vault consumes family quota.
    return unless family_visible && family && family.storage_remaining < size

    raise QuotaExceeded, "Your family doesn't have enough storage space left."
  end

  def create_file(upload, folder, visibility)
    StoredFile.transaction do
      stored_file = StoredFile.create!(
        user: user,
        family: visibility == "family" ? family : nil,
        folder: folder,
        name: sanitized_name(upload.original_filename),
        mime_type: upload.content_type.presence || "application/octet-stream",
        size: upload.size.to_i,
        file_type: StoredFile.file_type_for(upload.content_type),
        visibility: visibility
      )

      stored_file.attachment.attach(
        io: upload.tempfile,
        filename: stored_file.name,
        content_type: stored_file.mime_type
      )

      charge_storage(upload.size.to_i, family_id: stored_file.family_id)
      enqueue_processing(stored_file)

      stored_file
    end
  end

  # Re-uploading over a file keeps the previous bytes as a version and prunes
  # anything past FILE_VERSIONS_KEPT.
  def add_version(upload, stored_file)
    StoredFile.transaction do
      previous_size = stored_file.size

      version = stored_file.file_versions.create!(
        created_by: user,
        version_number: stored_file.version_number,
        size: previous_size,
        checksum: stored_file.checksum
      )

      # Move the current bytes to the version record before replacing them.
      if stored_file.attachment.attached?
        version.attachment.attach(stored_file.attachment.blob)
        stored_file.attachment.detach
      end

      stored_file.attachment.attach(
        io: upload.tempfile,
        filename: stored_file.name,
        content_type: upload.content_type
      )

      stored_file.update!(
        size: upload.size.to_i,
        mime_type: upload.content_type.presence || stored_file.mime_type,
        version_number: stored_file.version_number + 1
      )

      # Charge the full new size, not the delta: the previous bytes are kept as
      # a version rather than replaced, so they still occupy storage. (Pruning
      # an old version releases its bytes below.)
      charge_storage(upload.size.to_i, family_id: stored_file.family_id)
      prune_versions(stored_file)
      enqueue_processing(stored_file)

      stored_file
    end
  end

  def prune_versions(stored_file)
    excess = stored_file.file_versions.newest_first.offset(FileVersion.versions_kept)
    excess.each do |version|
      release_storage(version.size, family_id: stored_file.family_id)
      version.destroy!
    end
  end

  # The uploader always knows the user's family, but a private upload must not
  # consume the family's quota — only files that actually sit in the family
  # vault do. family_id is therefore taken from the record, not from @family.
  def charge_storage(bytes, family_id: nil)
    User.where(id: user.id).update_all("storage_used = GREATEST(storage_used + #{bytes.to_i}, 0)")
    return if family_id.nil?

    Family.where(id: family_id)
          .update_all("family_storage_used = GREATEST(family_storage_used + #{bytes.to_i}, 0)")
  end

  def release_storage(bytes, family_id: nil)
    charge_storage(-bytes.to_i, family_id: family_id)
  end

  def enqueue_processing(stored_file)
    ProcessImageJob.perform_later(stored_file.id) if stored_file.image?
  end

  # Strips any directory component a client may have sent.
  def sanitized_name(filename)
    File.basename(filename.to_s).presence || "untitled"
  end

  def max_upload_bytes
    ENV.fetch("MAX_UPLOAD_BYTES", 104_857_600).to_i
  end

  def max_upload_mb
    max_upload_bytes / 1_048_576
  end
end
