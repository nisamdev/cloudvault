# frozen_string_literal: true

# Renders PDF pages to PNG so the browser can show them without a PDF library.
#
# libvips reads PDFs through poppler, which is already in the image for
# thumbnails, so this needs no new dependency and no client-side rendering.
class PdfPageRenderer
  # Wide enough to place a signature accurately, small enough to send several.
  RENDER_WIDTH = 900
  MAX_PAGES = 20

  def initialize(pdf_bytes)
    @pdf_bytes = pdf_bytes
  end

  def page_count
    @page_count ||= begin
      image = Vips::Image.pdfload_buffer(@pdf_bytes, page: 0)
      image.get("pdf-n_pages")
    rescue Vips::Error, StandardError
      0
    end
  end

  # @return [Array<Hash>] one entry per page: number, aspect ratio, PNG bytes
  def pages(limit: MAX_PAGES)
    (0...[ page_count, limit ].min).map do |index|
      image = Vips::Image.pdfload_buffer(@pdf_bytes, page: index, dpi: 150)
      scaled = image.width > RENDER_WIDTH ? image.resize(RENDER_WIDTH.to_f / image.width) : image

      {
        number: index + 1,
        width: scaled.width,
        height: scaled.height,
        png: scaled.pngsave_buffer(compression: 9)
      }
    rescue Vips::Error => e
      Rails.logger.error("[pdf-render] page #{index + 1}: #{e.message}")
      nil
    end.compact
  end
end
