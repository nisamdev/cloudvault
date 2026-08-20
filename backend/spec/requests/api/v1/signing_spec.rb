require "rails_helper"

RSpec.describe "Api::V1 PDF signing" do
  let(:owner) { create(:user) }
  let!(:family) { create(:family, owner: owner) }
  let(:viewer) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "viewer") } }

  def pdf_bytes(pages: 2)
    require "prawn"
    Prawn::Document.new do |pdf|
      pages.times do |i|
        pdf.start_new_page if i.positive?
        pdf.text "Page #{i + 1}"
      end
    end.render
  end

  def signature_png
    Vips::Image.black(240, 90).add(255).cast("uchar").colourspace("srgb")
               .draw_line([ 0 ], 10, 70, 230, 25).pngsave_buffer
  end

  def saved_signature(user = owner)
    signature = user.signatures.new(name: "Signature #{user.signatures.count + 1}")
    signature.image.attach(io: StringIO.new(signature_png), filename: "sig.png", content_type: "image/png")
    signature.save!
    signature
  end

  def pdf_file(user = owner, **attrs)
    file = create(:stored_file, user: user, name: "Agreement.pdf", mime_type: "application/pdf", **attrs)
    file.attachment.attach(io: StringIO.new(pdf_bytes), filename: file.name, content_type: "application/pdf")
    file
  end

  describe "POST /api/v1/signatures" do
    it "saves a signature drawn on a canvas" do
      data_url = "data:image/png;base64,#{Base64.strict_encode64(signature_png)}"

      expect {
        post "/api/v1/signatures", params: { image_data: data_url, name: "Mine" },
             headers: auth_headers_for(owner), as: :json
      }.to change(Signature, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json["signature"]["name"]).to eq("Mine")
      expect(json["signature"]["image_url"]).to be_present
    end

    it "rejects a data URL that is not an image" do
      post "/api/v1/signatures", params: { image_data: "data:text/plain;base64,aGk=" },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects nonsense in place of an image" do
      post "/api/v1/signatures", params: { image_data: "not-a-data-url" },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "keeps signatures private to their owner" do
      saved_signature(owner)

      get "/api/v1/signatures", headers: auth_headers_for(viewer)

      expect(json["signatures"]).to be_empty
    end
  end

  describe "GET /api/v1/files/:id/pages" do
    it "renders each page as an image the browser can show" do
      file = pdf_file

      get "/api/v1/files/#{file.id}/pages", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json["page_count"]).to eq(2)
      expect(json["pages"].size).to eq(2)
      expect(json["pages"].first["image"]).to start_with("data:image/png;base64,")
      expect(json["pages"].first["width"]).to be > 0
    end

    it "refuses anything that is not a PDF" do
      file = create(:stored_file, :with_attachment, user: owner, mime_type: "text/plain")

      get "/api/v1/files/#{file.id}/pages", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("not_a_pdf")
    end

    it "is refused to someone who cannot see the file" do
      file = pdf_file

      get "/api/v1/files/#{file.id}/pages", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/files/:id/sign" do
    it "signs the document and keeps the original as a version" do
      file = pdf_file
      signature = saved_signature
      original_bytes = file.attachment.download

      post "/api/v1/files/#{file.id}/sign",
           params: { signature_id: signature.id,
                     placements: [ { page: 1, x: 0.5, y: 0.7, width: 0.25 } ] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)

      file.reload
      expect(file.version_number).to eq(2)
      expect(file.attachment.download).not_to eq(original_bytes)
      # The unsigned copy has to survive — a signature you cannot undo is a trap.
      expect(file.file_versions.count).to eq(1)
      expect(file.file_versions.first.attachment.download).to eq(original_bytes)
    end

    it "still produces a valid PDF" do
      file = pdf_file
      signature = saved_signature

      post "/api/v1/files/#{file.id}/sign",
           params: { signature_id: signature.id, placements: [ { page: 1, x: 0.4, y: 0.6, width: 0.3 } ] },
           headers: auth_headers_for(owner), as: :json

      signed = file.reload.attachment.download
      expect(signed[0, 5]).to eq("%PDF-")
      expect(CombinePDF.parse(signed).pages.size).to eq(2)
    end

    it "can sign a page other than the first" do
      file = pdf_file
      signature = saved_signature

      post "/api/v1/files/#{file.id}/sign",
           params: { signature_id: signature.id, placements: [ { page: 2, x: 0.3, y: 0.5, width: 0.2 } ] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
    end

    it "refuses a page that does not exist" do
      file = pdf_file
      signature = saved_signature

      post "/api/v1/files/#{file.id}/sign",
           params: { signature_id: signature.id, placements: [ { page: 99, x: 0.3, y: 0.5, width: 0.2 } ] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("signing_failed")
    end

    it "refuses someone else's signature" do
      file = pdf_file
      theirs = saved_signature(create(:user))

      post "/api/v1/files/#{file.id}/sign",
           params: { signature_id: theirs.id, placements: [ { page: 1, x: 0.3, y: 0.5, width: 0.2 } ] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a viewer signing family content" do
      file = pdf_file(owner, family: family, visibility: "family")
      signature = saved_signature(viewer)

      post "/api/v1/files/#{file.id}/sign",
           params: { signature_id: signature.id, placements: [ { page: 1, x: 0.3, y: 0.5, width: 0.2 } ] },
           headers: auth_headers_for(viewer), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a file that is not a PDF" do
      file = create(:stored_file, :with_attachment, user: owner, mime_type: "image/png")
      signature = saved_signature

      post "/api/v1/files/#{file.id}/sign",
           params: { signature_id: signature.id, placements: [ { page: 1, x: 0.3, y: 0.5, width: 0.2 } ] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe PdfSigner do
    it "clamps an absurdly large signature rather than covering the page" do
      signed = described_class.new(pdf_bytes, signature_png).call(
        [ described_class::Placement.new(page: 1, x: 0, y: 0, width: 50) ]
      )

      expect(signed[0, 5]).to eq("%PDF-")
    end

    it "accepts several placements on one page" do
      signed = described_class.new(pdf_bytes, signature_png).call([
        described_class::Placement.new(page: 1, x: 0.1, y: 0.2, width: 0.2),
        described_class::Placement.new(page: 1, x: 0.6, y: 0.8, width: 0.2)
      ])

      expect(CombinePDF.parse(signed).pages.size).to eq(2)
    end

    it "refuses to run with no placements" do
      expect {
        described_class.new(pdf_bytes, signature_png).call([])
      }.to raise_error(described_class::Error, /No placements/)
    end

    it "reports a file that is not a PDF" do
      expect {
        described_class.new("just some text", signature_png).call(
          [ described_class::Placement.new(page: 1, x: 0.1, y: 0.1, width: 0.2) ]
        )
      }.to raise_error(described_class::Error)
    end
  end
end
