require "rails_helper"

RSpec.describe "Api::V1::Account" do
  let(:user) { create(:user, password: "password123", full_name: "Dad Smith") }

  describe "GET /api/v1/account" do
    it "returns the profile without the password digest" do
      get "/api/v1/account", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(json["account"]["email"]).to eq(user.email)
      expect(response.body).not_to include(user.password_digest)
    end

    it "breaks the quota down by what is using it" do
      create(:stored_file, user: user, file_type: "image", size: 500)
      create(:stored_file, user: user, file_type: "file", size: 300)
      create(:stored_file, user: user, file_type: "file", size: 100, trashed_at: Time.current)

      get "/api/v1/account", headers: auth_headers_for(user)

      storage = json["storage"]
      expect(storage["by_type"]).to eq("image" => 500, "file" => 300)
      expect(storage["counts"]).to eq("image" => 1, "file" => 1)
      expect(storage["trashed"]).to eq("size" => 100, "count" => 1)
    end

    it "counts previous versions, which are charged but easy to forget" do
      file = create(:stored_file, user: user, size: 100)
      create(:file_version, stored_file: file, size: 400, created_by: user)

      get "/api/v1/account", headers: auth_headers_for(user)

      expect(json["storage"]["versions"]).to eq("size" => 400, "count" => 1)
    end

    it "needs a session" do
      get "/api/v1/account"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/account" do
    it "updates the name and time zone" do
      patch "/api/v1/account",
            params: { full_name: "Nisam", timezone: "America/Edmonton" },
            headers: auth_headers_for(user), as: :json

      expect(json["account"]["full_name"]).to eq("Nisam")
      expect(user.reload.timezone).to eq("America/Edmonton")
    end

    it "ignores anything else that is sent" do
      patch "/api/v1/account",
            params: { email: "someone@else.com", storage_quota: 999_999_999 },
            headers: auth_headers_for(user), as: :json

      expect(user.reload.email).not_to eq("someone@else.com")
      expect(user.storage_quota).not_to eq(999_999_999)
    end
  end

  describe "PATCH /api/v1/account/password" do
    it "changes the password" do
      patch "/api/v1/account/password",
            params: { current_password: "password123", password: "a-better-password" },
            headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("a-better-password")).to be_truthy
    end

    # Changing a password is what you do when you think it leaked, so leaving
    # other devices signed in would defeat the point.
    it "signs every other device out" do
      others = create_list(:refresh_token, 2, user: user)

      patch "/api/v1/account/password",
            params: { current_password: "password123", password: "a-better-password" },
            headers: auth_headers_for(user), as: :json

      expect(json["sessions_ended"]).to eq(2)
      expect(others.map { |t| t.reload.revoked_at }).to all(be_present)
    end

    it "refuses without the current password" do
      patch "/api/v1/account/password",
            params: { current_password: "wrong", password: "a-better-password" },
            headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.authenticate("password123")).to be_truthy
    end

    it "refuses a password that is too short" do
      patch "/api/v1/account/password",
            params: { current_password: "password123", password: "short" },
            headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.authenticate("password123")).to be_truthy
    end
  end
end
