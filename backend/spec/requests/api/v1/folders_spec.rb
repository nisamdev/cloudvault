require "rails_helper"

RSpec.describe "Api::V1::Folders" do
  let(:owner) { create(:user) }
  let!(:family) { create(:family, owner: owner) }
  let(:viewer) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "viewer") } }
  let(:stranger) { create(:user) }

  describe "POST /api/v1/folders" do
    it "creates a personal folder" do
      post "/api/v1/folders", params: { folder: { name: "Documents" } },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json["folder"]["name"]).to eq("Documents")
      expect(json["folder"]["shared"]).to be false
    end

    it "creates a shared folder when asked" do
      post "/api/v1/folders", params: { folder: { name: "Shared" }, shared: "true" },
           headers: auth_headers_for(owner), as: :json

      expect(json["folder"]["shared"]).to be true
    end

    it "inherits sharing from the parent" do
      post "/api/v1/folders", params: { folder: { name: "Top" }, shared: "true" },
           headers: auth_headers_for(owner), as: :json
      parent_id = json["folder"]["id"]

      post "/api/v1/folders", params: { folder: { name: "Child", parent_id: parent_id } },
           headers: auth_headers_for(owner), as: :json

      # A subfolder of a family folder must not be private, or its contents
      # would be invisible to the people who can see the parent.
      expect(json["folder"]["shared"]).to be true
    end

    it "refuses a viewer adding to a shared folder" do
      shared = Folder.create!(user: owner, family: family, name: "Family Docs")

      post "/api/v1/folders", params: { folder: { name: "Nope", parent_id: shared.id } },
           headers: auth_headers_for(viewer), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects a duplicate name in the same parent" do
      2.times do
        post "/api/v1/folders", params: { folder: { name: "Documents" } },
             headers: auth_headers_for(owner), as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/folders" do
    it "returns a nested tree" do
      top = Folder.create!(user: owner, name: "Documents")
      mid = Folder.create!(user: owner, name: "Legal", parent: top)
      Folder.create!(user: owner, name: "2026", parent: mid)

      get "/api/v1/folders", headers: auth_headers_for(owner)

      tree = json["tree"]
      expect(tree.map { |f| f["name"] }).to eq([ "Documents" ])
      expect(tree.first["children"].first["name"]).to eq("Legal")
      expect(tree.first["children"].first["children"].first["name"]).to eq("2026")
    end

    it "shows family folders to members and hides personal ones" do
      Folder.create!(user: owner, family: family, name: "Family Docs")
      Folder.create!(user: owner, name: "Dad's Private")

      get "/api/v1/folders", headers: auth_headers_for(viewer)

      expect(json["folders"].map { |f| f["name"] }).to contain_exactly("Family Docs")
    end

    it "shows a non-member nothing" do
      Folder.create!(user: owner, family: family, name: "Family Docs")

      get "/api/v1/folders", headers: auth_headers_for(stranger)

      expect(json["folders"]).to be_empty
    end

    it "counts the files in each folder" do
      folder = Folder.create!(user: owner, name: "Documents")
      create(:stored_file, user: owner, folder: folder)
      create(:stored_file, :trashed, user: owner, folder: folder)

      get "/api/v1/folders", headers: auth_headers_for(owner)

      # Trashed files must not inflate the count.
      expect(json["folders"].first["file_count"]).to eq(1)
    end
  end

  describe "GET /api/v1/folders/:id" do
    it "returns breadcrumbs from the root down" do
      top = Folder.create!(user: owner, name: "Documents")
      mid = Folder.create!(user: owner, name: "Legal", parent: top)
      leaf = Folder.create!(user: owner, name: "2026", parent: mid)

      get "/api/v1/folders/#{leaf.id}", headers: auth_headers_for(owner)

      expect(json["breadcrumbs"].map { |b| b["name"] }).to eq(%w[Documents Legal])
    end

    it "404s for someone else's folder" do
      folder = Folder.create!(user: owner, name: "Private")

      get "/api/v1/folders/#{folder.id}", headers: auth_headers_for(stranger)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/folders/:id" do
    it "renames a folder" do
      folder = Folder.create!(user: owner, name: "Old")

      patch "/api/v1/folders/#{folder.id}", params: { folder: { name: "New" } },
            headers: auth_headers_for(owner), as: :json

      expect(folder.reload.name).to eq("New")
    end

    it "moves a folder under another parent" do
      a = Folder.create!(user: owner, name: "A")
      b = Folder.create!(user: owner, name: "B")

      patch "/api/v1/folders/#{b.id}", params: { folder: { parent_id: a.id } },
            headers: auth_headers_for(owner), as: :json

      expect(b.reload.parent_id).to eq(a.id)
    end

    it "refuses to move a folder inside its own descendant" do
      top = Folder.create!(user: owner, name: "Top")
      child = Folder.create!(user: owner, name: "Child", parent: top)

      patch "/api/v1/folders/#{top.id}", params: { folder: { parent_id: child.id } },
            headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(top.reload.parent_id).to be_nil
    end

    it "refuses to make a folder its own parent" do
      folder = Folder.create!(user: owner, name: "Self")

      patch "/api/v1/folders/#{folder.id}", params: { folder: { parent_id: folder.id } },
            headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/v1/folders/:id" do
    it "trashes the folder, its subfolders and their files together" do
      top = Folder.create!(user: owner, name: "Top")
      child = Folder.create!(user: owner, name: "Child", parent: top)
      file = create(:stored_file, user: owner, folder: child)

      delete "/api/v1/folders/#{top.id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:no_content)
      expect(top.reload.trashed_at).to be_present
      expect(child.reload.trashed_at).to be_present
      # Otherwise the file would be stranded in a folder nobody can navigate to.
      expect(file.reload).to be_trashed
    end

    it "leaves files in other folders alone" do
      top = Folder.create!(user: owner, name: "Top")
      other = Folder.create!(user: owner, name: "Other")
      safe = create(:stored_file, user: owner, folder: other)

      delete "/api/v1/folders/#{top.id}", headers: auth_headers_for(owner)

      expect(safe.reload).not_to be_trashed
    end
  end
end
