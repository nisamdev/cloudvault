require "rails_helper"

RSpec.describe "Api::V1::Labels and search" do
  let(:owner) { create(:user) }
  let!(:family) { create(:family, owner: owner) }
  let(:editor) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") } }
  let(:stranger) { create(:user) }

  describe "POST /api/v1/labels" do
    it "creates a label shared with the family" do
      post "/api/v1/labels", params: { label: { name: "Important", color: "#EF4444" } },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json["label"]["name"]).to eq("Important")
      expect(json["label"]["shared"]).to be true
    end

    it "creates a personal label for a user with no family" do
      post "/api/v1/labels", params: { label: { name: "Mine" } },
           headers: auth_headers_for(stranger), as: :json

      expect(json["label"]["shared"]).to be false
    end

    it "rejects a duplicate name regardless of case" do
      post "/api/v1/labels", params: { label: { name: "Taxes" } },
           headers: auth_headers_for(owner), as: :json
      post "/api/v1/labels", params: { label: { name: "taxes" } },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["details"]).to have_key("name")
    end

    it "rejects a malformed colour" do
      post "/api/v1/labels", params: { label: { name: "Bad", color: "red" } },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "lets another family member reuse the shared vocabulary" do
      post "/api/v1/labels", params: { label: { name: "Receipts" } },
           headers: auth_headers_for(owner), as: :json

      get "/api/v1/labels", headers: auth_headers_for(editor)

      expect(json["labels"].map { |l| l["name"] }).to include("Receipts")
    end

    it "hides one family's labels from outsiders" do
      post "/api/v1/labels", params: { label: { name: "Receipts" } },
           headers: auth_headers_for(owner), as: :json

      get "/api/v1/labels", headers: auth_headers_for(stranger)

      expect(json["labels"]).to be_empty
    end
  end

  describe "labelling files" do
    let(:file) { create(:stored_file, user: owner, name: "Mortgage_Agreement.pdf") }
    let(:important) { Label.create!(user: owner, family: family, name: "Important") }
    let(:taxes) { Label.create!(user: owner, family: family, name: "Taxes") }

    it "assigns labels to a file" do
      patch "/api/v1/files/#{file.id}", params: { label_ids: [ important.id, taxes.id ] },
            headers: auth_headers_for(owner), as: :json

      expect(json["file"]["labels"].map { |l| l["name"] }).to contain_exactly("Important", "Taxes")
    end

    it "replaces the set rather than appending" do
      patch "/api/v1/files/#{file.id}", params: { label_ids: [ important.id, taxes.id ] },
            headers: auth_headers_for(owner), as: :json
      patch "/api/v1/files/#{file.id}", params: { label_ids: [ taxes.id ] },
            headers: auth_headers_for(owner), as: :json

      expect(json["file"]["labels"].map { |l| l["name"] }).to contain_exactly("Taxes")
    end

    it "clears labels when given an empty list" do
      patch "/api/v1/files/#{file.id}", params: { label_ids: [ important.id ] },
            headers: auth_headers_for(owner), as: :json
      patch "/api/v1/files/#{file.id}", params: { label_ids: [] },
            headers: auth_headers_for(owner), as: :json

      expect(json["file"]["labels"]).to be_empty
    end

    it "silently ignores labels belonging to another family" do
      foreign = Label.create!(user: stranger, name: "Theirs")

      patch "/api/v1/files/#{file.id}", params: { label_ids: [ important.id, foreign.id ] },
            headers: auth_headers_for(owner), as: :json

      expect(json["file"]["labels"].map { |l| l["name"] }).to contain_exactly("Important")
    end

    it "counts labelled files" do
      patch "/api/v1/files/#{file.id}", params: { label_ids: [ important.id ] },
            headers: auth_headers_for(owner), as: :json

      get "/api/v1/labels", headers: auth_headers_for(owner)

      row = json["labels"].find { |l| l["name"] == "Important" }
      expect(row["files_count"]).to eq(1)
    end
  end

  describe "DELETE /api/v1/labels/:id" do
    it "removes the label without touching the files" do
      file = create(:stored_file, user: owner)
      label = Label.create!(user: owner, family: family, name: "Temp")
      FileLabel.create!(stored_file: file, label: label)

      expect {
        delete "/api/v1/labels/#{label.id}", headers: auth_headers_for(owner)
      }.to change(Label, :count).by(-1)

      expect(response).to have_http_status(:no_content)
      expect(file.reload).to be_persisted
      expect(file.labels).to be_empty
    end
  end

  describe "GET /api/v1/files with search" do
    let!(:mortgage) { create(:stored_file, user: owner, name: "Mortgage_Agreement.pdf") }
    let!(:holiday) { create(:stored_file, user: owner, name: "Holiday Photos 2026.zip") }
    let!(:receipt) { create(:stored_file, user: owner, name: "receipt-january.pdf") }

    def found
      json["files"].map { |f| f["name"] }
    end

    it "matches a word inside an underscored filename" do
      get "/api/v1/files", params: { q: "mortgage" }, headers: auth_headers_for(owner)

      expect(found).to contain_exactly("Mortgage_Agreement.pdf")
    end

    it "matches a word inside a hyphenated filename" do
      get "/api/v1/files", params: { q: "january" }, headers: auth_headers_for(owner)

      expect(found).to contain_exactly("receipt-january.pdf")
    end

    it "matches a partial word" do
      get "/api/v1/files", params: { q: "mortg" }, headers: auth_headers_for(owner)

      expect(found).to contain_exactly("Mortgage_Agreement.pdf")
    end

    it "is case-insensitive" do
      get "/api/v1/files", params: { q: "HOLIDAY" }, headers: auth_headers_for(owner)

      expect(found).to contain_exactly("Holiday Photos 2026.zip")
    end

    it "finds files by the name of a label they carry" do
      label = Label.create!(user: owner, family: family, name: "Taxes")
      FileLabel.create!(stored_file: mortgage, label: label)

      get "/api/v1/files", params: { q: "taxes" }, headers: auth_headers_for(owner)

      expect(found).to contain_exactly("Mortgage_Agreement.pdf")
    end

    it "returns nothing for a term that matches nothing" do
      get "/api/v1/files", params: { q: "zzzznomatch" }, headers: auth_headers_for(owner)

      expect(found).to be_empty
    end

    it "searches across folders, not just the current one" do
      folder = Folder.create!(user: owner, name: "Legal")
      mortgage.update!(folder: folder)

      get "/api/v1/files", params: { q: "mortgage" }, headers: auth_headers_for(owner)

      expect(found).to contain_exactly("Mortgage_Agreement.pdf")
    end

    it "never leaks another user's files" do
      create(:stored_file, user: stranger, name: "Mortgage_Secret.pdf")

      get "/api/v1/files", params: { q: "mortgage" }, headers: auth_headers_for(owner)

      expect(found).to contain_exactly("Mortgage_Agreement.pdf")
    end

    it "treats a search term with special characters literally" do
      get "/api/v1/files", params: { q: "100%_" }, headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(found).to be_empty
    end
  end

  describe "GET /api/v1/files with filters" do
    let(:label) { Label.create!(user: owner, family: family, name: "Important") }
    let(:other_label) { Label.create!(user: owner, family: family, name: "Archive") }
    let(:folder) { Folder.create!(user: owner, name: "Legal") }
    let!(:in_folder) { create(:stored_file, user: owner, folder: folder, name: "Deed.pdf") }
    let!(:at_root) { create(:stored_file, user: owner, name: "Root.pdf") }

    it "filters to one folder" do
      get "/api/v1/files", params: { folder_id: folder.id }, headers: auth_headers_for(owner)

      expect(json["files"].map { |f| f["name"] }).to contain_exactly("Deed.pdf")
    end

    it "filters to the root with a blank folder_id" do
      get "/api/v1/files", params: { folder_id: "" }, headers: auth_headers_for(owner)

      expect(json["files"].map { |f| f["name"] }).to contain_exactly("Root.pdf")
    end

    it "filters by label" do
      FileLabel.create!(stored_file: in_folder, label: label)

      get "/api/v1/files", params: { label_ids: [ label.id ] }, headers: auth_headers_for(owner)

      expect(json["files"].map { |f| f["name"] }).to contain_exactly("Deed.pdf")
    end

    it "requires every label when several are given" do
      FileLabel.create!(stored_file: in_folder, label: label)
      FileLabel.create!(stored_file: at_root, label: label)
      FileLabel.create!(stored_file: at_root, label: other_label)

      get "/api/v1/files", params: { label_ids: [ label.id, other_label.id ] },
          headers: auth_headers_for(owner)

      expect(json["files"].map { |f| f["name"] }).to contain_exactly("Root.pdf")
    end

    it "includes the folder and labels in each result" do
      FileLabel.create!(stored_file: in_folder, label: label)

      get "/api/v1/files", params: { folder_id: folder.id }, headers: auth_headers_for(owner)

      row = json["files"].first
      expect(row["folder"]["name"]).to eq("Legal")
      expect(row["labels"].first["name"]).to eq("Important")
    end
  end
end
