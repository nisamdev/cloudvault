# frozen_string_literal: true

require "open3"
require "vips"

# Reads the writing inside a scan — pages that are pictures, not a text layer.
#
# Rasterises each page with libvips (same path as signing previews), then hands
# the PNG to tesseract. Used only when PdfTextExtractor finds nothing: a real
# text PDF should never pay this cost.
class PdfOcr
  MAX_PAGES = 30
  DPI = 200
  # Cap long edge so a huge scan doesn't melt the worker; tesseract still gets
  # enough pixels for body text at letter size.
  MAX_EDGE = 2000

  Result = Struct.new(:pages, :page_count, :truncated, keyword_init: true) do
    def text = pages.map { |page| page[:text] }.join("\n\n")
    def any_text? = pages.any? { |page| page[:text].present? }
  end

  def self.available?
    return @available if defined?(@available)

    @available = system("tesseract", "--version", out: File::NULL, err: File::NULL)
  end

  # Tesseract's page segmentation. 3 assumes a page of prose and suits most
  # documents; 4 assumes a single column of text in mixed sizes, which is what
  # an identity card is and what a page of prose is not.
  PAGE = "3"
  CARD = "4"

  def initialize(bytes, layout: PAGE)
    @bytes = bytes
    @layout = layout
  end

  def call
    return empty_result unless self.class.available?

    total = page_count
    return empty_result if total.zero?

    pages = []
    truncated = total > MAX_PAGES

    (0...[ total, MAX_PAGES ].min).each do |index|
      text = ocr_page(index)
      pages << { number: index + 1, text: text }
    end

    Result.new(pages: pages, page_count: total, truncated: truncated)
  rescue StandardError => e
    Rails.logger.error("[pdf_ocr] #{e.class}: #{e.message}")
    empty_result
  end

  private

  def empty_result
    Result.new(pages: [], page_count: 0, truncated: false)
  end

  def page_count
    image = Vips::Image.pdfload_buffer(@bytes, page: 0)
    image.get("pdf-n_pages")
  rescue Vips::Error, StandardError
    0
  end

  def ocr_page(index)
    image = Vips::Image.pdfload_buffer(@bytes, page: index, dpi: DPI)
    long = [ image.width, image.height ].max
    image = image.resize(MAX_EDGE.to_f / long) if long > MAX_EDGE
    png = greyscale(image).pngsave_buffer

    Tempfile.create([ "ocr", ".png" ]) do |file|
      file.binmode
      file.write(png)
      file.flush

      # stdout basename → text on stdout; English is enough for family docs.
      out, err, status = Open3.capture3(
        "tesseract", file.path, "stdout",
        "-l", "eng",
        "--psm", @layout
      )

      unless status.success?
        Rails.logger.info("[pdf_ocr] page #{index + 1}: #{err.to_s.strip.presence || status}")
        return ""
      end

      clean(out)
    end
  rescue Vips::Error, StandardError => e
    Rails.logger.info("[pdf_ocr] page #{index + 1}: #{e.class}: #{e.message}")
    ""
  end

  # Colour carries nothing tesseract wants, and a laminated card photographed
  # under a light reads better without it.
  def greyscale(image)
    image.colourspace("b-w")
  rescue Vips::Error
    image
  end

  def clean(text)
    text.to_s
        .unicode_normalize(:nfkc)
        .gsub(/\r\n?/, "\n")
        .gsub(/[   ]/, " ")
        .split("\n")
        .map { |line| line.gsub(/[ \t]+/, " ").strip }
        .join("\n")
        .gsub(/\n{3,}/, "\n\n")
        .strip
  rescue ArgumentError, Encoding::CompatibilityError
    text.to_s.scrub("?").gsub(/[ \t]+/, " ").strip
  end
end
