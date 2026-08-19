require "rails_helper"

RSpec.describe ExifExtractor do
  # A real, valid JPEG from libvips with an EXIF APP1 segment spliced in after
  # SOI. Hand-writing the whole JPEG produces a file exifr rejects outright.
  def jpeg_with_exif(app1)
    base = Vips::Image.black(32, 32).add(128).cast("uchar").colourspace("srgb").jpegsave_buffer(Q: 70)
    base[0, 2] + app1 + base[2..]
  end

  def app1_with_gps(lat:, lon:, lat_ref: "N", lon_ref: "W")
    def rational(num, den) = [ num, den ].pack("NN")

    dms = lambda do |value|
      degrees = value.to_i
      minutes_f = (value - degrees) * 60
      minutes = minutes_f.to_i
      seconds = ((minutes_f - minutes) * 6000).round
      rational(degrees, 1) + rational(minutes, 1) + rational(seconds, 100)
    end

    tiff = "MM\x00\x2a".b + [ 8 ].pack("N")
    gps_offset = 8 + 2 + 12 + 4
    ifd0 = [ 1 ].pack("n") + [ 0x8825, 4, 1, gps_offset ].pack("nnNN") + [ 0 ].pack("N")

    entries = 4
    data_start = gps_offset + 2 + (12 * entries) + 4
    lat_bytes = dms.call(lat.abs)
    lon_bytes = dms.call(lon.abs)

    gps = [ entries ].pack("n")
    gps += [ 1, 2, 2 ].pack("nnN") + lat_ref.b + "\x00\x00\x00".b
    gps += [ 2, 5, 3, data_start ].pack("nnNN")
    gps += [ 3, 2, 2 ].pack("nnN") + lon_ref.b + "\x00\x00\x00".b
    gps += [ 4, 5, 3, data_start + lat_bytes.bytesize ].pack("nnNN")
    gps += [ 0 ].pack("N") + lat_bytes + lon_bytes

    exif = "Exif\x00\x00".b + tiff + ifd0 + gps
    "\xff\xe1".b + [ exif.bytesize + 2 ].pack("n") + exif
  end

  def extract(bytes, type: "image/jpeg")
    described_class.call(StringIO.new(bytes), content_type: type)
  end

  describe "GPS coordinates" do
    it "reads latitude and longitude" do
      bytes = jpeg_with_exif(app1_with_gps(lat: 51.500729, lon: -0.124625))

      result = extract(bytes)

      expect(result.latitude).to be_within(0.001).of(51.5007)
      expect(result.longitude).to be_within(0.001).of(-0.1246)
    end

    it "applies the hemisphere references" do
      bytes = jpeg_with_exif(app1_with_gps(lat: 33.8688, lon: 151.2093, lat_ref: "S", lon_ref: "E"))

      result = extract(bytes)

      # Sydney: south and east, so the signs must flip the other way.
      expect(result.latitude).to be < 0
      expect(result.longitude).to be > 0
    end

    it "returns nothing for a photo with no GPS block" do
      base = Vips::Image.black(16, 16).cast("uchar").colourspace("srgb").jpegsave_buffer

      result = extract(base)

      expect(result.latitude).to be_nil
      expect(result.longitude).to be_nil
    end
  end

  describe "unsupported and broken input" do
    it "ignores formats that carry no EXIF" do
      png = Vips::Image.black(16, 16).cast("uchar").colourspace("srgb").pngsave_buffer

      result = extract(png, type: "image/png")

      expect(result.any?).to be false
    end

    it "survives a truncated file" do
      bytes = jpeg_with_exif(app1_with_gps(lat: 1.0, lon: 1.0)).byteslice(0, 40)

      expect { extract(bytes) }.not_to raise_error
      expect(extract(bytes).any?).to be false
    end

    it "survives bytes that are not an image at all" do
      expect(extract("this is not a jpeg").any?).to be false
    end
  end

  describe "#to_h" do
    it "drops the keys it found nothing for" do
      png = Vips::Image.black(8, 8).cast("uchar").colourspace("srgb").pngsave_buffer

      expect(extract(png, type: "image/png").to_h).to eq({})
    end
  end
end

RSpec.describe "capture date ordering" do
  let(:owner) { create(:user) }

  # Upload time is the default so that sorting agrees with the date filters and
  # the gallery's date headings, which both work on upload time.
  it "sorts by upload time by default, even when capture dates disagree" do
    recently_uploaded = create(:stored_file, :image, user: owner, name: "Holiday.jpg",
                               taken_at: 1.year.ago, created_at: Time.current)
    create(:stored_file, :image, user: owner, name: "Breakfast.jpg",
           taken_at: 1.hour.ago, created_at: 2.days.ago)

    names = StoredFile.images.sorted_by("newest").pluck(:name)

    expect(names.first).to eq(recently_uploaded.name)
  end

  it "sorts by capture time when asked for it explicitly" do
    create(:stored_file, :image, user: owner, name: "Holiday.jpg",
           taken_at: 1.year.ago, created_at: Time.current)
    taken_recently = create(:stored_file, :image, user: owner, name: "Breakfast.jpg",
                            taken_at: 1.hour.ago, created_at: 2.days.ago)

    names = StoredFile.images.sorted_by("taken_newest").pluck(:name)

    expect(names.first).to eq(taken_recently.name)
  end

  it "falls back to upload time for photos with no capture date" do
    no_exif = create(:stored_file, :image, user: owner, name: "Screenshot.png",
                     taken_at: nil, created_at: Time.current)
    older = create(:stored_file, :image, user: owner, name: "Old.jpg",
                   taken_at: 2.days.ago, created_at: 2.days.ago)

    names = StoredFile.images.sorted_by("taken_newest").pluck(:name)

    expect(names).to eq([ no_exif.name, older.name ])
  end

  it "exposes #captured_at as taken_at when present" do
    file = build(:stored_file, taken_at: 3.days.ago, created_at: Time.current)
    expect(file.captured_at).to eq(file.taken_at)
  end

  it "exposes #captured_at as created_at otherwise" do
    file = build(:stored_file, taken_at: nil, created_at: Time.current)
    expect(file.captured_at).to eq(file.created_at)
  end
end
