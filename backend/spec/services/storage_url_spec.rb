require "rails_helper"

RSpec.describe StorageUrl do
  # Whether a presigned URL is any use depends entirely on who is asking, so
  # every case here is the same file seen from a different network.
  around do |example|
    original = ENV.to_h.slice("S3_PUBLIC_ENDPOINT", "S3_ENDPOINT", "STORAGE_DELIVERY")
    example.run
    ENV["S3_PUBLIC_ENDPOINT"] = original["S3_PUBLIC_ENDPOINT"]
    ENV["S3_ENDPOINT"] = original["S3_ENDPOINT"]
    ENV["STORAGE_DELIVERY"] = original["STORAGE_DELIVERY"]
    Current.request_origin = nil
  end

  def presignable_from(origin, endpoint:)
    ENV["S3_PUBLIC_ENDPOINT"] = endpoint
    Current.request_origin = origin
    described_class.presignable?
  end

  describe "choosing between a presigned URL and streaming" do
    it "presigns for a browser on the machine storage is bound to" do
      expect(presignable_from("http://localhost:5273", endpoint: "http://localhost:9100")).to be true
    end

    it "streams for a phone on the LAN, which cannot resolve the server's localhost" do
      expect(presignable_from("http://192.168.21.244:5273", endpoint: "http://localhost:9100")).to be false
    end

    it "streams over a tunnel" do
      origin = "https://something.trycloudflare.com"
      expect(presignable_from(origin, endpoint: "http://localhost:9100")).to be false
    end

    it "presigns against a genuinely public endpoint, so production bytes skip the app" do
      origin = "https://vault.example.com"
      endpoint = "https://abc123.r2.cloudflarestorage.com"
      expect(presignable_from(origin, endpoint: endpoint)).to be true
    end

    it "streams when storage is a private address, wherever the caller is" do
      expect(presignable_from("https://vault.example.com", endpoint: "http://10.0.0.5:9000")).to be false
      expect(presignable_from("https://vault.example.com", endpoint: "http://minio:9000")).to be false
    end

    it "can be forced either way" do
      ENV["STORAGE_DELIVERY"] = "proxy"
      expect(presignable_from("http://localhost:5273", endpoint: "http://localhost:9100")).to be false

      ENV["STORAGE_DELIVERY"] = "presigned"
      expect(presignable_from("https://tunnel.example.com", endpoint: "http://localhost:9100")).to be true
    end
  end

  describe "the streamed URL" do
    let(:file) { create(:stored_file, :with_attachment) }

    before do
      ENV["S3_PUBLIC_ENDPOINT"] = "http://localhost:9100"
      Current.request_origin = "https://tunnel.example.com"
    end

    it "is on the origin the browser actually used" do
      url = described_class.for(file.attachment, disposition: "attachment", filename: "Passport.pdf")

      expect(url).to start_with("https://tunnel.example.com/api/v1/blobs/")
    end

    it "carries the name the file has now, not the one the blob was uploaded under" do
      url = described_class.for(file.attachment, disposition: "attachment", filename: "Renamed.pdf")
      payload = JwtService.decode_blob(url.split("/blobs/").last)

      expect(payload["filename"]).to eq("Renamed.pdf")
      expect(payload["disposition"]).to eq("attachment")
      expect(payload["key"]).to eq(file.attachment.blob.key)
    end

    it "expires, so a leaked URL stops working" do
      url = described_class.for(file.attachment, expires_in: 5.minutes)
      payload = JwtService.decode_blob(url.split("/blobs/").last)

      expect(payload["exp"]).to be_within(10).of(5.minutes.from_now.to_i)
    end
  end
end
