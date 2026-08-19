require "rails_helper"

RSpec.describe RefreshToken do
  let(:user) { create(:user) }

  it "exposes the raw token only on the instance that created it" do
    token = user.refresh_tokens.create!
    expect(token.raw_token).to be_present
    expect(described_class.find(token.id).raw_token).to be_nil
  end

  it "stores a digest, never the raw token" do
    token = user.refresh_tokens.create!
    expect(token.token_digest).not_to eq(token.raw_token)
    expect(token.token_digest).to eq(Digest::SHA256.hexdigest(token.raw_token))
  end

  it "finds a record by its raw token" do
    token = user.refresh_tokens.create!
    expect(described_class.find_by_raw_token(token.raw_token)).to eq(token)
  end

  it "is inactive once revoked" do
    token = user.refresh_tokens.create!
    token.revoke!
    expect(token).not_to be_active
  end

  it "is inactive once expired" do
    token = user.refresh_tokens.create!(expires_at: 1.hour.ago)
    expect(token).not_to be_active
  end

  describe "#detect_replay!" do
    it "revokes every active token when a rotated token is reused" do
      old = user.refresh_tokens.create!
      replacement = user.refresh_tokens.create!
      old.update!(replaced_by: replacement, revoked_at: Time.current)

      expect(old.detect_replay!).to be true
      expect(replacement.reload.revoked_at).to be_present
    end

    it "does nothing for a token that was never rotated" do
      token = user.refresh_tokens.create!
      expect(token.detect_replay!).to be false
      expect(token.reload).to be_active
    end
  end
end
