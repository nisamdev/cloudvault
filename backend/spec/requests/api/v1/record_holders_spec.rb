require "rails_helper"

# Whose a record is. A passport belongs to a person; a boiler contract belongs
# to nobody in particular, and both must be sayable.
RSpec.describe "Api::V1::Records holders" do
  let(:family) { create(:family) }
  let(:owner) { create(:user) }
  let!(:membership) { create(:family_member, family: family, user: owner, role: "admin") }

  let!(:child) do
    create(:vault_record, user: owner, family: family, record_type: "person",
                          title: "Ihaan Smith", data: { "full_name" => "Ihaan Smith" })
  end

  def create_passport(**params)
    post "/api/v1/records",
         params: { record: { record_type: "passport", title: "A passport", data: {} } }.merge(params),
         headers: auth_headers_for(owner), as: :json
    json["record"]
  end

  it "files a document under the person who holds it" do
    record = create_passport(held_by_id: child.id)

    expect(record["held_by"]).to eq("id" => child.id, "name" => "Ihaan Smith")
  end

  # A child holds a passport years before they hold a login, so the holder is a
  # person in the register rather than an account.
  it "does not need that person to have an account" do
    expect(User.find_by(email: nil)).to be_nil
    record = create_passport(held_by_id: child.id)

    expect(VaultRecord.find(record["id"]).held_by.title).to eq("Ihaan Smith")
  end

  it "leaves it unassigned when nobody is named" do
    expect(create_passport["held_by"]).to be_nil
  end

  it "hands it to somebody else when asked" do
    other = create(:vault_record, user: owner, family: family, record_type: "person",
                                  title: "Aisha Smith", data: {})
    record = create_passport(held_by_id: child.id)

    patch "/api/v1/records/#{record['id']}", params: { held_by_id: other.id },
          headers: auth_headers_for(owner), as: :json

    expect(json.dig("record", "held_by", "name")).to eq("Aisha Smith")
    expect(VaultRecord.find(record["id"]).record_links.count).to eq(1)
  end

  it "lets go of it without deleting anything" do
    record = create_passport(held_by_id: child.id)

    patch "/api/v1/records/#{record['id']}", params: { held_by_id: "" },
          headers: auth_headers_for(owner), as: :json

    expect(json.dig("record", "held_by")).to be_nil
    expect(VaultRecord.find(record["id"])).to be_present
  end

  it "ignores a holder that is not a person" do
    car = create(:vault_record, user: owner, family: family, record_type: "vehicle", data: {})

    expect(create_passport(held_by_id: car.id)["held_by"]).to be_nil
  end

  it "ignores somebody else's person" do
    stranger = create(:user)
    theirs = create(:vault_record, user: stranger, record_type: "person", data: {})

    expect(create_passport(held_by_id: theirs.id)["held_by"]).to be_nil
  end

  # Rewriting the "related to" links must not quietly drop whose it is: they
  # share a table and only one of them is on screen at a time.
  it "keeps the holder when the other links are rewritten" do
    note = create(:vault_record, user: owner, family: family, record_type: "document", data: {})
    record = create_passport(held_by_id: child.id)

    patch "/api/v1/records/#{record['id']}",
          params: { links: [ { linked_record_id: note.id, relation: "related_to" } ] },
          headers: auth_headers_for(owner), as: :json

    expect(json.dig("record", "held_by", "name")).to eq("Ihaan Smith")
  end

  describe "which half of the cabinet each kind lives in" do
    it "puts a person's documents with the people" do
      get "/api/v1/record_templates", headers: auth_headers_for(owner)

      by_group = json["templates"].group_by { |t| t["group"] }
      expect(by_group["people"].map { |t| t["type"] })
        .to contain_exactly("passport", "driving_licence", "birth_certificate", "health_card",
                            "immigration", "document", "person")
      expect(by_group["household"].map { |t| t["type"] })
        .to contain_exactly("login", "service_account", "property", "vehicle", "money",
                            "subscription", "emergency")
    end

    # Two kinds drawn with the same glyph defeat the point of drawing them.
    it "gives every kind an icon of its own" do
      get "/api/v1/record_templates", headers: auth_headers_for(owner)

      icons = json["templates"].map { |t| t["icon"] }
      expect(icons.uniq.size).to eq(icons.size)
    end
  end
end
