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

RSpec.describe FileUploader, "content type detection" do
  let(:user) { create(:user, storage_quota: 10_000_000) }

  # A minimal ISO-BMFF ftyp box declaring the HEIC brand — the magic bytes a
  # real iPhone photo starts with.
  def heic_bytes
    brands = "heic".b + [ 0 ].pack("N") + "mif1heic".b
    ftyp = [ 8 + brands.bytesize ].pack("N") + "ftyp".b + brands
    ftyp + ([ 16 ].pack("N") + "meta".b + ("\x00".b * 8)) + ("\x00".b * 64)
  end

  def upload_of(bytes, filename:, declared_type:)
    file = Tempfile.new(%w[upload .bin], binmode: true)
    file.write(bytes)
    file.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: file, filename: filename, type: declared_type
    )
  end

  it "files a HEIC as an image when the browser declares octet-stream" do
    # Chrome sends this for .heic wherever the OS has no registration for it.
    stored = described_class.new(user: user).call(
      upload_of(heic_bytes, filename: "IMG_0001.heic", declared_type: "application/octet-stream")
    )

    expect(stored.mime_type).to eq("image/heic")
    expect(stored.file_type).to eq("image")
  end

  it "files a HEIC as an image when the browser declares nothing at all" do
    stored = described_class.new(user: user).call(
      upload_of(heic_bytes, filename: "IMG_0002.heic", declared_type: "")
    )

    expect(stored.file_type).to eq("image")
  end

  it "keeps a correctly declared type" do
    stored = described_class.new(user: user).call(
      upload_of(heic_bytes, filename: "IMG_0003.heic", declared_type: "image/heic")
    )

    expect(stored.mime_type).to eq("image/heic")
  end

  it "trusts the bytes over a wrong declared type" do
    png = Vips::Image.black(8, 8).cast("uchar").colourspace("srgb").pngsave_buffer

    stored = described_class.new(user: user).call(
      upload_of(png, filename: "photo.png", declared_type: "text/plain")
    )

    expect(stored.mime_type).to eq("image/png")
    expect(stored.file_type).to eq("image")
  end

  it "leaves the tempfile readable for Active Storage after sniffing it" do
    stored = described_class.new(user: user).call(
      upload_of(heic_bytes, filename: "IMG_0004.heic", declared_type: "")
    )

    # Marcel reads from the tempfile; without a rewind the blob would be empty.
    expect(stored.attachment.download.bytesize).to eq(heic_bytes.bytesize)
  end

  it "still refuses an executable renamed to look like an image" do
    expect {
      described_class.new(user: user).call(
        upload_of("MZ\x90\x00".b, filename: "payload.exe", declared_type: "image/png")
      )
    }.to raise_error(described_class::UnsupportedType)
  end
end
