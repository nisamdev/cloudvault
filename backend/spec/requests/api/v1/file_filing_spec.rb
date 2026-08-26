require "rails_helper"
require "vips"

# Where a file *lives* — Photos or My Files — versus what it *is*. A
# photographed certificate is a JPEG either way; only its owner knows it is a
# document.
RSpec.describe "Api::V1::Files filing" do
  let(:user) { create(:user) }
  let!(:family) { create(:family, owner: user) }

  def jpeg(width: 200, height: 300)
    Vips::Image.black(width, height).add(200).cast(:uchar).colourspace("srgb").write_to_buffer(".jpg")
  end

  def certificate(owner: user, **attrs)
    file = create(:stored_file, user: owner, name: "Certificate.jpg",
                                mime_type: "image/jpeg", file_type: "image", **attrs)
    file.attachment.attach(io: StringIO.new(jpeg), filename: "Certificate.jpg", content_type: "image/jpeg")
    file
  end

  def file_as(file, type, as: user)
    patch "/api/v1/files/#{file.id}", params: { file_type: type }, headers: auth_headers_for(as), as: :json
  end

  def listed(type)
    get "/api/v1/files", params: { file_type: type }, headers: auth_headers_for(user)
    json["files"].map { |f| f["id"] }
  end

  describe "moving a photographed document to My Files" do
    it "takes it out of Photos and puts it in with the documents" do
      photo = certificate

      expect(listed("image")).to include(photo.id)

      file_as(photo, "file")

      expect(response).to have_http_status(:ok)
      expect(listed("image")).not_to include(photo.id)
      expect(listed("file")).to include(photo.id)
    end

    it "still knows the file is a picture, so the row keeps its thumbnail" do
      photo = certificate
      file_as(photo, "file")

      expect(json["file"]["file_type"]).to eq("file")
      # The image block describes the bytes, which have not changed.
      expect(json["file"]["image"]).to be_present
      expect(json["file"]["filed_as_document"]).to be(true)
    end

    it "can be undone" do
      photo = certificate
      file_as(photo, "file")
      file_as(photo, "image")
      # Read before `listed` runs a request of its own over the top of it.
      undone = json["file"]

      expect(undone["filed_as_document"]).to be(false)
      expect(listed("image")).to include(photo.id)
    end

    # The whole point of recording that a person chose this: uploading a better
    # scan of the same certificate must not send it back to the gallery.
    it "survives a new version of the same file" do
      photo = certificate
      file_as(photo, "file")

      upload = Rack::Test::UploadedFile.new(StringIO.new(jpeg(width: 400, height: 600)),
                                            "image/jpeg", original_filename: "Certificate.jpg")
      post "/api/v1/files", params: { file: upload }, headers: auth_headers_for(user)

      expect(photo.reload.version_number).to eq(2)
      expect(photo.file_type).to eq("file")
    end
  end

  describe "what cannot be filed as a photo" do
    it "refuses a document that is not a picture" do
      pdf = create(:stored_file, user: user, name: "Deed.pdf", mime_type: "application/pdf", file_type: "file")

      file_as(pdf, "image")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["message"]).to include("Deed.pdf")
      expect(pdf.reload.file_type).to eq("file")
    end

    it "refuses a type that is neither" do
      file_as(certificate, "video")

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses somebody who cannot edit the file" do
      stranger = create(:user)
      photo = certificate

      file_as(photo, "file", as: stranger)

      expect(response).to have_http_status(:not_found)
      expect(photo.reload.file_type).to eq("image")
    end
  end

  describe "files nobody has filed by hand" do
    it "still follows the mime type" do
      photo = certificate

      expect(photo.file_type_pinned).to be(false)
      expect(listed("image")).to include(photo.id)
    end

    # Guards the branch in FileUploader: an unpinned file re-uploaded as a
    # different type should follow the new bytes.
    it "follows the new bytes when a version changes the type" do
      photo = certificate

      pdf = Rack::Test::UploadedFile.new(StringIO.new(Prawn::Document.new.render),
                                         "application/pdf", original_filename: "Certificate.jpg")
      post "/api/v1/files", params: { file: pdf }, headers: auth_headers_for(user)

      expect(photo.reload.file_type).to eq("file")
      expect(photo.file_type_pinned).to be(false)
    end
  end
end
