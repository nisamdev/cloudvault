require "rails_helper"

RSpec.describe FileVisibilityUpdater do
  let(:owner) { create(:user) }
  let(:family) { create(:family, owner: owner, family_storage_used: 0) }
  let(:viewer) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "viewer") } }
  let(:file) { create(:stored_file, user: owner, visibility: "private", size: 500) }

  describe "private -> family" do
    it "attaches the file to the family and makes it visible" do
      family
      described_class.new(file: file, user: owner).call("family")

      expect(file.reload.visibility).to eq("family")
      expect(file.family_id).to eq(family.id)
    end

    it "moves the bytes onto the family's quota" do
      family

      expect {
        described_class.new(file: file, user: owner).call("family")
      }.to change { family.reload.family_storage_used }.by(500)
    end

    it "makes the file visible to other members" do
      viewer # create the family and the membership before sharing
      described_class.new(file: file, user: owner).call("family")

      expect(PermissionChecker.can_view?(viewer, file.reload)).to be true
    end

    it "refuses a user who belongs to no family" do
      loner = create(:user)
      their_file = create(:stored_file, user: loner, visibility: "private")

      expect {
        described_class.new(file: their_file, user: loner).call("family")
      }.to raise_error(described_class::Forbidden, /don't belong to a family/)
    end

    it "refuses a viewer" do
      viewer_file = create(:stored_file, user: viewer, visibility: "private")

      expect {
        described_class.new(file: viewer_file, user: viewer).call("family")
      }.to raise_error(described_class::Forbidden, /permission/)
    end

    it "refuses when the family has no room" do
      family.update!(family_storage_used: family.family_storage_quota)

      expect {
        described_class.new(file: file, user: owner).call("family")
      }.to raise_error(described_class::QuotaExceeded)
    end
  end

  describe "family -> private" do
    let(:shared) { create(:stored_file, user: owner, family: family, visibility: "family", size: 500) }

    it "detaches the file and hides it from the family" do
      shared
      described_class.new(file: shared, user: owner).call("private")

      expect(shared.reload.visibility).to eq("private")
      expect(shared.family_id).to be_nil
      expect(PermissionChecker.can_view?(viewer, shared)).to be false
    end

    it "releases the family's storage" do
      family.update!(family_storage_used: 500)
      shared

      expect {
        described_class.new(file: shared, user: owner).call("private")
      }.to change { family.reload.family_storage_used }.by(-500)
    end
  end

  it "is a no-op when the visibility is unchanged" do
    expect {
      described_class.new(file: file, user: owner).call("private")
    }.not_to change { file.reload.updated_at }
  end

  it "rejects an unknown visibility" do
    expect {
      described_class.new(file: file, user: owner).call("public")
    }.to raise_error(described_class::Error)
  end
end
