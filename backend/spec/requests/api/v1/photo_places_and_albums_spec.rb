require "rails_helper"

# Two things the gallery was missing: somewhere to say where a photograph was
# taken, and somewhere to put it.
RSpec.describe "Api::V1 photo places and albums" do
  let(:user) { create(:user) }

  def photo(**attrs)
    create(:stored_file, { user: user, file_type: "image", mime_type: "image/jpeg" }.merge(attrs))
  end

  describe "saying where a photograph was taken" do
    # One picture in eighty arrives with GPS still attached, so this is the only
    # way the gallery will ever know.
    it "records the place and its coordinates" do
      taken = photo(name: "Beach.jpg")

      patch "/api/v1/files/#{taken.id}",
            params: { place_name: "Edmonton", latitude: 53.5461, longitude: -113.4938 },
            headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("file", "image", "place_name")).to eq("Edmonton")
      expect(taken.reload.latitude.to_f).to be_within(0.001).of(53.5461)
    end

    it "lets the place be taken off again" do
      taken = photo(place_name: "Edmonton", latitude: 53.5, longitude: -113.4)

      patch "/api/v1/files/#{taken.id}", params: { place_name: "", latitude: nil, longitude: nil },
            headers: auth_headers_for(user), as: :json

      expect(taken.reload.place_name).to be_blank
      expect(taken.latitude).to be_nil
    end

    it "finds photographs by the name somebody gave the place" do
      photo(name: "A.jpg", place_name: "Edmonton, Alberta")
      photo(name: "B.jpg", place_name: "Cornwall")

      get "/api/v1/files", params: { file_type: "image", place: "edmonton" },
          headers: auth_headers_for(user)

      expect(json["files"].map { |f| f["name"] }).to eq([ "A.jpg" ])
    end

    it "matches part of a name, because nobody types the whole thing" do
      photo(name: "A.jpg", place_name: "Kulay Way SW, Edmonton")

      get "/api/v1/files", params: { file_type: "image", place: "kulay" },
          headers: auth_headers_for(user)

      expect(json["files"].size).to eq(1)
    end
  end

  describe "albums" do
    # A folder holding the mortgage and a folder called "Holidays" have no
    # business in the same tree.
    it "keeps albums out of the document folders" do
      get "/api/v1/folders", params: { kind: "photo" }, headers: auth_headers_for(user)
      album = json["folders"].first

      get "/api/v1/folders", headers: auth_headers_for(user)

      expect(json["folders"].map { |f| f["id"] }).not_to include(album["id"])
    end

    it "makes a default album the first time the gallery is opened" do
      expect {
        get "/api/v1/folders", params: { kind: "photo" }, headers: auth_headers_for(user)
      }.to change { Folder.of_kind("photo").count }.by(1)

      expect(json["folders"].first).to include("is_default" => true, "name" => "All photos")
    end

    it "does not make a second one" do
      2.times { get "/api/v1/folders", params: { kind: "photo" }, headers: auth_headers_for(user) }

      expect(Folder.of_kind("photo").where(user_id: user.id, is_default: true).count).to eq(1)
    end

    # Everything already in the gallery predates having anywhere to put it.
    it "takes in the photographs that were already there" do
      loose = photo(name: "Old.jpg", folder_id: nil)

      get "/api/v1/folders", params: { kind: "photo" }, headers: auth_headers_for(user)

      expect(loose.reload.folder_id).to eq(json["folders"].first["id"])
    end

    it "leaves documents where they are" do
      document = create(:stored_file, user: user, file_type: "file", folder_id: nil)

      get "/api/v1/folders", params: { kind: "photo" }, headers: auth_headers_for(user)

      expect(document.reload.folder_id).to be_nil
    end

    it "shows one album at a time" do
      get "/api/v1/folders", params: { kind: "photo" }, headers: auth_headers_for(user)
      default_id = json["folders"].first["id"]

      post "/api/v1/folders", params: { folder: { name: "Holidays", kind: "photo" } },
           headers: auth_headers_for(user), as: :json
      holidays = json.dig("folder", "id")

      here = photo(name: "Beach.jpg", folder_id: holidays)
      photo(name: "Elsewhere.jpg", folder_id: default_id)

      get "/api/v1/files", params: { file_type: "image", folder_id: holidays },
          headers: auth_headers_for(user)

      expect(json["files"].map { |f| f["id"] }).to eq([ here.id ])
    end
  end
end
