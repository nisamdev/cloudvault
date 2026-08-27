require "rails_helper"

# What somebody leaves behind when they are taken out of a family.
#
# The rule in one line: what they shared with the household stays with the
# household and stops being theirs; what they kept private stays entirely
# theirs. Nothing is deleted either way.
RSpec.describe FamilyDeparture do
  let(:family) { create(:family) }
  let(:owner) { family.owner }
  let(:leaver) { create(:user) }
  let!(:membership) { create(:family_member, family: family, user: leaver, role: "editor") }

  let!(:shared_file) do
    create(:stored_file, user: leaver, family: family, visibility: "family", name: "Passport.pdf")
  end
  let!(:private_file) do
    create(:stored_file, user: leaver, family: family, visibility: "private", name: "Diary.pdf")
  end
  let!(:shared_record) do
    create(:vault_record, user: leaver, family: family, visibility: "family", title: "Door codes")
  end
  let!(:shared_folder) { create(:folder, user: leaver, family: family, name: "School letters") }

  def depart = described_class.new(membership).call

  describe "what the family keeps" do
    it "does not delete the passports they scanned" do
      depart

      expect(shared_file.reload).to be_persisted
      expect(shared_record.reload).to be_persisted
    end

    it "hands what they shared to the family's owner" do
      depart

      expect(shared_file.reload.user_id).to eq(owner.id)
      expect(shared_record.reload.user_id).to eq(owner.id)
      expect(shared_folder.reload.user_id).to eq(owner.id)
    end

    it "leaves it visible to the family" do
      depart

      expect(PermissionChecker.can_view?(owner, shared_file.reload)).to be(true)
      expect(RecordPermissions.can_view?(owner, shared_record.reload)).to be(true)
    end

    it "counts what it kept, so somebody can be told" do
      summary = depart

      expect(summary.to_h).to include(files: 1, records: 1, folders: 1)
    end
  end

  # The whole reason ownership moves. Left as the owner they could go on
  # renaming it, unsharing it, sharing it back and deleting it — from outside
  # the family that depends on it.
  describe "what they no longer hold" do
    before { depart }

    it "takes the file out of their hands entirely" do
      file = shared_file.reload

      expect(PermissionChecker.can_view?(leaver, file)).to be(false)
      expect(PermissionChecker.can_edit?(leaver, file)).to be(false)
      expect(PermissionChecker.can_delete?(leaver, file)).to be(false)
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

  describe "what stays theirs" do
    it "does not touch what they kept private" do
      depart

      expect(private_file.reload.user_id).to eq(leaver.id)
      expect(PermissionChecker.can_view?(leaver, private_file.reload)).to be(true)
    end

    it "leaves their private things invisible to the family, as they always were" do
      depart

      expect(PermissionChecker.can_view?(owner, private_file.reload)).to be(false)
    end
  end

  describe "a grant made to them by name" do
    it "goes with them when it is on this family's things" do
      AccessGrant.create!(resource: shared_file, subject: leaver, role: "editor", granted_by: owner)

      depart

      expect(AccessGrant.where(subject: leaver, resource: shared_file)).to be_empty
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

  describe ".settle_orphans, for everything already left in that state" do
    # People were removed before removal settled anything, so the family was
    # left with a file it could not open, could not unshare, and could only
    # delete — while the person who left could still do all three.
    it "hands an already-orphaned share to the family's owner" do
      membership.destroy!

      described_class.settle_orphans

      expect(shared_file.reload.user_id).to eq(owner.id)
      expect(shared_record.reload.user_id).to eq(owner.id)
      expect(shared_folder.reload.user_id).to eq(owner.id)
    end

    it "leaves alone what a current member shared" do
      described_class.settle_orphans

      expect(shared_file.reload.user_id).to eq(leaver.id)
    end

    # A file whose column says shared and which grants nobody anything is
    # listed by every family screen and opens for none of them.
    it "repairs a file whose grant has drifted away from its column" do
      AccessGrant.where(resource: shared_file).delete_all
      expect(PermissionChecker.can_view?(owner, shared_file.reload)).to be(false)

      expect(described_class.settle_orphans[:regranted]).to eq(1)
      expect(PermissionChecker.can_view?(owner, shared_file.reload)).to be(true)
    end

    it "changes nothing when there is nothing to settle" do
      described_class.settle_orphans

      expect(described_class.settle_orphans.values.sum).to eq(0)
    end
  end

  # A secret is sealed with the vault key of whoever wrote it, so a record
  # changing hands cannot make its password readable by anybody else. It never
  # was — this counts them rather than pretending otherwise.
  it "counts the secrets that leave unreadable" do
    create(:record_secret, vault_record: shared_record)

    expect(depart.sealed_secrets).to eq(1)
  end
end
