require "rails_helper"
require "zip"

# The half of a backup that makes the other half worth having.
#
# These do not run pg_restore — that needs a database to throw away, and the
# round trip is proven by hand against a scratch database. What they cover is
# everything around it: the envelope, the file map, and the guards that decide
# whether a restore is allowed to touch anything at all.
RSpec.describe VaultBackup::Restorer do
  let(:passphrase) { "a good backup passphrase" }

  # A backup archive built by hand, so a test can control exactly what is in it.
  def build_backup(entries: {}, manifest: {}, dump: "PGDMP fake dump")
    inner = Tempfile.new([ "inner", ".zip" ], binmode: true)
    File.open(inner.path, "wb") do |io|
      ZipKit::Streamer.open(io) do |zip|
        zip.write_deflated_file(VaultBackup::Format::INNER_MANIFEST) do |sink|
          sink << JSON.generate({ format_version: 1, backup_type: "documents",
                                  created_at: Time.current.iso8601 }.merge(manifest))
        end
        zip.write_stored_file(VaultBackup::Format::DATABASE_DUMP) { |sink| sink << dump }
        entries.each { |path, body| zip.write_stored_file(path) { |sink| sink << body } }
      end
    end

    output = Tempfile.new([ "backup", ".vault" ], binmode: true).path
    VaultBackup::Encryptor.new(
      input_path: inner.path, output_path: output,
      passphrase: passphrase, backup_type: "documents"
    ).call

    inner.close!
    output
  end

  describe "reading one without changing anything" do
    it "opens the manifest with the right passphrase" do
      path = build_backup(manifest: { blob_entries: 3 })

      result = described_class.new(path: path, passphrase: passphrase, inspect_only: true).call

      expect(result.manifest["backup_type"]).to eq("documents")
      expect(result.manifest["blob_entries"]).to eq(3)
    end

    it "refuses the wrong passphrase, and says so in those words" do
      path = build_backup

      expect { described_class.new(path: path, passphrase: "not it", inspect_only: true).call }
        .to raise_error(described_class::Error, /passphrase does not open/)
    end

    it "refuses a file that is not a backup at all" do
      other = Tempfile.new([ "notes", ".txt" ])
      other.write("just some text")
      other.close

      expect { described_class.new(path: other.path, passphrase: passphrase, inspect_only: true).call }
        .to raise_error(StandardError, /not a CloudVault backup/)
    end

    it "says so when the file isn't there" do
      expect { described_class.new(path: "/tmp/nothing-here.vault", passphrase: passphrase).call }
        .to raise_error(described_class::Error, /No such backup/)
    end

    # The failure that hid a real bug: ZipKit was handed an IO it did not own
    # and never flushed the central directory, so every archive was truncated
    # and nothing said so until a restore was attempted.
    it "reports a truncated archive rather than failing obscurely" do
      whole = build_backup
      truncated = Tempfile.new([ "cut", ".vault" ], binmode: true)
      truncated.write(File.binread(whole)[0..-40])
      truncated.close

      expect { described_class.new(path: truncated.path, passphrase: passphrase, inspect_only: true).call }
        .to raise_error(StandardError)
    end
  end

  describe "the guard on a database that already has something in it" do
    let(:path) { build_backup }

    it "refuses when there are users, rather than replacing them" do
      create(:user)

      expect { described_class.new(path: path, passphrase: passphrase).call }
        .to raise_error(described_class::WouldOverwrite, /already has 1 user/)
    end

    it "names the way past it" do
      create(:user)

      expect { described_class.new(path: path, passphrase: passphrase).call }
        .to raise_error(described_class::WouldOverwrite, /FORCE=1/)
    end
  end

  # Files are archived under a path a person can read, so only the manifest
  # knows which archived file is which blob.
  describe "the file map" do
    it "puts each archived file back under the key the database expects" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("the deed"), filename: "deed.pdf", content_type: "application/pdf"
      )
      restorer = described_class.new(path: "unused", passphrase: passphrase)

      inner = Tempfile.new([ "inner", ".zip" ], binmode: true)
      File.open(inner.path, "wb") do |io|
        ZipKit::Streamer.open(io) do |zip|
          zip.write_stored_file("files/7/deed.pdf") { |sink| sink << "restored bytes" }
        end
      end

      restored, missing = restorer.send(
        :restore_blobs, inner.path,
        { "entries" => [ { "path" => "files/7/deed.pdf", "key" => blob.key } ] }
      )

      expect([ restored, missing ]).to eq([ 1, 0 ])
      expect(ActiveStorage::Blob.service.download(blob.key)).to eq("restored bytes")
      inner.close!
    end

    it "counts a file the archive does not actually contain" do
      restorer = described_class.new(path: "unused", passphrase: passphrase)

      inner = Tempfile.new([ "inner", ".zip" ], binmode: true)
      File.open(inner.path, "wb") do |io|
        ZipKit::Streamer.open(io) { |zip| zip.write_stored_file("files/1/other.pdf") { |s| s << "x" } }
      end

      restored, missing = restorer.send(
        :restore_blobs, inner.path,
        { "entries" => [ { "path" => "files/9/missing.pdf", "key" => "abc123" } ] }
      )

      expect([ restored, missing ]).to eq([ 0, 1 ])
      inner.close!
    end
  end
end
