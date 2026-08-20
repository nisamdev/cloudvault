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

RSpec.describe PermissionChecker, "with grants" do
  let(:owner) { create(:user) }
  let(:family) { create(:family, owner: owner) }
  let(:outsider) { create(:user) }
  let(:viewer_member) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "viewer") } }

  def grant(resource, to:, role: "viewer")
    AccessGrant.create!(resource: resource, subject: to, role: role, granted_by: owner)
  end

  # The point of the whole thing: hand one folder to one person, read only,
  # without making them part of the family.
  describe "sharing with one person" do
    let(:file) { create(:stored_file, user: owner, visibility: "private") }

    it "gives no access without a grant" do
      expect(described_class.can_view?(outsider, file)).to be false
    end

    it "lets a named person view a private file" do
      grant(file, to: outsider)

      expect(described_class.can_view?(outsider, file)).to be true
      expect(described_class.can_edit?(outsider, file)).to be false
    end

    it "can hand over editing too" do
      grant(file, to: outsider, role: "editor")

      expect(described_class.can_edit?(outsider, file)).to be true
    end

    # Access should not spread without the owner's say-so.
    it "never lets a guest re-share or delete" do
      grant(file, to: outsider, role: "editor")

      expect(described_class.can_share?(outsider, file)).to be false
      expect(described_class.can_delete?(outsider, file)).to be false
    end

    it "stops when the grant expires" do
      grant(file, to: outsider).update!(expires_at: 1.hour.ago)

      expect(described_class.can_view?(outsider, file)).to be false
    end
  end

  describe "a grant on a folder" do
    let(:folder) { create(:folder, user: owner, name: "Tax 2026") }
    let(:sub) { create(:folder, user: owner, name: "Receipts", parent: folder) }
    let(:file) { create(:stored_file, user: owner, folder: sub, visibility: "private") }

    it "reaches everything inside it, however deep" do
      grant(folder, to: outsider)

      expect(described_class.can_view?(outsider, file)).to be true
      expect(described_class.can_view_folder?(outsider, sub)).to be true
    end

    it "does not reach a file outside it" do
      grant(folder, to: outsider)
      elsewhere = create(:stored_file, user: owner, visibility: "private")

      expect(described_class.can_view?(outsider, elsewhere)).to be false
    end

    # "Everything in here is read-only, except this one thing."
    it "is overridden by a grant closer to the file" do
      grant(folder, to: outsider, role: "viewer")
      grant(file, to: outsider, role: "editor")

      expect(described_class.can_edit?(outsider, file)).to be true
    end
  end

  describe "sharing with a whole family" do
    let(:other_family) { create(:family, owner: create(:user)) }
    let(:cousin) { create(:user).tap { |u| create(:family_member, family: other_family, user: u, role: "editor") } }
    let(:file) { create(:stored_file, user: owner, visibility: "private") }

    it "reaches every member of that family" do
      grant(file, to: other_family)

      expect(described_class.can_view?(cousin, file)).to be true
    end

    it "stops reaching them when they leave" do
      grant(file, to: other_family)
      cousin.family_memberships.destroy_all

      expect(described_class.can_view?(cousin.reload, file)).to be false
    end

    # Between two grants the more specific one wins.
    it "lets a grant naming the person beat one naming their family" do
      grant(file, to: other_family, role: "editor")
      grant(file, to: cousin, role: "viewer")

      expect(described_class.can_edit?(cousin, file)).to be false
      expect(described_class.can_view?(cousin, file)).to be true
    end
  end

  # Sharing with a family is itself a grant now, so a grant naming one person is
  # the more specific statement of the two and decides it — which is what makes
  # "the family can edit these, but Mum only reads this one" sayable at all.
  it "lets a grant naming one person narrow what their family was given" do
    file = create(:stored_file, user: owner, family: family, visibility: "family")
    editor_member = create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") }
    grant(file, to: editor_member, role: "viewer")

    expect(described_class.can_view?(editor_member, file)).to be true
    expect(described_class.can_edit?(editor_member, file)).to be false
  end

  it "leaves the rest of the family where they were" do
    file = create(:stored_file, user: owner, family: family, visibility: "family")
    editor_member = create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") }
    other = create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") }
    grant(file, to: editor_member, role: "viewer")

    expect(described_class.can_edit?(other, file)).to be true
  end

  it "does not promote a family viewer just because the file was shared with them" do
    file = create(:stored_file, user: owner, family: family, visibility: "family")
    grant(file, to: viewer_member, role: "viewer")

    expect(described_class.can_edit?(viewer_member, file)).to be false
  end
end
