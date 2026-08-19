require "rails_helper"

RSpec.describe "Api::V1::Folders ZIP download" do
  let(:owner) { create(:user) }
  let!(:family) { create(:family, owner: owner) }
  let(:viewer) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "viewer") } }
  let(:stranger) { create(:user) }

  let!(:root) { Folder.create!(user: owner, family: family, name: "Documents") }
  let!(:child) { Folder.create!(user: owner, family: family, name: "Legal", parent: root) }
  let!(:top_file) do
    create(:stored_file, :with_attachment, user: owner, family: family,
           visibility: "family", folder: root, name: "Readme.txt")
  end
  let!(:nested_file) do
    create(:stored_file, :with_attachment, user: owner, family: family,
           visibility: "family", folder: child, name: "Deed.pdf")
  end

  def zip_entries(body)
    Zip::File.open_buffer(StringIO.new(body)) { |zip| return zip.map(&:name) }
  rescue NameError
    # rubyzip isn't a dependency; fall back to reading the central directory
    # names out of the raw bytes.
    body.scan(%r{[\w /.()-]+\.(?:txt|pdf)}).uniq
  end

  describe "POST /api/v1/folders/:id/download_url" do
    it "returns a signed URL and a summary of what will be archived" do
      post "/api/v1/folders/#{root.id}/download_url", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json["url"]).to include("/folders/#{root.id}/download?token=")
      expect(json["filename"]).to eq("documents.zip")
      # Counts the nested file too.
      expect(json["file_count"]).to eq(2)
    end

    it "refuses a folder with nothing in it" do
      empty = Folder.create!(user: owner, name: "Empty")

      post "/api/v1/folders/#{empty.id}/download_url", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("folder_empty")
    end

    it "hides folders the caller cannot see" do
      post "/api/v1/folders/#{root.id}/download_url", headers: auth_headers_for(stranger)

      expect(response).to have_http_status(:not_found)
    end

    it "lets a viewer download a shared folder" do
      post "/api/v1/folders/#{root.id}/download_url", headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/folders/:id/download" do
    def signed_url_for(folder, user)
      post "/api/v1/folders/#{folder.id}/download_url", headers: auth_headers_for(user)
      json["url"]
    end

    it "streams a ZIP without an Authorization header" do
      url = signed_url_for(root, owner)

      get url.sub(Rails.configuration.x.api_url, "")

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("zip")
      expect(response.body.bytesize).to be > 0
      # Local file header magic.
      expect(response.body[0, 2]).to eq("PK")
    end

    it "keeps the nested folder structure in the entry paths" do
      url = signed_url_for(root, owner)

      get url.sub(Rails.configuration.x.api_url, "")

      expect(response.body).to include("Documents/Readme.txt")
      expect(response.body).to include("Documents/Legal/Deed.pdf")
    end

    it "rejects a request with no token" do
      get "/api/v1/folders/#{root.id}/download"

      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]["code"]).to eq("invalid_download_token")
    end

    it "rejects a forged token" do
      get "/api/v1/folders/#{root.id}/download", params: { token: "not-a-token" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a token issued for a different folder" do
      url = signed_url_for(root, owner)
      token = url[/token=(.+)\z/, 1]

      get "/api/v1/folders/#{child.id}/download", params: { token: CGI.unescape(token) }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an expired token" do
      token = JwtService.encode_download(
        user_id: owner.id, scope: "folder:#{root.id}", expires_in: -1.minute
      )

      get "/api/v1/folders/#{root.id}/download", params: { token: token }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a token whose user can no longer see the folder" do
      token = JwtService.encode_download(user_id: stranger.id, scope: "folder:#{root.id}")

      get "/api/v1/folders/#{root.id}/download", params: { token: token }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe FolderArchiver do
    it "excludes files the user may not see" do
      # A private upload sitting inside a shared folder.
      create(:stored_file, user: owner, family: family, visibility: "private",
             folder: root, name: "Secret.txt")

      paths = described_class.new(folder: root, user: viewer).entries.map(&:path)

      expect(paths).to include("Documents/Readme.txt")
      expect(paths).not_to include("Documents/Secret.txt")
    end

    it "skips trashed files and folders" do
      nested_file.trash!
      described_class.new(folder: root, user: owner).tap do |archiver|
        expect(archiver.entries.map(&:path)).to contain_exactly("Documents/Readme.txt")
      end
    end

    it "keeps empty folders so the structure survives" do
      empty = Folder.create!(user: owner, family: family, name: "Scans", parent: root)

      dirs = described_class.new(folder: root, user: owner).empty_directories

      expect(dirs).to include("Documents/#{empty.name}/")
    end

    it "de-duplicates identical names in the same folder" do
      create(:stored_file, :with_attachment, user: owner, family: family,
             visibility: "family", folder: root, name: "Readme.txt")

      paths = described_class.new(folder: root, user: owner).entries.map(&:path)

      expect(paths).to include("Documents/Readme.txt", "Documents/Readme (1).txt")
    end

    it "strips path separators from names so entries cannot escape the archive" do
      create(:stored_file, :with_attachment, user: owner, family: family,
             visibility: "family", folder: root, name: "../../etc/passwd")

      paths = described_class.new(folder: root, user: owner).entries.map(&:path)

      expect(paths.none? { |p| p.include?("..") }).to be true
    end
  end
end
