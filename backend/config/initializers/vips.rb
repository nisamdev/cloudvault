# frozen_string_literal: true

require "vips"

# libvips blocks its PDF loader by default. The block exists because poppler
# parses a complex format written by other people's software, and libvips treats
# that as untrusted input.
#
# We unblock exactly that one loader — nothing else — because rendering PDF
# pages to images is what makes signing possible without shipping a PDF renderer
# to the browser. The exposure is bounded: PDFs here are uploaded by
# authenticated members of one family, rendering happens server-side inside the
# container, and the output is a PNG.
#
# If that trade stops being acceptable, the alternative is poppler-utils
# (pdftoppm) in a separate process.
Rails.application.config.after_initialize do
  Vips.block("VipsForeignLoadPdf", false)
rescue StandardError => e
  # An older libvips without the block API simply has nothing to unblock.
  Rails.logger.info("[vips] PDF loader unblock skipped: #{e.class}")
end
