# frozen_string_literal: true

require "prawn"

# Lays images out as the pages of a PDF.
#
# The interesting decision is the page itself. A photographed passport and a
# photographed receipt have nothing in common but being rectangular, so "A4 with
# a margin" is right for some and wasteful for others — hence "auto", where the
# page takes the shape of the image and there is no border at all. Fixed sizes
# exist for the other case: a document somebody is going to print.
#
# Pages arrive already cropped and enhanced (the scanner does that in the
# browser, where the user can see what they are getting), so nothing here
# touches the pixels.
class ImagePdfBuilder
  class Error < StandardError; end

  # A document is built entirely in memory, so these are what stop one request
  # taking the process down with it.
  MAX_PAGES = 60
  MAX_TOTAL_BYTES = 150 * 1024 * 1024

  # Prawn embeds JPEG and PNG directly and cannot read anything else.
  SUPPORTED_TYPES = %w[image/jpeg image/png].freeze

  PAGE_SIZES = { "a4" => "A4", "letter" => "LETTER", "legal" => "LEGAL" }.freeze
  MARGINS = { "none" => 0, "small" => 18, "medium" => 36, "large" => 54 }.freeze

  # A point is 1/72", so reading an image as 150dpi keeps an auto-sized page
  # close to the physical size of the thing that was photographed.
  AUTO_DPI = 150
  # PDF's own limit is 200 inches; below about an inch it stops being a page.
  MIN_SIDE = 72.0
  MAX_SIDE = 14_400.0

  # @param images [Array<Hash>] { name:, bytes:, content_type: } in page order
  def initialize(images, page_size: "auto", orientation: "auto", margin: "small", title: nil)
    @images = Array(images)
    @page_size = page_size.to_s.presence || "auto"
    @orientation = orientation.to_s.presence || "auto"
    @margin = MARGINS.fetch(margin.to_s, MARGINS["small"])
    @title = title.presence || "Document"
  end

  # @return [String] PDF bytes
  def call
    validate!

    document = Prawn::Document.new(
      skip_page_creation: true,
      info: { Title: @title, Creator: "CloudVault", CreationDate: Time.current }
    )

    @images.each { |image| draw(document, image) }

    document.render
  end

  private

  def validate!
    raise Error, "Add at least one image." if @images.empty?
    raise Error, "That's more than #{MAX_PAGES} images." if @images.size > MAX_PAGES

    total = @images.sum { |image| image[:bytes].bytesize }
    if total > MAX_TOTAL_BYTES
      raise Error, "Those images come to more than #{MAX_TOTAL_BYTES / (1024 * 1024)} MB together."
    end

    unsupported = @images.find { |image| SUPPORTED_TYPES.exclude?(image[:content_type].to_s) }
    return if unsupported.nil?

    # Naming it matters: with twenty pages, "one of those isn't an image" leaves
    # the user opening each one to find out which.
    raise Error, "#{unsupported[:name]} isn't a JPEG or PNG."
  end

  def draw(document, image)
    width, height = dimensions(image)
    document.start_new_page(page_options(width, height))

    # Prawn wants an IO it can rewind. `fit` contains rather than crops, so
    # nothing photographed is ever silently cut off.
    document.image(
      StringIO.new(image[:bytes]),
      fit: [ document.bounds.width, document.bounds.height ],
      position: :center,
      vposition: :center
    )
  rescue StandardError => e
    Rails.logger.warn("[image_pdf] #{image[:name]}: #{e.class}: #{e.message}")
    raise Error, "#{image[:name]} could not be read — it may be damaged."
  end

  def page_options(width, height)
    # An auto page is the image's own shape, so an orientation would only fight
    # it. The caller's orientation applies to the fixed sizes.
    return { size: auto_size(width, height), margin: @margin } if @page_size == "auto"

    { size: PAGE_SIZES.fetch(@page_size, "A4"), layout: layout_for(width, height), margin: @margin }
  end

  def auto_size(width, height)
    scale = 72.0 / AUTO_DPI

    [
      side(width * scale + (@margin * 2)),
      side(height * scale + (@margin * 2))
    ]
  end

  def side(points)
    points.clamp(MIN_SIDE, MAX_SIDE)
  end

  def layout_for(width, height)
    return @orientation.to_sym if %w[portrait landscape].include?(@orientation)

    width > height ? :landscape : :portrait
  end

  # libvips reads the header lazily, so this costs a parse and not a decode.
  def dimensions(image)
    vips = Vips::Image.new_from_buffer(image[:bytes], "")
    [ vips.width, vips.height ]
  rescue Vips::Error => e
    Rails.logger.warn("[image_pdf] could not measure #{image[:name]}: #{e.message}")
    # A4 at AUTO_DPI, so an unmeasurable image still lands on a sane page.
    [ 1240, 1754 ]
  end
end
