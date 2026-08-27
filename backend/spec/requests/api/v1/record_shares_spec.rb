require "rails_helper"

# A timed, read-only link to one record and the documents on it — for the
# landlord who wants to see a passport and should not keep the access.
RSpec.describe "Api::V1::Records shares" do
  let(:family) { create(:family) }
  let(:owner) { create(:user) }
  let!(:membership) { create(:family_member, family: family, user: owner, role: "admin") }

  let(:scan) do
    file = create(:stored_file, user: owner, family: family, name: "Passport scan.pdf",
                               mime_type: "application/pdf")
    file.attachment.attach(io: StringIO.new("%PDF-1.4 the scan"), filename: "Passport scan.pdf",
                           content_type: "application/pdf")
    file
  end

  let(:record) do
    create(:vault_record, user: owner, family: family, record_type: "passport",
                          title: "Aisha Rahman — Passport",
                          data: { "full_name" => "Aisha Rahman", "passport_number" => "L898902C3",
                                  "expires_on" => "2030-07-15" })
  end

  before { RecordAttachment.create!(vault_record: record, stored_file: scan, position: 0) }

  def create_link(user: owner, **params)
    post "/api/v1/records/#{record.id}/shares",
         params: { expires_in: "7d" }.merge(params),
         headers: auth_headers_for(user), as: :json
    json.dig("share", "url").to_s.split("/").last
  end

  describe "making one" do
    it "hands back a URL, exactly once" do
      post "/api/v1/records/#{record.id}/shares", params: { expires_in: "24h" },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("share", "url")).to include("/share/")
      expect(json.dig("share", "expires_at")).to be_present
    end

    it "refuses somebody who cannot even see the record" do
      stranger = create(:user)

      post "/api/v1/records/#{record.id}/shares", headers: auth_headers_for(stranger), as: :json

      expect(response).to have_http_status(:not_found)
    end

    # Sharing a record outward is a bigger decision than reading it, so it
    # takes the same standing as changing it.
    it "refuses a family member who may only read it" do
      viewer = create(:user)
      create(:family_member, family: family, user: viewer, role: "viewer")
      record.update!(visibility: "family")

      post "/api/v1/records/#{record.id}/shares", headers: auth_headers_for(viewer), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "lists the links already out on this record" do
      create_link
      get "/api/v1/records/#{record.id}/shares", headers: auth_headers_for(owner)

      expect(json["shares"].size).to eq(1)
      # Never the token, not even to the person who made it.
      expect(json["shares"].first).not_to have_key("url")
    end
  end

  describe "what the person holding the link sees" do
    it "shows the details and the documents, without signing in" do
      token = create_link

      get "/api/v1/shares/#{token}"

      expect(json.dig("share", "kind")).to eq("record")
      expect(json.dig("share", "record", "title")).to eq("Aisha Rahman — Passport")
      expect(json.dig("share", "record", "details").map { |d| d["label"] })
        .to include("Full name", "Passport number", "Expires")
      expect(json.dig("share", "record", "documents", 0, "name")).to eq("Passport scan.pdf")
    end

    # The whole point of a template: a field nobody filled in is not a blank
    # row on somebody else's screen.
    it "leaves out the fields that were never filled in" do
      token = create_link

      get "/api/v1/shares/#{token}"

      labels = json.dig("share", "record", "details").map { |d| d["label"] }
      expect(labels).not_to include("Place of birth", "Notes")
    end

    it "never carries a password down the link" do
      login = create(:vault_record, user: owner, family: family, record_type: "login",
                                    title: "Netflix", data: { "name" => "Netflix" })
      post "/api/v1/records/#{login.id}/shares", headers: auth_headers_for(owner), as: :json
      token = json.dig("share", "url").split("/").last

      get "/api/v1/shares/#{token}"

      expect(json.dig("share", "record", "details").map { |d| d["label"] }).not_to include("Password")
    end

    it "says nothing once the link is revoked" do
      token = create_link
      SharedLink.last.revoke!

      get "/api/v1/shares/#{token}"

      expect(response).to have_http_status(:not_found)
    end

    it "goes quiet when the record is archived" do
      token = create_link
      record.update!(archived_at: Time.current)

      get "/api/v1/shares/#{token}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "downloading a document from it" do
    it "hands over a document on the record" do
      token = create_link

      post "/api/v1/shares/#{token}/download", params: { file_id: scan.id }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["url"]).to be_present
      expect(SharedLink.last.download_count).to eq(1)
    end

    # Otherwise a link to one record is a way to read every file in the vault.
    it "refuses a file that is not on this record" do
      other = create(:stored_file, user: owner, family: family, name: "Bank statement.pdf")
      token = create_link

      post "/api/v1/shares/#{token}/download", params: { file_id: other.id }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "wants the password when one was set" do
      token = create_link(password: "the blue door")

      post "/api/v1/shares/#{token}/download", params: { file_id: scan.id }, as: :json
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/shares/#{token}/download",
           params: { file_id: scan.id, password: "the blue door" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "stops working once it has expired" do
      token = create_link
      SharedLink.last.update!(expires_at: 1.minute.ago)

      post "/api/v1/shares/#{token}/download", params: { file_id: scan.id }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  it "shows both kinds of link in one list" do
    create_link
    file = create(:stored_file, user: owner, family: family)
    post "/api/v1/files/#{file.id}/shares", headers: auth_headers_for(owner), as: :json

    get "/api/v1/shares", headers: auth_headers_for(owner)

    kinds = json["shares"].map { |share| share.key?("record") ? "record" : "file" }
    expect(kinds).to contain_exactly("record", "file")
  end

  # A link points at one thing. Two, or none, is a link nobody can follow.
  it "will not build a link to nothing" do
    expect { SharedLink.create!(user: owner) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
