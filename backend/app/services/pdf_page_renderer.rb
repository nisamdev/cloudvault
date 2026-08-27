# frozen_string_literal: true

# Renders PDF pages to PNG so the browser can show them without a PDF library.
#
# libvips reads PDFs through poppler, which is already in the image for
# thumbnails, so this needs no new dependency and no client-side rendering.
class PdfPageRenderer
  # Wide enough to place a signature accurately, small enough to send several.
  RENDER_WIDTH = 900
  MAX_PAGES = 20

  # Rearranging pages only needs to show which page is which, so they come back
  # small enough that a long document can be sent a batch at a time.
  THUMB_WIDTH = 260
  MAX_THUMBS = 24

  # Wide enough to read the small print on a card that occupies a corner of the
  # page. A scan is going to be cropped and put through OCR, and a rendering
  # too small to read is too small to crop out of.
  READ_WIDTH = 1700

  def initialize(pdf_bytes, width: RENDER_WIDTH, format: :png)
    @pdf_bytes = pdf_bytes
    @width = width
    @format = format
  end

  def page_count
    @page_count ||= begin
      image = Vips::Image.pdfload_buffer(@pdf_bytes, page: 0)
      image.get("pdf-n_pages")
    rescue Vips::Error, StandardError
      0
    end
  end

  # @param from [Integer] first page to render, counting from 1 — so a long
  #   document can be fetched in batches rather than in one enormous response.
  # @return [Array<Hash>] one entry per page: number, aspect ratio, PNG bytes
  def pages(limit: MAX_PAGES, from: 1)
    first = [ from.to_i, 1 ].max - 1
    last = [ first + limit, page_count ].min

    (first...last).map do |index|
      # Rendering below the width being asked for and scaling up loses the
      # detail the width was asked for in the first place.
      image = Vips::Image.pdfload_buffer(@pdf_bytes, page: index, dpi: @width > 1200 ? 300 : 150)
      scaled = image.width > @width ? image.resize(@width.to_f / image.width) : image

      {
        number: index + 1,
        width: scaled.width,
        height: scaled.height,
        # JPEG for the big renders: a photograph of a card compresses to a
        # tenth of the PNG, and these travel inline as base64.
        png: encode(scaled),
        content_type: @format == :jpeg ? "image/jpeg" : "image/png"
      }
    rescue Vips::Error => e
      Rails.logger.error("[pdf-render] page #{index + 1}: #{e.message}")
      nil
    end.compact
  end

  private

  def encode(image)
    return image.jpegsave_buffer(Q: 88, strip: true) if @format == :jpeg

    image.pngsave_buffer(compression: 9)
  end
end
