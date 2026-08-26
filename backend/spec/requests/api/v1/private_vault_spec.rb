require "rails_helper"
require "vips"

# What the private section is *for*. Every one of these is a way somebody could
# reach a locked file without the passphrase, and every one has to fail.
RSpec.describe "Api::V1::Vault" do
  let(:user) { create(:user) }
  let!(:family) { create(:family, owner: user) }
  let(:passphrase) { "a good long passphrase" }

  def headers(token = nil)
    base = auth_headers_for(user)
    token ? base.merge("X-Vault-Key" => token) : base
  end

  def set_up_vault
    post "/api/v1/vault", params: { passphrase: passphrase }, headers: auth_headers_for(user)
    [ json["token"], json["recovery_key"] ]
  end

  def unlock
    post "/api/v1/vault/unlock", params: { passphrase: passphrase }, headers: auth_headers_for(user)
    json["token"]
  end

  def private_folder(token)
    folder = create(:folder, user: user, name: "Passports")
    post "/api/v1/folders/#{folder.id}/lock", headers: headers(token)
    folder.reload
  end

  # The document these tests protect. Kept so a decrypted file can be compared
  # against it byte for byte — Prawn compresses its content streams, so looking
  # for the words inside the PDF would prove nothing either way.
  def document
    @document ||= Prawn::Document.new.tap { |d| d.text "PASSPORT NUMBER 12345" }.render
  end

  def upload(folder:, token: nil, name: "passport.pdf")
    post "/api/v1/files",
         params: { file: Rack::Test::UploadedFile.new(
           StringIO.new(document), "application/pdf", original_filename: name
         ), folder_id: folder.id },
         headers: headers(token)
    StoredFile.find_by(id: json.dig("file", "id"))
  end

  describe "setting it up" do
    it "hands back a recovery key exactly once" do
      token, recovery = set_up_vault

      expect(response).to have_http_status(:created)
      expect(recovery).to be_present
      expect(token).to be_present

      get "/api/v1/vault", headers: headers(token)
      expect(json).not_to have_key("recovery_key")
      expect(json["exists"]).to be(true)
      expect(json["unlocked"]).to be(true)
    end

    it "refuses a second one" do
      set_up_vault
      post "/api/v1/vault", params: { passphrase: passphrase }, headers: auth_headers_for(user)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "a file in the private section" do
    let!(:token) { set_up_vault.first }
    let!(:folder) { private_folder(token) }
    let!(:file) { upload(folder: folder, token: token) }

    it "is encrypted in storage, not merely flagged" do
      expect(file.encrypted?).to be(true)
      expect(file.locked?).to be(true)

      stored = file.attachment.download
      expect(stored).not_to eq(document)
      expect(stored).not_to start_with("%PDF")
    end

    it "is absent from the file list when the section is locked" do
      get "/api/v1/files", headers: auth_headers_for(user)

      expect(json["files"].map { |f| f["id"] }).not_to include(file.id)
    end

    it "is absent from search, which spans everything else" do
      get "/api/v1/files", params: { q: "passport" }, headers: auth_headers_for(user)

      expect(json["files"]).to be_empty
    end

    it "cannot be opened, previewed or downloaded when locked" do
      %w[/ /preview /download /content /text].each do |suffix|
        get "/api/v1/files/#{file.id}#{suffix.sub(%r{\A/\z}, "")}", headers: auth_headers_for(user)
        expect(response).to have_http_status(:not_found), "#{suffix} answered #{response.status}"
      end
    end

    it "cannot be reached with somebody else's unlock token" do
      other = create(:user)
      post "/api/v1/vault", params: { passphrase: passphrase }, headers: auth_headers_for(other)
      stolen = json["token"]

      get "/api/v1/files/#{file.id}", headers: auth_headers_for(user).merge("X-Vault-Key" => stolen)

      expect(response).to have_http_status(:not_found)
    end

    it "cannot be reached with a made-up token" do
      get "/api/v1/files/#{file.id}", headers: headers("deadbeef.notarealsecret")

      expect(response).to have_http_status(:not_found)
    end

    it "comes back whole once the section is open" do
      get "/api/v1/files/#{file.id}/content", headers: headers(token)

      expect(response).to have_http_status(:ok)
      expect(response.body.b).to eq(document.b)
    end

    it "appears in the list, and only there, once the section is open" do
      get "/api/v1/files", params: { locked: "true" }, headers: headers(token)

      expect(json["files"].map { |f| f["id"] }).to eq([ file.id ])
    end

    it "cannot be given a public link" do
      post "/api/v1/files/#{file.id}/shares", headers: headers(token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("file_locked")
    end

    it "cannot be shared with a person" do
      post "/api/v1/files/#{file.id}/grants",
           params: { email: create(:user).email, role: "viewer" }, headers: headers(token)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "the folder" do
    let!(:token) { set_up_vault.first }

    it "hides itself and takes what is in it with it" do
      folder = create(:folder, user: user, name: "Passports")
      file = upload(folder: folder)
      expect(file.encrypted?).to be(false)

      post "/api/v1/folders/#{folder.id}/lock", headers: headers(token)
      expect(response).to have_http_status(:ok)
      expect(file.reload.encrypted?).to be(true)

      get "/api/v1/folders", headers: auth_headers_for(user)
      expect(json["folders"].map { |f| f["id"] }).not_to include(folder.id)
    end

    it "takes the folders below it too" do
      parent = create(:folder, user: user, name: "Private")
      child = create(:folder, user: user, name: "Passports", parent: parent)
      inside = upload(folder: child)

      post "/api/v1/folders/#{parent.id}/lock", headers: headers(token)

      expect(child.reload.locked?).to be(true)
      expect(inside.reload.encrypted?).to be(true)
    end

    it "gives everything back when it is brought out again" do
      folder = private_folder(token)
      file = upload(folder: folder, token: token)

      delete "/api/v1/folders/#{folder.id}/lock", headers: headers(token)

      expect(response).to have_http_status(:ok)
      expect(file.reload.encrypted?).to be(false)
      expect(file.attachment.download.b).to eq(document.b)
    end

    it "cannot be locked without the passphrase" do
      folder = create(:folder, user: user)

      post "/api/v1/folders/#{folder.id}/lock", headers: auth_headers_for(user)

      expect(response).to have_http_status(:forbidden)
      expect(folder.reload.locked?).to be(false)
    end
  end

  describe "moving a file across the boundary" do
    let!(:token) { set_up_vault.first }
    let!(:locked_folder) { private_folder(token) }

    it "encrypts it on the way in" do
      file = upload(folder: create(:folder, user: user))

      patch "/api/v1/files/#{file.id}", params: { folder_id: locked_folder.id },
            headers: headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(file.reload.encrypted?).to be(true)
      expect(file.attachment.download).not_to eq(document)
    end

    it "decrypts it on the way out" do
      file = upload(folder: locked_folder, token: token)
      open_folder = create(:folder, user: user, name: "Ordinary")

      patch "/api/v1/files/#{file.id}", params: { folder_id: open_folder.id },
            headers: headers(token), as: :json

      expect(file.reload.encrypted?).to be(false)
      expect(file.attachment.download.b).to eq(document.b)
    end

    it "refuses to move anything in or out while the section is locked" do
      file = upload(folder: create(:folder, user: user))

      patch "/api/v1/files/#{file.id}", params: { folder_id: locked_folder.id },
            headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:not_found).or have_http_status(:forbidden)
      expect(file.reload.encrypted?).to be(false)
    end
  end

  describe "locking a single file" do
    let!(:token) { set_up_vault.first }

    def plain_upload(name: "passport.pdf")
      post "/api/v1/files",
           params: { file: Rack::Test::UploadedFile.new(
             StringIO.new(document), "application/pdf", original_filename: name
           ) },
           headers: auth_headers_for(user)
      StoredFile.find_by(id: json.dig("file", "id"))
    end

    it "encrypts it and puts it in a private folder" do
      file = plain_upload

      post "/api/v1/files/#{file.id}/lock", headers: headers(token)

      expect(response).to have_http_status(:ok)
      file.reload
      expect(file.encrypted?).to be(true)
      expect(file.locked?).to be(true)
      expect(file.folder).to be_present
      expect(file.folder.locked?).to be(true)
      expect(file.attachment.download).not_to eq(document)
    end

    it "reuses the same private folder for later files" do
      first = plain_upload(name: "one.pdf")
      second = plain_upload(name: "two.pdf")

      post "/api/v1/files/#{first.id}/lock", headers: headers(token)
      post "/api/v1/files/#{second.id}/lock", headers: headers(token)

      expect(first.reload.folder_id).to eq(second.reload.folder_id)
    end

    it "brings it back out decrypted" do
      file = plain_upload
      post "/api/v1/files/#{file.id}/lock", headers: headers(token)

      delete "/api/v1/files/#{file.id}/lock", headers: headers(token)

      expect(response).to have_http_status(:ok)
      file.reload
      expect(file.encrypted?).to be(false)
      expect(file.locked?).to be(false)
      expect(file.folder_id).to be_nil
      expect(file.attachment.download.b).to eq(document.b)
    end

    it "cannot be locked without the passphrase" do
      file = plain_upload

      post "/api/v1/files/#{file.id}/lock", headers: auth_headers_for(user)

      expect(response).to have_http_status(:forbidden)
      expect(file.reload.encrypted?).to be(false)
    end
  end

  describe "getting back in" do
    it "opens with the right passphrase and refuses the wrong one" do
      set_up_vault

      expect(unlock).to be_present

      post "/api/v1/vault/unlock", params: { passphrase: "not it" }, headers: auth_headers_for(user)
      expect(response).to have_http_status(:unauthorized)
    end

    it "locks again on request" do
      token = set_up_vault.first

      delete "/api/v1/vault/unlock", headers: headers(token)
      expect(json["unlocked"]).to be(false)

      get "/api/v1/vault", headers: headers(token)
      expect(json["unlocked"]).to be(false)
    end

    # The whole reason for choosing a recovery key.
    it "lets the recovery key set a new passphrase, and the files still open" do
      token, recovery = set_up_vault
      folder = private_folder(token)
      file = upload(folder: folder, token: token)

      post "/api/v1/vault/recover",
           params: { recovery_key: recovery, passphrase: "a completely new passphrase" },
           headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      fresh = json["token"]
      expect(json["recovery_key"]).to be_present
      expect(json["recovery_key"]).not_to eq(recovery)

      get "/api/v1/files/#{file.id}/content", headers: headers(fresh)
      expect(response.body.b).to eq(document.b)
    end

    it "refuses a recovery key that is not the one" do
      set_up_vault

      post "/api/v1/vault/recover",
           params: { recovery_key: VaultCipher.generate_recovery_key, passphrase: "x" * 12 },
           headers: auth_headers_for(user)

      expect(response).to have_http_status(:unauthorized)
    end

    it "changes the passphrase without disturbing the files" do
      token, = set_up_vault
      file = upload(folder: private_folder(token), token: token)

      patch "/api/v1/vault/passphrase",
            params: { current_passphrase: passphrase, passphrase: "another good passphrase" },
            headers: headers(token)

      expect(response).to have_http_status(:ok)
      get "/api/v1/files/#{file.id}/content", headers: headers(json["token"])
      expect(response.body.b).to eq(document.b)
    end
  end
end
