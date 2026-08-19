require "rails_helper"

RSpec.describe "Api::V1 trash" do
  let(:owner) { create(:user, storage_used: 0) }
  let!(:family) { create(:family, owner: owner, family_storage_used: 0) }
  let(:editor) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") } }
  let(:stranger) { create(:user) }

  describe "DELETE /api/v1/files/:id/purge" do
    let!(:file) { create(:stored_file, :with_attachment, user: owner, size: 500) }

    before { owner.update!(storage_used: 500) }

    it "refuses to purge a file that is not in the trash" do
      delete "/api/v1/files/#{file.id}/purge", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("not_trashed")
      expect(file.reload).to be_persisted
    end

    it "deletes a trashed file for good" do
      file.trash!

      expect {
        delete "/api/v1/files/#{file.id}/purge", headers: auth_headers_for(owner)
      }.to change(StoredFile, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "gives the storage back" do
      file.trash!

      expect {
        delete "/api/v1/files/#{file.id}/purge", headers: auth_headers_for(owner)
      }.to change { owner.reload.storage_used }.from(500).to(0)
    end

    it "gives family storage back for a shared file" do
      shared = create(:stored_file, :with_attachment, user: owner, family: family,
                      visibility: "family", size: 300)
      family.update!(family_storage_used: 300)
      shared.trash!

      expect {
        delete "/api/v1/files/#{shared.id}/purge", headers: auth_headers_for(owner)
      }.to change { family.reload.family_storage_used }.from(300).to(0)
    end

    it "releases the storage held by retained versions too" do
      file.trash!
      file.file_versions.create!(created_by: owner, version_number: 1, size: 200)
      owner.update!(storage_used: 700)

      expect {
        delete "/api/v1/files/#{file.id}/purge", headers: auth_headers_for(owner)
      }.to change { owner.reload.storage_used }.from(700).to(0)
    end

    it "refuses someone who cannot delete the file" do
      shared = create(:stored_file, user: owner, family: family, visibility: "family")
      shared.trash!

      delete "/api/v1/files/#{shared.id}/purge", headers: auth_headers_for(editor)

      expect(response).to have_http_status(:forbidden)
      expect(shared.reload).to be_persisted
    end
  end

  describe "POST /api/v1/files/:id/restore" do
    it "brings a file back" do
      file = create(:stored_file, :trashed, user: owner)

      post "/api/v1/files/#{file.id}/restore", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(file.reload).not_to be_trashed
    end

    it "returns a file to the root when its folder is still trashed" do
      folder = Folder.create!(user: owner, name: "Legal", trashed_at: Time.current)
      file = create(:stored_file, :trashed, user: owner, folder: folder)

      post "/api/v1/files/#{file.id}/restore", headers: auth_headers_for(owner)

      # Otherwise it would sit in a folder the user cannot navigate to.
      expect(file.reload.folder_id).to be_nil
      expect(file).not_to be_trashed
    end
  end

  describe "GET /api/v1/folders/trashed" do
    it "lists trashed folders with a purge date" do
      Folder.create!(user: owner, name: "Old Stuff", trashed_at: Time.current)

      get "/api/v1/folders/trashed", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json["folders"].first["name"]).to eq("Old Stuff")
      expect(json["folders"].first["purge_after"]).to be_present
    end

    it "does not list active folders" do
      Folder.create!(user: owner, name: "Current")

      get "/api/v1/folders/trashed", headers: auth_headers_for(owner)

      expect(json["folders"]).to be_empty
    end

    it "hides other people's trash" do
      Folder.create!(user: stranger, name: "Theirs", trashed_at: Time.current)

      get "/api/v1/folders/trashed", headers: auth_headers_for(owner)

      expect(json["folders"]).to be_empty
    end
  end

  describe "POST /api/v1/folders/:id/restore" do
    it "restores the folder and the files that went down with it" do
      folder = Folder.create!(user: owner, name: "Legal")
      file = create(:stored_file, user: owner, folder: folder)

      delete "/api/v1/folders/#{folder.id}", headers: auth_headers_for(owner)
      expect(file.reload).to be_trashed

      post "/api/v1/folders/#{folder.id}/restore", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(folder.reload.trashed_at).to be_nil
      expect(file.reload).not_to be_trashed
    end

    it "restores to the top level when the parent is still trashed" do
      parent = Folder.create!(user: owner, name: "Parent", trashed_at: Time.current)
      child = Folder.create!(user: owner, name: "Child", parent: parent, trashed_at: Time.current)

      post "/api/v1/folders/#{child.id}/restore", headers: auth_headers_for(owner)

      expect(child.reload.parent_id).to be_nil
      expect(child.trashed_at).to be_nil
    end

    it "404s for someone else's folder" do
      folder = Folder.create!(user: stranger, name: "Theirs", trashed_at: Time.current)

      post "/api/v1/folders/#{folder.id}/restore", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe PurgeTrashJob do
    it "removes files trashed longer ago than the retention window" do
      old = create(:stored_file, user: owner, size: 100, trashed_at: 31.days.ago)
      recent = create(:stored_file, user: owner, size: 100, trashed_at: 2.days.ago)
      active = create(:stored_file, user: owner, size: 100)
      owner.update!(storage_used: 300)

      expect { described_class.perform_now }.to change(StoredFile, :count).by(-1)

      expect { old.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(recent.reload).to be_persisted
      expect(active.reload).to be_persisted
    end

    it "reclaims the storage of everything it removes" do
      create(:stored_file, user: owner, size: 250, trashed_at: 40.days.ago)
      owner.update!(storage_used: 250)

      expect { described_class.perform_now }.to change { owner.reload.storage_used }.from(250).to(0)
    end

    it "keeps a trashed folder that still holds files" do
      folder = Folder.create!(user: owner, name: "Old", trashed_at: 40.days.ago)
      # Trashed recently, so it survives this run — the folder must survive too.
      create(:stored_file, user: owner, folder: folder, trashed_at: 1.day.ago)

      described_class.perform_now

      expect(folder.reload).to be_persisted
    end
  end
end
