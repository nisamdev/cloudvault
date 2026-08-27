# frozen_string_literal: true

# Generates the gallery thumbnail and records image dimensions.
#
# Runs on the thumbnails queue so a burst of photo uploads cannot starve
# invitation emails on the critical queue.
class ProcessImageJob < ApplicationJob
  queue_as :thumbnails

  THUMBNAIL_SIZE = [ 300, 300 ].freeze

  def perform(stored_file_id, force: false)
    stored_file = StoredFile.find_by(id: stored_file_id)
    # picture?, not image?: a certificate filed under My Files is still a photo
    # on disk and should still get a thumbnail for its row.
    return if stored_file.nil? || !stored_file.picture?
    return unless stored_file.attachment.attached?

    # Ciphertext is not a JPEG. Generate the thumb before lock (FolderLocker /
    # lock_into_vault), or unlock first — never variant the sealed bytes.
    if stored_file.encrypted?
      Rails.logger.info("[thumbnails] #{stored_file.id}: skipped (encrypted)")
      return
    end

    stored_file.attachment.blob.analyze unless stored_file.attachment.blob.analyzed?
    metadata = stored_file.attachment.blob.metadata

    attributes = {
      image_width: metadata["width"],
      image_height: metadata["height"]
    }.merge(exif_attributes(stored_file))

    # Capture date priority: EXIF → already stored (browser mtime) → filename.
    if attributes[:taken_at].blank?
      attributes[:taken_at] = stored_file.taken_at.presence || FilenameDateParser.call(stored_file.name)
    end

    stored_file.update_columns(attributes.compact)

    return if stored_file.thumbnail.attached? && !force

    generate_thumbnail(stored_file.reload)
  end

  private

  # Capture date, GPS and camera, when the file carries them.
  def exif_attributes(stored_file)
    stored_file.attachment.blob.open do |file|
      ExifExtractor.call(file, content_type: stored_file.mime_type).to_h
    end
  rescue StandardError => e
    Rails.logger.warn("[exif] #{stored_file.id}: #{e.class}: #{e.message}")
    {}
  end

  def generate_thumbnail(stored_file)
    opts = {
      resize_to_limit: THUMBNAIL_SIZE,
      saver: { quality: 80 },
      # Always JPEG: HEIC/TIFF/AVIF variants are useless as <img> sources, and
      # odd phone JPEGs sometimes only succeed once forced through a saver.
      format: :jpeg
    }

    variant = stored_file.attachment.variant(**opts).processed

    stored_file.thumbnail.purge if stored_file.thumbnail.attached?
    stored_file.thumbnail.attach(
      io: StringIO.new(variant.download),
      filename: "thumb_#{stored_file.id}.jpg",
      content_type: "image/jpeg"
    )
  rescue StandardError => e
    # A missing thumbnail degrades the gallery; it must not fail the upload or
    # spin in the retry queue forever.
    Rails.logger.error("[thumbnails] #{stored_file.id}: #{e.class}: #{e.message}")
  end
end
