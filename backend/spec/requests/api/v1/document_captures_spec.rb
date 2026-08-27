require "rails_helper"
require "vips"

RSpec.describe "Api::V1::DocumentCaptures" do
  let(:user) { create(:user) }
  let!(:family) { create(:family, owner: user) }

  # A photographed page: a picture of text, with no text layer behind it.
  def photographed(lines)
    markup = lines.gsub("&", "&amp;").gsub("<", "&lt;")
    text = Vips::Image.text(markup, dpi: 200, font: "mono")
    page = text.invert.embed(70, 70, text.width + 140, text.height + 140, extend: :white)

    Rack::Test::UploadedFile.new(
      StringIO.new(page.colourspace("srgb").write_to_buffer(".jpg", Q: 92)),
      "image/jpeg", original_filename: "page.jpg"
    )
  end

  let(:passport_page) do
    photographed(
      "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n" \
      "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
    )
  end

  # Not Array(): an UploadedFile delegates to its tempfile, so Array() reads the
  # JPEG into a list of lines instead of wrapping the file.
  def capture(pages, preset: "passport", **extra)
    list = pages.is_a?(Array) ? pages : [ pages ]

    post "/api/v1/document_captures",
         params: { pages: list, preset: preset, **extra },
         headers: auth_headers_for(user)
  end

  describe "GET presets" do
    it "lists what can be scanned, and whether reading is possible at all" do
      get "/api/v1/document_captures/presets", headers: auth_headers_for(user)

      expect(json["presets"].map { |p| p["key"] })
        .to include("passport", "driving_licence", "birth_certificate", "health_card", "other")
      expect(json).to have_key("ocr_available")
    end
  end

  describe "scanning a passport" do
    it "reads the page and offers the fields to check" do
      capture(passport_page)

      expect(response).to have_http_status(:created)
      expect(json["record_type"]).to eq("person")
      expect(json["title"]).to eq("Anna Maria Eriksson")
      expect(json["fields"]).to include(
        "passport_number" => "L898902C3",
        "date_of_birth" => "1974-08-12",
        "passport_expires_on" => "2012-04-15"
      )
    end

    # The document's own check digits, which is why this beats guessing.
    it "says which fields the document vouches for" do
      capture(passport_page)

      expect(json["verified"]).to include("passport_number", "date_of_birth")
      expect(json["read_as"]).to eq("TD3")
    end

    # What gets kept is the thing that was read, and it is a PDF because that is
    # what you would send to somebody.
    it "keeps the scan as a PDF, ready to attach" do
      expect { capture(passport_page) }.to change(StoredFile, :count).by(1)

      stored = StoredFile.find(json.dig("file", "id"))
      expect(stored.mime_type).to eq("application/pdf")
      expect(stored.name).to include("Passport")
    end

    # It suggests; it does not file.
    it "creates no record of its own" do
      expect { capture(passport_page) }.not_to change(VaultRecord, :count)
    end
  end

  describe "what it refuses" do
    it "will not guess what kind of document it is" do
      capture(passport_page, preset: "a made up kind")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("unknown_preset")
    end

    it "asks for something to read" do
      capture([])

      expect(response).to have_http_status(:bad_request)
    end

    it "needs somebody signed in" do
      post "/api/v1/document_captures", params: { pages: [ passport_page ], preset: "passport" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "reading a PDF already in the vault" do
    it "reads it without storing a second copy" do
      file = create(:stored_file, user: user, name: "Passport.pdf", mime_type: "application/pdf")
      doc = Prawn::Document.new
      doc.text "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
      doc.text "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
      file.attachment.attach(io: StringIO.new(doc.render), filename: "Passport.pdf",
                             content_type: "application/pdf")

      expect {
        post "/api/v1/document_captures", params: { file_id: file.id, preset: "passport" },
             headers: auth_headers_for(user)
      }.not_to change(StoredFile, :count)

      expect(json["fields"]["passport_number"]).to eq("L898902C3")
    end

    it "will not read somebody else's file" do
      other = create(:stored_file, user: create(:user), mime_type: "application/pdf")

      post "/api/v1/document_captures", params: { file_id: other.id, preset: "passport" },
           headers: auth_headers_for(user)

      expect(response).to have_http_status(:not_found)
    end
  end
end
