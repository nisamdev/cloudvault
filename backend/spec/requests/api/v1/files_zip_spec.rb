require "rails_helper"

RSpec.describe "Api::V1::Files zip download" do
  let(:user) { create(:user) }
  let!(:family) { create(:family, owner: user) }

  def document
    @document ||= Prawn::Document.new.tap { |d| d.text "hello" }.render
  end

  def upload!(name:)
    post "/api/v1/files",
         params: { file: Rack::Test::UploadedFile.new(
           StringIO.new(document), "application/pdf", original_filename: name
         ) },
         headers: auth_headers_for(user)
    StoredFile.find(json.dig("file", "id"))
  end

  it "hands back a URL that streams a ZIP of the selection" do
    a = upload!(name: "a.pdf")
    b = upload!(name: "b.pdf")

    post "/api/v1/files/zip_url",
         params: { file_ids: [ a.id, b.id ] },
         headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    expect(json["file_count"]).to eq(2)
    expect(json["url"]).to include("/api/v1/files/zip?token=")

    get json["url"].sub(%r{\Ahttps?://[^/]+}, "")
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("zip")
  end

  it "refuses an empty selection" do
    post "/api/v1/files/zip_url", params: { file_ids: [] }, headers: auth_headers_for(user)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "refuses a stranger's files" do
    file = upload!(name: "mine.pdf")
    stranger = create(:user)

    post "/api/v1/files/zip_url",
         params: { file_ids: [ file.id ] },
         headers: auth_headers_for(stranger)

    expect(response).to have_http_status(:unprocessable_content)
  end
end
