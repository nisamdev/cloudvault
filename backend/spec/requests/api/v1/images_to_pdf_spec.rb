require "rails_helper"
require "combine_pdf"
require "vips"

RSpec.describe "Api::V1::Utilities images_to_pdf" do
  let(:user) { create(:user) }
  let!(:family) { create(:family, owner: user) }

  # Real images, so Prawn is embedding real pixels and the page sizes are
  # measured rather than assumed.
  def image(width:, height:, format: ".jpg", name: nil)
    bytes = Vips::Image.black(width, height).add(200).cast(:uchar)
                       .colourspace("srgb")
                       .write_to_buffer(format)

    Rack::Test::UploadedFile.new(
      StringIO.new(bytes),
      format == ".png" ? "image/png" : "image/jpeg",
      original_filename: name || "page#{format}"
    )
  end

  def build(pages, as: user, **extra)
    post "/api/v1/utilities/images_to_pdf",
         params: { pages: Array(pages), **extra },
         headers: auth_headers_for(as)
  end

  def pages_of(file)
    CombinePDF.parse(file.attachment.download).pages
  end

  it "makes one page per image, in the order they were sent" do
    build([ image(width: 400, height: 600), image(width: 400, height: 600) ])

    expect(response).to have_http_status(:created)
    stored = StoredFile.find(json["file"]["id"])
    expect(stored.mime_type).to eq("application/pdf")
    expect(pages_of(stored).size).to eq(2)
  end

  it "gives an auto-sized page the shape of its own image" do
    build([ image(width: 1500, height: 750) ], page_size: "auto", margin: "none")

    page = pages_of(StoredFile.find(json["file"]["id"])).first
    width = page[:MediaBox][2] - page[:MediaBox][0]
    height = page[:MediaBox][3] - page[:MediaBox][1]

    # 150dpi: 1500px is ten inches, which is 720 points.
    expect(width).to be_within(1).of(720)
    expect(height).to be_within(1).of(360)
  end

  it "puts a fixed size on the page when one is asked for" do
    build([ image(width: 1500, height: 750) ], page_size: "a4", orientation: "portrait")

    page = pages_of(StoredFile.find(json["file"]["id"])).first
    width = page[:MediaBox][2] - page[:MediaBox][0]

    expect(width).to be_within(1).of(595) # A4 portrait, in points
  end

  it "names the file after what the caller typed, without doubling the extension" do
    build([ image(width: 200, height: 200) ], name: "Passport.pdf")

    expect(json["file"]["name"]).to eq("Passport.pdf")
  end

  it "falls back to a dated name when none is given" do
    build([ image(width: 200, height: 200) ])

    expect(json["file"]["name"]).to match(/\AScan .+\.pdf\z/)
  end

  it "refuses a file that is not an image, naming the one at fault" do
    not_an_image = Rack::Test::UploadedFile.new(
      StringIO.new("this is not a picture"), "image/jpeg", original_filename: "notes.jpg"
    )

    build([ image(width: 200, height: 200), not_an_image ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]["message"]).to include("notes.jpg")
  end

  it "refuses an empty request" do
    build([])

    expect(response).to have_http_status(:bad_request)
  end

  it "refuses more pages than it will build, before reading any of them" do
    page = image(width: 100, height: 100)
    expect_any_instance_of(ImagePdfBuilder).not_to receive(:call)

    build(Array.new(ImagePdfBuilder::MAX_PAGES + 1) { page })

    expect(response).to have_http_status(:content_too_large)
  end

  it "saves privately by default" do
    build([ image(width: 200, height: 200) ])

    expect(StoredFile.find(json["file"]["id"]).visibility).to eq("private")
  end

  it "shares with the family when asked" do
    build([ image(width: 200, height: 200) ], visibility: "family")

    expect(StoredFile.find(json["file"]["id"]).visibility).to eq("family")
  end

  it "will not share with a family the caller cannot add to" do
    outsider = create(:user)

    build([ image(width: 200, height: 200) ], as: outsider, visibility: "family")

    expect(response).to have_http_status(:forbidden)
  end

  it "needs a signed-in caller" do
    post "/api/v1/utilities/images_to_pdf", params: { pages: [ image(width: 200, height: 200) ] }

    expect(response).to have_http_status(:unauthorized)
  end
end
