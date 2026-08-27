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

# Deciding who can see a file is the owner's call, not an editing right.
# Family visibility already lets every member change what is *in* a file; it
# does not make somebody else's file theirs to publish or to keep.
RSpec.describe FileVisibilityUpdater, "whose decision it is" do
  let(:family) { create(:family) }
  let(:owner) { family.owner }
  let(:member) { create(:user) }
  let!(:membership) { create(:family_member, family: family, user: member, role: "editor") }

  let(:theirs) do
    create(:stored_file, user: member, family: family, visibility: "family", name: "Holiday.jpg")
  end
  let(:their_private) do
    create(:stored_file, user: member, family: nil, visibility: "private", name: "Diary.pdf")
  end

  it "will not let one member publish another's private file" do
    expect { described_class.new(file: their_private, user: owner).call("family") }
      .to raise_error(FileVisibilityUpdater::Forbidden, /Only whoever uploaded/)
  end

  # A household has to be able to take down something it should not be holding.
  it "lets somebody who runs the family take a file back out of it" do
    described_class.new(file: theirs, user: owner).call("private")

    expect(theirs.reload.visibility).to eq("private")
    expect(theirs.family_id).to be_nil
  end

  # This is the part that read as "it disappeared": unsharing does not take
  # possession, it returns the file to whoever put it there.
  it "returns it to the person who uploaded it, rather than keeping it" do
    described_class.new(file: theirs, user: owner).call("private")

    expect(theirs.reload.user_id).to eq(member.id)
    expect(PermissionChecker.can_view?(member, theirs)).to be(true)
    expect(PermissionChecker.can_view?(owner, theirs)).to be(false)
  end

  it "will not let an ordinary member unshare somebody else's file" do
    other = create(:user)
    create(:family_member, family: family, user: other, role: "editor")

    expect { described_class.new(file: theirs, user: other).call("private") }
      .to raise_error(FileVisibilityUpdater::Forbidden, /or a family admin/)
  end

  it "still lets people share and unshare their own" do
    described_class.new(file: their_private, user: member).call("family")
    expect(their_private.reload.visibility).to eq("family")

    described_class.new(file: their_private, user: member).call("private")
    expect(their_private.reload.visibility).to eq("private")
  end
end
