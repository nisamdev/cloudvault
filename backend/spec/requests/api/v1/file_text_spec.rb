require "rails_helper"
require "vips"

RSpec.describe "Api::V1::Files text" do
  let(:user) { create(:user) }
  let!(:family) { create(:family, owner: user) }

  def stored(bytes, name: "Policy.pdf", type: "application/pdf", owner: user)
    file = create(:stored_file, user: owner, name: name, mime_type: type,
                                file_type: type.start_with?("image/") ? "image" : "file")
    file.attachment.attach(io: StringIO.new(bytes), filename: name, content_type: type)
    file
  end

  def written(&block)
    doc = Prawn::Document.new(page_size: "A4", margin: 40)
    doc.instance_eval(&block)
    doc.render
  end

  def get_text(file, as: user)
    get "/api/v1/files/#{file.id}/text", headers: auth_headers_for(as)
  end

  it "returns the text, the details and the tidied lines" do
    file = stored(written do
      text "CERTIFICATE OF INSURANCE"
      text "Policy Number: GB-8842-7731X"
      text "Annual premium: £482.60"
    end)

    get_text(file)

    expect(response).to have_http_status(:ok)
    expect(json["has_text"]).to be(true)
    expect(json["source"]).to eq("text_layer")
    expect(json["title"]).to eq("CERTIFICATE OF INSURANCE")
    expect(json["details"]).to include("label" => "Policy Number", "value" => "GB-8842-7731X")
    expect(json["found"]["amounts"]).to include("£482.60")
    expect(json["pages"].first["text"]).to include("Policy Number")
  end

  # The case that matters most here: a PDF made by photographing something has
  # no text layer. OCR may still find nothing on a blank page — the important
  # part is that the response stays a clean "no text", not a 500.
  it "says plainly when a document has no readable text" do
    allow(PdfOcr).to receive(:available?).and_return(false)

    photograph = Vips::Image.black(600, 800).add(210).cast(:uchar)
                            .colourspace("srgb").write_to_buffer(".jpg")
    scan = ImagePdfBuilder.new([ { name: "page.jpg", bytes: photograph, content_type: "image/jpeg" } ]).call

    get_text(stored(scan, name: "Scan.pdf"))

    expect(response).to have_http_status(:ok)
    expect(json["has_text"]).to be(false)
    expect(json["source"]).to eq("none")
    expect(json["details"]).to be_empty
  end

  it "falls back to OCR when the PDF has no text layer" do
    photograph = Vips::Image.black(600, 800).add(210).cast(:uchar)
                            .colourspace("srgb").write_to_buffer(".jpg")
    scan = ImagePdfBuilder.new([ { name: "page.jpg", bytes: photograph, content_type: "image/jpeg" } ]).call

    ocr_result = PdfOcr::Result.new(
      pages: [ { number: 1, text: "Policy Number: SCAN-99" } ],
      page_count: 1,
      truncated: false
    )
    allow_any_instance_of(PdfOcr).to receive(:call).and_return(ocr_result)

    get_text(stored(scan, name: "Scan.pdf"))

    expect(response).to have_http_status(:ok)
    expect(json["has_text"]).to be(true)
    expect(json["source"]).to eq("ocr")
    expect(json["pages"].first["text"]).to include("SCAN-99")
  end

  it "refuses a file that is not a PDF" do
    get_text(stored("not a pdf", name: "Photo.png", type: "image/png"))

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]["code"]).to eq("not_a_pdf")
  end

  it "does not read a document out to somebody who cannot see it" do
    file = stored(written { text "Policy Number: GB-8842" })

    get_text(file, as: create(:user))

    expect(response).to have_http_status(:not_found)
  end

  it "survives a damaged document rather than failing the request" do
    get_text(stored("%PDF-1.4 this is not really a pdf"))

    expect(response).to have_http_status(:ok)
    expect(json["has_text"]).to be(false)
  end
end
