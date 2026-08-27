# frozen_string_literal: true

require "combine_pdf"

# Rebuilds a PDF from its own pages, in whatever order and orientation the
# caller asks for — and without the ones they left out.
#
# The layout is absolute rather than a list of edits: the caller sends the
# document it wants, page by page, and this produces it. A stream of "move page
# 3 to 1, then rotate page 2" would have to be replayed in the same order on
# both sides to agree, and the two sides would eventually disagree.
class PdfPageArranger
  class Error < StandardError; end

  # Held in memory while it is rebuilt, and every page is a thumbnail on
  # somebody's screen before it gets here.
  MAX_PAGES = 200

  ROTATIONS = [ 0, 90, 180, 270 ].freeze

  def initialize(pdf_bytes)
    @pdf_bytes = pdf_bytes
  end

  # @param layout [Array<Hash>] { number:, rotation: }, in the order wanted.
  #   `number` counts from 1 and refers to the *original* document; `rotation`
  #   is clockwise degrees to turn that page by.
  # @return [String] PDF bytes
  def call(layout)
    raise Error, "A document needs at least one page." if layout.blank?
    raise Error, "That's more than #{MAX_PAGES} pages." if layout.size > MAX_PAGES

    source = parse
    seen = []

    document = CombinePDF.new

    layout.each do |entry|
      number = entry[:number].to_i
      page = source.pages[number - 1]
      raise Error, "This document has no page #{number}." if number < 1 || page.nil?

      # The same page twice would be the same object twice, so rotating one copy
      # would rotate both. Duplicating a page is a fair thing to want; it is not
      # this tool, and quietly producing the wrong document would be worse.
      raise Error, "Page #{number} can only appear once." if seen.include?(number)

      seen << number
      rotate(page, entry[:rotation])
      document << page
    end

    document.to_pdf
  end

  private

  def parse
    document = CombinePDF.parse(@pdf_bytes)
    raise Error, "That document has no pages." if document.pages.empty?

    document
  rescue Error
    raise
  rescue StandardError => e
    Rails.logger.warn("[pdf_pages] could not read: #{e.class}: #{e.message}")
    raise Error, "That document could not be read — it may be encrypted or damaged."
  end

  # CombinePDF turns a page rather than setting a /Rotate flag, so the result is
  # rotated for every reader rather than only the ones that honour the flag.
  def rotate(page, degrees)
    case normalise(degrees)
    when 90 then page.rotate_right
    when 180 then page.rotate_180
    when 270 then page.rotate_left
    end
  end

  def normalise(degrees)
    turned = degrees.to_i % 360
    raise Error, "Pages turn in quarters." unless ROTATIONS.include?(turned)

    turned
  end
end
