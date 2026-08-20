require "rails_helper"

RSpec.describe "Api::V1::Sessions" do
  let(:user) { create(:user) }
  let(:other) { create(:user) }

  describe "GET /api/v1/sessions" do
    it "lists the devices that can stay signed in" do
      create(:refresh_token, user: user)

      get "/api/v1/sessions", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(json["sessions"].size).to eq(1)
      expect(json["sessions"].first["device"]).to eq("Chrome on Mac")
      expect(json["sessions"].first["ip_address"]).to eq("192.168.1.20")
    end

    it "leaves out sessions that have already ended" do
      create(:refresh_token, user: user).revoke!
      create(:refresh_token, user: user, expires_at: 1.day.ago)

      get "/api/v1/sessions", headers: auth_headers_for(user)

      expect(json["sessions"]).to be_empty
    end

    it "never shows another person's devices" do
      create(:refresh_token, user: other)

      get "/api/v1/sessions", headers: auth_headers_for(user)

      expect(json["sessions"]).to be_empty
    end

    it "does not leak the token itself" do
      token = create(:refresh_token, user: user)

      get "/api/v1/sessions", headers: auth_headers_for(user)

      expect(response.body).not_to include(token.token_digest)
      expect(json["sessions"].first).not_to have_key("token_digest")
    end
  end

  describe "DELETE /api/v1/sessions/:id" do
    it "ends that session" do
      token = create(:refresh_token, user: user)

      delete "/api/v1/sessions/#{token.id}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:no_content)
      expect(token.reload.revoked_at).to be_present
    end

    it "cannot reach somebody else's session" do
      token = create(:refresh_token, user: other)

      delete "/api/v1/sessions/#{token.id}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:not_found)
      expect(token.reload.revoked_at).to be_nil
    end
  end

  describe "DELETE /api/v1/sessions" do
    it "ends all of them when the caller has no session cookie to spare" do
      create_list(:refresh_token, 3, user: user)

      delete "/api/v1/sessions", headers: auth_headers_for(user)

      expect(json["sessions_ended"]).to eq(3)
      expect(user.refresh_tokens.active).to be_empty
    end

    it "leaves other people alone" do
      mine = create(:refresh_token, user: user)
      theirs = create(:refresh_token, user: other)

      delete "/api/v1/sessions", headers: auth_headers_for(user)

      expect(mine.reload.revoked_at).to be_present
      expect(theirs.reload.revoked_at).to be_nil
    end
  end

  describe DeviceName do
    it "names something a person would recognise" do
      expect(described_class.for("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) AppleWebKit/605.1 Version/17.0 Mobile Safari/604.1"))
        .to eq("Safari on iPhone")
    end

    # Chrome's user agent contains "Safari", and Edge's contains both.
    it "does not mistake Chrome or Edge for Safari" do
      chrome = "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/140.0 Safari/537.36"
      edge = "#{chrome} Edg/140.0"

      expect(described_class.for(chrome)).to eq("Chrome on Windows")
      expect(described_class.for(edge)).to eq("Edge on Windows")
    end

    it "says so rather than guessing" do
      expect(described_class.for(nil)).to eq("Unknown device")
      expect(described_class.for("curl/8.4.0")).to eq("Unknown device")
    end
  end
end
