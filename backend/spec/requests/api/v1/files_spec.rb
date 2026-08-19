require "rails_helper"

RSpec.describe "Api::V1::Files" do
  let(:owner) { create(:user) }
  let(:family) { create(:family, owner: owner) }
  let(:editor) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") } }
  let(:viewer) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "viewer") } }
  let(:stranger) { create(:user) }

  def upload_fixture(filename: "notes.txt", content: "hello world", type: "text/plain")
    file = Tempfile.new(%w[upload .txt])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, original_filename: filename)
  end

  describe "POST /api/v1/files" do
    it "uploads a private file" do
      expect {
        post "/api/v1/files", params: { file: upload_fixture }, headers: auth_headers_for(owner)
      }.to change(StoredFile, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json["file"]["name"]).to eq("notes.txt")
      expect(json["file"]["visibility"]).to eq("private")
    end

    it "uploads to the family vault as an editor" do
      post "/api/v1/files",
           params: { file: upload_fixture, visibility: "family" },
           headers: auth_headers_for(editor)

      expect(response).to have_http_status(:created)
      expect(json["file"]["visibility"]).to eq("family")
    end

    it "refuses a family upload from a viewer" do
      post "/api/v1/files",
           params: { file: upload_fixture, visibility: "family" },
           headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:forbidden)
      expect(json["error"]["code"]).to eq("forbidden")
    end

    it "rejects a request with no file" do
      post "/api/v1/files", params: {}, headers: auth_headers_for(owner)

      expect(response).to have_http_status(:bad_request)
      expect(json["error"]["code"]).to eq("file_missing")
    end

    it "rejects an executable" do
      post "/api/v1/files",
           params: { file: upload_fixture(filename: "virus.exe") },
           headers: auth_headers_for(owner)

      expect(response).to have_http_status(:unsupported_media_type)
      expect(json["error"]["code"]).to eq("unsupported_type")
    end

    it "reports a quota overrun rather than failing opaquely" do
      owner.update!(storage_used: owner.storage_quota)

      post "/api/v1/files", params: { file: upload_fixture }, headers: auth_headers_for(owner)

      expect(response).to have_http_status(:content_too_large)
      expect(json["error"]["code"]).to eq("quota_exceeded")
    end

    it "versions an upload of the same name in the same folder" do
      post "/api/v1/files", params: { file: upload_fixture }, headers: auth_headers_for(owner)
      expect(response).to have_http_status(:created)

      expect {
        post "/api/v1/files", params: { file: upload_fixture(content: "v2") }, headers: auth_headers_for(owner)
      }.not_to change(StoredFile, :count)

      expect(response).to have_http_status(:ok)
      expect(json["file"]["version_number"]).to eq(2)
    end

    it "requires authentication" do
      post "/api/v1/files", params: { file: upload_fixture }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/files" do
    let!(:own_file) { create(:stored_file, user: owner, visibility: "private") }
    let!(:family_file) { create(:stored_file, user: owner, family: family, visibility: "family") }
    let!(:other_private) { create(:stored_file, user: editor, visibility: "private") }

    it "lists the caller's own files and the family's shared ones" do
      get "/api/v1/files", headers: auth_headers_for(owner)

      ids = json["files"].map { |f| f["id"] }
      expect(ids).to contain_exactly(own_file.id, family_file.id)
    end

    it "does not leak another member's private files" do
      get "/api/v1/files", headers: auth_headers_for(viewer)

      ids = json["files"].map { |f| f["id"] }
      expect(ids).to contain_exactly(family_file.id)
      expect(ids).not_to include(other_private.id)
    end

    it "shows a non-member nothing" do
      get "/api/v1/files", headers: auth_headers_for(stranger)

      expect(json["files"]).to be_empty
    end

    it "filters by file type" do
      image = create(:stored_file, :image, user: owner)

      get "/api/v1/files", params: { file_type: "image" }, headers: auth_headers_for(owner)

      expect(json["files"].map { |f| f["id"] }).to contain_exactly(image.id)
    end

    it "excludes trashed files by default and includes them on request" do
      trashed = create(:stored_file, :trashed, user: owner)

      get "/api/v1/files", headers: auth_headers_for(owner)
      expect(json["files"].map { |f| f["id"] }).not_to include(trashed.id)

      get "/api/v1/files", params: { trashed: "true" }, headers: auth_headers_for(owner)
      expect(json["files"].map { |f| f["id"] }).to contain_exactly(trashed.id)
    end

    it "searches by name" do
      match = create(:stored_file, user: owner, name: "Mortgage_Agreement.pdf")

      get "/api/v1/files", params: { q: "mortgage" }, headers: auth_headers_for(owner)

      expect(json["files"].map { |f| f["id"] }).to contain_exactly(match.id)
    end

    it "returns pagination headers" do
      get "/api/v1/files", headers: auth_headers_for(owner)

      expect(response.headers["X-Total-Count"]).to be_present
      expect(response.headers["X-Page"]).to eq("1")
    end
  end

  describe "GET /api/v1/files/:id" do
    let(:file) { create(:stored_file, user: owner, family: family, visibility: "family") }

    it "returns the file with its permissions for the caller" do
      get "/api/v1/files/#{file.id}", headers: auth_headers_for(editor)

      expect(response).to have_http_status(:ok)
      expect(json["file"]["permissions"]["can_edit"]).to be true
      # Deleting someone else's file is admin-only.
      expect(json["file"]["permissions"]["can_delete"]).to be false
    end

    it "returns 404 — not 403 — for a file the caller cannot see" do
      private_file = create(:stored_file, user: owner, visibility: "private")

      get "/api/v1/files/#{private_file.id}", headers: auth_headers_for(stranger)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/files/:id" do
    let!(:file) { create(:stored_file, user: owner, family: family, visibility: "family") }

    it "soft-deletes rather than destroying" do
      expect {
        delete "/api/v1/files/#{file.id}", headers: auth_headers_for(owner)
      }.not_to change(StoredFile, :count)

      expect(response).to have_http_status(:no_content)
      expect(file.reload).to be_trashed
    end

    it "refuses an editor deleting someone else's file" do
      delete "/api/v1/files/#{file.id}", headers: auth_headers_for(editor)

      expect(response).to have_http_status(:forbidden)
      expect(file.reload).not_to be_trashed
    end

    it "sets a purge date for the trash countdown" do
      delete "/api/v1/files/#{file.id}", headers: auth_headers_for(owner)

      expect(file.reload.purge_after).to be_within(1.minute)
        .of(ENV.fetch("TRASH_RETENTION_DAYS", 30).to_i.days.from_now)
    end
  end

  describe "POST /api/v1/files/:id/restore" do
    let!(:file) { create(:stored_file, :trashed, user: owner) }

    it "restores a trashed file" do
      post "/api/v1/files/#{file.id}/restore", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(file.reload).not_to be_trashed
    end
  end

  describe "GET /api/v1/files/:id/download" do
    it "returns a presigned URL the browser can follow" do
      file = create(:stored_file, :with_attachment, user: owner)

      get "/api/v1/files/#{file.id}/download", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json["url"]).to be_present
      expect(json["filename"]).to eq(file.name)
    end

    it "refuses a caller who cannot view the file" do
      file = create(:stored_file, :with_attachment, user: owner, visibility: "private")

      get "/api/v1/files/#{file.id}/download", headers: auth_headers_for(stranger)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "moving a file between folders" do
    let!(:folder) { Folder.create!(user: owner, name: "Legal") }
    let!(:file) { create(:stored_file, user: owner) }

    it "moves the file into a folder" do
      patch "/api/v1/files/#{file.id}", params: { folder_id: folder.id },
            headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(file.reload.folder_id).to eq(folder.id)
      expect(json["file"]["folder"]["name"]).to eq("Legal")
    end

    it "moves the file back to the root with a blank folder" do
      file.update!(folder: folder)

      patch "/api/v1/files/#{file.id}", params: { folder_id: "" },
            headers: auth_headers_for(owner), as: :json

      expect(file.reload.folder_id).to be_nil
    end

    it "refuses a folder belonging to someone else" do
      other_folder = Folder.create!(user: stranger, name: "Theirs")

      patch "/api/v1/files/#{file.id}", params: { folder_id: other_folder.id },
            headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:not_found)
      expect(file.reload.folder_id).to be_nil
    end

    it "refuses a folder from another family" do
      other_family = create(:family)
      other_folder = Folder.create!(user: other_family.owner, family: other_family, name: "Theirs")

      patch "/api/v1/files/#{file.id}", params: { folder_id: other_folder.id },
            headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "lets a family member move a file into a shared folder" do
      shared = Folder.create!(user: owner, family: family, name: "Family Docs")
      family_file = create(:stored_file, user: editor, family: family, visibility: "family")

      patch "/api/v1/files/#{family_file.id}", params: { folder_id: shared.id },
            headers: auth_headers_for(editor), as: :json

      expect(response).to have_http_status(:ok)
      expect(family_file.reload.folder_id).to eq(shared.id)
    end
  end
end
