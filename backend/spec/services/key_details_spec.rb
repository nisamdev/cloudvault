require "rails_helper"

RSpec.describe KeyDetails do
  def details_for(*page_texts)
    pages = page_texts.each_with_index.map { |text, i| { number: i + 1, text: text } }
    described_class.new(pages).call
  end

  describe "the details it picks out" do
    it "reads a label and its value off one line" do
      result = details_for("Policy Number: GB-8842-7731X\nPolicyholder: Aisha Rahman")

      expect(result[:details]).to include(
        { label: "Policy Number", value: "GB-8842-7731X" },
        { label: "Policyholder", value: "Aisha Rahman" }
      )
    end

    # Forms are laid out with dot leaders and columns as often as with colons.
    it "reads a label separated by dot leaders or a run of spaces" do
      result = details_for("Cover starts .......... 1 April 2026\nExcess       £250.00")

      expect(result[:details]).to include(
        { label: "Cover starts", value: "1 April 2026" },
        { label: "Excess", value: "£250.00" }
      )
    end

    it "takes the next line when the label has nothing after it" do
      result = details_for("Address:\n27 Bellwood Gardens, Leeds LS8 2QH")

      expect(result[:details]).to include(
        { label: "Address", value: "27 Bellwood Gardens, Leeds LS8 2QH" }
      )
    end

    it "does not pair two labels together" do
      result = details_for("Surname:\nGiven names:\nAisha")

      expect(result[:details].map { |d| d[:label] }).not_to include("Surname")
    end

    # A schedule says "Item" four times and means four things.
    it "keeps a repeated label when the value differs" do
      result = details_for("Item: Buildings\nSum insured: £350,000\nItem: Contents\nSum insured: £60,000")

      expect(result[:details]).to include(
        { label: "Item", value: "Buildings" },
        { label: "Item", value: "Contents" }
      )
    end

    it "does not turn ordinary prose into a detail" do
      result = details_for(
        "We wrote to you last month about your renewal: please read the enclosed schedule carefully."
      )

      expect(result[:details]).to be_empty
    end

    it "picks a passport number out of OCR noise under Passport No." do
      result = details_for(<<~TEXT)
        Type / Country Code / Passport No.
        ss T9622490
        Surname
        IHAAN ADAM
      TEXT

      expect(result[:details]).to include(label: "Passport No.", value: "T9622490")
    end

    it "prefers the MRZ lettered number over digit-only OCR under Passport No." do
      result = details_for(<<~TEXT)
        Type / Country Code / Passport No.
        ss 79622490
        Surname
        IHAAN ADAM
        P<IND<<IHAAN<ADAM<<<<<<<<<<<<<<<<<<<<<<<
        T9622490<31ND1812224M2410306<<<<<<<<<<<<<<<6
      TEXT

      expect(result[:details]).to include(label: "Passport No.", value: "T9622490")
      expect(result[:details].map { |d| d[:value] }).not_to include("79622490")
    end

    it "reads a passport number from the machine-readable zone" do
      result = details_for(<<~TEXT)
        P<IND<<IHAAN<ADAM<<<<<<<<<<<<<<<<<<<<<<<
        T9622490<31ND1812224M2410306<<<<<<<<<<<<<<<6
      TEXT

      expect(result[:details]).to include(label: "Passport No.", value: "T9622490")
    end
  end

  describe "the noise it throws away" do
    it "drops page numbers" do
      result = details_for("Real content here\n1 of 2", "More content\nPage 2")

      expect(result[:lines]).to eq([ "Real content here", "More content" ])
    end

    # Half a dropped paragraph reads worse than the whole of it.
    it "drops a boilerplate paragraph including the lines it wraps onto" do
      result = details_for(
        "Sum insured: £350,000\n" \
        "This document is issued subject to the policy terms\n" \
        "and conditions in force at the date of issue. It is not\n" \
        "proof of ownership.\n" \
        "Reference: NG-2026-004471"
      )

      expect(result[:lines]).to eq([ "Sum insured: £350,000", "Reference: NG-2026-004471" ])
    end

    it "drops the header that appears on every page" do
      header = "Northgate Insurance Ltd · Company No 4471"
      result = details_for(
        "#{header}\nPolicy Number: GB-1",
        "#{header}\nPolicy Number: GB-2",
        "#{header}\nPolicy Number: GB-3"
      )

      expect(result[:lines]).not_to include(header)
      expect(result[:lines].size).to eq(3)
    end

    # Two pages is not enough to tell a header from a coincidence.
    it "keeps a line repeated across only two pages" do
      result = details_for("Shared line\nOne", "Shared line\nTwo")

      expect(result[:lines]).to include("Shared line")
    end

    it "drops the debris extraction makes of rules and logos" do
      result = details_for("~~~~~~~~~~~~~~~~~~~~\nPolicy Number: GB-8842\n||| ... |||")

      expect(result[:lines]).to eq([ "Policy Number: GB-8842" ])
    end

    it "keeps a line that is mostly digits, which is usually a number that matters" do
      result = details_for("4471 8829 0021 5567")

      expect(result[:lines]).to include("4471 8829 0021 5567")
    end
  end

  describe "what it finds in the text" do
    let(:result) do
      details_for(
        "Date of Birth: 14/03/1986\nRenewed 1 April 2026\n" \
        "Premium £482.60 and excess £250.00\n" \
        "claims@northgate-insure.co.uk\n+44 113 496 2200\nReference NG-2026-004471"
      )
    end

    it "finds dates in the formats documents use" do
      expect(result[:found][:dates]).to include("14/03/1986", "1 April 2026")
    end

    it "finds amounts of money" do
      expect(result[:found][:amounts]).to include("£482.60", "£250.00")
    end

    it "finds an email address and a telephone number" do
      expect(result[:found][:emails]).to eq([ "claims@northgate-insure.co.uk" ])
      expect(result[:found][:phones].join).to include("113 496 2200")
    end

    it "finds the reference nobody can remember" do
      expect(result[:found][:references]).to include("NG-2026-004471")
    end
  end

  it "calls the document what the document calls itself" do
    result = details_for("CERTIFICATE OF INSURANCE\nPolicy Number: GB-8842")

    expect(result[:title]).to eq("CERTIFICATE OF INSURANCE")
  end

  it "has nothing to say about an empty document rather than failing" do
    result = details_for("")

    expect(result[:details]).to be_empty
    expect(result[:lines]).to be_empty
    expect(result[:title]).to be_nil
  end
end
