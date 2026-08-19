require "rails_helper"

RSpec.describe PermissionChecker do
  let(:owner) { create(:user) }
  let(:family) { create(:family, owner: owner) }
  let(:admin) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "admin") } }
  let(:editor) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") } }
  let(:viewer) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "viewer") } }
  let(:stranger) { create(:user) }

  def file_for(user, visibility:, in_family: family)
    create(:stored_file, user: user, family: in_family, visibility: visibility)
  end

  describe ".can_view?" do
    it "lets the owner view their own private file" do
      file = file_for(owner, visibility: "private", in_family: nil)
      expect(described_class.can_view?(owner, file)).to be true
    end

    it "hides a private file from other family members" do
      file = file_for(owner, visibility: "private", in_family: nil)
      expect(described_class.can_view?(editor, file)).to be false
    end

    it "lets every family member view a family file" do
      file = file_for(owner, visibility: "family")

      [ admin, editor, viewer ].each do |member|
        expect(described_class.can_view?(member, file)).to be(true), "expected #{member.id} to view"
      end
    end

    it "hides family files from non-members" do
      file = file_for(owner, visibility: "family")
      expect(described_class.can_view?(stranger, file)).to be false
    end

    it "returns false for a nil user" do
      file = file_for(owner, visibility: "family")
      expect(described_class.can_view?(nil, file)).to be false
    end

    it "returns false for a nil file" do
      expect(described_class.can_view?(owner, nil)).to be false
    end
  end

  describe ".can_edit?" do
    let(:file) { file_for(owner, visibility: "family") }

    it "allows the owner, admins and editors" do
      [ owner, admin, editor ].each do |user|
        expect(described_class.can_edit?(user, file)).to be(true), "expected #{user.id} to edit"
      end
    end

    it "refuses viewers" do
      expect(described_class.can_edit?(viewer, file)).to be false
    end

    it "refuses non-members" do
      expect(described_class.can_edit?(stranger, file)).to be false
    end

    it "refuses everyone but the owner on a private file" do
      private_file = file_for(owner, visibility: "private", in_family: nil)
      expect(described_class.can_edit?(admin, private_file)).to be false
    end
  end

  describe ".can_delete?" do
    let(:file) { file_for(owner, visibility: "family") }

    it "allows the owner" do
      expect(described_class.can_delete?(owner, file)).to be true
    end

    it "allows family admins" do
      expect(described_class.can_delete?(admin, file)).to be true
    end

    it "refuses editors — deleting is stricter than editing" do
      expect(described_class.can_delete?(editor, file)).to be false
    end

    it "refuses viewers" do
      expect(described_class.can_delete?(viewer, file)).to be false
    end
  end

  describe ".can_upload_to_family?" do
    it "allows editors and above" do
      [ owner, admin, editor ].each do |user|
        expect(described_class.can_upload_to_family?(user, family)).to be(true), "expected #{user.id} to upload"
      end
    end

    it "refuses viewers" do
      expect(described_class.can_upload_to_family?(viewer, family)).to be false
    end
  end

  describe ".can_manage_family?" do
    it "allows owners and admins only" do
      expect(described_class.can_manage_family?(owner, family)).to be true
      expect(described_class.can_manage_family?(admin, family)).to be true
      expect(described_class.can_manage_family?(editor, family)).to be false
      expect(described_class.can_manage_family?(viewer, family)).to be false
    end
  end
end
