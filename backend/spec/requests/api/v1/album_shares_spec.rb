require "rails_helper"

# Sharing a photograph at a time is not how anybody shares a holiday.
RSpec.describe "Api::V1 sharing an album" do
  let(:family) { create(:family) }
  let(:owner) { family.owner }
  let!(:membership) { create(:family_member, family: family, user: create(:user), role: "editor") }
  let(:relative) { membership.user }

  let(:album) { create(:folder, user: owner, kind: "photo", name: "Cornwall") }
  let!(:photo) do
    file = create(:stored_file, user: owner, file_type: "image", mime_type: "image/jpeg",
                                folder_id: album.id, name: "Beach.jpg", visibility: "private")
    file.attachment.attach(io: StringIO.new("jpeg bytes"), filename: "Beach.jpg",
                           content_type: "image/jpeg")
    file
  end

  describe "with the family" do
    # One grant on the album carries down to every photograph in it, in the
    # permission check and in the listing alike.
    it "opens the whole album with a single grant" do
      expect(PermissionChecker.can_view?(relative, photo)).to be(false)

      post "/api/v1/folders/#{album.id}/grants",
           params: { family_id: family.id, role: "viewer" },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(PermissionChecker.can_view?(relative, photo.reload)).to be(true)
    end

    it "covers a photograph added afterwards" do
      post "/api/v1/folders/#{album.id}/grants",
           params: { family_id: family.id, role: "viewer" },
           headers: auth_headers_for(owner), as: :json
      later = create(:stored_file, user: owner, file_type: "image", mime_type: "image/jpeg",
                                   folder_id: album.id, visibility: "private")

      expect(PermissionChecker.can_view?(relative, later)).to be(true)
    end

    it "takes it all back when the grant goes" do
      post "/api/v1/folders/#{album.id}/grants",
           params: { family_id: family.id, role: "viewer" },
           headers: auth_headers_for(owner), as: :json
      grant_id = json.dig("grant", "id")

      delete "/api/v1/grants/#{grant_id}", headers: auth_headers_for(owner)

      expect(PermissionChecker.can_view?(relative, photo.reload)).to be(false)
    end
  end

  describe "with anybody, on a link" do
    def share(**params)
      post "/api/v1/folders/#{album.id}/shares", params: { expires_in: "7d" }.merge(params),
           headers: auth_headers_for(owner), as: :json
      json.dig("share", "url").to_s.split("/").last
    end

    it "shows the album and what is in it, without signing in" do
      token = share

      get "/api/v1/shares/#{token}"

      expect(json.dig("share", "kind")).to eq("album")
      expect(json.dig("share", "album", "name")).to eq("Cornwall")
      expect(json.dig("share", "album", "photos").map { |p| p["name"] }).to eq([ "Beach.jpg" ])
    end

    it "hands over a photograph from it" do
      token = share

      post "/api/v1/shares/#{token}/download", params: { file_id: photo.id }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["url"]).to be_present
    end

    # Otherwise a link to one album is a way to read the whole vault.
    it "refuses a photograph from somewhere else" do
      elsewhere = create(:stored_file, user: owner, file_type: "image", mime_type: "image/jpeg")
      token = share

      post "/api/v1/shares/#{token}/download", params: { file_id: elsewhere.id }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "stops when the album is thrown away" do
      token = share
      album.update!(trashed_at: Time.current)

      get "/api/v1/shares/#{token}"

      expect(response).to have_http_status(:not_found)
    end

    it "stops when it is revoked" do
      token = share
      SharedLink.last.revoke!

      get "/api/v1/shares/#{token}"

      expect(response).to have_http_status(:not_found)
    end

    it "is not somebody else's album to share" do
      post "/api/v1/folders/#{album.id}/shares", headers: auth_headers_for(relative), as: :json

      expect(response).to have_http_status(:not_found).or have_http_status(:forbidden)
    end

    it "appears in the list of links I have out" do
      share

      get "/api/v1/shares", headers: auth_headers_for(owner)

      expect(json["shares"].first.dig("album", "name")).to eq("Cornwall")
    end
  end

  # A link points at exactly one thing, and there are three kinds now.
  it "will not point at two things at once" do
    expect {
      SharedLink.create!(user: owner, folder: album, stored_file: photo)
    }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
