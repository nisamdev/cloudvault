# frozen_string_literal: true

require "combine_pdf"
require "prawn"

# Flattens editor fields — text, dates, checkboxes, signatures, initials — onto
# a PDF.
#
# Shaped after the LocalSign editor: the user places overlays on a rendered page
# and the server burns them in. Two deliberate differences from that
# implementation:
#
#   * Geometry arrives as fractions of the page (0..1), not pixels. Pixels only
#     work if the preview happens to be rendered at exactly 72dpi; fractions
#     survive any zoom or render width.
#   * Checkboxes are drawn as two stroked lines rather than a "✓" glyph, which
#     Helvetica does not carry in WinAnsi and would come out as garbage.
#
# The caller saves the result as a new version, so the unfilled original stays.
class PdfFieldStamper
  class Error < StandardError; end

  TYPES = %w[text date checkbox signature initials].freeze

  Field = Struct.new(
    :type, :page, :x, :y, :width, :height, :value,
    :font_size, :bold, :italic, :align, :color,
    keyword_init: true
  )

  DEFAULT_COLOR = "111827"
  CHECK_COLOR = "4F46E5"

  # @param images [Hash{String=>String}] signature id => PNG bytes, resolved by
  #   the caller so this class never touches the database.
  def initialize(pdf_bytes, images: {})
    @pdf_bytes = pdf_bytes
    @images = images
  end

  def call(fields)
    fields = Array(fields).select { |f| TYPES.include?(f.type.to_s) }
    raise Error, "Nothing to stamp" if fields.empty?

    document = CombinePDF.parse(@pdf_bytes)
    raise Error, "That PDF has no pages" if document.pages.empty?

    fields.group_by { |f| f.page.to_i }.each do |page_number, page_fields|
      page = document.pages[page_number - 1]
      raise Error, "Page #{page_number} does not exist" if page.nil?

      page << CombinePDF.parse(stamp_for(page, page_fields)).pages.first
    end

    document.to_pdf
  rescue CombinePDF::ParsingError => e
    raise Error, "That file could not be read as a PDF (#{e.message})"
  end

  private

  def stamp_for(page, fields)
    width, height = page_dimensions(page)

    Prawn::Document.new(page_size: [ width, height ], margin: 0) do |pdf|
      fields.each { |field| draw(pdf, field, width, height) }
    end.render
  end

  def draw(pdf, field, page_width, page_height)
    box = geometry(field, page_width, page_height)

    case field.type.to_s
    when "text" then draw_text(pdf, field, box)
    when "date" then draw_text(pdf, field, box)
    when "checkbox" then draw_checkbox(pdf, field, box)
    when "signature", "initials" then draw_image(pdf, field, box)
    end
  rescue Prawn::Errors::UnsupportedImageType, StandardError => e
    # One bad field must not cost the whole document.
    Rails.logger.error("[stamp] #{field.type} on page #{field.page}: #{e.class}: #{e.message}")
  end

  # Fractions from the top-left to Prawn's points-from-the-bottom.
  def geometry(field, page_width, page_height)
    w = clamp(field.width, 0.01, 1.0) * page_width
    h = clamp(field.height, 0.005, 1.0) * page_height
    x = clamp(field.x, 0.0, 1.0) * page_width
    top = clamp(field.y, 0.0, 1.0) * page_height

    { x: x, y: page_height - top, width: w, height: h }
  end

  def draw_text(pdf, field, box)
    text = field.value.to_s
    return if text.blank?

    style = if field.bold && field.italic then :bold_italic
    elsif field.bold then :bold
    elsif field.italic then :italic
    else :normal
    end

    pdf.fill_color(colour(field.color))
    pdf.text_box(
      text,
      at: [ box[:x], box[:y] ],
      width: box[:width],
      height: box[:height],
      size: (field.font_size || 11).to_f.clamp(5, 72),
      style: style,
      align: (field.align.presence || "left").to_sym,
      valign: :center,
      overflow: :shrink_to_fit
    )
  end

  def draw_checkbox(pdf, _field, box)
    side = [ box[:width], box[:height] ].min
    x = box[:x]
    y = box[:y] - side

    pdf.stroke_color(CHECK_COLOR)
    pdf.line_width(side * 0.14)
    # A tick drawn as two strokes: Helvetica has no check glyph in WinAnsi.
    pdf.stroke_line([ x + side * 0.2, y + side * 0.5 ], [ x + side * 0.42, y + side * 0.25 ])
    pdf.stroke_line([ x + side * 0.42, y + side * 0.25 ], [ x + side * 0.82, y + side * 0.75 ])
    pdf.stroke_color("000000")
  end

  def draw_image(pdf, field, box)
    bytes = @images[field.value.to_s] || inline_image(field.value)
    return if bytes.blank?

    pdf.image(
      StringIO.new(bytes),
      at: [ box[:x], box[:y] ],
      width: box[:width],
      height: box[:height]
    )
  end

  # A signature drawn in the editor and not saved arrives as a data URL.
  def inline_image(value)
    match = value.to_s.match(%r{\Adata:image/(?:png|jpeg);base64,(?<data>.+)\z}m)
    return nil if match.nil?

    Base64.strict_decode64(match[:data])
  rescue ArgumentError
    nil
  end

  def page_dimensions(page)
    box = page[:MediaBox] || page[:CropBox] || [ 0, 0, 595, 842 ]
    [ (box[2].to_f - box[0].to_f).abs, (box[3].to_f - box[1].to_f).abs ]
  end

  def colour(value)
    hex = value.to_s.delete("#")
    hex.match?(/\A[0-9A-Fa-f]{6}\z/) ? hex : DEFAULT_COLOR
  end

  def clamp(value, low, high)
    value.to_f.clamp(low, high)
  end
end
