require "rails_helper"

RSpec.describe "Api::V1::RecordSecrets" do
  let(:user) { create(:user) }
  let!(:family) { create(:family, owner: user) }
  let(:passphrase) { "a good long passphrase" }
  let!(:record) { create(:vault_record, user: user) }

  def set_up_vault
    post "/api/v1/vault", params: { passphrase: passphrase }, headers: auth_headers_for(user)
    json["token"]
  end

  def unlock_vault
    post "/api/v1/vault/unlock", params: { passphrase: passphrase }, headers: auth_headers_for(user)
    json["token"]
  end

  def vault_headers(token = unlock_vault)
    auth_headers_for(user).merge("X-Vault-Key" => token)
  end

  let!(:vault_token) { set_up_vault }
  let(:vault_key) { PrivateVault.find_by!(user_id: user.id).unlock(passphrase) }
  let!(:secret) do
    create(:record_secret, vault_record: record, vault_key: vault_key, plaintext: "current-pass")
  end

  describe "GET /api/v1/records/:record_id/secrets/:key/reveal" do
    it "returns the decrypted value when unlocked" do
      get "/api/v1/records/#{record.id}/secrets/password/reveal", headers: vault_headers

      expect(response).to have_http_status(:ok)
      expect(json["value"]).to eq("current-pass")
    end

    it "refuses without the vault token" do
      get "/api/v1/records/#{record.id}/secrets/password/reveal", headers: auth_headers_for(user)

      expect(response).to have_http_status(:forbidden)
      expect(json.dig("error", "code")).to eq("vault_locked")
    end
  end

  describe "GET /api/v1/records/:record_id/secrets/:key/history" do
    before do
      secret.secret_versions.create!(
        sealed: VaultCipher.seal(vault_key, "old-pass"),
        replaced_at: 1.day.ago
      )
    end

    it "lists previous versions without their values" do
      get "/api/v1/records/#{record.id}/secrets/password/history", headers: vault_headers

      expect(response).to have_http_status(:ok)
      expect(json["versions"].first).to include("id", "replaced_at")
      expect(json["versions"].first).not_to have_key("value")
    end
  end

  describe "PATCH /api/v1/records/:id with secrets" do
    it "keeps the old value in history when replaced" do
      patch "/api/v1/records/#{record.id}",
            params: { secrets: { password: "new-pass" } },
            headers: vault_headers,
            as: :json

      expect(response).to have_http_status(:ok)

      get "/api/v1/records/#{record.id}/secrets/password/reveal", headers: vault_headers
      expect(json["value"]).to eq("new-pass")

      get "/api/v1/records/#{record.id}/secrets/password/history", headers: vault_headers
      expect(json["versions"].length).to eq(1)

      version_id = json["versions"].first["id"]
      get "/api/v1/records/#{record.id}/secrets/password/history/#{version_id}/reveal",
          headers: vault_headers

      expect(json["value"]).to eq("current-pass")
    end
  end
end
