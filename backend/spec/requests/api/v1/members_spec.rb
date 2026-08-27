require "rails_helper"

RSpec.describe "Api::V1::Members" do
  let(:owner) { create(:user) }
  let!(:family) { create(:family, owner: owner) }
  let(:admin) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "admin") } }
  let(:editor) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") } }
  let(:teen) { create(:family_member, family: family, user: create(:user), role: "viewer") }

  describe "PATCH /api/v1/families/:family_id/members/:id" do
    it "changes a role" do
      patch "/api/v1/families/#{family.id}/members/#{teen.id}",
            params: { role: "editor" }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(teen.reload.role).to eq("editor")
    end

    it "lets an admin do it too" do
      patch "/api/v1/families/#{family.id}/members/#{teen.id}",
            params: { role: "editor" }, headers: auth_headers_for(admin), as: :json

      expect(teen.reload.role).to eq("editor")
    end

    it "refuses an editor, who is not an admin" do
      patch "/api/v1/families/#{family.id}/members/#{teen.id}",
            params: { role: "admin" }, headers: auth_headers_for(editor), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(teen.reload.role).to eq("viewer")
    end

    it "refuses somebody outside the family" do
      patch "/api/v1/families/#{family.id}/members/#{teen.id}",
            params: { role: "admin" }, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a role that does not exist" do
      patch "/api/v1/families/#{family.id}/members/#{teen.id}",
            params: { role: "superuser" }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(teen.reload.role).to eq("viewer")
    end

    # Ownership decides whose family it is; the model allows exactly one, and
    # handing it over is not a dropdown on a settings page.
    it "will not grant ownership" do
      patch "/api/v1/families/#{family.id}/members/#{teen.id}",
            params: { role: "owner" }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(family.family_members.where(role: "owner").count).to eq(1)
    end

    it "will not demote the owner" do
      owner_member = family.family_members.find_by(user_id: owner.id)

      patch "/api/v1/families/#{family.id}/members/#{owner_member.id}",
            params: { role: "editor" }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(owner_member.reload.role).to eq("owner")
    end
  end

  describe "DELETE /api/v1/families/:family_id/members/:id" do
    it "removes a member, and says what the family kept" do
      delete "/api/v1/families/#{family.id}/members/#{teen.id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json["kept"]).to include("files" => 0, "records" => 0, "folders" => 0)
      expect(FamilyMember.exists?(teen.id)).to be false
    end

    # Removing a person should not destroy the passports they scanned.
    it "leaves the files they uploaded in the vault" do
      file = create(:stored_file, user: teen.user, family: family, visibility: "family")

      delete "/api/v1/families/#{family.id}/members/#{teen.id}", headers: auth_headers_for(owner)

      expect(file.reload).to be_persisted
      expect(file.trashed_at).to be_nil
    end

    it "will not remove the owner" do
      owner_member = family.family_members.find_by(user_id: owner.id)

      delete "/api/v1/families/#{family.id}/members/#{owner_member.id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:unprocessable_content)
      expect(owner_member.reload).to be_persisted
    end

    it "refuses an editor" do
      delete "/api/v1/families/#{family.id}/members/#{teen.id}", headers: auth_headers_for(editor)

      expect(response).to have_http_status(:forbidden)
      expect(FamilyMember.exists?(teen.id)).to be true
    end
  end
end
