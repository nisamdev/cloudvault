require "rails_helper"
require "zip_kit"

RSpec.describe VaultBackup::Encryptor do
  let(:passphrase) { "a good backup passphrase" }
  let(:plaintext) { "secret household archive bytes" }
  let(:input) { Tempfile.new([ "inner", ".zip" ], binmode: true) }
  let(:encrypted) { Tempfile.new([ "vault", ".vault" ], binmode: true) }

  before do
    ZipKit::Streamer.open(input) do |zip|
      zip.write_deflated_file("hello.txt") { |sink| sink << plaintext }
    end
    input.close
  end

  after do
    input.unlink
    encrypted.unlink
  end

  it "round-trips the inner archive" do
    described_class.new(
      input_path: input.path,
      output_path: encrypted.path,
      passphrase: passphrase,
      backup_type: "documents"
    ).call

    # decrypt hands back the Tempfile itself, not its path: a Tempfile deletes
    # itself when collected, and a restore still reading the archive would find
    # it gone.
    decrypted = described_class.decrypt(input_path: encrypted.path, passphrase: passphrase)

    expect(decrypted).to be_a(Tempfile)
    expect(File.binread(decrypted.path, 2)).to eq("PK")
  ensure
    decrypted&.close!
  end

  it "refuses a short passphrase" do
    expect {
      described_class.new(
        input_path: input.path,
        output_path: encrypted.path,
        passphrase: "short",
        backup_type: "documents"
      ).call
    }.to raise_error(VaultBackup::Encryptor::Error, /at least 8/)
  end
end
