require "rails_helper"

# Written against a real Alberta licence photographed on a table, cropped in
# the browser and read. Every text below is something tesseract actually
# produced from it — including the mistakes, which are the point: the card is
# small print on a laminated surface and no reading of it is clean.
RSpec.describe DocumentExtractors::CanadianLicence do
  def parse(text) = described_class.parse(text)

  let(:as_read) do
    <<~TEXT
      Moen DRIVER'S LICENCE g&
      = 7. 1786 11- 770 cass 5

      Cond/End A
      exp 07 OCT 2029

      KALAMPULAN
      Nisamudheen

      3305 Kulay Way S
      Edmonton AB ce 5E7

      007 OCT 1985
      sexM tyesBIK Haw BIk
      iss25 SEP 2024
    TEXT
  end

  it "reads a real photographed card" do
    fields = parse(as_read)[:fields]

    expect(fields).to include(
      "full_name" => "Nisamudheen KALAMPULAN",
      "licence_number" => "178611-770",
      "date_of_birth" => "1985-10-07",
      "issued_on" => "2024-09-25",
      "expires_on" => "2029-10-07",
      "categories" => "Class 5",
      "authority" => "Alberta"
    )
  end

  # The card's kerning invites OCR to break the number up.
  it "closes up a number split across spaces" do
    expect(parse("no 1786 11- 770\nKALAMPULAN\nexp 07 OCT 2029")[:fields]["licence_number"])
      .to eq("178611-770")
  end

  it "finds the number when the dash itself was lost" do
    expect(parse("no 176611770\nKALAMPULAN\nexp 07 OCT 2029")[:fields]["licence_number"])
      .to eq("176611-770")
  end

  # A postcode alternates letters and digits in the smallest type on the card,
  # and is the first thing to go.
  it "finds the address by its province when the postcode is unreadable" do
    fields = parse(as_read)[:fields]

    expect(fields["address"]).to eq("3305 Kulay Way S\nEdmonton AB ce 5E7")
    expect(fields["authority"]).to eq("Alberta")
  end

  describe "the three dates" do
    # The labels are small and the dates are not, so the order of the dates is
    # the more reliable of the two: nobody is born after their licence issued.
    it "sorts them out when every label was misread" do
      fields = parse("no 176611-770\nKALAMPULAN\n007 OCT 1985\n%%% 25 SEP 2024\n### 07 OCT 2029")[:fields]

      expect(fields).to include(
        "date_of_birth" => "1985-10-07", "issued_on" => "2024-09-25", "expires_on" => "2029-10-07"
      )
    end

    # "DOB" comes back as digits and glues itself to the date behind it.
    it "reads a date with the label run into it" do
      expect(parse("no 176611-770\nKALAMPULAN\n00807 OCT 1985")[:fields]["date_of_birth"])
        .to eq("1985-10-07")
    end
  end

  describe "the name" do
    it "takes the capitalised line under the surname as the given names" do
      fields = parse("no 176611-770\nKALAMPULAN\nNisamudheen\nexp 07 OCT 2029")[:fields]

      expect(fields).to include("surname" => "KALAMPULAN", "given_names" => "Nisamudheen")
    end

    # The failure that put "SexM eyesBIK Hav BIK OCT" in the name box: with the
    # digits stripped out, "00807 OCT 1985" looks exactly like a short surname.
    it "does not mistake a date or a label for a name" do
      fields = parse("no 176611-770\nexp 07 OCT 2029\n00807 OCT 1985\nSexM eyesBIK Hav BIK")[:fields]

      expect(fields["full_name"]).to be_nil
    end
  end

  it "vouches for nothing, because nothing on the card checks anything else" do
    expect(parse(as_read)[:verified]).to be_empty
  end

  it "leaves a page that is not a licence alone" do
    expect(parse("A receipt for some shopping\nTotal 24.99")).to be_nil
  end

  # A UK licence must not be swallowed by the reader that comes after it.
  it "does not claim a UK licence" do
    expect(parse("1. MORGAN\n2. SARAH ANN\n5. MORGA753116SM9IJ")).to be_nil
  end
end
