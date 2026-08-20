require "rails_helper"
require "vips"

RSpec.describe MetadataStripper do
  describe ".strippable?" do
    it "knows the image formats it can clean" do
      expect(described_class.strippable?("image/jpeg")).to be true
      expect(described_class.strippable?("image/heic")).to be true
      expect(described_class.strippable?("image/png")).to be true
    end

    it "leaves anything that is not an image alone" do
      expect(described_class.strippable?("application/pdf")).to be false
      expect(described_class.strippable?("text/plain")).to be false
    end
  end

  describe ".output_for" do
    it "keeps the format for anything it can write back" do
      expect(described_class.output_for("image/jpeg")).to eq(content_type: "image/jpeg", extension: nil)
    end

    # This build of libvips decodes HEIC but cannot encode it.
    it "says HEIC comes back as a JPEG" do
      expect(described_class.output_for("image/heic")).to eq(content_type: "image/jpeg", extension: ".jpg")
    end
  end

  describe "JPEG" do
    let(:jpeg) do
      Vips::Image.black(80, 60).add(200).cast("uchar").bandjoin([ 200, 200 ]).write_to_buffer(".jpg")
    end

    # libvips writes its own EXIF block, so even a freshly encoded JPEG has
    # something to remove.
    it "removes the metadata libvips itself wrote" do
      expect(jpeg).to include("Exif")

      result = described_class.call(jpeg, content_type: "image/jpeg")

      expect(result.bytes).not_to include("Exif")
      expect(Vips::Image.new_from_buffer(result.bytes, "").width).to eq(80)
    end

    it "removes an APP1 block without touching the image data" do
      # APP1: marker, length, then payload.
      payload = "Exif\0\0#{'GPS coordinates live here'.b}"
      app1 = [ 0xFF, 0xE1 ].pack("C*") + [ payload.bytesize + 2 ].pack("n") + payload
      with_exif = jpeg.byteslice(0, 2) + app1 + jpeg.byteslice(2..)

      result = described_class.call(with_exif, content_type: "image/jpeg")

      expect(result.bytes).not_to include("GPS coordinates live here")
      # Adding a metadata block and removing it again is a round trip to the
      # same bytes, which is what "lossless" means here — nothing recompressed.
      expect(result.bytes.b).to eq(described_class.call(jpeg, content_type: "image/jpeg").bytes.b)
      expect(result.content_type).to eq("image/jpeg")
    end

    it "hands back something still decodable" do
      result = described_class.call(jpeg, content_type: "image/jpeg")
      image = Vips::Image.new_from_buffer(result.bytes, "")

      expect([ image.width, image.height ]).to eq([ 80, 60 ])
    end
  end

  describe "PNG" do
    let(:png) { Vips::Image.black(40, 40).add(10).cast("uchar").write_to_buffer(".png") }

    it "drops a text chunk and leaves the image readable" do
      # tEXt chunk: length, type, data, CRC.
      data = "Comment\0taken at home".b
      chunk = [ data.bytesize ].pack("N") + "tEXt" + data + [ 0 ].pack("N")
      # Insert after the 8-byte signature and the IHDR chunk.
      ihdr_end = 8 + 25
      with_text = png.byteslice(0, ihdr_end) + chunk + png.byteslice(ihdr_end..)

      result = described_class.call(with_text, content_type: "image/png")

      expect(result.bytes).not_to include("taken at home")
      expect(Vips::Image.new_from_buffer(result.bytes, "").width).to eq(40)
    end
  end

  describe "when it cannot clean something" do
    it "returns the bytes rather than failing the download" do
      result = described_class.call("not an image at all", content_type: "image/jpeg")

      expect(result.bytes).to eq("not an image at all")
    end

    it "passes non-images straight through" do
      result = described_class.call("%PDF-1.4", content_type: "application/pdf")

      expect(result.bytes).to eq("%PDF-1.4")
    end
  end
end
