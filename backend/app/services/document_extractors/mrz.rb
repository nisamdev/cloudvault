# frozen_string_literal: true

module DocumentExtractors
  # The two or three lines of <<<-padded text at the bottom of a passport,
  # residence permit or ID card.
  #
  # This is the one place where reading a document by machine is genuinely
  # solved. The zone has fixed columns and **check digits**, so it can be parsed
  # exactly and then verified — the document tells you whether you read it
  # correctly. No amount of cleverness elsewhere beats that.
  #
  # TD3 is the passport shape (2 lines of 44); TD1 is the card shape (3 lines of
  # 30) used by residence permits and most national ID cards.
  module Mrz
    module_function

    FILLER = "<"

    # OCR reliably confuses these inside the zone, where only A–Z, 0–9 and <
    # can legally appear.
    LETTER_FIXES = { "0" => "O", "1" => "I", "2" => "Z", "5" => "S", "8" => "B" }.freeze
    DIGIT_FIXES = { "O" => "0", "Q" => "0", "D" => "0", "I" => "1", "L" => "1",
                    "Z" => "2", "S" => "5", "B" => "8", "G" => "6" }.freeze

    # @return [Hash, nil] the fields, plus which of them the check digits confirm
    def parse(text)
      lines = candidate_lines(text)

      parse_td3(lines) || parse_td1(lines)
    end

    # Lines that look like part of a zone: long, and made only of the alphabet
    # a zone is allowed to use.
    def candidate_lines(text)
      text.to_s.upcase.split(/\r?\n/).filter_map do |line|
        cleaned = line.gsub(/[^A-Z0-9<]/, "")
        next if cleaned.length < 28

        cleaned
      end
    end

    def parse_td3(lines)
      first = lines.find { |l| l.start_with?("P") && l.length.between?(40, 48) }
      return nil if first.nil?

      second = lines[(lines.index(first) + 1)..]&.find { |l| l.length.between?(40, 48) }
      return nil if second.nil?

      first = pad(first, 44)
      second = pad(second, 44)

      names = read_names(first[5..])
      number = letters_to_digits_free(second[0, 9])

      fields = {
        "document_number" => number.delete(FILLER),
        "country" => second[10, 3].delete(FILLER),
        "date_of_birth" => read_date(second[13, 6], :past),
        "expires_on" => read_date(second[21, 6], :future),
        "sex" => read_sex(second[20])
      }.merge(names)

      verified = {
        "document_number" => check(second[0, 9], second[9]),
        "date_of_birth" => check(second[13, 6], second[19]),
        "expires_on" => check(second[21, 6], second[27])
      }

      finish(fields, verified, "TD3")
    end

    def parse_td1(lines)
      run = lines.each_cons(3).find { |trio| trio.all? { |l| l.length.between?(28, 32) } }
      return nil if run.nil?

      first, second, third = run.map { |l| pad(l, 30) }
      return nil unless first.match?(/\A[A-Z]/)

      fields = {
        "document_number" => first[5, 9].delete(FILLER),
        "country" => second[15, 3].delete(FILLER),
        "date_of_birth" => read_date(second[0, 6], :past),
        "expires_on" => read_date(second[8, 6], :future),
        "sex" => read_sex(second[7])
      }.merge(read_names(third))

      verified = {
        "document_number" => check(first[5, 9], first[14]),
        "date_of_birth" => check(second[0, 6], second[6]),
        "expires_on" => check(second[8, 6], second[14])
      }

      finish(fields, verified, "TD1")
    end

    def finish(fields, verified, format)
      fields = fields.compact.reject { |_k, v| v.to_s.strip.empty? }
      return nil if fields["document_number"].blank?

      { fields: fields, verified: verified.select { |_k, ok| ok }.keys, format: format }
    end

    # SURNAME<<GIVEN<NAMES — the double filler separates the two.
    def read_names(segment)
      surname, given = segment.to_s.split("#{FILLER}#{FILLER}", 2)

      {
        "surname" => titleise(surname),
        "given_names" => titleise(given),
        "full_name" => [ titleise(given), titleise(surname) ].compact_blank.join(" ").presence
      }.compact
    end

    def titleise(part)
      return nil if part.blank?

      part.tr(FILLER, " ").squeeze(" ").strip.split.map(&:capitalize).join(" ").presence
    end

    def read_sex(char)
      { "M" => "Male", "F" => "Female" }[char]
    end

    # YYMMDD, with no century in it. Which century is decided by what the date
    # is for: a birth is behind us and an expiry is ahead.
    def read_date(raw, direction)
      digits = letters_to_digits(raw.to_s)
      return nil unless digits.match?(/\A\d{6}\z/)

      year = digits[0, 2].to_i
      month = digits[2, 2].to_i
      day = digits[4, 2].to_i
      return nil unless month.between?(1, 12) && day.between?(1, 31)

      century = direction == :past ? past_century(year) : future_century(year)

      Date.new(century + year, month, day).iso8601
    rescue Date::Error
      nil
    end

    def past_century(year)
      year > (Date.current.year % 100) ? 1900 : 2000
    end

    def future_century(year)
      year < 70 ? 2000 : 1900
    end

    # 7-3-1 weighting, digits count as themselves and letters as 10 upwards.
    def check(value, digit)
      expected = letters_to_digits(digit.to_s)
      return false unless expected.match?(/\A\d\z/)

      weights = [ 7, 3, 1 ]
      total = value.to_s.chars.each_with_index.sum do |char, index|
        char_value(char) * weights[index % 3]
      end

      (total % 10).to_s == expected
    end

    def char_value(char)
      return 0 if char == FILLER
      return char.to_i if char.match?(/\d/)
      return char.ord - "A".ord + 10 if char.match?(/[A-Z]/)

      0
    end

    def letters_to_digits(text)
      text.to_s.chars.map { |c| DIGIT_FIXES.fetch(c, c) }.join
    end

    # A document number may legitimately contain letters, so only the shapes
    # OCR gets wrong in both directions are left alone here.
    def letters_to_digits_free(text) = text.to_s

    def pad(line, width)
      line.length >= width ? line[0, width] : line.ljust(width, FILLER)
    end
  end
end
