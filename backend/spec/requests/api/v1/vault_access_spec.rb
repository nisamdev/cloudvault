require "rails_helper"

# Who in the family may reach the family's own things.
#
# Role says what somebody may *do* with a shared file. This says whether the
# shared half is open to them at all — the teenager trusted with the wifi
# password and not with the mortgage. It has nothing to do with anybody's
# private section.
RSpec.describe "Family vault access" do
  let(:family) { create(:family) }
  # The family factory brings its own owner and their membership with it.
  let(:owner) { family.owner }
  let(:owner_membership) { family.family_members.find_by(role: "owner") }
  let(:member) { create(:user) }
  let!(:membership) { create(:family_member, family: family, user: member, role: "editor") }

  let!(:shared_record) do
    create(:vault_record, user: owner, family: family, visibility: "family",
                          record_type: "document", title: "Door codes")
  end
  let!(:shared_file) do
    create(:stored_file, user: owner, family: family, visibility: "family", name: "Notes.txt")
  end

  def shut_out!
    patch "/api/v1/families/#{family.id}/members/#{membership.id}",
          params: { can_use_vault: false }, headers: auth_headers_for(owner), as: :json
  end

  describe "by default" do
    # A viewer whose whole role is to look must be able to look. The switch is
    # a door, not a rank.
    it "is open to everybody, whatever their role" do
      membership.update!(role: "viewer")

      expect(RecordPermissions.can_view?(member, shared_record)).to be(true)
      expect(PermissionChecker.can_view?(member, shared_file)).to be(true)
    end
  end

  describe "once the owner shuts somebody out" do
    before { shut_out! }

    it "closes the family's records to them" do
      expect(RecordPermissions.can_view?(member, shared_record)).to be(false)
    end

    it "closes the family's files to them" do
      expect(PermissionChecker.can_view?(member, shared_file)).to be(false)
    end

    # A permission check that disagrees with the list beside it is the whole
    # bug: a shut door that still shows what is behind it.
    it "keeps them out of the listings too, not only the checks" do
      get "/api/v1/records", headers: auth_headers_for(member)
      expect(json["records"].map { |r| r["id"] }).not_to include(shared_record.id)

      get "/api/v1/files", headers: auth_headers_for(member)
      expect(json["files"].map { |f| f["id"] }).not_to include(shared_file.id)
    end

    it "stops writing to them about dates on records they cannot open" do
      shared_record.update!(record_type: "passport",
                            data: { "expires_on" => 20.days.from_now.to_date.iso8601 })

      due = UpcomingExpiries.for_user(member)

      expect(due.map { |d| d.record.id }).not_to include(shared_record.id)
    end

    it "leaves their own records alone" do
      mine = create(:vault_record, user: member, family: family, visibility: "private")

      expect(RecordPermissions.can_view?(member, mine)).to be(true)
    end

    # Being shut out of the shared vault is not the same as being shut out of
    # what was handed to you by name.
    it "still honours a grant made to them personally" do
      AccessGrant.create!(resource: shared_file, subject: member, role: "viewer",
                          granted_by: owner)

      expect(PermissionChecker.can_view?(member, shared_file)).to be(true)
    end

    # What somebody put into the family stays in it. They shared it
    # deliberately, and withdrawing their *access* is not the same as
    # retracting their *contribution* — the same reasoning that keeps a
    # departing member's scanned passports where they are.
    it "leaves what they already shared where it is" do
      theirs = create(:stored_file, user: member, family: family, visibility: "family")

      expect(PermissionChecker.can_view?(owner, theirs)).to be(true)
    end

    it "leaves them able to see the thing they shared, because they own it" do
      theirs = create(:stored_file, user: member, family: family, visibility: "family")

      expect(PermissionChecker.can_view?(member, theirs)).to be(true)
    end

    # A one-way door: nothing more goes in either.
    it "stops them sharing anything new with the family" do
      expect(PermissionChecker.can_upload_to_family?(member, family)).to be(false)
    end

    # Shutting the door is not removing somebody. Remove is its own button.
    it "leaves them in the family" do
      expect(family.family_members.exists?(user_id: member.id)).to be(true)
    end

    # Otherwise every family screen is silently empty and nothing says why.
    it "tells their own session that the family is shut to them" do
      post "/api/v1/auth/login", params: { email: member.email, password: "password123" },
           as: :json

      expect(json.dig("family", "can_use_vault")).to be(false)
    end

    it "opens again when the owner says so" do
      patch "/api/v1/families/#{family.id}/members/#{membership.id}",
            params: { can_use_vault: true }, headers: auth_headers_for(owner), as: :json

      expect(RecordPermissions.can_view?(member, shared_record)).to be(true)
    end
  end

  describe "the switch itself" do
    it "is reported with every member" do
      get "/api/v1/families/#{family.id}", headers: auth_headers_for(owner)

      row = json["members"].find { |m| m["id"] == membership.id }
      expect(row["can_use_vault"]).to be(true)
      expect(row["vault_access_decided"]).to be(false)
    end

    it "remembers that a decision was made" do
      shut_out!

      expect(json.dig("member", "can_use_vault")).to be(false)
      expect(json.dig("member", "vault_access_decided")).to be(true)
    end

    it "keeps the owner's reason for turning it off" do
      patch "/api/v1/families/#{family.id}/members/#{membership.id}",
            params: { can_use_vault: false, vault_note: "Until they finish their exams" },
            headers: auth_headers_for(owner), as: :json

      expect(json.dig("member", "vault_note")).to eq("Until they finish their exams")
    end

    # Somebody has to be able to open the door again.
    it "will not shut the owner out" do
      patch "/api/v1/families/#{family.id}/members/#{owner_membership.id}",
            params: { can_use_vault: false }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(owner_membership.reload.can_use_vault?).to be(true)
    end

    it "is not somebody else's to change" do
      patch "/api/v1/families/#{family.id}/members/#{membership.id}",
            params: { can_use_vault: false }, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
