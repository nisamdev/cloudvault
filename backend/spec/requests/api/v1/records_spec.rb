require "rails_helper"

RSpec.describe "Api::V1::Records" do
  let(:user) { create(:user) }
  let!(:family) { create(:family, owner: user) }
  let(:passphrase) { "a good long passphrase" }

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

  describe "GET /api/v1/record_templates" do
    it "returns the starting templates" do
      get "/api/v1/record_templates", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(json["templates"].map { |t| t["type"] }).to include("login", "service_account", "immigration")
      expect(json["templates"].first["fields"]).to be_present
    end
  end

  describe "GET /api/v1/records" do
    let!(:mine) { create(:vault_record, user: user, title: "Electricity") }
    let!(:other) { create(:vault_record, user: create(:user), title: "Hidden") }

    it "lists records the user can see" do
      get "/api/v1/records", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(json["records"].map { |r| r["title"] }).to include("Electricity")
      expect(json["records"].map { |r| r["title"] }).not_to include("Hidden")
    end

    it "includes family records shared with the family" do
      sibling = create(:user)
      create(:family_member, family: family, user: sibling, role: "editor")
      shared = create(:vault_record, :family, user: sibling, family: family, title: "Halifax mortgage")

      get "/api/v1/records", headers: auth_headers_for(user)

      expect(json["records"].map { |r| r["title"] }).to include("Halifax mortgage")
    end
  end

  describe "POST /api/v1/records" do
    it "creates a record from a template" do
      post "/api/v1/records",
           params: {
             record: {
               record_type: "service_account",
               title: "British Gas — electricity",
               visibility: "private",
               data: { provider: "British Gas", account_email: "home@example.com" }
             }
           },
           headers: auth_headers_for(user),
           as: :json

      expect(response).to have_http_status(:created)
      expect(json["record"]["title"]).to eq("British Gas — electricity")
      expect(json["record"]["fields"].map { |f| f["key"] }).to include("provider", "account_email")
    end

    it "stores secrets when the private section is unlocked" do
      token = set_up_vault

      post "/api/v1/records",
           params: {
             record: {
               record_type: "service_account",
               title: "British Gas — electricity",
               visibility: "private",
               data: { provider: "British Gas" }
             },
             secrets: { password: "correct horse" }
           },
           headers: vault_headers(token),
           as: :json

      expect(response).to have_http_status(:created)
      expect(json["record"]["secrets"]).to include(
        hash_including("key" => "password", "set" => true)
      )
      expect(json["record"]["data"]).not_to have_key("password")
    end

    it "refuses secrets while the private section is locked" do
      set_up_vault

      post "/api/v1/records",
           params: {
             record: {
               record_type: "service_account",
               title: "British Gas — electricity",
               visibility: "private",
               data: { provider: "British Gas" }
             },
             secrets: { password: "correct horse" }
           },
           headers: auth_headers_for(user),
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/records/:id" do
    let!(:record) do
      create(:vault_record, :immigration, user: user, title: "Ihaan's passport")
    end

    it "returns the record with its fields and template" do
      get "/api/v1/records/#{record.id}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(json["record"]["fields"]).to include(
        hash_including("key" => "document_number", "value" => "GB-123456")
      )
      expect(json["record"]["expiries"].first["key"]).to eq("expires_on")
    end
  end

  describe "PATCH /api/v1/records/:id" do
    let!(:record) { create(:vault_record, user: user) }
    let!(:file) { create(:stored_file, :with_attachment, user: user, name: "Passport.pdf") }

    it "updates fields" do
      patch "/api/v1/records/#{record.id}",
            params: { record: { data: { provider: "Octopus Energy" } } },
            headers: auth_headers_for(user),
            as: :json

      expect(response).to have_http_status(:ok)
      expect(json["record"]["data"]["provider"]).to eq("Octopus Energy")
    end

    it "links files from My Files" do
      patch "/api/v1/records/#{record.id}",
            params: { attachment_ids: [ file.id ] },
            headers: auth_headers_for(user),
            as: :json

      expect(response).to have_http_status(:ok)
      expect(json["record"]["attachments"].first["file_id"]).to eq(file.id)
      expect(json["record"]["attachments"].first["name"]).to eq("Passport.pdf")
    end
  end

  describe "DELETE /api/v1/records/:id" do
    let!(:record) { create(:vault_record, user: user) }

    it "archives the record" do
      delete "/api/v1/records/#{record.id}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:no_content)
      expect(record.reload.archived?).to be(true)
    end
  end
  # A form posts every field it drew, so most of them arrive empty. Keeping them
  # would fill the register with empty strings and pad the search vector with
  # nothing.
  describe "the fields it keeps" do
    it "stores only the fields that were filled in" do
      post "/api/v1/records",
           params: { record: { record_type: "service_account", title: "British Gas",
                               data: { provider: "British Gas", username: "", website: "",
                                       customer_ref: "GB-8842", notes: nil } } },
           headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:created)
      expect(VaultRecord.find(json["record"]["id"]).data)
        .to eq("provider" => "British Gas", "customer_ref" => "GB-8842")
    end

    it "keeps a field the template has never heard of" do
      post "/api/v1/records",
           params: { record: { record_type: "property", title: "The house",
                               data: { address: "27 Bellwood Gardens", bin_day: "Tuesday" } } },
           headers: auth_headers_for(user), as: :json

      expect(VaultRecord.find(json["record"]["id"]).data["bin_day"]).to eq("Tuesday")
    end

    it "drops a field that has been cleared" do
      record = create(:vault_record, user: user, record_type: "service_account",
                                     data: { "provider" => "British Gas", "username" => "nisam" })

      patch "/api/v1/records/#{record.id}",
            params: { record: { data: { provider: "British Gas", username: "" } } },
            headers: auth_headers_for(user), as: :json

      expect(record.reload.data).to eq("provider" => "British Gas")
    end
  end

end
