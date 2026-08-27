# frozen_string_literal: true

module DocumentExtractors
  # A UK driving licence.
  #
  # The licence number is not arbitrary: it encodes the surname, the date of
  # birth and the sex of the holder. So reading the number gives a second,
  # independent source for details printed elsewhere on the card — and if the
  # two disagree, one of them was misread.
  #
  #   MORGA 6 57 05 4 SM 9 IJ
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

    NUMBER = /\b([A-Z9]{5}\d{6}[A-Z0-9]{2}\d?[A-Z]{2})\b/

    # The card prints its dates against numbers rather than words.
    FIELD_LINES = {
      "surname" => /^\s*1\.?\s+([A-Z][A-Za-z'\- ]{1,40})\s*$/,
      "given_names" => /^\s*2\.?\s+([A-Z][A-Za-z'\- ]{1,40})\s*$/,
      "issued_on" => /^\s*4a\.?\s+(\d{2}[.\/-]\d{2}[.\/-]\d{2,4})/,
      "expires_on" => /^\s*4b\.?\s+(\d{2}[.\/-]\d{2}[.\/-]\d{2,4})/
    }.freeze

    def parse(text)
      body = text.to_s
      fields = {}
      verified = []

      FIELD_LINES.each do |key, pattern|
        match = body.match(pattern)
        fields[key] = tidy(key, match[1]) if match
      end

      number = body.upcase.match(NUMBER)&.captures&.first
      if number
        fields["licence_number"] = number
        decoded = decode(number)
        fields.merge!(decoded) { |_key, printed, _from_number| printed }
        # The number agreeing with what is printed above it is as close to a
        # check digit as this document gets.
        verified << "date_of_birth" if decoded["date_of_birth"].present?
        verified << "surname" if surname_agrees?(number, fields["surname"])
      end

      return nil if fields.empty?

      { fields: fields.compact, verified: verified, format: "UK licence" }
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

      {
        "date_of_birth" => safe_date(year, month, day),
        "sex" => female ? "Female" : "Male"
      }.compact
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
      cleaned = value.to_s.strip
      return cleaned unless key.end_with?("_on")

      parts = cleaned.split(/[.\/-]/)
      return cleaned unless parts.size == 3

      day, month, year = parts.map(&:to_i)
      year += year < 70 ? 2000 : 1900 if year < 100
      safe_date(year, month, day) || cleaned
    end
  end
end
