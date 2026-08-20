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
           params: { fields: [ { type: "signature", page: 1, x: 0.5, y: 0.7,
                                 width: 0.25, height: 0.07, value: signature.id.to_s } ] },
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
           params: { fields: [ { type: "signature", page: 1, x: 0.4, y: 0.6,
                                 width: 0.3, height: 0.07, value: signature.id.to_s } ] },
           headers: auth_headers_for(owner), as: :json

      signed = file.reload.attachment.download
      expect(signed[0, 5]).to eq("%PDF-")
      expect(CombinePDF.parse(signed).pages.size).to eq(2)
    end

    it "can sign a page other than the first" do
      file = pdf_file
      signature = saved_signature

      post "/api/v1/files/#{file.id}/sign",
           params: { fields: [ { type: "signature", page: 2, x: 0.3, y: 0.5,
                                 width: 0.2, height: 0.07, value: signature.id.to_s } ] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
    end

    it "refuses a page that does not exist" do
      file = pdf_file
      signature = saved_signature

      post "/api/v1/files/#{file.id}/sign",
           params: { fields: [ { type: "signature", page: 99, x: 0.3, y: 0.5,
                                 width: 0.2, height: 0.07, value: signature.id.to_s } ] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("signing_failed")
    end

    it "refuses someone else's signature" do
      file = pdf_file
      theirs = saved_signature(create(:user))

      post "/api/v1/files/#{file.id}/sign",
           params: { fields: [ { type: "signature", page: 1, x: 0.3, y: 0.5,
                                 width: 0.2, height: 0.07, value: theirs.id.to_s } ] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a viewer signing family content" do
      file = pdf_file(owner, family: family, visibility: "family")
      signature = saved_signature(viewer)

      post "/api/v1/files/#{file.id}/sign",
           params: { fields: [ { type: "signature", page: 1, x: 0.3, y: 0.5,
                                 width: 0.2, height: 0.07, value: signature.id.to_s } ] },
           headers: auth_headers_for(viewer), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a file that is not a PDF" do
      file = create(:stored_file, :with_attachment, user: owner, mime_type: "image/png")
      signature = saved_signature

      post "/api/v1/files/#{file.id}/sign",
           params: { fields: [ { type: "signature", page: 1, x: 0.3, y: 0.5,
                                 width: 0.2, height: 0.07, value: signature.id.to_s } ] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "fills text, dates and checkboxes in the same pass" do
      file = pdf_file
      signature = saved_signature

      post "/api/v1/files/#{file.id}/sign",
           params: { fields: [
             { type: "text", page: 1, x: 0.1, y: 0.2, width: 0.4, height: 0.04, value: "Nisam" },
             { type: "date", page: 1, x: 0.1, y: 0.3, width: 0.2, height: 0.03, value: "20 August 2026" },
             { type: "checkbox", page: 1, x: 0.1, y: 0.4, width: 0.03, height: 0.02, value: true },
             { type: "signature", page: 2, x: 0.3, y: 0.5, width: 0.25, height: 0.07, value: signature.id.to_s }
           ] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(file.reload.version_number).to eq(2)
    end

    it "refuses a request with nothing placed" do
      file = pdf_file

      post "/api/v1/files/#{file.id}/sign", params: { fields: [] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("no_fields")
    end

    it "refuses the whole request if any signature is not yours" do
      file = pdf_file
      theirs = saved_signature(create(:user))

      post "/api/v1/files/#{file.id}/sign",
           params: { fields: [
             { type: "signature", page: 1, x: 0.3, y: 0.5, width: 0.2, height: 0.07, value: theirs.id.to_s },
             { type: "text", page: 1, x: 0.1, y: 0.2, width: 0.3, height: 0.04, value: "Still fills" }
           ] },
           headers: auth_headers_for(owner), as: :json

      # Dropping it quietly would leave the signer believing they had signed.
      expect(response).to have_http_status(:not_found)
      expect(file.reload.version_number).to eq(1)
    end

    it "refuses when every field was left empty" do
      file = pdf_file

      post "/api/v1/files/#{file.id}/sign",
           params: { fields: [ { type: "text", page: 1, x: 0.1, y: 0.2,
                                 width: 0.3, height: 0.04, value: "" } ] },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("no_fields")
      # No pointless version for a document nothing was written on.
      expect(file.reload.version_number).to eq(1)
    end
  end

  describe PdfFieldStamper do
    def field(type, **attrs)
      described_class::Field.new(
        { type: type, page: 1, x: 0.2, y: 0.3, width: 0.3, height: 0.05 }.merge(attrs)
      )
    end

    def stamp(fields, images: { "sig" => signature_png })
      described_class.new(pdf_bytes, images: images).call(fields)
    end

    it "stamps text" do
      out = stamp([ field("text", value: "Nisam Kalampulan", font_size: 12, bold: true) ])
      expect(out[0, 5]).to eq("%PDF-")
    end

    it "stamps a date" do
      expect(stamp([ field("date", value: "20 August 2026") ])[0, 5]).to eq("%PDF-")
    end

    it "stamps a checkbox without relying on a glyph the font lacks" do
      # Helvetica has no check mark in WinAnsi; it is drawn as two strokes.
      expect(stamp([ field("checkbox", value: true) ])[0, 5]).to eq("%PDF-")
    end

    it "stamps a saved signature by id" do
      expect(stamp([ field("signature", value: "sig") ])[0, 5]).to eq("%PDF-")
    end

    it "stamps a signature drawn inline as a data URL" do
      data_url = "data:image/png;base64,#{Base64.strict_encode64(signature_png)}"

      expect(stamp([ field("signature", value: data_url) ], images: {})[0, 5]).to eq("%PDF-")
    end

    it "leaves the page count alone" do
      out = stamp([ field("text", value: "hello"), field("signature", page: 2, value: "sig") ])

      expect(CombinePDF.parse(out).pages.size).to eq(2)
    end

    it "draws nothing for an empty text field but still stamps the rest" do
      out = stamp([ field("text", value: ""), field("signature", value: "sig", y: 0.6) ])

      expect(out[0, 5]).to eq("%PDF-")
    end

    it "ignores an unknown field type" do
      expect {
        stamp([ field("barcode", value: "x") ])
      }.to raise_error(described_class::Error, /Nothing to stamp/)
    end

    it "clamps geometry that would cover the whole page" do
      expect(stamp([ field("signature", value: "sig", width: 50, height: 50) ])[0, 5]).to eq("%PDF-")
    end

    it "refuses a page that does not exist" do
      expect {
        stamp([ field("text", page: 99, value: "hi") ])
      }.to raise_error(described_class::Error, /does not exist/)
    end

    it "reports a file that is not a PDF" do
      expect {
        described_class.new("just some text").call([ field("text", value: "hi") ])
      }.to raise_error(described_class::Error)
    end

    it "keeps going when one field is broken" do
      out = stamp([
        field("signature", value: "missing-id"),
        field("text", value: "This still lands", page: 1, y: 0.6)
      ])

      expect(out[0, 5]).to eq("%PDF-")
    end
  end
end

RSpec.describe "Api::V1::Signatures management" do
  let(:owner) { create(:user) }

  def signature_png
    Vips::Image.black(200, 80).add(255).cast("uchar").colourspace("srgb")
               .draw_line([ 0 ], 10, 60, 190, 20).pngsave_buffer
  end

  def create_signature(user = owner, name: nil)
    signature = user.signatures.new(name: name || "Signature #{user.signatures.count + 1}")
    signature.image.attach(io: StringIO.new(signature_png), filename: "s.png", content_type: "image/png")
    signature.save!
    signature
  end

  describe "defaults" do
    it "makes the first signature the default" do
      first = create_signature

      expect(first.reload).to be_is_default
    end

    it "does not make later ones default automatically" do
      create_signature
      second = create_signature

      expect(second.reload).not_to be_is_default
    end

    it "moves the default when another is chosen" do
      first = create_signature
      second = create_signature

      patch "/api/v1/signatures/#{second.id}", params: { is_default: true },
            headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(second.reload).to be_is_default
      # The database has a partial unique index; two defaults cannot coexist.
      expect(first.reload).not_to be_is_default
    end

    it "promotes another when the default is deleted" do
      first = create_signature
      second = create_signature
      patch "/api/v1/signatures/#{second.id}", params: { is_default: true },
            headers: auth_headers_for(owner), as: :json

      delete "/api/v1/signatures/#{second.id}", headers: auth_headers_for(owner)

      # Otherwise the user is left with signatures but no default.
      expect(first.reload).to be_is_default
    end

    it "lists the default first" do
      create_signature(name: "Alpha")
      second = create_signature(name: "Beta")
      patch "/api/v1/signatures/#{second.id}", params: { is_default: true },
            headers: auth_headers_for(owner), as: :json

      get "/api/v1/signatures", headers: auth_headers_for(owner)

      expect(json["signatures"].first["name"]).to eq("Beta")
      expect(json["signatures"].first["is_default"]).to be true
    end
  end

  describe "renaming" do
    it "renames a signature" do
      signature = create_signature

      patch "/api/v1/signatures/#{signature.id}", params: { name: "Formal" },
            headers: auth_headers_for(owner), as: :json

      expect(signature.reload.name).to eq("Formal")
    end

    it "refuses to touch someone else's" do
      theirs = create_signature(create(:user))

      patch "/api/v1/signatures/#{theirs.id}", params: { name: "Mine now" },
            headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "drawing one on a phone" do
    def new_session
      post "/api/v1/signatures/session", headers: auth_headers_for(owner), as: :json
      json["url"].split("/signature/").last
    end

    it "returns a link and a QR code" do
      post "/api/v1/signatures/session", headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json["url"]).to include("/signature/")
      expect(json["qr_svg"]).to include("<svg")
    end

    it "tells the phone whose account it is, without a session" do
      token = new_session

      get "/api/v1/signatures/session/#{token}"

      expect(response).to have_http_status(:ok)
      expect(json["account"]).to eq(owner.full_name.presence || owner.email)
    end

    it "saves what the phone drew against the right account" do
      token = new_session
      data_url = "data:image/png;base64,#{Base64.strict_encode64(signature_png)}"

      expect {
        post "/api/v1/signatures/session/#{token}", params: { image_data: data_url, name: "On phone" },
             as: :json
      }.to change(owner.signatures, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(owner.signatures.order(:id).last.name).to eq("On phone")
    end

    it "lets the desktop see that it arrived" do
      token = new_session
      data_url = "data:image/png;base64,#{Base64.strict_encode64(signature_png)}"
      post "/api/v1/signatures/session/#{token}", params: { image_data: data_url }, as: :json

      get "/api/v1/signatures/session/#{token}/status", headers: auth_headers_for(owner)

      expect(json["receipt"]).to be_present
      expect(json["receipt"]["signature_id"]).to eq(owner.signatures.order(:id).last.id)
    end

    it "rejects an expired link" do
      token = JwtService.encode_signature(user_id: owner.id, expires_in: -1.minute)

      get "/api/v1/signatures/session/#{token}"

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a scan token replayed here" do
      scan = JwtService.encode_scan(user_id: owner.id, folder_id: nil, visibility: "private", expires_in: 5.minutes)

      get "/api/v1/signatures/session/#{scan}"

      expect(response).to have_http_status(:unauthorized)
    end

    it "cannot be used to read anything" do
      token = new_session

      get "/api/v1/files", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
