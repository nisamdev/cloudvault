# frozen_string_literal: true

module DocumentExtractors
  # A Canadian provincial driver's licence — Alberta's layout, which most of the
  # provinces follow closely enough to be worth trying.
  #
  # Nothing on the card checks anything else on it: the number encodes no date
  # and carries no check digit, unlike a UK licence. So this reads, and vouches
  # for nothing. Every field comes back as something to look at.
  #
  # The card is also read by a machine that is guessing. "07" comes back as
  # "OT", "Exp07" arrives with no space in it, and the province name across the
  # top is decoration that often does not survive at all. So the shape of the
  # card is what is trusted here, not its labels.
  module CanadianLicence
    module_function

    MONTHS = %w[JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC].freeze
    # Six digits, a dash, three more. No boundary in front of it: OCR reads the
    # tiny "No" label as a digit and glues it on — "%0176611-770" — and a
    # boundary there puts the number out of reach. The dash is what makes the
    # shape specific enough to find without one.
    NUMBER = /(\d{6})\s?-\s?(\d{3})\b/
    # And a fallback for when the dash itself was not read.
    NUMBER_RUN = /\b(\d{6})(\d{3})\b/
    POSTCODE = /\b[A-Z]\d[A-Z]\s?\d[A-Z]\d\b/
    PROVINCE = /\b(AB|BC|MB|NB|NL|NS|NT|NU|ON|PE|QC|SK|YT)\b/
    STREET = /\A\d+\s+[A-Za-z]/
    # No word boundary in front of the day. OCR reads the "DOB" label as digits
    # and runs it into the date — "00807 OCT 1985" — and a boundary there puts
    # the day out of reach. The month name and the four-digit year are anchor
    # enough on their own.
    DATE = /([A-Z0-9]{1,2})\s+(#{MONTHS.join("|")})\s+(\d{4})\b/i
    AS_DIGIT = { "O" => "0", "Q" => "0", "D" => "0", "I" => "1", "L" => "1",
                 "S" => "5", "B" => "8", "Z" => "2", "G" => "6", "T" => "7" }.freeze

    PROVINCES = {
      "AB" => "Alberta", "BC" => "British Columbia", "MB" => "Manitoba",
      "NB" => "New Brunswick", "NL" => "Newfoundland and Labrador", "NS" => "Nova Scotia",
      "NT" => "Northwest Territories", "NU" => "Nunavut", "ON" => "Ontario",
      "PE" => "Prince Edward Island", "QC" => "Quebec", "SK" => "Saskatchewan", "YT" => "Yukon"
    }.freeze

    # A surname is printed alone, in capitals, and is a word rather than a
    # label or a month. Requiring the whole line to be capitals keeps it away
    # from the mangled lines of small print around it.
    SURNAME_LINE = /\A[A-Z][A-Z' -]{3,}\z/
    # And a given name is printed under it, capitalised the ordinary way.
    GIVEN_LINE = /\A[A-Z][a-z]+(?:[ -][A-Z][a-z]+)*\z/
    NOT_A_NAME = Regexp.union(
      /\A(?:ALBERTA|CANADA|DRIVER|DRIVERS|LICENCE|LICENSE|CLASS|COND|ENDORSEMENTS|SEX|EYES|HAIR|EXP|DOB|ISS)\b/,
      /\A(?:#{MONTHS.join("|")})\b/
    )

    def parse(text)
      body = spaced(text)
      fields = {}

      # OCR breaks the number up wherever the card's kerning invites it —
      # "1786 11- 770" — so the digits are closed up before it is looked for.
      closed = body.gsub(/(?<=\d)[ ]+(?=\d)/, "")
      number = closed.match(NUMBER) || closed.match(NUMBER_RUN)
      fields["licence_number"] = "#{number[1]}-#{number[2]}" if number

      fields.merge!(dates(body))
      # Names and addresses are read off the page as it came: prising labels
      # off their values splits a postcode down the middle.
      fields.merge!(name(text.to_s))
      fields.merge!(where(text.to_s))

      # "Class" is set in small letters on the card and comes back as "cass",
      # "clss", "Cass" as often as itself.
      klass = body.match(/\bc[lia]{0,2}ss\s*([1-7])\b/i)
      fields["categories"] = "Class #{klass[1]}" if klass

      fields = fields.compact_blank
      # A date on its own could be anything. A licence number, or a name with a
      # date beside it, is a licence.
      return nil unless fields["licence_number"] || (fields["full_name"] && fields["expires_on"])

      { fields: fields, verified: [], format: "Canadian licence" }
    end

    # OCR runs a label into its value — "Exp07 OCT 2029", "iss25 SEP 2024" —
    # and every pattern here wants them apart.
    def spaced(text)
      text.to_s.gsub(/([A-Za-z])(\d)/, '\1 \2').gsub(/(\d)([A-Za-z])/, '\1 \2')
    end

    # Three dates on the card and the labels are the least reliable thing on
    # it, so the labels are used where they survived and the order of the dates
    # where they did not: nobody is born after their licence was issued.
    def dates(body)
      found = body.scan(DATE).filter_map { |day, month, year| iso(day, month, year) }.uniq.sort
      return {} if found.empty?

      labelled = {
        "expires_on" => labelled_date(body, /EXP/i),
        "issued_on" => labelled_date(body, /ISS/i),
        "date_of_birth" => labelled_date(body, /DOB|BIRTH/i)
      }.compact

      spare = found - labelled.values
      labelled["date_of_birth"] ||= spare.shift
      labelled["expires_on"] ||= spare.pop
      labelled["issued_on"] ||= spare.pop

      labelled.compact
    end

    def labelled_date(body, label)
      match = body.match(/#{label}[^A-Za-z0-9]{0,4}#{DATE.source}/i)
      return nil if match.nil?

      iso(match[1], match[2], match[3])
    end

    def iso(day, month, year)
      number = day.to_s.upcase.chars.map { |char| AS_DIGIT.fetch(char, char) }.join
      return nil unless number.match?(/\A\d{1,2}\z/)

      Date.new(year.to_i, MONTHS.index(month.upcase) + 1, number.to_i).iso8601
    rescue Date::Error, TypeError
      nil
    end

    # The surname is printed in capitals with the given names under it.
    #
    # The line is judged as it was read, not with the digits stripped out of
    # it: "00807 OCT 1985" reduced to letters is "OCT", which looks exactly
    # like a short surname and is not one.
    def name(body)
      lines = body.split("\n").map { |line| line.strip.squeeze(" ") }
      index = lines.index { |line| line.match?(SURNAME_LINE) && !line.match?(NOT_A_NAME) }
      return {} if index.nil?

      surname = lines[index]
      given = lines[index + 1].to_s
      given = "" unless given.match?(GIVEN_LINE)

      { "surname" => surname, "given_names" => given.presence,
        "full_name" => [ given, surname ].compact_blank.join(" ") }
    end

    # The line with the postcode on it is the town, and the line above it is
    # the street.
    #
    # A postcode is three characters of small print alternating letters and
    # digits, which is the hardest thing on the card to read — "T6W" comes back
    # as "ce". So the province is the anchor when the postcode is not: two
    # capitals that name a province, on the line under a street address.
    def where(body)
      lines = body.split("\n").map(&:strip)
      town = lines.index { |line| line.match?(POSTCODE) && line.match?(PROVINCE) } ||
             lines.index { |line| line.match?(PROVINCE) && street?(lines[lines.index(line) - 1]) }
      return {} if town.nil?

      street = street?(lines[town - 1]) ? lines[town - 1] : ""

      { "address" => [ street, lines[town] ].compact_blank.join("\n"),
        "authority" => PROVINCES[lines[town][PROVINCE, 1]] }
    end

    def street?(line) = line.to_s.match?(STREET)
  end
end
