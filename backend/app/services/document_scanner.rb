# frozen_string_literal: true

# Turns raw phone photos into something worth keeping: straightened, trimmed of
# noise, and optionally combined into a single PDF.
#
# This is deliberately modest compared with a dedicated scanner app — no corner
# detection or perspective correction. Those need either a heavy CV dependency
# or client-side work, and neither belongs in a first pass. What it does do is
# the part that matters most for a passport photographed on a table: honour the
# camera's rotation, cap the resolution, and lift the contrast so text reads.
class DocumentScanner
  MAX_DIMENSION = 2400
  JPEG_QUALITY = 85

  # @param mode [String] "colour" keeps the photo as-is; "document" boosts
  #   contrast and drops saturation, which is what makes scans legible.
  def initialize(mode: "document")
    @mode = mode
  end

  # @return [String] JPEG bytes
  def process(bytes)
    # Document mode runs a histogram pass, which has to see the whole image;
    # sequential access makes libvips read it once and complain ("error in
    # tile"), producing garbage. Colour mode can stream.
    access = @mode == "document" ? :random : :sequential
    image = Vips::Image.new_from_buffer(bytes, "", access: access)

    # autorot applies the EXIF orientation and strips the tag, so the result is
    # upright everywhere rather than only in viewers that read EXIF.
    image = image.autorot
    image = downscale(image)
    image = enhance(image) if @mode == "document"

    image.jpegsave_buffer(Q: JPEG_QUALITY, strip: true, optimize_coding: true)
  rescue Vips::Error => e
    Rails.logger.error("[scan] processing failed: #{e.message}")
    # Better to store the original than to lose the capture.
    bytes
  end

  # Lays the pages out one per page, each scaled to fit A4 with a small margin.
  def self.to_pdf(pages, title: "Scan")
    require "prawn"

    Prawn::Document.new(page_size: "A4", margin: 20, info: { Title: title }) do |pdf|
      pages.each_with_index do |bytes, index|
        pdf.start_new_page if index.positive?

        # Prawn wants an IO it can rewind.
        pdf.image(StringIO.new(bytes), fit: [ pdf.bounds.width, pdf.bounds.height ], position: :center, vposition: :center)
      end
    end.render
  end

  private

  def downscale(image)
    longest = [ image.width, image.height ].max
    return image if longest <= MAX_DIMENSION

    image.resize(MAX_DIMENSION.to_f / longest)
  end

  # Greyscale plus a histogram stretch: the cheap version of "scan mode".
  # Anything more aggressive (adaptive thresholding) turns photos of glossy
  # passports into unreadable blotches, so this stops short of that.
  def enhance(image)
    image = image.colourspace("b-w")
    image = image.hist_equal if image.width * image.height < 12_000_000
    image.colourspace("srgb")
  rescue Vips::Error
    image
  end
end
