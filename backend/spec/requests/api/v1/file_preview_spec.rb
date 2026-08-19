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
