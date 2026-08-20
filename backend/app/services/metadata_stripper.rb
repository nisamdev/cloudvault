# frozen_string_literal: true

# Removes the metadata a photo carries about where and when it was taken.
#
# A holiday photo shared with a public link otherwise tells whoever opens it the
# coordinates of the house it was taken in. Family members keep the metadata —
# they are trusted with it and the app shows it to them — so this only runs on
# the anonymous path.
#
# JPEG and PNG are edited at the container level: the marker or chunk carrying
# the metadata is dropped and every other byte is passed through untouched, so
# the image is not recompressed and loses no quality. Formats without a safe
# lossless edit go through libvips, which re-encodes.
class MetadataStripper
  # APP1 holds EXIF (including GPS) and XMP; APP13 holds IPTC. APP0 (JFIF) and
  # APP2 (ICC colour profile) are kept — they describe how to display the image,
  # not who took it.
  JPEG_DROP_MARKERS = ([ 0xE1, 0xED, 0xFE ]).freeze
  PNG_DROP_CHUNKS = %w[eXIf tEXt zTXt iTXt tIME].freeze
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b

  # Formats libvips can both read and write here, so the metadata comes out by
  # re-encoding into the same format.
  VIPS_TYPES = %w[image/tiff image/x-tiff image/webp].freeze

  # HEIC is what an iPhone actually produces, and this build of libvips can
  # decode it but not encode it (no HEIF encoder), so there is nowhere to put
  # the cleaned pixels except another format. JPEG is the one every recipient
  # of a link can open anyway.
  RECODE_TO_JPEG = %w[image/heic image/heif image/avif].freeze

  Result = Struct.new(:bytes, :content_type, :extension, keyword_init: true)

  class << self
    def strippable?(content_type)
      type = content_type.to_s.downcase
      type.in?(%w[image/jpeg image/jpg image/png]) || type.in?(VIPS_TYPES) || type.in?(RECODE_TO_JPEG)
    end

    # What the caller will end up serving, knowable before the bytes are read so
    # a filename can be settled up front.
    def output_for(content_type)
      type = content_type.to_s.downcase
      return { content_type: "image/jpeg", extension: ".jpg" } if type.in?(RECODE_TO_JPEG)

      { content_type: type, extension: nil }
    end

    # Never raises. A refusal to hand back *something* would turn a metadata
    # concern into a broken download, so every failure falls back to bytes that
    # are merely as private as the original was.
    def call(bytes, content_type:)
      type = content_type.to_s.downcase

      case type
      when "image/jpeg", "image/jpg" then Result.new(bytes: strip_jpeg(bytes), content_type: type)
      when "image/png"               then Result.new(bytes: strip_png(bytes), content_type: type)
      when *VIPS_TYPES               then recode(bytes, type, suffix_for(type), type)
      when *RECODE_TO_JPEG           then recode(bytes, type, ".jpg", "image/jpeg", extension: ".jpg")
      else Result.new(bytes: bytes, content_type: type)
      end
    rescue StandardError => e
      Rails.logger.warn("[metadata_stripper] #{type} failed: #{e.class}: #{e.message}")
      Result.new(bytes: bytes, content_type: type)
    end

    private

    def strip_jpeg(bytes)
      data = bytes.b
      return bytes unless data.start_with?("\xFF\xD8".b)

      out = +"\xFF\xD8".b
      offset = 2

      while offset < data.bytesize - 1
        # Segments are FF <marker>; padding FFs between segments are legal.
        return out << data.byteslice(offset..) unless data.getbyte(offset) == 0xFF

        marker = data.getbyte(offset + 1)

        # Start of scan: everything after it is compressed image data.
        if marker == 0xDA
          out << data.byteslice(offset..)
          return out
        end

        # Standalone markers carry no length.
        if marker == 0x01 || (0xD0..0xD9).cover?(marker)
          out << data.byteslice(offset, 2)
          offset += 2
          next
        end

        length = data.byteslice(offset + 2, 2)&.unpack1("n")
        return out << data.byteslice(offset..) if length.nil? || length < 2

        out << data.byteslice(offset, length + 2) unless JPEG_DROP_MARKERS.include?(marker)
        offset += length + 2
      end

      out
    end

    def strip_png(bytes)
      data = bytes.b
      return bytes unless data.start_with?(PNG_SIGNATURE)

      out = +PNG_SIGNATURE.dup
      offset = PNG_SIGNATURE.bytesize

      while offset + 8 <= data.bytesize
        length = data.byteslice(offset, 4).unpack1("N")
        type = data.byteslice(offset + 4, 4)
        # length + type + data + CRC
        total = 12 + length

        out << data.byteslice(offset, total) unless PNG_DROP_CHUNKS.include?(type)
        offset += total

        break if type == "IEND"
      end

      out
    end

    def suffix_for(type)
      type == "image/webp" ? ".webp" : ".tif"
    end

    # Anything without a safe lossless edit goes through libvips, which drops
    # every metadata block on the way out.
    def recode(bytes, source_type, suffix, content_type, extension: nil)
      image = Vips::Image.new_from_buffer(bytes, "")
      out = image.write_to_buffer(suffix, strip: true)

      Result.new(bytes: out, content_type: content_type, extension: extension)
    rescue StandardError => e
      Rails.logger.warn("[metadata_stripper] recode #{source_type} failed: #{e.class}: #{e.message}")
      Result.new(bytes: bytes, content_type: source_type)
    end
  end
end
