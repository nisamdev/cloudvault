# frozen_string_literal: true

# Generates the gallery thumbnail and records image dimensions.
#
# Runs on the thumbnails queue so a burst of photo uploads cannot starve
# invitation emails on the critical queue.
class ProcessImageJob < ApplicationJob
  queue_as :thumbnails

  THUMBNAIL_SIZE = [ 300, 300 ].freeze

  def perform(stored_file_id)
    stored_file = StoredFile.find_by(id: stored_file_id)
    return if stored_file.nil? || !stored_file.image?
    return unless stored_file.attachment.attached?

    stored_file.attachment.blob.analyze unless stored_file.attachment.blob.analyzed?
    metadata = stored_file.attachment.blob.metadata

    stored_file.update_columns(
      image_width: metadata["width"],
      image_height: metadata["height"]
    )

    generate_thumbnail(stored_file)
  end

  private

  def generate_thumbnail(stored_file)
    variant = stored_file.attachment.variant(
      resize_to_limit: THUMBNAIL_SIZE,
      saver: { quality: 80 }
    ).processed

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
