require "rails_helper"

RSpec.describe "Api::V1::Files preview" do
  let(:owner) { create(:user) }
  let!(:family) { create(:family, owner: owner) }
  let(:viewer) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "viewer") } }
  let(:stranger) { create(:user) }

  def file_with(name:, mime:, content: "hello", **attrs)
    file = create(:stored_file, user: owner, name: name, mime_type: mime,
                  file_type: StoredFile.file_type_for(mime), **attrs)
    file.attachment.attach(io: StringIO.new(content), filename: name, content_type: mime)
    file
  end

  describe "GET /api/v1/files/:id/preview" do
    it "returns an inline URL for an image" do
      file = file_with(name: "photo.png", mime: "image/png")

      get "/api/v1/files/#{file.id}/preview", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json["kind"]).to eq("image")
      # inline, not attachment — otherwise the browser downloads instead of showing.
      expect(json["url"]).to include("inline")
    end

    it "returns an inline URL for a PDF" do
      file = file_with(name: "deed.pdf", mime: "application/pdf")

      get "/api/v1/files/#{file.id}/preview", headers: auth_headers_for(owner)

      expect(json["kind"]).to eq("pdf")
      expect(json["url"]).to be_present
    end

    it "returns the contents for a text file rather than a URL" do
      file = file_with(name: "notes.txt", mime: "text/plain", content: "line one\nline two")

      get "/api/v1/files/#{file.id}/preview", headers: auth_headers_for(owner)

      expect(json["kind"]).to eq("text")
      expect(json["text"]).to eq("line one\nline two")
      # Reading it from storage with fetch() would need bucket CORS.
      expect(json["url"]).to be_nil
      expect(json["truncated"]).to be false
    end

    it "truncates a very large text file" do
      stub_const("Api::V1::FilesController::TEXT_PREVIEW_LIMIT", 10)
      file = file_with(name: "big.txt", mime: "text/plain", content: "0123456789abcdef")
      file.update!(size: 16)

      get "/api/v1/files/#{file.id}/preview", headers: auth_headers_for(owner)

      expect(json["text"].bytesize).to eq(10)
      expect(json["truncated"]).to be true
    end

    it "treats SVG as text, not as an image" do
      file = file_with(name: "logo.svg", mime: "image/svg+xml", content: "<svg onload='alert(1)'/>")

      get "/api/v1/files/#{file.id}/preview", headers: auth_headers_for(owner)

      # Rendering it as an image would run any script it carries.
      expect(json["kind"]).to eq("text")
    end

    it "identifies video and audio" do
      video = file_with(name: "clip.mp4", mime: "video/mp4")
      audio = file_with(name: "song.mp3", mime: "audio/mpeg")

      get "/api/v1/files/#{video.id}/preview", headers: auth_headers_for(owner)
      expect(json["kind"]).to eq("video")

      get "/api/v1/files/#{audio.id}/preview", headers: auth_headers_for(owner)
      expect(json["kind"]).to eq("audio")
    end

    it "says so when the type cannot be shown" do
      file = file_with(name: "archive.zip", mime: "application/zip")

      get "/api/v1/files/#{file.id}/preview", headers: auth_headers_for(owner)

      expect(json["kind"]).to eq("none")
    end

    it "says so when the file has no contents" do
      file = create(:stored_file, user: owner, name: "empty.txt", mime_type: "text/plain")

      get "/api/v1/files/#{file.id}/preview", headers: auth_headers_for(owner)

      expect(json["kind"]).to eq("none")
      expect(json["reason"]).to eq("empty")
    end

    it "lets a family member preview a shared file" do
      file = file_with(name: "shared.txt", mime: "text/plain", family: family, visibility: "family")

      get "/api/v1/files/#{file.id}/preview", headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:ok)
      expect(json["kind"]).to eq("text")
    end

    it "refuses someone who cannot view the file" do
      file = file_with(name: "private.txt", mime: "text/plain")

      get "/api/v1/files/#{file.id}/preview", headers: auth_headers_for(stranger)

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      file = file_with(name: "private.txt", mime: "text/plain")

      get "/api/v1/files/#{file.id}/preview"

      expect(response).to have_http_status(:unauthorized)
    end

    it "does not choke on text that is not valid UTF-8" do
      file = file_with(name: "weird.txt", mime: "text/plain", content: "caf\xE9 binary\xFF")

      get "/api/v1/files/#{file.id}/preview", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json["text"]).to include("caf")
    end
  end
end

RSpec.describe "Api::V1::Files preview conversion" do
  let(:owner) { create(:user) }

  def attach(file, bytes, type)
    file.attachment.attach(io: StringIO.new(bytes), filename: file.name, content_type: type)
    file
  end

  it "converts a HEIC to JPEG, because no mainstream browser renders HEIC" do
    heic = create(:stored_file, :image, user: owner, name: "IMG_0001.heic", mime_type: "image/heic")
    # libvips here can decode HEIC but not encode it, so the payload is JPEG
    # bytes labelled image/heic. That is enough: this asserts the conversion
    # decision, which is driven by the stored mime type.
    attach(heic, Vips::Image.black(64, 64).cast("uchar").colourspace("srgb").jpegsave_buffer, "image/heic")

    get "/api/v1/files/#{heic.id}/preview", headers: auth_headers_for(owner)

    expect(response).to have_http_status(:ok)
    expect(json["kind"]).to eq("image")
    expect(json["converted"]).to be true
    expect(json["url"]).to be_present
  end

  it "serves a JPEG unconverted" do
    jpeg = create(:stored_file, :image, user: owner, name: "photo.jpg", mime_type: "image/jpeg")
    attach(jpeg, Vips::Image.black(32, 32).cast("uchar").colourspace("srgb").jpegsave_buffer, "image/jpeg")

    get "/api/v1/files/#{jpeg.id}/preview", headers: auth_headers_for(owner)

    expect(json["converted"]).to be false
  end

  it "serves AVIF unconverted, since browsers render it" do
    avif = create(:stored_file, :image, user: owner, name: "photo.avif", mime_type: "image/avif")
    attach(avif, Vips::Image.black(32, 32).cast("uchar").colourspace("srgb").jpegsave_buffer, "image/avif")

    get "/api/v1/files/#{avif.id}/preview", headers: auth_headers_for(owner)

    expect(json["converted"]).to be false
  end

  it "converts TIFF too" do
    tiff = create(:stored_file, :image, user: owner, name: "scan.tiff", mime_type: "image/tiff")
    attach(tiff, Vips::Image.black(32, 32).cast("uchar").colourspace("srgb").tiffsave_buffer, "image/tiff")

    get "/api/v1/files/#{tiff.id}/preview", headers: auth_headers_for(owner)

    expect(json["converted"]).to be true
  end

  it "still returns a usable URL when conversion fails" do
    broken = create(:stored_file, :image, user: owner, name: "broken.heic", mime_type: "image/heic")
    attach(broken, "not an image at all", "image/heic")

    get "/api/v1/files/#{broken.id}/preview", headers: auth_headers_for(owner)

    # Falls back to the original rather than erroring the whole preview.
    expect(response).to have_http_status(:ok)
    expect(json["url"]).to be_present
  end
end
