require "rails_helper"

RSpec.describe FileUploader do
  let(:user) { create(:user, storage_quota: 1_000_000, storage_used: 0) }
  let(:family) { create(:family, owner: user, family_storage_quota: 2_000_000, family_storage_used: 0) }

  def upload_of(content: "hello world", filename: "notes.txt", type: "text/plain")
    file = Tempfile.new("upload")
    file.write(content)
    file.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: file, filename: filename, type: type
    )
  end

  describe "creating a file" do
    it "stores the file and attaches the bytes" do
      stored = described_class.new(user: user).call(upload_of)

      expect(stored).to be_persisted
      expect(stored.attachment).to be_attached
      expect(stored.name).to eq("notes.txt")
      expect(stored.size).to eq("hello world".bytesize)
    end

    it "classifies images by mime type" do
      stored = described_class.new(user: user).call(
        upload_of(filename: "photo.png", type: "image/png")
      )

      expect(stored.file_type).to eq("image")
    end

    it "charges the uploader's storage" do
      expect {
        described_class.new(user: user).call(upload_of)
      }.to change { user.reload.storage_used }.by("hello world".bytesize)
    end

    it "charges family storage for a family upload" do
      expect {
        described_class.new(user: user, family: family).call(upload_of, visibility: "family")
      }.to change { family.reload.family_storage_used }.by("hello world".bytesize)
    end

    it "strips any directory component from the filename" do
      stored = described_class.new(user: user).call(upload_of(filename: "../../etc/passwd"))
      expect(stored.name).to eq("passwd")
    end

    it "enqueues thumbnail processing for images only" do
      expect {
        described_class.new(user: user).call(upload_of(filename: "a.png", type: "image/png"))
      }.to have_enqueued_job(ProcessImageJob)

      expect {
        described_class.new(user: user).call(upload_of)
      }.not_to have_enqueued_job(ProcessImageJob)
    end
  end

  describe "limits" do
    it "refuses a file over the size limit" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("MAX_UPLOAD_BYTES", 104_857_600).and_return("5")

      expect {
        described_class.new(user: user).call(upload_of)
      }.to raise_error(described_class::FileTooLarge)
    end

    it "refuses a file that exceeds the user's remaining quota" do
      user.update!(storage_used: user.storage_quota - 2)

      expect {
        described_class.new(user: user).call(upload_of)
      }.to raise_error(described_class::QuotaExceeded)
    end

    it "refuses a file that exceeds the family's remaining quota" do
      family.update!(family_storage_used: family.family_storage_quota - 2)

      expect {
        described_class.new(user: user, family: family).call(upload_of, visibility: "family")
      }.to raise_error(described_class::QuotaExceeded, /family/i)
    end

    it "refuses executable file types" do
      expect {
        described_class.new(user: user).call(upload_of(filename: "malware.exe"))
      }.to raise_error(described_class::UnsupportedType)
    end

    it "leaves storage untouched when validation fails" do
      expect {
        begin
          described_class.new(user: user).call(upload_of(filename: "malware.exe"))
        rescue described_class::UnsupportedType
          # expected
        end
      }.not_to change { user.reload.storage_used }
    end
  end

  describe "versioning" do
    let!(:existing) { described_class.new(user: user).call(upload_of(content: "v1")) }

    it "creates a version instead of a second file" do
      expect {
        described_class.new(user: user).call(upload_of(content: "v2-longer"), replaces: existing)
      }.to change { existing.reload.file_versions.count }.by(1)
        .and change { existing.reload.version_number }.from(1).to(2)

      expect(StoredFile.count).to eq(1)
    end

    it "keeps the previous bytes on the version record" do
      described_class.new(user: user).call(upload_of(content: "v2-longer"), replaces: existing)

      version = existing.reload.file_versions.newest_first.first
      expect(version.attachment).to be_attached
      expect(version.attachment.download).to eq("v1")
      expect(existing.attachment.download).to eq("v2-longer")
    end

    it "counts retained versions against storage" do
      # The old bytes stay in storage as a version, so the charge is the full new
      # size, not the difference between them.
      expect {
        described_class.new(user: user).call(upload_of(content: "v2-longer"), replaces: existing)
      }.to change { user.reload.storage_used }.by("v2-longer".bytesize)

      total = StoredFile.sum(:size) + FileVersion.sum(:size)
      expect(user.reload.storage_used).to eq(total)
    end

    it "prunes versions beyond the retention count and releases their storage" do
      stub_const("ENV", ENV.to_h.merge("FILE_VERSIONS_KEPT" => "2"))

      4.times { |i| described_class.new(user: user).call(upload_of(content: "rev#{i}"), replaces: existing) }

      expect(existing.reload.file_versions.count).to eq(2)
      total = StoredFile.sum(:size) + FileVersion.sum(:size)
      expect(user.reload.storage_used).to eq(total)
    end
  end
end
