# frozen_string_literal: true

require "combine_pdf"

# Joins several PDFs into one, in the order given.
#
# The order is the caller's, not the order the files happen to come back from
# the database in — passport page 2 after page 1 is the whole point.
class PdfMerger
  class Error < StandardError; end

  # A merge is held entirely in memory, so this is what stops one request
  # taking the process down with it.
  MAX_PARTS = 30
  MAX_TOTAL_BYTES = 100 * 1024 * 1024

  def initialize(parts)
    @parts = parts
  end

  # parts: [{ name:, bytes: }, ...]
  def call
    raise Error, "Pick at least two PDFs to merge." if @parts.size < 2
    raise Error, "That's more than #{MAX_PARTS} files." if @parts.size > MAX_PARTS

    total = @parts.sum { |part| part[:bytes].bytesize }
    raise Error, "Those files come to more than 100 MB together." if total > MAX_TOTAL_BYTES

    merged = CombinePDF.new

    @parts.each do |part|
      merged << load_part(part)
    end

    raise Error, "The result had no pages." if merged.pages.empty?

    merged.to_pdf
  end

  private

  def load_part(part)
    CombinePDF.parse(part[:bytes])
  rescue StandardError => e
    # Naming the file matters: with ten of them, "a PDF was unreadable" leaves
    # the user opening each one to find out which.
    Rails.logger.warn("[pdf_merger] #{part[:name]}: #{e.class}: #{e.message}")
    raise Error, "#{part[:name]} could not be read — it may be encrypted or damaged."
  end
end
