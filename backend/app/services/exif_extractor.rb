# frozen_string_literal: true

require "exifr/jpeg"
require "exifr/tiff"

# Pulls capture time, GPS coordinates and camera details out of a photo.
#
# Everything here is best-effort: EXIF is frequently absent (screenshots, PNGs),
# stripped by messaging apps, or malformed. A photo without it is normal, not an
# error, so every failure path returns an empty hash.
class ExifExtractor
  JPEG_TYPES = %w[image/jpeg image/jpg].freeze
  TIFF_TYPES = %w[image/tiff image/x-tiff].freeze
  # Modern phone formats. exifr cannot parse the container, but libvips can, and
  # it hands back the embedded EXIF block verbatim — which exifr reads happily.
  CONTAINER_TYPES = %w[image/heic image/heif image/avif].freeze

  Result = Struct.new(:taken_at, :latitude, :longitude, :camera_make, :camera_model, keyword_init: true) do
    def to_h
      super.compact
    end

    def any?
      to_h.any?
    end
  end

  def self.call(io, content_type:)
    new(io, content_type).call
  end

  def initialize(io, content_type)
    @io = io
    @content_type = content_type.to_s.downcase
  end

  def call
    exif = read_exif
    return Result.new if exif.nil?

    Result.new(
      taken_at: capture_time(exif),
      latitude: coordinate(exif) { |gps| gps.latitude },
      longitude: coordinate(exif) { |gps| gps.longitude },
      camera_make: presence(exif.make),
      camera_model: presence(exif.model)
    )
  rescue StandardError => e
    # Corrupt EXIF must never cost us the upload.
    Rails.logger.warn("[exif] unreadable: #{e.class}: #{e.message}")
    Result.new
  end

  private

  def read_exif
    if JPEG_TYPES.include?(@content_type)
      EXIFR::JPEG.new(@io)
    elsif TIFF_TYPES.include?(@content_type)
      EXIFR::TIFF.new(@io)
    elsif CONTAINER_TYPES.include?(@content_type)
      exif_from_container
    end
  end

  # HEIC/AVIF wrap EXIF inside an ISO-BMFF container. libvips already decodes
  # these for thumbnails, and exposes the raw EXIF block as "exif-data", so the
  # same exifr parser handles it — including GPS hemispheres and date checks.
  def exif_from_container
    require "vips"

    bytes = @io.read
    @io.rewind if @io.respond_to?(:rewind)
    return nil if bytes.blank?

    raw = Vips::Image.new_from_buffer(bytes, "").get("exif-data")
    return nil if raw.blank?

    # vips keeps the "Exif\0\0" prefix; the TIFF structure starts after it.
    payload = raw.start_with?("Exif\x00\x00") ? raw.byteslice(6..) : raw
    EXIFR::TIFF.new(StringIO.new(payload))
  rescue StandardError => e
    # No EXIF block, or a container libvips cannot open.
    Rails.logger.debug { "[exif] container read failed: #{e.class}: #{e.message}" }
    nil
  end

  # date_time_original is when the shutter fired; the others are when the file
  # was written or last edited, so they are only fallbacks.
  def capture_time(exif)
    raw = exif.date_time_original || exif.date_time_digitized || exif.date_time
    return nil if raw.nil?

    time = raw.to_time
    # EXIF carries no timezone. Treat it as UTC rather than inventing an offset,
    # and reject absurd values from cameras with a dead clock battery.
    return nil if time.year < 1900 || time > 1.day.from_now

    time
  rescue StandardError
    nil
  end

  def coordinate(exif)
    gps = exif.gps
    return nil if gps.nil?

    value = yield(gps)
    return nil if value.nil? || value.to_f.nan? || value.to_f.infinite?

    value.to_f.round(6)
  rescue StandardError
    # Some files carry a GPS IFD with no usable fix.
    nil
  end

  def presence(value)
    value.to_s.strip.presence&.truncate(80)
  end
end
