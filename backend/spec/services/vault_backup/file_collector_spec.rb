require "rails_helper"

RSpec.describe VaultBackup::FileCollector do
  let(:user) { create(:user) }

  it "includes documents but not gallery photos" do
    doc = create(:stored_file, :with_attachment, user: user, file_type: "file", name: "deed.pdf")
    photo = create(:stored_file, :with_attachment, user: user, file_type: "image", name: "holiday.jpg")

    paths = described_class.new.entries.map(&:path)

    expect(paths).to include(a_string_matching(%r{files/#{doc.id}/deed\.pdf}))
    expect(paths).not_to include(a_string_matching(/#{photo.id}/))
  end
end
