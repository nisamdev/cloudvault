require "rails_helper"
require "combine_pdf"
require "vips"

RSpec.describe "Api::V1::Files pages" do
  let(:user) { create(:user) }
  let!(:family) { create(:family, owner: user) }

  # Each page says which page it is, so the order after a rearrange can be read
  # back off the rendered result rather than taken on trust.
  def pdf(pages: 4, name: "Statements.pdf", owner: user)
    doc = Prawn::Document.new(skip_page_creation: true)
    pages.times { |i| doc.start_new_page; doc.text "PAGE #{i + 1}", size: 60 }

    file = create(:stored_file, user: owner, name: name, mime_type: "application/pdf", file_type: "file")
    file.attachment.attach(io: StringIO.new(doc.render), filename: name, content_type: "application/pdf")
    file
  end

  def rearrange(file, layout, as: user)
    patch "/api/v1/files/#{file.id}/pages",
          params: { pages: layout }, headers: auth_headers_for(as), as: :json
  end

  def order_of(file)
    # The bytes of a rendered page identify it, since each page differs.
    CombinePDF.parse(file.attachment.download).pages.size
  end

  def shapes(file)
    PdfPageRenderer.new(file.attachment.download).pages(limit: 10)
                   .map { |p| p[:width] > p[:height] ? :landscape : :portrait }
  end

  describe "GET /api/v1/files/:id/pages" do
    it "renders the pages for the signing editor" do
      get "/api/v1/files/#{pdf.id}/pages", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(json["page_count"]).to eq(4)
      expect(json["pages"].first["image"]).to start_with("data:image/png;base64,")
    end

    it "renders smaller ones when the caller asks for thumbnails" do
      file = pdf

      get "/api/v1/files/#{file.id}/pages", params: { size: "thumb" }, headers: auth_headers_for(user)
      thumb = json["pages"].first["width"]

      get "/api/v1/files/#{file.id}/pages", headers: auth_headers_for(user)
      full = json["pages"].first["width"]

      expect(thumb).to be < full
    end

    # A long document is fetched a screenful at a time rather than in one
    # response big enough to stall the tab.
    it "starts where the caller asks it to" do
      get "/api/v1/files/#{pdf.id}/pages", params: { size: "thumb", from: 3 },
          headers: auth_headers_for(user)

      expect(json["pages"].map { |p| p["number"] }).to eq([ 3, 4 ])
      expect(json["page_count"]).to eq(4)
    end
  end

  describe "PATCH /api/v1/files/:id/pages" do
    it "puts the pages in the order it was given" do
      file = pdf(pages: 3)
      before = PdfPageRenderer.new(file.attachment.download).pages(limit: 3).map { |p| p[:png] }

      rearrange(file, [ { number: 3 }, { number: 1 }, { number: 2 } ])

      expect(response).to have_http_status(:ok)
      after = PdfPageRenderer.new(file.reload.attachment.download).pages(limit: 3).map { |p| p[:png] }
      expect(after).to eq([ before[2], before[0], before[1] ])
    end

    it "drops the pages left out of the layout" do
      file = pdf(pages: 4)

      rearrange(file, [ { number: 2 }, { number: 4 } ])

      expect(order_of(file.reload)).to eq(2)
    end

    it "turns a page that was scanned sideways" do
      file = pdf(pages: 2)

      rearrange(file, [ { number: 1, rotation: 90 }, { number: 2, rotation: 0 } ])

      expect(shapes(file.reload)).to eq(%i[landscape portrait])
    end

    # The backlog is explicit that page edits must keep the original.
    it "keeps the document it started from as a version" do
      file = pdf(pages: 3)

      expect { rearrange(file, [ { number: 1 } ]) }
        .to change { file.reload.version_number }.from(1).to(2)

      original = file.file_versions.newest_first.first
      expect(CombinePDF.parse(original.attachment.download).pages.size).to eq(3)
    end

    it "refuses to spend a version on a document that has not changed" do
      file = pdf(pages: 3)

      rearrange(file, [ { number: 1 }, { number: 2 }, { number: 3 } ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("no_changes")
      expect(file.reload.version_number).to eq(1)
    end

    it "refuses an empty document" do
      file = pdf(pages: 2)

      rearrange(file, [])

      expect(response).to have_http_status(:unprocessable_content)
      expect(file.reload.version_number).to eq(1)
    end

    it "refuses a page the document does not have" do
      file = pdf(pages: 2)

      rearrange(file, [ { number: 9 } ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["message"]).to include("no page 9")
    end

    it "refuses the same page twice, rather than quietly rotating both copies" do
      file = pdf(pages: 2)

      rearrange(file, [ { number: 1 }, { number: 1, rotation: 90 } ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["message"]).to include("once")
    end

    it "refuses a file that is not a PDF" do
      image = create(:stored_file, :image, user: user, name: "Photo.png")

      rearrange(image, [ { number: 1 } ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("not_a_pdf")
    end

    it "refuses somebody who cannot edit the file" do
      file = pdf
      stranger = create(:user)

      rearrange(file, [ { number: 1 } ], as: stranger)

      expect(response).to have_http_status(:not_found)
      expect(file.reload.version_number).to eq(1)
    end
  end

  describe "POST /api/v1/files/:id/split" do
    def split(file, from:, to:, as: user)
      post "/api/v1/files/#{file.id}/split",
           params: { from: from, to: to }, headers: auth_headers_for(as), as: :json
    end

    it "writes the range out as a document of its own" do
      file = pdf(pages: 6)

      split(file, from: 2, to: 4)

      expect(response).to have_http_status(:created)
      piece = StoredFile.find(json["file"]["id"])
      expect(CombinePDF.parse(piece.attachment.download).pages.size).to eq(3)
    end

    # A year of statements is not edited by taking one out of it.
    it "leaves the document it came from untouched" do
      file = pdf(pages: 6)

      expect { split(file, from: 2, to: 4) }
        .not_to change { [ file.reload.version_number, order_of(file) ] }
    end

    it "names it after the pages it holds" do
      file = pdf(pages: 6, name: "Statements 2026.pdf")

      split(file, from: 2, to: 4)
      expect(json["file"]["name"]).to eq("Statements 2026 (pages 2-4).pdf")

      split(file, from: 5, to: 5)
      expect(json["file"]["name"]).to eq("Statements 2026 (page 5).pdf")
    end

    it "lands beside the document it came from" do
      folder = create(:folder, user: user)
      file = pdf(pages: 3)
      file.update!(folder: folder)

      split(file, from: 1, to: 2)

      expect(json["file"]["folder"]["id"]).to eq(folder.id)
    end

    it "refuses a range that runs off the end" do
      split(pdf(pages: 3), from: 2, to: 9)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["message"]).to include("no page 4")
    end

    it "refuses a range that ends before it starts" do
      split(pdf(pages: 3), from: 3, to: 1)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("empty_range")
    end

    it "refuses somebody who cannot edit the file" do
      split(pdf(pages: 3), from: 1, to: 2, as: create(:user))

      expect(response).to have_http_status(:not_found)
    end
  end
end
