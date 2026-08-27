require "rails_helper"

# What tesseract actually hands back for a photograph of a card, rather than
# what a licence looks like when it is typed out.
#
# Every text here is a real failure the reader had: columns read across instead
# of down, a space where the card prints one, a letter where a digit belongs,
# and a stray character picked off the border.
RSpec.describe DocumentExtractors::DrivingLicence do
  # MORGA-7-53-11-6: decade 7, month 53 (over fifty, so female, month 3),
  # day 11, year digit 6 — the eleventh of March 1976.
  let(:number) { "MORGA753116SM9IJ" }

  def parse(text) = described_class.parse(text)

  describe "the licence number" do
    it "reads it when the card is read cleanly" do
      expect(parse("5. #{number}")[:fields]["licence_number"]).to eq(number)
    end

    # The card prints the number in groups, and OCR keeps the gaps.
    it "reads it through the spaces the card prints" do
      expect(parse("5. MORGA 753116 SM9IJ")[:fields]["licence_number"]).to eq(number)
    end

    # The six date characters can only be digits, so a letter among them is a
    # misread and not a different number.
    it "puts back digits that were read as letters" do
      expect(parse("5. MORGA7S3II6SM9IJ")[:fields]["licence_number"]).to eq(number)
    end

    # The failure that sent an empty licence number to the form: the card's
    # border was read as a seventeenth character, and a pattern anchored on
    # word boundaries then matched nothing at all.
    it "finds it with a stray character hanging off the end" do
      expect(parse("5. #{number}T")[:fields]["licence_number"]).to eq(number)
    end

    it "offers nothing rather than a number of the wrong shape" do
      expect(parse("5. NOTALICENCE1234")&.dig(:fields, "licence_number")).to be_nil
    end
  end

  describe "the numbered fields" do
    it "reads them one to a line" do
      fields = parse(<<~TEXT)[:fields]
        1. MORGAN
        2. SARAH MEREDYTH
        3. 11.03.1976 UNITED KINGDOM
        4a. 19.01.2013
        4b. 18.01.2029
      TEXT

      expect(fields).to include(
        "surname" => "MORGAN", "given_names" => "SARAH MEREDYTH",
        "date_of_birth" => "1976-03-11", "issued_on" => "2013-01-19",
        "expires_on" => "2029-01-18"
      )
    end

    # The card is in columns and OCR reads across them as often as down, so a
    # field ends where the next number begins rather than at a line break.
    it "reads them with the columns run together" do
      fields = parse(<<~TEXT)[:fields]
        1. MORGAN 4a. 19.01.2013
        2. SARAH MEREDYTH 4b. 18.01.2029
        3. 11.03.1976 UNITED KINGDOM 4c. DVLA
      TEXT

      expect(fields).to include(
        "surname" => "MORGAN", "given_names" => "SARAH MEREDYTH",
        "date_of_birth" => "1976-03-11", "expires_on" => "2029-01-18"
      )
    end

    it "builds the name the form asks for out of the two the card prints" do
      expect(parse("1. MORGAN\n2. SARAH MEREDYTH")[:fields]["full_name"])
        .to eq("SARAH MEREDYTH MORGAN")
    end
  end

  # The card carries no check digit. The only thing that can confirm a field is
  # the number agreeing with what is printed beside it.
  describe "what it will vouch for" do
    it "confirms a date the card prints and the number agrees with" do
      result = parse("1. MORGAN\n2. SARAH ANN\n3. 11.03.1976\n5. #{number}")

      expect(result[:verified]).to include("date_of_birth", "surname", "licence_number")
    end

    it "refuses to confirm a date only the number knows" do
      result = parse("1. MORGAN\n5. #{number}")

      expect(result[:fields]["date_of_birth"]).to eq("1976-03-11")
      expect(result[:verified]).not_to include("date_of_birth")
    end

    it "refuses to confirm a date the two disagree about" do
      result = parse("1. MORGAN\n3. 12.03.1976\n5. #{number}")

      expect(result[:verified]).not_to include("date_of_birth", "licence_number")
    end

    it "confirms a surname the number spells the same way" do
      expect(parse("1. MORGAN\n5. #{number}")[:verified]).to include("surname")
    end

    it "will not confirm a surname the number disagrees with" do
      expect(parse("1. PATEL\n5. #{number}")[:verified]).not_to include("surname")
    end
  end

  it "offers nothing at all rather than guessing at a page it cannot read" do
    expect(parse("SPECIMEN\nsome unrelated words")).to be_nil
  end
end
