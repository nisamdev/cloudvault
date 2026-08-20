require "rails_helper"

RSpec.describe "Api::V1::Blobs" do
  let(:user) { create(:user) }
  let(:file) { create(:stored_file, :with_attachment, user: user) }
  let(:blob) { file.attachment.blob }

  def token_for(**overrides)
    JwtService.encode_blob(
      **{ key: blob.key, disposition: "attachment", filename: "Passport.pdf" }.merge(overrides)
    )
  end

  it "streams the bytes" do
    get "/api/v1/blobs/#{token_for}"

    expect(response).to have_http_status(:ok)
    expect(response.body.bytesize).to eq(blob.byte_size)
  end

  it "names the download after the token, not the blob" do
    get "/api/v1/blobs/#{token_for}"

    expect(response.headers["Content-Disposition"]).to include("attachment", "Passport.pdf")
  end

  it "needs no session — an <img> and a navigation cannot send one" do
    get "/api/v1/blobs/#{token_for}"

    expect(response).to have_http_status(:ok)
  end

  it "serves a byte range so video can seek" do
    get "/api/v1/blobs/#{token_for}", headers: { "Range" => "bytes=0-3" }

    expect(response).to have_http_status(:partial_content)
    expect(response.headers["Content-Range"]).to eq("bytes 0-3/#{blob.byte_size}")
  end

  it "keeps the bytes out of shared caches" do
    get "/api/v1/blobs/#{token_for}"

    expect(response.headers["Cache-Control"]).to include("private")
  end

  describe "refusing anything else" do
    it "rejects a token that has expired" do
      token = travel_to(1.hour.ago) { token_for(expires_in: 15.minutes) }

      get "/api/v1/blobs/#{token}"

      expect(response).to have_http_status(:not_found)
    end

    it "rejects a forged token" do
      forged = JWT.encode({ key: blob.key, typ: "blob", exp: 1.hour.from_now.to_i }, "not-the-secret", "HS256")

      get "/api/v1/blobs/#{forged}"

      expect(response).to have_http_status(:not_found)
    end

    it "rejects an access token replayed as a blob token" do
      get "/api/v1/blobs/#{JwtService.encode({ sub: user.id })}"

      expect(response).to have_http_status(:not_found)
    end

    it "rejects a token naming a blob that no longer exists" do
      get "/api/v1/blobs/#{token_for(key: 'no-such-key')}"

      expect(response).to have_http_status(:not_found)
    end
  end

  # These bytes come from our own origin now, where the session cookie lives.
  describe "content that must never render inline" do
    let(:file) { create(:stored_file, user: user, name: "page.html") }

    before do
      file.attachment.attach(
        io: StringIO.new("<script>alert(document.cookie)</script>"),
        filename: "page.html",
        content_type: "text/html"
      )
    end

    it "forces an HTML upload to download even when the token asks for inline" do
      get "/api/v1/blobs/#{token_for(disposition: 'inline', filename: 'page.html')}"

      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Type"]).to include("application/octet-stream")
    end
  end
end
