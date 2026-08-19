require "rails_helper"

RSpec.describe "Api::V1::Scans" do
  let(:owner) { create(:user) }
  let!(:family) { create(:family, owner: owner) }
  let(:viewer) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "viewer") } }
  let(:stranger) { create(:user) }

  def page_image
    Vips::Image.black(600, 800).add(200).cast("uchar").colourspace("srgb").jpegsave_buffer(Q: 80)
  end

  def uploaded_page(bytes = page_image, filename: "page.jpg")
    file = Tempfile.new([ "page", ".jpg" ], binmode: true)
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/jpeg", original_filename: filename)
  end

  def token_for(user, **attrs)
    post "/api/v1/scans", params: attrs, headers: auth_headers_for(user), as: :json
    json["url"].split("/scan/").last
  end

  describe "POST /api/v1/scans" do
    it "returns a link and a QR code" do
      post "/api/v1/scans", headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json["url"]).to include("/scan/")
      expect(json["qr_svg"]).to include("<svg")
      expect(json["expires_in_minutes"]).to be_between(1, 20)
    end

    it "requires a session — the desktop side is not public" do
      post "/api/v1/scans", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a folder the caller cannot reach" do
      theirs = Folder.create!(user: stranger, name: "Theirs")

      post "/api/v1/scans", params: { folder_id: theirs.id }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a viewer asking for family visibility" do
      post "/api/v1/scans", params: { visibility: "family" }, headers: auth_headers_for(viewer), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/scans/:token" do
    it "tells the phone where the scan will land, without a session" do
      folder = Folder.create!(user: owner, name: "Documents")
      token = token_for(owner, folder_id: folder.id)

      get "/api/v1/scans/#{token}"

      expect(response).to have_http_status(:ok)
      expect(json["destination"]["folder"]).to eq("Documents")
      expect(json["account"]).to eq(owner.full_name.presence || owner.email)
    end

    it "rejects a made-up token" do
      get "/api/v1/scans/not-a-real-token"

      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]["code"]).to eq("invalid_scan_token")
    end

    it "rejects an expired token" do
      token = JwtService.encode_scan(
        user_id: owner.id, folder_id: nil, visibility: "private", expires_in: -1.minute
      )

      get "/api/v1/scans/#{token}"

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an access token replayed as a scan token" do
      access = JwtService.encode({ sub: owner.id, email: owner.email })

      get "/api/v1/scans/#{access}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/scans/:token" do
    it "turns photographed pages into one PDF" do
      token = token_for(owner)

      expect {
        post "/api/v1/scans/#{token}",
             params: { pages: [ uploaded_page, uploaded_page ], mode: "pdf", name: "Passport" }
      }.to change(StoredFile, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json["page_count"]).to eq(2)
      expect(json["files"].first["name"]).to eq("Passport.pdf")

      stored = StoredFile.order(:id).last
      expect(stored.mime_type).to eq("application/pdf")
      expect(stored.attachment.download[0, 5]).to eq("%PDF-")
    end

    it "can save the pages as separate images instead" do
      token = token_for(owner)

      expect {
        post "/api/v1/scans/#{token}", params: { pages: [ uploaded_page, uploaded_page ], mode: "images" }
      }.to change(StoredFile, :count).by(2)

      expect(StoredFile.order(:id).last.file_type).to eq("image")
    end

    it "files the scan against the account that created the link" do
      token = token_for(owner)

      post "/api/v1/scans/#{token}", params: { pages: [ uploaded_page ] }

      expect(StoredFile.order(:id).last.user_id).to eq(owner.id)
    end

    it "honours the destination folder chosen on the desktop" do
      folder = Folder.create!(user: owner, name: "Documents")
      token = token_for(owner, folder_id: folder.id)

      post "/api/v1/scans/#{token}", params: { pages: [ uploaded_page ] }

      expect(StoredFile.order(:id).last.folder_id).to eq(folder.id)
    end

    it "honours family visibility chosen on the desktop" do
      token = token_for(owner, visibility: "family")

      post "/api/v1/scans/#{token}", params: { pages: [ uploaded_page ] }

      stored = StoredFile.order(:id).last
      expect(stored.visibility).to eq("family")
      expect(stored.family_id).to eq(family.id)
    end

    it "rejects an expired token" do
      token = JwtService.encode_scan(
        user_id: owner.id, folder_id: nil, visibility: "private", expires_in: -1.second
      )

      expect {
        post "/api/v1/scans/#{token}", params: { pages: [ uploaded_page ] }
      }.not_to change(StoredFile, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a request with no pages" do
      token = token_for(owner)

      post "/api/v1/scans/#{token}", params: {}

      expect(response).to have_http_status(:bad_request)
      expect(json["error"]["code"]).to eq("no_pages")
    end

    it "caps how many pages one request may carry" do
      token = token_for(owner)

      post "/api/v1/scans/#{token}", params: { pages: Array.new(31) { uploaded_page } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("too_many_pages")
    end

    it "reports a quota overrun rather than failing opaquely" do
      owner.update!(storage_used: owner.storage_quota)
      token = token_for(owner)

      post "/api/v1/scans/#{token}", params: { pages: [ uploaded_page ] }

      expect(response).to have_http_status(:content_too_large)
      expect(json["error"]["code"]).to eq("quota_exceeded")
    end

    it "counts the scan against the uploader's storage" do
      token = token_for(owner)

      expect {
        post "/api/v1/scans/#{token}", params: { pages: [ uploaded_page ] }
      }.to change { owner.reload.storage_used }
    end
  end

  describe "what the token cannot do" do
    it "cannot list files" do
      token = token_for(owner)

      get "/api/v1/files", headers: { "Authorization" => "Bearer #{token}" }

      # A scan token is not an access token, so ordinary endpoints reject it.
      expect(response).to have_http_status(:unauthorized)
    end

    it "cannot read a file" do
      file = create(:stored_file, :with_attachment, user: owner)
      token = token_for(owner)

      get "/api/v1/files/#{file.id}", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "cannot delete anything" do
      file = create(:stored_file, user: owner)
      token = token_for(owner)

      delete "/api/v1/files/#{file.id}", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
      expect(file.reload).not_to be_trashed
    end
  end

  describe DocumentScanner do
    it "produces a valid PDF from page images" do
      pdf = described_class.to_pdf([ page_image, page_image ], title: "Test")

      expect(pdf[0, 5]).to eq("%PDF-")
      expect(pdf).to include("%%EOF")
    end

    it "returns JPEG bytes from processing" do
      out = described_class.new(mode: "document").process(page_image)

      expect(out[0, 2].bytes).to eq([ 0xFF, 0xD8 ])
    end

    it "keeps the original bytes when the image cannot be read" do
      garbage = "not an image"

      expect(described_class.new.process(garbage)).to eq(garbage)
    end
  end
end
