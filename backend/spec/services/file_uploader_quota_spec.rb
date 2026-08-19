require "rails_helper"

RSpec.describe FileUploader, "family quota isolation" do
  let(:user) { create(:user, storage_quota: 1_000_000) }
  let(:family) { create(:family, owner: user, family_storage_quota: 2_000_000, family_storage_used: 0) }

  def upload_of(content: "hello world")
    file = Tempfile.new("upload")
    file.write(content)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "notes.txt", type: "text/plain")
  end

  it "does not charge the family for a private upload" do
    # The uploader is always constructed with the user's family, but a private
    # file never enters the family vault and must not consume its quota.
    expect {
      described_class.new(user: user, family: family).call(upload_of, visibility: "private")
    }.not_to change { family.reload.family_storage_used }
  end

  it "still charges the user for a private upload" do
    expect {
      described_class.new(user: user, family: family).call(upload_of, visibility: "private")
    }.to change { user.reload.storage_used }.by("hello world".bytesize)
  end

  it "charges the family for a family upload" do
    expect {
      described_class.new(user: user, family: family).call(upload_of, visibility: "family")
    }.to change { family.reload.family_storage_used }.by("hello world".bytesize)
  end

  it "allows a private upload even when the family quota is exhausted" do
    family.update!(family_storage_used: family.family_storage_quota)

    expect {
      described_class.new(user: user, family: family).call(upload_of, visibility: "private")
    }.not_to raise_error
  end

  it "leaves user and family counters reconcilable after mixed uploads" do
    described_class.new(user: user, family: family).call(upload_of(content: "aaa"), visibility: "private")
    described_class.new(user: user, family: family).call(upload_of(content: "bbbb"), visibility: "family")

    user_total = StoredFile.where(user_id: user.id).sum(:size) +
                 FileVersion.joins(:stored_file).where(stored_files: { user_id: user.id }).sum(:size)
    family_total = StoredFile.where(family_id: family.id).sum(:size) +
                   FileVersion.joins(:stored_file).where(stored_files: { family_id: family.id }).sum(:size)

    expect(user.reload.storage_used).to eq(user_total)
    expect(family.reload.family_storage_used).to eq(family_total)
  end
end
