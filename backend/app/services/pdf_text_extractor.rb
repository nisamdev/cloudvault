# frozen_string_literal: true

require "pdf/reader"

# Pulls the text layer out of a PDF.
#
# Only the text that is *in* the file. A PDF made by photographing something —
# which is most of what a family scans — carries no text at all, and saying so
# is far more useful than returning an empty string that looks like a bug.
class PdfTextExtractor
  # Beyond this the answer stops being something a person reads and starts being
  # a download, and both the JSON and the browser suffer for it.
  MAX_PAGES = 120
  MAX_CHARS = 400_000

  Result = Struct.new(:pages, :page_count, :truncated, keyword_init: true) do
    def text = pages.map { |page| page[:text] }.join("\n\n")
    def any_text? = pages.any? { |page| page[:text].present? }
  end

  def initialize(bytes)
    @bytes = bytes
  end

  def call
    reader = PDF::Reader.new(StringIO.new(@bytes))
    pages = []
    characters = 0
    truncated = false

    reader.pages.each_with_index do |page, index|
      if index >= MAX_PAGES || characters >= MAX_CHARS
        truncated = true
        break
      end

      text = clean(safe_text(page))
      characters += text.length
      pages << { number: index + 1, text: text }
    end

    Result.new(pages: pages, page_count: reader.page_count, truncated: truncated)
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    Rails.logger.info("[pdf_text] #{e.class}: #{e.message}")
    Result.new(pages: [], page_count: 0, truncated: false)
  rescue StandardError => e
    Rails.logger.error("[pdf_text] #{e.class}: #{e.message}")
    Result.new(pages: [], page_count: 0, truncated: false)
  end

  private

  # One unreadable page should cost that page, not the document.
  def safe_text(page)
    page.text
  rescue StandardError => e
    Rails.logger.info("[pdf_text] page unreadable: #{e.class}")
    ""
  end

  # PDFs lay text out by position, so what comes back is full of runs of spaces
  # holding columns apart, and of blank lines. Neither survives being pasted
  # somewhere else, so both are tidied here rather than by every caller.
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
    # Text extracted from a damaged PDF is not always valid UTF-8.
    text.to_s.scrub("?").gsub(/[ \t]+/, " ").strip
  end
end
