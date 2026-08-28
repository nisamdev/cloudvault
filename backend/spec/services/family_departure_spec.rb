require "rails_helper"

# What somebody takes with them when they are removed from a family.
#
# The rule in one line: what they shared goes home with them. They uploaded it,
# it was theirs throughout, and being removed does not make their photograph
# somebody else's — so it is unshared back to their own files and the family
# stops seeing it. Nothing is deleted, and nothing changes hands.
RSpec.describe FamilyDeparture do
  let(:family) { create(:family) }
  let(:owner) { family.owner }
  let(:leaver) { create(:user) }
  let!(:membership) { create(:family_member, family: family, user: leaver, role: "editor") }

  let!(:shared_file) do
    create(:stored_file, user: leaver, family: family, visibility: "family", name: "Holiday.jpg")
  end
  let!(:private_file) do
    create(:stored_file, user: leaver, family: family, visibility: "private", name: "Diary.pdf")
  end
  let!(:shared_record) do
    create(:vault_record, user: leaver, family: family, visibility: "family", title: "Door codes")
  end
  let!(:shared_folder) { create(:folder, user: leaver, family: family, name: "School letters") }

  def depart = described_class.new(membership).call

  describe "what goes home with them" do
    it "does not take their photographs off them" do
      depart

      expect(shared_file.reload.user_id).to eq(leaver.id)
      expect(shared_record.reload.user_id).to eq(leaver.id)
    end

    it "unshares it, so the family stops seeing it" do
      depart

      expect(shared_file.reload.visibility).to eq("private")
      expect(shared_file.family_id).to be_nil
      expect(PermissionChecker.can_view?(owner, shared_file)).to be(false)
      expect(RecordPermissions.can_view?(owner, shared_record.reload)).to be(false)
    end

    it "leaves them able to reach their own things afterwards" do
      depart

      expect(PermissionChecker.can_view?(leaver, shared_file.reload)).to be(true)
      expect(RecordPermissions.can_view?(leaver, shared_record.reload)).to be(true)
    end

    it "deletes nothing" do
      depart

      expect(StoredFile.exists?(shared_file.id)).to be(true)
      expect(VaultRecord.exists?(shared_record.id)).to be(true)
    end

    it "gives the family back the storage it was holding" do
      family.update!(family_storage_used: shared_file.size)

      depart

      expect(family.reload.family_storage_used).to eq(0)
    end

    # A folder is a place, not a possession — everything of theirs inside it
    # has already gone home.
    it "leaves the folder with the family" do
      depart

      expect(shared_folder.reload.user_id).to eq(owner.id)
    end

    it "counts what left, so somebody can be told" do
      expect(depart.to_h).to include(files: 1, records: 1)
    end
  end

  # They are out of the family, so the family's things are shut to them — but
  # their own possessions came with them.
  describe "what they no longer reach" do
    before { depart }

    it "shuts them out of what the family still shares" do
      of_the_family = create(:stored_file, user: owner, family: family, visibility: "family")

      expect(PermissionChecker.can_view?(leaver, of_the_family)).to be(false)
    end

    it "stops them sharing anything back into the family" do
      expect(PermissionChecker.can_upload_to_family?(leaver, family)).to be(false)
    end

    it "stops showing them a family they are not in" do
      expect(leaver.reload.current_family_id).to be_nil
    end

    it "closes any side door left open by a grant in their name" do
      expect(AccessGrant.where(subject: leaver).count).to eq(0)
    end
  end

  describe "what stays theirs untouched" do
    it "does not disturb what they kept private" do
      depart

      expect(private_file.reload.user_id).to eq(leaver.id)
      expect(private_file.visibility).to eq("private")
      expect(PermissionChecker.can_view?(leaver, private_file)).to be(true)
    end

    it "leaves it invisible to the family, as it always was" do
      depart

      expect(PermissionChecker.can_view?(owner, private_file.reload)).to be(false)
    end
  end

  describe "a grant made to them by name" do
    it "goes with them when it is on this family's things" do
      other = create(:stored_file, user: owner, family: family, visibility: "family")
      AccessGrant.create!(resource: other, subject: leaver, role: "editor", granted_by: owner)

      depart

      expect(AccessGrant.where(subject: leaver, resource: other)).to be_empty
    end

    # Somebody else's family is none of this family's business.
    it "is left alone when it belongs to another family" do
      elsewhere = create(:family)
      other_file = create(:stored_file, user: elsewhere.owner, family: elsewhere,
                                        visibility: "family")
      grant = AccessGrant.create!(resource: other_file, subject: leaver, role: "viewer",
                                  granted_by: elsewhere.owner)

      depart

      expect(AccessGrant.exists?(grant.id)).to be(true)
    end
  end

  describe ".settle_orphans, undoing the rule this replaced" do
    # Removal used to hand what somebody shared to the family owner. The family
    # grant records who shared it and never moves, so those can be given back.
    it "gives back a file taken from somebody who has left" do
      grant = AccessGrant.find_by(resource: shared_file, subject_type: "Family")
      expect(grant.granted_by_id).to eq(leaver.id)
      shared_file.update_columns(user_id: owner.id)
      membership.destroy!

      described_class.settle_orphans

      expect(shared_file.reload.user_id).to eq(leaver.id)
      expect(shared_file.visibility).to eq("private")
    end

    it "leaves alone what a current member shared" do
      described_class.settle_orphans

      expect(shared_file.reload.user_id).to eq(leaver.id)
      expect(shared_file.visibility).to eq("family")
    end

    # A file whose column says shared and which grants nobody anything is
    # listed by every family screen and opens for none of them.
    it "repairs a file whose grant has drifted away from its column" do
      AccessGrant.where(resource: shared_file).delete_all
      expect(PermissionChecker.can_view?(owner, shared_file.reload)).to be(false)

      expect(described_class.settle_orphans[:regranted]).to eq(1)
      expect(PermissionChecker.can_view?(owner, shared_file.reload)).to be(true)
    end
  end
end
