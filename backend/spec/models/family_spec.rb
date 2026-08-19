require "rails_helper"

RSpec.describe Family do
  it "adds the owner as an owner-role member on create" do
    owner = create(:user)
    family = create(:family, owner: owner)

    membership = family.family_members.find_by(user: owner)
    expect(membership).to be_present
    expect(membership.role).to eq("owner")
  end

  it "rejects a second owner" do
    family = create(:family)
    second = build(:family_member, family: family, user: create(:user), role: "owner")

    expect(second).not_to be_valid
    expect(second.errors[:role]).to include("is already held by another member")
  end

  it "rejects duplicate memberships for the same user" do
    family = create(:family)
    user = create(:user)
    create(:family_member, family: family, user: user, role: "viewer")

    duplicate = build(:family_member, family: family, user: user, role: "editor")
    expect(duplicate).not_to be_valid
  end

  describe "role capabilities" do
    it "lets owners, admins and editors edit" do
      %w[owner admin editor].each do |role|
        expect(build(:family_member, role: role).can_edit?).to be(true), "expected #{role} to edit"
      end
    end

    it "does not let viewers edit" do
      expect(build(:family_member, role: "viewer").can_edit?).to be false
    end

    it "only lets owners and admins manage the family" do
      expect(build(:family_member, role: "admin").can_manage_family?).to be true
      expect(build(:family_member, role: "editor").can_manage_family?).to be false
    end
  end
end
