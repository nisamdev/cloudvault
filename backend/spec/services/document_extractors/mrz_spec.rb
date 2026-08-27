require "rails_helper"

RSpec.describe DocumentExtractors::Mrz do
  # The specimen zone from ICAO Doc 9303, check digits and all.
  let(:passport) do
    <<~MRZ
      P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
      L898902C36UTO7408122F1204159ZE184226B<<<<<10
    MRZ
  end

  describe "a passport" do
    subject(:result) { described_class.parse(passport) }

    it "reads the name, split the way the document splits it" do
      expect(result[:fields]).to include(
        "surname" => "Eriksson",
        "given_names" => "Anna Maria",
        "full_name" => "Anna Maria Eriksson"
      )
    end

    it "reads the number, country and sex" do
      expect(result[:fields]).to include(
        "document_number" => "L898902C3",
        "country" => "UTO",
        "sex" => "Female"
      )
    end

    # The century is not in the zone; a birth is behind us, an expiry ahead.
    it "puts the dates in the right century" do
      expect(result[:fields]).to include(
        "date_of_birth" => "1974-08-12",
        "expires_on" => "2012-04-15"
      )
    end

    # The whole reason this beats guessing: the document says whether we read it
    # correctly.
    it "confirms what the check digits agree with" do
      expect(result[:verified]).to include("document_number", "date_of_birth", "expires_on")
      expect(result[:format]).to eq("TD3")
    end

    it "notices when a digit has been misread" do
      broken = passport.sub("L898902C36", "L898902C37")

      expect(described_class.parse(broken)[:verified]).not_to include("document_number")
    end
  end

  describe "a residence permit or ID card" do
    # TD1: three lines of thirty.
    let(:card) do
      <<~MRZ
        I<UTOD231458907<<<<<<<<<<<<<<<
        7408122F1204159UTO<<<<<<<<<<<6
        ERIKSSON<<ANNA<MARIA<<<<<<<<<<
      MRZ
    end

    it "reads it in the card shape too" do
      result = described_class.parse(card)

      expect(result[:format]).to eq("TD1")
      expect(result[:fields]).to include(
        "document_number" => "D23145890",
        "full_name" => "Anna Maria Eriksson",
        "date_of_birth" => "1974-08-12",
        "expires_on" => "2012-04-15"
      )
    end
  end

  describe "reading a scan rather than a file" do
    # OCR puts the page's other text around the zone and mangles the glyphs it
    # only ever sees inside it.
    it "finds the zone among everything else on the page" do
      page = <<~TEXT
        UNITED KINGDOM OF SOMEWHERE
        PASSPORT / PASSEPORT
        Surname / Nom
        ERIKSSON
        #{passport}
        Issuing authority
      TEXT

      expect(described_class.parse(page)[:fields]["document_number"]).to eq("L898902C3")
    end

    it "reads letters that OCR turned into digits inside a date" do
      # O for 0 in the expiry — a shape tesseract confuses constantly.
      misread = passport.sub("1204159", "12O4159")

      expect(described_class.parse(misread)[:fields]["expires_on"]).to eq("2012-04-15")
    end

    it "copes with the zone arriving in lower case" do
      expect(described_class.parse(passport.downcase)[:fields]["document_number"])
        .to eq("L898902C3")
    end
  end

  describe "when there is no zone" do
    it "says so rather than inventing one" do
      expect(described_class.parse("A birth certificate, with no machine zone")).to be_nil
      expect(described_class.parse("")).to be_nil
      expect(described_class.parse(nil)).to be_nil
    end

    it "is not fooled by a long line of ordinary text" do
      expect(described_class.parse("THIS IS A VERY LONG LINE OF PLAIN WORDS ON A CERTIFICATE"))
        .to be_nil
    end
  end
end
