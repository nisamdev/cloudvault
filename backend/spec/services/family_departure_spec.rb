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

  let!(:photo) do
    create(:stored_file, user: leaver, family: family, visibility: "family",
                         name: "Holiday.jpg", file_type: "image")
  end
  let!(:document) do
    create(:stored_file, user: leaver, family: family, visibility: "family",
                         name: "Deed.pdf", file_type: "file")
  end
  let(:shared_file) { photo }
  let!(:private_file) do
    create(:stored_file, user: leaver, family: family, visibility: "private", name: "Diary.pdf")
  end
  let!(:shared_record) do
    create(:vault_record, user: leaver, family: family, visibility: "family", title: "Door codes")
  end
  let!(:shared_folder) { create(:folder, user: leaver, family: family, name: "School letters") }

  def depart = described_class.new(membership).call

  # The default policy: a photograph is personal and goes back to whoever took
  # it; a document or a register entry was contributed to the household.
  describe "with the family's default policy" do
    it "sends their photographs home with them" do
      depart

      expect(photo.reload.user_id).to eq(leaver.id)
      expect(photo.visibility).to eq("private")
      expect(PermissionChecker.can_view?(owner, photo)).to be(false)
      expect(PermissionChecker.can_view?(leaver, photo)).to be(true)
    end

    it "keeps the documents they contributed" do
      depart

      expect(document.reload.user_id).to eq(owner.id)
      expect(document.visibility).to eq("family")
      expect(PermissionChecker.can_view?(owner, document)).to be(true)
    end

    it "keeps the register entries they contributed" do
      depart

      expect(shared_record.reload.user_id).to eq(owner.id)
      expect(RecordPermissions.can_view?(owner, shared_record)).to be(true)
    end

    it "deletes nothing, whichever way each thing went" do
      depart

      expect(StoredFile.exists?(photo.id)).to be(true)
      expect(StoredFile.exists?(document.id)).to be(true)
      expect(VaultRecord.exists?(shared_record.id)).to be(true)
    end

    it "counts both directions, so somebody can be told" do
      expect(depart.to_h).to include(went_home: 1, stayed: 2)
    end

    it "leaves the folder with the family either way" do
      depart

      expect(shared_folder.reload.user_id).to eq(owner.id)
    end
  end

  describe "when the family says photographs stay too" do
    before { family.update!(on_departure_photos: "stay") }

    it "keeps them" do
      depart

      expect(photo.reload.user_id).to eq(owner.id)
      expect(photo.visibility).to eq("family")
    end
  end

  describe "when the family says everything goes home" do
    before do
      family.update!(on_departure_photos: "home", on_departure_files: "home",
                     on_departure_records: "home")
    end

    it "sends all of it back to them" do
      depart

      expect(photo.reload.user_id).to eq(leaver.id)
      expect(document.reload.user_id).to eq(leaver.id)
      expect(shared_record.reload.user_id).to eq(leaver.id)
      expect(PermissionChecker.can_view?(owner, document.reload)).to be(false)
    end

    it "gives the family back the storage it was holding" do
      family.update!(family_storage_used: photo.size + document.size)

      depart

      expect(family.reload.family_storage_used).to eq(0)
    end
  end

  # A retained record pointing at a document that walked out of the door is
  # worse than either answer.
  describe "a document attached to a record that stays" do
    before do
      family.update!(on_departure_files: "home")
      RecordAttachment.create!(vault_record: shared_record, stored_file: document, position: 0)
    end

    it "stays, whatever the policy says about documents" do
      depart

      expect(document.reload.user_id).to eq(owner.id)
      expect(document.visibility).to eq("family")
    end

    it "goes home when the record goes home too" do
      family.update!(on_departure_records: "home")

      depart

      expect(document.reload.user_id).to eq(leaver.id)
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
    it "gives back a photograph taken from somebody who has left" do
      grant = AccessGrant.find_by(resource: photo, subject_type: "Family")
      expect(grant.granted_by_id).to eq(leaver.id)
      photo.update_columns(user_id: owner.id)
      membership.destroy!

      described_class.settle_orphans

      expect(photo.reload.user_id).to eq(leaver.id)
      expect(photo.visibility).to eq("private")
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
