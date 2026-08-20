# frozen_string_literal: true

require "combine_pdf"
require "prawn"

# Stamps a signature image onto an existing PDF.
#
# The original file is never modified in place — the caller saves the result as
# a new version, so the unsigned document always survives. That matters more
# here than saving space: a signed passport form you cannot un-sign is a trap.
#
# Placements arrive as fractions of the page (0..1) rather than points, because
# the client positions the signature on a rendered preview image and has no idea
# what the underlying page geometry is.
class PdfSigner
  class Error < StandardError; end

  Placement = Struct.new(:page, :x, :y, :width, keyword_init: true)

  # Guards against a signature scaled to cover the whole document, which is
  # almost always a bug in the caller rather than an intent.
  MAX_WIDTH_FRACTION = 0.9
  MIN_WIDTH_FRACTION = 0.02

  def initialize(pdf_bytes, signature_bytes)
    @pdf_bytes = pdf_bytes
    @signature_bytes = signature_bytes
  end

  # @param placements [Array<Placement>]
  # @return [String] the signed PDF
  def call(placements)
    raise Error, "No placements given" if placements.blank?

    document = CombinePDF.parse(@pdf_bytes)
    raise Error, "That PDF has no pages" if document.pages.empty?

    placements.group_by(&:page).each do |page_number, on_this_page|
      page = document.pages[page_number - 1]
      raise Error, "Page #{page_number} does not exist" if page.nil?

      stamp = build_stamp(page, on_this_page)
      # << overlays; the original page content stays underneath.
      page << CombinePDF.parse(stamp).pages.first
    end

    document.to_pdf
  rescue CombinePDF::ParsingError => e
    raise Error, "That file could not be read as a PDF (#{e.message})"
  end

  private

  # One transparent page the same size as the original, carrying the signature
  # at each requested spot.
  def build_stamp(page, placements)
    width, height = page_dimensions(page)

    Prawn::Document.new(page_size: [ width, height ], margin: 0) do |pdf|
      placements.each do |placement|
        draw_width = clamp(placement.width) * width

        # Prawn measures y from the bottom and anchors an image by its top-left
        # corner; the client measures from the top.
        x = placement.x.to_f.clamp(0.0, 1.0) * width
        y = height - (placement.y.to_f.clamp(0.0, 1.0) * height)

        pdf.image(StringIO.new(@signature_bytes), at: [ x, y ], width: draw_width)
      end
    end.render
  end

  # MediaBox is [x0, y0, x1, y1] and need not start at the origin.
  def page_dimensions(page)
    box = page[:MediaBox] || page[:CropBox] || [ 0, 0, 595, 842 ]
    [ (box[2].to_f - box[0].to_f).abs, (box[3].to_f - box[1].to_f).abs ]
  end

  def clamp(fraction)
    fraction.to_f.clamp(MIN_WIDTH_FRACTION, MAX_WIDTH_FRACTION)
  end
end
