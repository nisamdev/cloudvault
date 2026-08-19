require "rails_helper"

RSpec.describe User do
  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }

    it "rejects malformed emails" do
      expect(build(:user, email: "not-an-email")).not_to be_valid
    end

    it "requires a password of at least 8 characters" do
      expect(build(:user, password: "short")).not_to be_valid
    end

    it "requires a password when there is no OAuth identity" do
      user = build(:user, password: nil)
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("can't be blank")
    end

    it "allows an OAuth user to have no password" do
      expect(build(:user, :oauth)).to be_valid
    end
  end

  describe "email normalisation" do
    it "downcases and strips on write" do
      user = create(:user, email: "  Dad@Smith.COM  ")
      expect(user.email).to eq("dad@smith.com")
    end
  end

  describe "#authenticate" do
    let(:user) { create(:user, password: "password123") }

    it "accepts the correct password" do
      expect(user.authenticate("password123")).to be_truthy
    end

    it "rejects the wrong password" do
      expect(user.authenticate("nope")).to be false
    end
  end

  describe "storage helpers" do
    it "reports remaining bytes" do
      user = build(:user, storage_quota: 1000, storage_used: 250)
      expect(user.storage_remaining).to eq(750)
    end

    it "never reports negative remaining space" do
      user = build(:user, storage_quota: 100, storage_used: 500)
      expect(user.storage_remaining).to eq(0)
    end

    it "reports percentage used" do
      user = build(:user, storage_quota: 200, storage_used: 50)
      expect(user.storage_percent_used).to eq(25.0)
    end
  end
end
