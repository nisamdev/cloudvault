# frozen_string_literal: true

namespace :cloudvault do
  desc "Create the object storage bucket if it does not exist (MinIO in dev; no-op on R2/S3 when it already exists)"
  task ensure_bucket: :environment do
    require "aws-sdk-s3"

    bucket_name = ENV.fetch("S3_BUCKET", "cloudvault")

    client = Aws::S3::Client.new(
      access_key_id: ENV.fetch("S3_ACCESS_KEY_ID"),
      secret_access_key: ENV.fetch("S3_SECRET_ACCESS_KEY"),
      region: ENV.fetch("S3_REGION", "us-east-1"),
      endpoint: ENV.fetch("S3_ENDPOINT"),
      force_path_style: ENV.fetch("S3_FORCE_PATH_STYLE", "true") == "true"
    )

    begin
      client.head_bucket(bucket: bucket_name)
      puts "[cloudvault] bucket '#{bucket_name}' already exists"
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchBucket
      client.create_bucket(bucket: bucket_name)
      puts "[cloudvault] created bucket '#{bucket_name}'"
    rescue Aws::S3::Errors::Forbidden
      # Managed buckets (R2/S3 in production) are provisioned out of band and
      # the app's credentials usually cannot inspect or create them.
      puts "[cloudvault] no permission to inspect '#{bucket_name}'; assuming it exists"
    end
  end

  desc "Recalculate storage_used for every user and family from the files that actually exist"
  task recalculate_storage: :environment do
    # Counters are maintained incrementally on upload and delete, so a bug or an
    # interrupted transaction can leave them drifted. This recomputes them from
    # the records themselves. Safe to run at any time.
    User.find_each do |user|
      files = StoredFile.where(user_id: user.id)
      versions = FileVersion.joins(:stored_file).where(stored_files: { user_id: user.id })
      actual = files.sum(:size) + versions.sum(:size)

      next if user.storage_used == actual

      puts "user #{user.email}: #{user.storage_used} -> #{actual}"
      user.update_column(:storage_used, actual)
    end

    Family.find_each do |family|
      files = StoredFile.where(family_id: family.id)
      versions = FileVersion.joins(:stored_file).where(stored_files: { family_id: family.id })
      actual = files.sum(:size) + versions.sum(:size)

      next if family.family_storage_used == actual

      puts "family #{family.name}: #{family.family_storage_used} -> #{actual}"
      family.update_column(:family_storage_used, actual)
    end

    puts "storage recalculated"
  end

  desc "Backfill EXIF (capture date, GPS, camera) for images uploaded before extraction existed"
  task backfill_exif: :environment do
    scope = StoredFile.images.where(taken_at: nil)
    puts "[cloudvault] checking #{scope.count} images..."

    found = 0
    scope.find_each do |file|
      next unless file.attachment.attached?

      data = file.attachment.blob.open do |io|
        ExifExtractor.call(io, content_type: file.mime_type).to_h
      end

      next if data.empty?

      file.update_columns(data)
      found += 1
      puts "  #{file.name}: #{data.keys.join(", ")}"
    rescue StandardError => e
      puts "  #{file.name}: skipped (#{e.class})"
    end

    puts "[cloudvault] EXIF found for #{found} image(s)"
  end

  desc "Re-detect file types for uploads misfiled because the browser sent a vague Content-Type"
  task reclassify_files: :environment do
    require "marcel"

    fixed = 0

    StoredFile.where(file_type: "file").find_each do |file|
      next unless file.attachment.attached?

      # Marcel only needs the head of the file to match magic bytes.
      head = file.attachment.blob.open { |io| io.read(8192) }
      detected = Marcel::MimeType.for(StringIO.new(head.to_s), name: file.name)
      next if detected.blank? || detected == file.mime_type

      new_type = StoredFile.file_type_for(detected)
      next if new_type == file.file_type

      file.update_columns(mime_type: detected, file_type: new_type)
      ProcessImageJob.perform_later(file.id) if new_type == "image"

      fixed += 1
      puts "  #{file.name}: #{file.mime_type_previously_was rescue "file"} -> #{detected} (#{new_type})"
    rescue StandardError => e
      puts "  #{file.name}: skipped (#{e.class})"
    end

    puts "[cloudvault] reclassified #{fixed} file(s)"
  end
end
