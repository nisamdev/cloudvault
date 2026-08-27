# frozen_string_literal: true

module DocumentExtractors
  # An NHS card, or any card whose value is the number on it.
  #
  # An NHS number carries a modulus-11 check digit, so a ten-digit run either is
  # one or it is not — which stops a random reference on the card being filed as
  # somebody's health number.
  module HealthCard
    module_function

    TEN_DIGITS = /\b(\d{3}[\s-]?\d{3}[\s-]?\d{4})\b/
    NAME_LABEL = /(?:name|patient)\s*[:\-]?\s*([A-Z][A-Za-z'\- ]{2,40})/i
    DOB_LABEL = /(?:date of birth|d\.?o\.?b\.?|born)\s*[:\-]?\s*(\d{1,2}[.\/-]\d{1,2}[.\/-]\d{2,4})/i

    def parse(text)
      body = text.to_s
      fields = {}
      verified = []

      body.scan(TEN_DIGITS).flatten.each do |candidate|
        digits = candidate.gsub(/\D/, "")
        next unless valid_nhs_number?(digits)

        fields["nhs_number"] = digits.insert(6, " ").insert(3, " ")
        verified << "nhs_number"
        break
      end

      if (name = body.match(NAME_LABEL))
        fields["full_name"] = name[1].strip.squeeze(" ")
      end

      if (dob = body.match(DOB_LABEL))
        fields["date_of_birth"] = iso_date(dob[1])
      end

      fields.compact!
      return nil if fields.empty?

      { fields: fields, verified: verified, format: "Health card" }
    end

    # Weights ten down to two across the first nine digits; the remainder of
    # eleven gives the tenth. A remainder of ten means no valid number ends that
    # way, so the run is something else.
    def valid_nhs_number?(digits)
      return false unless digits.match?(/\A\d{10}\z/)
      return false if digits.chars.uniq.size == 1

      total = digits[0, 9].chars.each_with_index.sum { |d, i| d.to_i * (10 - i) }
      remainder = 11 - (total % 11)
      remainder = 0 if remainder == 11

      remainder != 10 && remainder == digits[9].to_i
    end

    def iso_date(raw)
      day, month, year = raw.split(/[.\/-]/).map(&:to_i)
      year += year < 70 ? 2000 : 1900 if year < 100

      Date.new(year, month, day).iso8601
    rescue Date::Error, TypeError
      nil
    end
  end
end
