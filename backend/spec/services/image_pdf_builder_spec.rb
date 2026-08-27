require "rails_helper"
require "vips"

RSpec.describe ImagePdfBuilder do
  def image(width: 400, height: 600, format: ".jpg", name: "page.jpg")
    bytes = Vips::Image.black(width, height).add(200).cast(:uchar)
                       .colourspace("srgb")
                       .write_to_buffer(format)

    { name: name, bytes: bytes, content_type: format == ".png" ? "image/png" : "image/jpeg" }
  end

  it "refuses to build a document out of nothing" do
    expect { described_class.new([]).call }.to raise_error(described_class::Error, /at least one/)
  end

  it "refuses more pages than it can hold in memory" do
    pages = Array.new(described_class::MAX_PAGES + 1) { image(width: 20, height: 20) }

    expect { described_class.new(pages).call }.to raise_error(described_class::Error, /more than/)
  end

  it "names the offending file when one is not an image it can embed" do
    pages = [ image, image(name: "receipt.gif").merge(content_type: "image/gif") ]

    expect { described_class.new(pages).call }
      .to raise_error(described_class::Error, /receipt\.gif/)
  end

  # An image big enough to blow past PDF's own 200-inch page limit should still
  # produce a page, not an exception from deep inside Prawn.
  it "keeps an enormous image inside a page PDF can describe" do
    bytes = described_class.new([ image(width: 40_000, height: 200) ], page_size: "auto").call

    page = CombinePDF.parse(bytes).pages.first
    expect(page[:MediaBox][2] - page[:MediaBox][0]).to be <= described_class::MAX_SIDE
  end
end
