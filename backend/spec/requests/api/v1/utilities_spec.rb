require "rails_helper"
require "combine_pdf"
require "vips"

RSpec.describe "Api::V1::Utilities" do
  let(:user) { create(:user) }
  let!(:family) { create(:family, owner: user) }
  let(:stranger) { create(:user) }

  # Real PDFs, so the merge is doing real work rather than moving bytes around.
  def pdf(pages:, name:, owner: user, **attrs)
    doc = Prawn::Document.new(skip_page_creation: true)
    pages.times { |i| doc.start_new_page; doc.text "Page #{i + 1} of #{name}" }

    file = create(:stored_file, user: owner, name: name, mime_type: "application/pdf",
                                file_type: "file", **attrs)
    file.attachment.attach(io: StringIO.new(doc.render), filename: name, content_type: "application/pdf")
    file
  end

  def merge(ids, as: user, **extra)
    post "/api/v1/utilities/merge", params: { file_ids: ids, **extra },
         headers: auth_headers_for(as), as: :json
  end

  describe "POST /api/v1/utilities/merge" do
    it "joins them into one document" do
      first = pdf(pages: 2, name: "Passport front.pdf")
      second = pdf(pages: 3, name: "Passport back.pdf")

      merge([ first.id, second.id ])

      expect(response).to have_http_status(:created)
      merged = StoredFile.find(json["file"]["id"])
      expect(CombinePDF.parse(merged.attachment.download).pages.size).to eq(5)
    end

    # The order is the point: page 2 of a passport after page 1. Compared by
    # rendering, since that is what the person opening it will see.
    it "keeps the order the caller asked for" do
      first = pdf(pages: 1, name: "One.pdf")
      second = pdf(pages: 1, name: "Two.pdf")

      merge([ second.id, first.id ])

      merged = StoredFile.find(json["file"]["id"])
      rendered = PdfPageRenderer.new(merged.attachment.download).pages(limit: 2)
      expected_first = PdfPageRenderer.new(second.attachment.download).pages(limit: 1).first

      expect(rendered.first[:bytes]).to eq(expected_first[:bytes])
    end

    it "leaves the originals alone" do
      first = pdf(pages: 1, name: "One.pdf")
      second = pdf(pages: 1, name: "Two.pdf")

      expect { merge([ first.id, second.id ]) }
        .not_to change { [ first.reload.name, second.reload.name, StoredFile.where(id: [ first.id, second.id ]).count ] }
    end

    it "names the result after the first document" do
      first = pdf(pages: 1, name: "Passport.pdf")
      second = pdf(pages: 1, name: "Licence.pdf")

      merge([ first.id, second.id ])

      expect(json["file"]["name"]).to eq("Passport (merged).pdf")
    end

    # "Passport (merged) (merged) (merged).pdf" says nothing the first one does
    # not, and merging a merge is a normal thing to do.
    it "does not stack the suffix when merging a merge" do
      first = pdf(pages: 1, name: "Passport (merged).pdf")
      second = pdf(pages: 1, name: "Licence.pdf")

      merge([ first.id, second.id ])

      expect(json["file"]["name"]).to eq("Passport (merged).pdf")
    end

    it "says where it put it" do
      folder = create(:folder, user: user, name: "Passports")
      first = pdf(pages: 1, name: "One.pdf")
      second = pdf(pages: 1, name: "Two.pdf")

      merge([ first.id, second.id ], folder_id: folder.id)

      expect(json["file"]["folder"]).to include("id" => folder.id, "name" => "Passports")
    end

    # A merge of family documents is a new document, and its author decides who
    # sees it.
    it "saves the result privately, whatever the sources were" do
      first = pdf(pages: 1, name: "One.pdf", family: family, visibility: "family")
      second = pdf(pages: 1, name: "Two.pdf", family: family, visibility: "family")

      merge([ first.id, second.id ])

      expect(StoredFile.find(json["file"]["id"]).visibility).to eq("private")
    end

    it "can be dropped into a folder" do
      folder = create(:folder, user: user, name: "Passports")
      first = pdf(pages: 1, name: "One.pdf")
      second = pdf(pages: 1, name: "Two.pdf")

      merge([ first.id, second.id ], folder_id: folder.id)

      expect(json["file"]["folder"]["name"]).to eq("Passports")
    end

    describe "refusing" do
      it "a single file" do
        merge([ pdf(pages: 1, name: "Alone.pdf").id ])

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]["message"]).to include("at least two")
      end

      it "anything that is not a PDF" do
        first = pdf(pages: 1, name: "One.pdf")
        image = create(:stored_file, user: user, name: "Holiday.jpg", mime_type: "image/jpeg", file_type: "image")
        image.attachment.attach(
          io: StringIO.new(Vips::Image.black(8, 8).write_to_buffer(".jpg")),
          filename: "Holiday.jpg", content_type: "image/jpeg"
        )

        merge([ first.id, image.id ])

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]["message"]).to include("Holiday.jpg")
      end

      # Merging is a way of reading a file, so it needs the same permission.
      it "a file the caller cannot see" do
        mine = pdf(pages: 1, name: "Mine.pdf")
        theirs = pdf(pages: 1, name: "Theirs.pdf", owner: stranger, visibility: "private")

        merge([ mine.id, theirs.id ])

        expect(response).to have_http_status(:not_found)
        expect(StoredFile.where("name like ?", "%merged%")).to be_empty
      end

      it "a file that does not exist" do
        merge([ pdf(pages: 1, name: "One.pdf").id, 999_999 ])

        expect(response).to have_http_status(:not_found)
      end

      # Naming it matters: with ten files, "one was unreadable" means opening
      # each to find out which.
      it "a damaged PDF, by name" do
        good = pdf(pages: 1, name: "Good.pdf")
        broken = create(:stored_file, user: user, name: "Broken.pdf", mime_type: "application/pdf", file_type: "file")
        broken.attachment.attach(io: StringIO.new("not really a pdf"), filename: "Broken.pdf",
                                 content_type: "application/pdf")

        merge([ good.id, broken.id ])

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]["message"]).to include("Broken.pdf")
      end

      it "a request with no session" do
        post "/api/v1/utilities/merge", params: { file_ids: [ 1, 2 ] }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
