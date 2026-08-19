require "rails_helper"

RSpec.describe "Api::V1::Auth" do
  let(:refresh_cookie) { Api::V1::AuthController::REFRESH_COOKIE.to_s }

  describe "POST /api/v1/auth/register" do
    let(:params) { { email: "dad@smith.com", password: "password123", full_name: "Dad Smith" } }

    it "creates the account and returns a session" do
      expect {
        post "/api/v1/auth/register", params: params, as: :json
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json["access_token"]).to be_present
      expect(json["user"]["email"]).to eq("dad@smith.com")
    end

    it "sets the refresh token as an httpOnly cookie, never in the body" do
      post "/api/v1/auth/register", params: params, as: :json

      expect(response.cookies[refresh_cookie]).to be_present
      # Rack normalises the attribute to lowercase.
      expect(response.headers["Set-Cookie"].to_s.downcase).to include("httponly")
      expect(response.body).not_to include("refresh_token")
    end

    it "applies the configured storage quota" do
      post "/api/v1/auth/register", params: params, as: :json
      expect(json["user"]["storage_quota"]).to eq(ENV.fetch("USER_STORAGE_QUOTA_BYTES", 268_435_456).to_i)
    end

    it "returns field-level errors for a duplicate email" do
      create(:user, email: "dad@smith.com")
      post "/api/v1/auth/register", params: params, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("validation_failed")
      expect(json["error"]["details"]).to have_key("email")
    end

    it "rejects a short password" do
      post "/api/v1/auth/register", params: params.merge(password: "short"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/v1/auth/login" do
    let!(:user) { create(:user, email: "dad@smith.com", password: "password123") }

    it "returns a session for correct credentials" do
      login_as(user)

      expect(response).to have_http_status(:ok)
      expect(json["access_token"]).to be_present
      expect(json["expires_in"]).to eq(JwtService.access_ttl.to_i)
    end

    it "records the sign-in time" do
      expect { login_as(user) }.to change { user.reload.last_signed_in_at }.from(nil)
    end

    it "is case-insensitive about the email" do
      post "/api/v1/auth/login", params: { email: "DAD@SMITH.COM", password: "password123" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "rejects a wrong password without revealing whether the account exists" do
      post "/api/v1/auth/login", params: { email: user.email, password: "wrong" }, as: :json
      wrong_password_body = response.body

      post "/api/v1/auth/login", params: { email: "nobody@smith.com", password: "wrong" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to eq(wrong_password_body)
    end

    it "refuses to log in an OAuth-only account with a password" do
      oauth_user = create(:user, :oauth, email: "oauth@smith.com")
      post "/api/v1/auth/login", params: { email: oauth_user.email, password: "anything" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/auth/refresh" do
    let!(:user) { create(:user, password: "password123") }

    it "issues a new access token from the cookie" do
      login_as(user)
      post "/api/v1/auth/refresh", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["access_token"]).to be_present
    end

    it "rotates the refresh token on every use" do
      login_as(user)
      first = user.refresh_tokens.order(:created_at).last

      post "/api/v1/auth/refresh", as: :json

      expect(first.reload.revoked_at).to be_present
      expect(first.replaced_by).to be_present
      expect(user.refresh_tokens.active.count).to eq(1)
    end

    it "revokes the whole chain when a rotated token is replayed" do
      # Built directly rather than via login: the raw token is only readable on
      # the instance that created it, and an attacker replaying a stolen token
      # has no cookie of their own (the controller prefers the cookie).
      stolen = user.refresh_tokens.create!
      replacement = user.refresh_tokens.create!
      stolen.update!(replaced_by: replacement, revoked_at: Time.current)

      post "/api/v1/auth/refresh", params: { refresh_token: stolen.raw_token }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]["code"]).to eq("refresh_token_replayed")
      expect(user.refresh_tokens.active.count).to eq(0)
    end

    it "rejects an unknown token" do
      post "/api/v1/auth/refresh", params: { refresh_token: "made-up" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]["code"]).to eq("invalid_refresh_token")
    end

    it "rejects an expired token" do
      login_as(user)
      user.refresh_tokens.update_all(expires_at: 1.day.ago)

      post "/api/v1/auth/refresh", as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]["code"]).to eq("expired_refresh_token")
    end
  end

  describe "POST /api/v1/auth/logout" do
    let!(:user) { create(:user, password: "password123") }

    it "revokes the refresh token" do
      login_as(user)
      post "/api/v1/auth/logout"

      expect(response).to have_http_status(:no_content)
      expect(user.refresh_tokens.active.count).to eq(0)
    end

    it "works without a valid access token, so an expired session can still sign out" do
      login_as(user)
      post "/api/v1/auth/logout", headers: { "Authorization" => "Bearer garbage" }

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET /api/v1/auth/me" do
    let(:user) { create(:user) }

    it "returns the current user" do
      get "/api/v1/auth/me", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(json["user"]["id"]).to eq(user.id)
      expect(json).not_to have_key("access_token")
    end

    it "includes family details once the user belongs to one" do
      family = create(:family, owner: user)
      get "/api/v1/auth/me", headers: auth_headers_for(user)

      expect(json["family"]["id"]).to eq(family.id)
      expect(json["family"]["role"]).to eq("owner")
    end

    it "requires authentication" do
      get "/api/v1/auth/me"

      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]["code"]).to eq("unauthenticated")
    end

    it "rejects an expired access token" do
      token = travel_to(1.hour.ago) { JwtService.encode({ sub: user.id, email: user.email }) }
      get "/api/v1/auth/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a token signed with the wrong secret" do
      forged = JWT.encode({ sub: user.id, typ: "access", exp: 1.hour.from_now.to_i }, "not-the-secret", "HS256")
      get "/api/v1/auth/me", headers: { "Authorization" => "Bearer #{forged}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
