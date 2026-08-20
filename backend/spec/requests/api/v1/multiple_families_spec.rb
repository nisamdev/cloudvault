require "rails_helper"

RSpec.describe "Api::V1 belonging to several families" do
  let(:user) { create(:user) }

  describe "POST /api/v1/families" do
    it "lets an account with no family make one" do
      post "/api/v1/families", params: { name: "The Smiths" }, headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:created)
      expect(user.reload.families.map(&:name)).to eq([ "The Smiths" ])
    end

    # The old rule. A family is a group you make when you want one, and wanting
    # a second is not an error.
    it "lets them make another" do
      2.times do |i|
        post "/api/v1/families", params: { name: "Family #{i}" }, headers: auth_headers_for(user), as: :json
        expect(response).to have_http_status(:created)
      end

      expect(user.reload.families.count).to eq(2)
    end

    it "shows the newly created one" do
      post "/api/v1/families", params: { name: "Tax Stuff" }, headers: auth_headers_for(user), as: :json

      expect(user.reload.current_family_id).to eq(Family.find_by(name: "Tax Stuff").id)
    end
  end

  describe "GET /api/v1/families" do
    it "lists them all and says which is showing" do
      first = create(:family, owner: user, name: "Home")
      create(:family, owner: user, name: "Parents")
      user.update!(current_family_id: first.id)

      get "/api/v1/families", headers: auth_headers_for(user)

      expect(json["families"].map { |f| f["name"] }).to contain_exactly("Home", "Parents")
      expect(json["current_family_id"]).to eq(first.id)
    end

    it "is empty for an account that has none" do
      get "/api/v1/families", headers: auth_headers_for(user)

      expect(json["families"]).to be_empty
      expect(json["current_family_id"]).to be_nil
    end
  end

  describe "POST /api/v1/families/:id/select" do
    it "switches which one the app shows" do
      create(:family, owner: user, name: "Home")
      other = create(:family, owner: create(:user), name: "In-laws")
      create(:family_member, family: other, user: user, role: "editor")

      post "/api/v1/families/#{other.id}/select", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(user.reload.current_family_id).to eq(other.id)
    end

    it "refuses a family they are not in" do
      other = create(:family, owner: create(:user))

      post "/api/v1/families/#{other.id}/select", headers: auth_headers_for(user)

      expect(response).to have_http_status(:not_found)
      expect(user.reload.current_family_id).to be_nil
    end
  end

  describe "DELETE /api/v1/families/:id/leave" do
    let(:family) { create(:family, owner: create(:user)) }

    before { create(:family_member, family: family, user: user, role: "editor") }

    it "leaves" do
      delete "/api/v1/families/#{family.id}/leave", headers: auth_headers_for(user)

      expect(response).to have_http_status(:no_content)
      expect(user.reload.families).to be_empty
    end

    # Their uploads belong to the family, not to their membership.
    it "leaves the files they put there behind" do
      file = create(:stored_file, user: user, family: family, visibility: "family")

      delete "/api/v1/families/#{family.id}/leave", headers: auth_headers_for(user)

      expect(file.reload).to be_persisted
    end

    it "stops showing a family they just left" do
      user.update!(current_family_id: family.id)

      delete "/api/v1/families/#{family.id}/leave", headers: auth_headers_for(user)

      expect(user.reload.current_family_id).to be_nil
    end

    it "will not let the owner walk away and leave it ownerless" do
      owned = create(:family, owner: user)

      delete "/api/v1/families/#{owned.id}/leave", headers: auth_headers_for(user)

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.families).to include(owned)
    end
  end

  # current_family_id only records what the app is showing. A family going away
  # must not be blocked by it.
  it "lets a family be deleted while somebody is looking at it" do
    family = create(:family, owner: user)
    user.update!(current_family_id: family.id)

    expect { family.destroy! }.not_to raise_error
    expect(user.reload.current_family_id).to be_nil
  end

  describe "an account with no family at all" do
    it "can still sign in and list its files" do
      create(:stored_file, user: user, visibility: "private", name: "Mine.pdf")

      get "/api/v1/files", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(json["files"].map { |f| f["name"] }).to eq([ "Mine.pdf" ])
    end

    it "sees nothing belonging to anybody else" do
      create(:stored_file, user: create(:user), visibility: "private")

      get "/api/v1/files", headers: auth_headers_for(user)

      expect(json["files"]).to be_empty
    end
  end
end
