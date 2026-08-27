# frozen_string_literal: true

module DocumentExtractors
  # A UK driving licence.
  #
  # The licence number is not arbitrary: it encodes the surname, the date of
  # birth and the sex of the holder. So reading the number gives a second,
  # independent source for details printed elsewhere on the card — and the two
  # agreeing is the closest this document comes to a check digit.
  #
  #   MORGA 7 53 11 6 SM 9 IJ
  #   |     | |  |  | |  | └ check
  #   |     | |  |  | |  └── arbitrary
  #   |     | |  |  | └───── initials
  #   |     | |  |  └─────── year digit
  #   |     | |  └────────── day
  #   |     | └───────────── month, +50 when female
  #   |     └─────────────── decade
  #   └───────────────────── surname, padded with 9s
  module DrivingLicence
    module_function

    # The card is laid out in columns, and OCR reads across them as often as
    # down: "1. MORGAN 4a. 19.01.2013" is one line as far as tesseract is
    # concerned. So a field runs until the next number rather than to the end
    # of the line.
    NEXT_FIELD = /(?=\s+\d{1,2}[a-d]?[.)]|\s*$)/
    DATE = %r{\d{1,2}\s?[.\-/]\s?\d{1,2}\s?[.\-/]\s?\d{2,4}}
    NAME = /[A-Z][A-Za-z'\-]*(?:[ ][A-Z][A-Za-z'\-]*)*/

    # A DVLA number is exactly sixteen characters, and always the same shape:
    # five of surname, six of date, two initials, a digit, two more letters.
    #
    # It is never looked for by its edges. OCR puts a space where the card
    # prints one and hangs a stray letter off the end where the card has a
    # border, so a pattern anchored on word boundaries finds nothing at all on
    # a real photograph. Instead: pull out the long runs, and slide a
    # sixteen-character window along each until one has the right shape.
    LENGTH = 16
    RUN = /[A-Z0-9]{#{LENGTH},#{LENGTH + 6}}/
    SHAPE = /\A(?<surname>[A-Z9]{5})(?<born>[A-Z0-9]{6})(?<tail>[A-Z]{2}\d[A-Z]{2})\z/

    # What tesseract reaches for when it sees a digit in a word-shaped place.
    AS_DIGIT = { "O" => "0", "Q" => "0", "D" => "0", "I" => "1", "L" => "1",
                 "S" => "5", "B" => "8", "Z" => "2", "G" => "6", "T" => "7" }.freeze

    FIELDS = {
      "surname" => 1,
      "given_names" => 2,
      "date_of_birth" => 3,
      "issued_on" => "4a",
      "expires_on" => "4b"
    }.freeze

    def parse(text)
      body = text.to_s
      fields = {}

      FIELDS.each do |key, marker|
        value = date?(key) ? field(body, marker, DATE) : field(body, marker, NAME, bounded: true)
        fields[key] = tidy(key, value) if value
      end

      fields.merge!(from_number(body))
      confirmed = verified(fields)

      # The number is the only source for a date of birth the card did not
      # print legibly, so it stands in — as a reading, not as a confirmation.
      fields["date_of_birth"] ||= fields["born_by_number"]
      fields.delete("born_by_number")
      fields["full_name"] = full_name(fields)

      fields = fields.compact_blank
      return nil if fields.empty?

      { fields: fields, verified: confirmed, format: "UK licence" }
    end

    # Pulls one numbered field out, wherever on the line it landed.
    #
    # A name has to be told where to stop, or it runs into the next column. A
    # date stops at itself — the card prints the country of issue right after
    # the date of birth, and waiting for a field number loses the date.
    def field(body, marker, shape, bounded: false)
      stop = bounded ? NEXT_FIELD : ""

      body.match(/(?:^|\s)#{marker}\s*[.)]?\s+(#{shape})#{stop}/)&.captures&.first
    end

    def date?(key) = key.end_with?("_on") || key == "date_of_birth"

    def from_number(body)
      number = licence_number(body)
      return {} if number.nil?

      { "licence_number" => number }.merge(decode(number))
    end

    def licence_number(body)
      upper = body.upcase
      # The line numbered 5 is where it belongs, so it is tried first; the rest
      # of the page is the fallback for a card whose numbering went unread.
      runs = [ field(upper, 5, /[A-Z0-9 ]{#{LENGTH},}/).to_s.delete(" ") ]
      runs.concat(upper.scan(RUN))

      runs.compact_blank.each do |run|
        (0..run.length - LENGTH).each do |offset|
          number = repair(run[offset, LENGTH])
          return number if number
        end
      end

      nil
    end

    # The six date characters must be digits, so a letter sitting among them is
    # a misread rather than a different number.
    def repair(candidate)
      parts = candidate.match(/\A(.{5})(.{6})(.{5})\z/)
      return nil if parts.nil?

      surname, born, tail = parts.captures
      born = born.chars.map { |char| AS_DIGIT.fetch(char, char) }.join
      number = "#{surname}#{born}#{tail}"

      number if number.match?(SHAPE)
    end

    def decode(number)
      return {} unless number.length >= 11

      decade = number[5]
      month = number[6, 2].to_i
      day = number[8, 2].to_i
      year_digit = number[10]

      female = month > 50
      month -= 50 if female
      return {} unless month.between?(1, 12) && day.between?(1, 31)

      year = "19#{decade}#{year_digit}".to_i
      # A licence holder born this century has a 20xx year; the decade digit
      # alone cannot say which, so anything implying a future birth rolls back.
      year += 100 if year + 100 <= Date.current.year - 15

      { "sex" => female ? "Female" : "Male", "born_by_number" => safe_date(year, month, day) }.compact
    end

    # What the card prints and what the number encodes are two independent
    # readings. Where they agree, the field is as good as checked; where only
    # one exists, it is a reading and nothing more.
    def verified(fields)
      number = fields["licence_number"]
      return [] if number.blank?

      confirmed = []
      born = fields["born_by_number"]
      confirmed << "date_of_birth" if born.present? && fields["date_of_birth"] == born
      confirmed << "surname" if surname_agrees?(number, fields["surname"])
      confirmed << "full_name" if confirmed.include?("surname") && fields["given_names"].present?
      # Both halves of the number checking out against what is printed beside
      # them says the number itself was read correctly.
      confirmed << "licence_number" if confirmed.include?("date_of_birth") && confirmed.include?("surname")

      confirmed
    end

    def full_name(fields)
      [ fields["given_names"], fields["surname"] ].compact_blank.join(" ").presence
    end

    def surname_agrees?(number, printed)
      return false if printed.blank?

      number[0, 5] == printed.upcase.gsub(/[^A-Z]/, "").ljust(5, "9")[0, 5]
    end

    def safe_date(year, month, day)
      Date.new(year, month, day).iso8601
    rescue Date::Error
      nil
    end

    def tidy(key, value)
      cleaned = value.to_s.strip.squeeze(" ")
      return cleaned unless date?(key)

      parts = cleaned.delete(" ").split(%r{[.\-/]})
      return cleaned unless parts.size == 3

      day, month, year = parts.map(&:to_i)
      year += year < 70 ? 2000 : 1900 if year < 100
      safe_date(year, month, day) || cleaned
    end
  end
end
