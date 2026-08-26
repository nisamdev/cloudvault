# frozen_string_literal: true

# The parts of a document worth reading, picked out of the text.
#
# There is no model behind this and it does not pretend to understand anything.
# It knows the shapes that documents put their important parts in — "Label:
# value", a date, an amount of money, a reference number — and it knows what
# boilerplate looks like so it can throw that away. On a passport, a certificate
# or a bill that is enough to surface the handful of things somebody actually
# wanted, which is the difference between this and a page of extracted text.
#
# It is deliberately cautious: a wrong "key detail" is worse than a missing one,
# because the whole text is right there underneath it.
class KeyDetails
  Detail = Struct.new(:label, :value, keyword_init: true)

  # A label is short, starts like a word, and is not a sentence.
  LABEL = /[A-Z][\p{L}][\p{L} .\/'()-]{1,30}?/
  # ":" is the common case; runs of spaces and dot leaders are how PDFs lay out
  # a form without one.
  SEPARATOR = /:|\.{3,}|…|\s{3,}/
  LABELLED_LINE = /\A\s*(#{LABEL})\s*(?:#{SEPARATOR})\s*(\S.{0,120}?)\s*\z/
  # "Surname" on one line, the value on the next — how most forms are laid out.
  TRAILING_LABEL = /\A\s*(#{LABEL})\s*:\s*\z/

  # Passport / ID numbers OCR often puts on the line under a mangled "Passport No."
  PASSPORT_HINT = /passport\s*(?:no\.?|number|#)?/i
  # Letter + digits is the real form (e.g. T9622490). Bare digits are a common
  # OCR miss of the leading letter and only used as a last resort.
  PASSPORT_LETTERED = /\b([A-Z]\d{7,8})\b/i
  PASSPORT_DIGITS = /\b(\d{7,8})\b/
  # ICAO MRZ line 2 starts with the document number (9 chars, < padded).
  # Line 1 starts with P< / V< / etc. and must not be read as a number.
  MRZ_LINE = /\A(?!P<|V<|I<)([A-Z0-9<]{9})[A-Z0-9<]{20,}\z/

  DATE = %r{
    \b(?:
      \d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}
      | \d{4}-\d{2}-\d{2}
      | \d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{2,4}
      | (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{2,4}
    )\b
  }xi

  AMOUNT = /(?:[£$€₹¥]|\b(?:USD|EUR|GBP|INR|AED|AUD|CAD)\b)\s?\d[\d,]*(?:\.\d{2})?/i
  EMAIL = /\b[\w.+-]+@[\w-]+\.[\w.-]{2,}\b/
  # Loose on purpose: phone numbers are written every way there is.
  PHONE = /(?<![\w-])(?:\+\d{1,3}[\s-]?)?(?:\(\d{2,4}\)[\s-]?)?\d{3,5}[\s-]?\d{3,4}(?:[\s-]?\d{3,4})?(?![\w-])/
  # A reference is the thing with both letters and digits that nobody can
  # remember: policy numbers, serials, registrations.
  REFERENCE = /\b(?=[A-Z0-9-]{6,24}\b)(?=[^\s]*\d)(?=[^\s]*[A-Z])[A-Z0-9][A-Z0-9-]{4,22}[A-Z0-9]\b/

  PAGE_NUMBER = %r{\A(page\s*)?\d{1,4}(\s*(of|/)\s*\d{1,4})?\z}i

  # Words that make a line boilerplate however it is laid out.
  BOILERPLATE = /\A(this (page|document) (is|was)|all rights reserved|printed on|generated (on|by)|confidential|do not (reply|write))/i

  MAX_DETAILS = 24
  MAX_PER_KIND = 12

  # @param pages [Array<Hash>] { number:, text: } from PdfTextExtractor
  def initialize(pages)
    @pages = Array(pages)
  end

  def call
    lines = meaningful_lines
    details = labelled(lines)
    merge_detail!(details, passport_number(lines))

    {
      title: title_from(lines),
      details: details.first(MAX_DETAILS).map(&:to_h),
      found: {
        dates: scan(DATE),
        amounts: scan(AMOUNT),
        emails: scan(EMAIL),
        phones: scan(PHONE).select { |phone| phone.count("0-9") >= 7 },
        references: scan(REFERENCE)
      },
      lines: lines
    }
  end

  private

  def all_text
    @all_text ||= @pages.map { |page| page[:text].to_s }.join("\n")
  end

  # Every line of the document with the noise taken out: the running header on
  # every page, the page numbers, and the fragments that extraction produces
  # from a logo or a table border.
  def meaningful_lines
    raw = @pages.flat_map { |page| page[:text].to_s.split("\n") }.map(&:strip)
    repeated = repeated_lines(raw)
    dropping_paragraph = false

    raw.reject do |line|
      # Boilerplate wraps. Dropping the line that starts "This document is
      # issued subject to…" and keeping "…should be retained for your records"
      # reads worse than keeping the lot, so the rest of the paragraph goes with
      # it — up to the next thing that starts something new.
      if dropping_paragraph
        dropping_paragraph = false if line.blank? || starts_something?(line)
        next true if dropping_paragraph
      end

      if line.match?(BOILERPLATE)
        dropping_paragraph = true
        next true
      end

      line.length < 2 ||
        line.match?(PAGE_NUMBER) ||
        repeated.include?(line) ||
        gibberish?(line)
    end
  end

  # A label, or a heading — either way, the paragraph before it has ended.
  def starts_something?(line)
    line.match?(LABELLED_LINE) || line.match?(TRAILING_LABEL) ||
      (line.length < 60 && line == line.upcase && line.count("A-Z") >= 4)
  end

  # A line that shows up on most pages is a header or a footer, not content.
  # Two pages are not enough to tell the difference.
  def repeated_lines(lines)
    return Set.new if @pages.size < 3

    counts = Hash.new(0)
    lines.each { |line| counts[line] += 1 if line.length > 2 }

    threshold = (@pages.size * 0.6).ceil
    counts.select { |_, count| count >= threshold }.keys.to_set
  end

  # Extraction turns rules, logos and ligature tables into runs of punctuation
  # and stray letters. Anything with barely any letters in it and no digits
  # worth keeping is one of those.
  def gibberish?(line)
    return false if line.length <= 3

    letters = line.count("A-Za-z")
    digits = line.count("0-9")
    return false if digits >= 4 # a reference or an amount, not noise

    letters.to_f / line.length < 0.4
  end

  # The first line with some substance to it, which on almost every document is
  # what the document calls itself.
  def title_from(lines)
    lines.find { |line| line.length.between?(4, 80) && line.count("A-Za-z") >= 4 }
  end

  def labelled(lines)
    details = []
    seen = Set.new

    lines.each_with_index do |line, index|
      label, value = split_label(line, lines[index + 1])
      next if label.nil?

      # By label *and* value: a schedule that lists "Item" four times is saying
      # four different things, while a header repeated on every page is not.
      key = [ label.downcase, value.downcase ]
      next if seen.include?(key)
      next unless plausible?(label, value)

      seen << key
      details << Detail.new(label: label, value: value)
    end

    details
  end

  def merge_detail!(details, detail)
    return if detail.nil?

    key = [ detail.label.downcase, detail.value.downcase ]
    return if details.any? { |d| [ d.label.downcase, d.value.downcase ] == key }

    # Prefer an explicit passport detail over a weaker label that grabbed the
    # same digits (e.g. OCR noise treated as a phone).
    details.reject! { |d| d.value.gsub(/\s/, "").casecmp?(detail.value.gsub(/\s/, "")) }
    details.unshift(detail)
  end

  # Passports rarely OCR into a clean "Passport No: X" line. Prefer the MRZ
  # (keeps the leading letter), then a lettered number near "Passport No.",
  # and only then bare digits.
  def passport_number(lines)
    from_mrz = passport_from_mrz
    return from_mrz if from_mrz

    lettered = passport_near_hint(lines, PASSPORT_LETTERED)
    return lettered if lettered

    passport_near_hint(lines, PASSPORT_DIGITS)
  end

  def passport_from_mrz
    all_text.each_line do |line|
      mrz = line.gsub(/\s/, "").upcase
      next unless (match = mrz.match(MRZ_LINE))

      number = match[1].delete("<")
      next if number.length < 6

      return Detail.new(label: "Passport No.", value: number)
    end
    nil
  end

  def passport_near_hint(lines, pattern)
    lines.each_with_index do |line, index|
      next unless line.match?(PASSPORT_HINT)

      from_same = line[pattern, 1]
      return Detail.new(label: "Passport No.", value: from_same.upcase) if from_same

      following = lines[(index + 1)..(index + 3)] || []
      following.each do |candidate|
        value = candidate[pattern, 1]
        return Detail.new(label: "Passport No.", value: value.upcase) if value
      end
    end
    nil
  end

  def split_label(line, following)
    if (match = line.match(LABELLED_LINE))
      [ match[1].strip, match[2].strip ]
    elsif (match = line.match(TRAILING_LABEL)) && following.present?
      # A label with nothing after it takes the next line as its value — but not
      # if that line is itself a label, which would pair two questions together.
      return [ nil, nil ] if following.match?(LABELLED_LINE) || following.match?(TRAILING_LABEL)

      [ match[1].strip, following.strip ]
    else
      [ nil, nil ]
    end
  end

  # The guard against turning ordinary prose into "key details". A real label is
  # a few words; a real value is short and says something.
  def plausible?(label, value)
    return false if value.blank? || value.length > 120
    return false if label.split.size > 4
    return false if label.end_with?(".") # the end of a sentence, not a label
    return false if value.match?(PAGE_NUMBER)

    value.count("A-Za-z0-9") >= 2
  end

  def scan(pattern)
    all_text.scan(pattern)
            .map { |match| (match.is_a?(Array) ? match.first : match).to_s.strip }
            .reject(&:blank?)
            .uniq
            .first(MAX_PER_KIND)
  end
end
