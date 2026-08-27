require "rails_helper"

RSpec.describe FilenameDateParser do
  it "reads a WhatsApp filename with AM/PM" do
    time = described_class.call("WhatsApp Image 2024-04-30 at 2.21.30 PM.jpeg")

    expect(time).to eq(Time.utc(2024, 4, 30, 14, 21, 30))
  end

  it "reads a compact camera-style stamp" do
    time = described_class.call("IMG_20240430_142130.jpg")

    expect(time).to eq(Time.utc(2024, 4, 30, 14, 21, 30))
  end

  it "reads a bare ISO date" do
    time = described_class.call("holiday-2023-12-25.png")

    expect(time).to eq(Time.utc(2023, 12, 25, 12, 0, 0))
  end

  it "returns nothing when there is no date" do
    expect(described_class.call("photo.jpeg")).to be_nil
  end
end
