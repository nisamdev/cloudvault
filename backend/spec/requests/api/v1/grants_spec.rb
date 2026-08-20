require "rails_helper"

RSpec.describe "Api::V1::Grants" do
  let(:owner) { create(:user) }
  let!(:family) { create(:family, owner: owner) }
  let(:accountant) { create(:user, email: "accountant@example.com", full_name: "The Accountant") }
  let(:viewer) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "viewer") } }
  let(:file) { create(:stored_file, user: owner, visibility: "private", name: "Passport.pdf") }

  describe "POST /api/v1/files/:file_id/grants" do
    it "shares a private file with one person by email" do
      post "/api/v1/files/#{file.id}/grants",
           params: { email: accountant.email, role: "viewer" },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json["grant"]["subject"]).to include("type" => "user", "name" => "The Accountant")
      expect(PermissionChecker.can_view?(accountant, file)).to be true
    end

    it "shares with a whole family" do
      post "/api/v1/files/#{file.id}/grants",
           params: { family_id: family.id, role: "viewer" },
           headers: auth_headers_for(owner), as: :json

      expect(json["grant"]["subject"]["type"]).to eq("family")
      expect(PermissionChecker.can_view?(viewer, file)).to be true
    end

    it "changes the role instead of stacking a second grant" do
      2.times do |i|
        post "/api/v1/files/#{file.id}/grants",
             params: { email: accountant.email, role: i.zero? ? "viewer" : "editor" },
             headers: auth_headers_for(owner), as: :json
      end

      expect(AccessGrant.where(resource: file).count).to eq(1)
      expect(AccessGrant.last.role).to eq("editor")
    end

    it "can be given an expiry" do
      post "/api/v1/files/#{file.id}/grants",
           params: { email: accountant.email, expires_at: 3.days.from_now },
           headers: auth_headers_for(owner), as: :json

      expect(json["grant"]["expires_at"]).to be_present
    end

    # A grant needs somebody to point at; inviting a stranger into the vault is
    # a heavier decision than sharing a file.
    it "will not invent an account for an unknown address" do
      post "/api/v1/files/#{file.id}/grants",
           params: { email: "nobody@example.com" },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:not_found)
      expect(json["error"]["code"]).to eq("user_not_found")
    end

    it "refuses a nonsense role" do
      post "/api/v1/files/#{file.id}/grants",
           params: { email: accountant.email, role: "admin" },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "does not let somebody share a file that is not theirs" do
      post "/api/v1/files/#{file.id}/grants",
           params: { email: viewer.email },
           headers: auth_headers_for(accountant), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    # Access must not spread without the owner.
    it "does not let a grantee pass their access on" do
      AccessGrant.create!(resource: file, subject: accountant, role: "editor", granted_by: owner)

      post "/api/v1/files/#{file.id}/grants",
           params: { email: viewer.email },
           headers: auth_headers_for(accountant), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "sharing a folder" do
    let(:folder) { create(:folder, user: owner, name: "Tax 2026") }

    it "reaches the files inside it" do
      inside = create(:stored_file, user: owner, folder: folder, visibility: "private")

      post "/api/v1/folders/#{folder.id}/grants",
           params: { email: accountant.email },
           headers: auth_headers_for(owner), as: :json

      get "/api/v1/files", params: { folder_id: folder.id }, headers: auth_headers_for(accountant)
      expect(json["files"].map { |f| f["id"] }).to include(inside.id)
    end
  end

  describe "GET /api/v1/files/:file_id/grants" do
    it "lists who it has been shared with" do
      AccessGrant.create!(resource: file, subject: accountant, role: "viewer", granted_by: owner)

      get "/api/v1/files/#{file.id}/grants", headers: auth_headers_for(owner)

      expect(json["grants"].size).to eq(1)
      expect(json["grants"].first["subject"]["email"]).to eq(accountant.email)
    end
  end

  describe "PATCH /api/v1/grants/:id" do
    it "changes the role" do
      grant = AccessGrant.create!(resource: file, subject: accountant, role: "viewer", granted_by: owner)

      patch "/api/v1/grants/#{grant.id}", params: { role: "editor" },
            headers: auth_headers_for(owner), as: :json

      expect(grant.reload.role).to eq("editor")
    end

    it "refuses anyone who cannot share the file" do
      grant = AccessGrant.create!(resource: file, subject: accountant, role: "viewer", granted_by: owner)

      patch "/api/v1/grants/#{grant.id}", params: { role: "editor" },
            headers: auth_headers_for(accountant), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(grant.reload.role).to eq("viewer")
    end
  end

  describe "DELETE /api/v1/grants/:id" do
    it "takes the access away" do
      grant = AccessGrant.create!(resource: file, subject: accountant, role: "viewer", granted_by: owner)

      delete "/api/v1/grants/#{grant.id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:no_content)
      expect(PermissionChecker.can_view?(accountant.reload, file)).to be false
    end
  end

  describe "what a grant shows up as" do
    it "appears in shared-with-me" do
      AccessGrant.create!(resource: file, subject: accountant, role: "viewer", granted_by: owner)

      get "/api/v1/files", params: { shared_with_me: "true" }, headers: auth_headers_for(accountant)

      expect(json["files"].map { |f| f["id"] }).to eq([ file.id ])
    end

    it "does not put my own files in my shared-with-me" do
      AccessGrant.create!(resource: file, subject: accountant, role: "viewer", granted_by: owner)

      get "/api/v1/files", params: { shared_with_me: "true" }, headers: auth_headers_for(owner)

      expect(json["files"]).to be_empty
    end
  end
end
