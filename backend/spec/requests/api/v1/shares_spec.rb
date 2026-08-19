require "rails_helper"

RSpec.describe "Api::V1::Shares" do
  let(:owner) { create(:user) }
  let(:family) { create(:family, owner: owner) }
  let(:viewer) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "viewer") } }
  let(:stranger) { create(:user) }
  let(:file) { create(:stored_file, :with_attachment, user: owner, family: family, visibility: "family") }

  # The raw token exists only on the instance that created the link.
  def create_link(**attrs)
    link = file.shared_links.new(user: owner, **attrs)
    link.password = attrs[:password] if attrs[:password]
    link.save!
    link
  end

  describe "POST /api/v1/files/:file_id/shares" do
    it "creates a link and returns its URL exactly once" do
      post "/api/v1/files/#{file.id}/shares",
           params: { expires_in: "7d" }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json["share"]["url"]).to include("/share/")
      expect(json["share"]["expires_at"]).to be_present
    end

    it "stores only a digest of the token" do
      post "/api/v1/files/#{file.id}/shares", headers: auth_headers_for(owner), as: :json

      token = json["share"]["url"].split("/share/").last
      link = SharedLink.last
      expect(link.token_digest).to eq(SharedLink.digest_for(token))
      expect(link.attributes.values).not_to include(token)
    end

    it "does not expose the URL when listing links afterwards" do
      post "/api/v1/files/#{file.id}/shares", headers: auth_headers_for(owner), as: :json

      get "/api/v1/files/#{file.id}/shares", headers: auth_headers_for(owner)

      expect(json["shares"].first).not_to have_key("url")
    end

    it "accepts a password" do
      post "/api/v1/files/#{file.id}/shares",
           params: { password: "letmein" }, headers: auth_headers_for(owner), as: :json

      expect(json["share"]["password_protected"]).to be true
      expect(SharedLink.last.authenticate_password("letmein")).to be_truthy
    end

    it "refuses a viewer" do
      post "/api/v1/files/#{file.id}/shares", headers: auth_headers_for(viewer), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "hides files the caller cannot see" do
      private_file = create(:stored_file, user: owner, visibility: "private")

      post "/api/v1/files/#{private_file.id}/shares", headers: auth_headers_for(stranger), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/shares/:token" do
    it "returns file details without a session" do
      link = create_link

      get "/api/v1/shares/#{link.raw_token}"

      expect(response).to have_http_status(:ok)
      expect(json["share"]["file"]["name"]).to eq(file.name)
      expect(json["share"]["requires_password"]).to be false
    end

    it "never reveals the file id or owner email" do
      link = create_link

      get "/api/v1/shares/#{link.raw_token}"

      expect(json["share"]["file"]).not_to have_key("id")
      expect(response.body).not_to include(owner.email)
    end

    it "gives one indistinguishable answer for unknown, revoked and expired links" do
      unknown = get_response_for("does-not-exist")

      revoked = create_link
      revoked.revoke!
      revoked_body = get_response_for(revoked.raw_token)

      expired = create_link(expires_at: 1.hour.ago)
      expired_body = get_response_for(expired.raw_token)

      expect([ revoked_body, expired_body ]).to all(eq(unknown))
    end

    it "stops working once the file is trashed" do
      link = create_link
      file.trash!

      get "/api/v1/shares/#{link.raw_token}"

      expect(response).to have_http_status(:not_found)
    end

    def get_response_for(token)
      get "/api/v1/shares/#{token}"
      [ response.status, response.body ]
    end
  end

  describe "POST /api/v1/shares/:token/download" do
    it "returns a presigned URL for an open link" do
      link = create_link

      post "/api/v1/shares/#{link.raw_token}/download"

      expect(response).to have_http_status(:ok)
      expect(json["url"]).to be_present
      expect(json["filename"]).to eq(file.name)
    end

    it "counts downloads" do
      link = create_link

      expect {
        post "/api/v1/shares/#{link.raw_token}/download"
      }.to change { link.reload.download_count }.by(1)
    end

    it "requires the password when one is set" do
      link = create_link(password: "letmein")

      post "/api/v1/shares/#{link.raw_token}/download"
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/shares/#{link.raw_token}/download", params: { password: "wrong" }, as: :json
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/shares/#{link.raw_token}/download", params: { password: "letmein" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "stops at the download limit" do
      link = create_link(max_downloads: 1)

      post "/api/v1/shares/#{link.raw_token}/download"
      expect(response).to have_http_status(:ok)

      post "/api/v1/shares/#{link.raw_token}/download"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/shares/:id" do
    it "revokes the link" do
      link = create_link

      delete "/api/v1/shares/#{link.id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:no_content)
      expect(link.reload).to be_revoked
    end

    it "refuses someone who cannot share the file" do
      link = create_link

      delete "/api/v1/shares/#{link.id}", headers: auth_headers_for(viewer)

      expect(response).to have_http_status(:forbidden)
      expect(link.reload).not_to be_revoked
    end
  end
end
