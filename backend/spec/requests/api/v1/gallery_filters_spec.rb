require "rails_helper"

RSpec.describe "Api::V1::Files gallery filters" do
  let(:owner) { create(:user) }
  let!(:family) { create(:family, owner: owner) }
  let(:member) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") } }

  def photo(name:, **attrs)
    create(:stored_file, :image, user: owner, name: name, **attrs)
  end

  let!(:today_wide) { photo(name: "Wide.png", image_width: 400, image_height: 200) }
  let!(:old_tall) do
    photo(name: "Tall.png", image_width: 200, image_height: 400, created_at: 40.days.ago)
  end
  let!(:square_shared) do
    photo(name: "Square.png", image_width: 300, image_height: 300,
          family: family, visibility: "family")
  end

  def names
    json["files"].map { |f| f["name"] }
  end

  def get_photos(params = {})
    get "/api/v1/files", params: { file_type: "image" }.merge(params), headers: auth_headers_for(owner)
  end

  describe "orientation" do
    it "filters to landscape" do
      get_photos(orientation: "landscape")
      expect(names).to contain_exactly("Wide.png")
    end

    it "filters to portrait" do
      get_photos(orientation: "portrait")
      expect(names).to contain_exactly("Tall.png")
    end

    it "filters to square" do
      get_photos(orientation: "square")
      expect(names).to contain_exactly("Square.png")
    end

    it "leaves out images whose dimensions are not known yet" do
      photo(name: "Unprocessed.png", image_width: nil, image_height: nil)

      get_photos(orientation: "square")

      expect(names).not_to include("Unprocessed.png")
    end

    it "ignores an unknown value rather than returning nothing" do
      get_photos(orientation: "diagonal")
      expect(names.size).to eq(3)
    end
  end

  describe "date range" do
    it "filters from a date" do
      get_photos(date_from: 7.days.ago.to_date.to_s)
      expect(names).to contain_exactly("Wide.png", "Square.png")
    end

    it "filters to a date" do
      get_photos(date_to: 7.days.ago.to_date.to_s)
      expect(names).to contain_exactly("Tall.png")
    end

    it "includes items uploaded on the boundary day" do
      edge = photo(name: "Edge.png", created_at: 10.days.ago.change(hour: 23, min: 30))

      get_photos(date_to: 10.days.ago.to_date.to_s)

      # end_of_day, or anything uploaded that afternoon would vanish.
      expect(names).to include(edge.name)
    end

    it "ignores a malformed date instead of erroring" do
      get_photos(date_from: "yesterday-ish")

      expect(response).to have_http_status(:ok)
      expect(names.size).to eq(3)
    end
  end

  describe "visibility" do
    it "filters to family photos" do
      get_photos(visibility: "family")
      expect(names).to contain_exactly("Square.png")
    end

    it "filters to private photos" do
      get_photos(visibility: "private")
      expect(names).to contain_exactly("Wide.png", "Tall.png")
    end
  end

  describe "owner" do
    it "filters by who uploaded it" do
      theirs = create(:stored_file, :image, user: member, family: family,
                      visibility: "family", name: "Theirs.png")

      get_photos(owner_id: member.id)

      expect(names).to contain_exactly(theirs.name)
    end

    it "returns nothing for an unknown owner" do
      get_photos(owner_id: 999_999)
      expect(names).to be_empty
    end
  end

  describe "sorting" do
    it "defaults to newest first" do
      get_photos
      expect(names.last).to eq("Tall.png")
    end

    it "sorts oldest first" do
      get_photos(sort: "oldest")
      expect(names.first).to eq("Tall.png")
    end

    it "sorts by name case-insensitively" do
      photo(name: "apple.png")

      get_photos(sort: "name")

      expect(names.first).to eq("apple.png")
    end

    it "sorts by size" do
      big = photo(name: "Big.png", size: 9_000_000)

      get_photos(sort: "largest")

      expect(names.first).to eq(big.name)
    end

    it "falls back to newest for an unknown sort" do
      get_photos(sort: "sideways")
      expect(names.last).to eq("Tall.png")
    end
  end

  describe "combining filters" do
    it "applies them together" do
      get_photos(visibility: "private", orientation: "landscape")
      expect(names).to contain_exactly("Wide.png")
    end

    it "still respects what the caller may see" do
      stranger = create(:user)
      create(:stored_file, :image, user: stranger, name: "Secret.png",
             image_width: 400, image_height: 200)

      get_photos(orientation: "landscape")

      expect(names).not_to include("Secret.png")
    end
  end
end
