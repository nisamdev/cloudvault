require "rails_helper"

RSpec.describe DocumentReader do
  let(:passport_text) do
    <<~TEXT
      UNITED KINGDOM OF SOMEWHERE
      PASSPORT
      P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
      L898902C36UTO7408122F1204159ZE184226B<<<<<10
    TEXT
  end

  describe "a passport" do
    subject(:result) { described_class.new(passport_text, "passport").call.to_h }

    # A passport is a document in its own right, with its own expiry and its
    # own scan. It is not a column on the person who holds it.
    it "fills a passport record" do
      expect(result[:record_type]).to eq("passport")
      expect(result[:fields]).to eq(
        "full_name" => "Anna Maria Eriksson",
        "date_of_birth" => "1974-08-12",
        "passport_number" => "L898902C3",
        "expires_on" => "2012-04-15",
        "nationality" => "UTO",
        "sex" => "Female"
      )
    end

    # Whose it is and what it is. Named after the person alone, somebody's four
    # documents would be four rows with the same name on them.
    it "names the record for whose it is and what it is" do
      expect(result[:title]).to eq("Anna Maria Eriksson — Passport")
    end

    # The screen shows these differently: a value the document vouches for
    # deserves less squinting than one that was guessed at.
    it "says which fields the document itself confirms" do
      expect(result[:verified]).to contain_exactly(
        "passport_number", "date_of_birth", "expires_on"
      )
      expect(result[:read_as]).to eq("TD3")
    end
  end

  describe "the same document filed as a permit" do
    it "maps the very same zone onto immigration fields instead" do
      result = described_class.new(passport_text, "residence_permit").call.to_h

      expect(result[:record_type]).to eq("immigration")
      expect(result[:fields]).to include(
        "document_number" => "L898902C3",
        "expires_on" => "2012-04-15",
        "country" => "UTO",
        "holder" => "Anna Maria Eriksson"
      )
    end
  end

  describe "a driving licence" do
    let(:text) do
      <<~TEXT
        DRIVING LICENCE
        1. MORGAN
        2. SARAH ANN
        4a. 19.03.2019
        4b. 18.03.2029
        5. MORGA657054SM9IJ
      TEXT
    end

    it "fills a driving licence record" do
      result = described_class.new(text, "driving_licence").call.to_h

      expect(result[:record_type]).to eq("driving_licence")
      expect(result[:fields]).to include(
        "full_name" => "SARAH ANN MORGAN",
        "licence_number" => "MORGA657054SM9IJ",
        "issued_on" => "2019-03-19",
        "expires_on" => "2029-03-18"
      )
    end

    # The number encodes the birth date, so the card carries its own second
    # opinion about it.
    it "takes the date of birth out of the number itself" do
      result = described_class.new(text, "driving_licence").call.to_h

      # MORGA-6-57-05-4: decade 6, month 57 (over fifty, so female, month 7),
      # day 05, year digit 4 — the fifth of July 1964.
      expect(result[:fields]["date_of_birth"]).to eq("1964-07-05")
    end

    # The card does not print a check digit, so "confirmed" can only mean two
    # parts of it agreeing. This one prints no date of birth at all, so the
    # number is the sole source and nothing about it is confirmed.
    it "will not vouch for a date only the number knows" do
      result = described_class.new(text, "driving_licence").call.to_h

      expect(result[:verified]).not_to include("date_of_birth")
    end

    it "vouches for the date when the card prints it too" do
      printed = text.sub("2. SARAH ANN", "2. SARAH ANN\n3. 05.07.1964")
      result = described_class.new(printed, "driving_licence").call.to_h

      expect(result[:verified]).to include("date_of_birth", "licence_number")
    end
  end

  describe "a health card" do
    it "accepts a number that passes its check digit" do
      result = described_class.new("NHS No 943 476 5919\nName: Anna Eriksson", "health_card").call.to_h

      expect(result[:fields]["nhs_number"]).to eq("943 476 5919")
      expect(result[:verified]).to include("nhs_number")
    end

    # Otherwise any ten digits on the card would be filed as somebody's health
    # number.
    it "ignores ten digits that are not one" do
      result = described_class.new("Reference 1234567890", "health_card").call

      expect(result.fields["nhs_number"]).to be_nil
    end
  end

  describe "anything else" do
    it "falls back to reading labelled lines" do
      text = "Certificate of Birth\nName: Thomas Reed\nDate of birth: 04/11/2016"
      result = described_class.new(text, "birth_certificate").call.to_h

      expect(result[:fields]["full_name"]).to eq("Thomas Reed")
      expect(result[:record_type]).to eq("birth_certificate")
    end

    # "Something else" is still a document; it just has no shelf of its own.
    it "reads a document it has no preset for without failing" do
      result = described_class.new("Some notes with no structure", "other").call.to_h

      expect(result[:record_type]).to eq("document")
      expect(result[:fields]).to eq({})
    end
  end

  it "offers nothing rather than guessing when the page is blank" do
    result = described_class.new("", "passport").call.to_h

    expect(result[:fields]).to eq({})
    expect(result[:verified]).to be_empty
  end
end
