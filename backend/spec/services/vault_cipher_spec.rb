require "rails_helper"

RSpec.describe VaultCipher do
  describe "sealing and opening" do
    let(:key) { described_class.random_key }

    it "gives back exactly what was sealed" do
      expect(described_class.open(key, described_class.seal(key, "passport scan"))).to eq("passport scan")
    end

    it "handles binary that is not text" do
      bytes = SecureRandom.random_bytes(50_000)

      expect(described_class.open(key, described_class.seal(key, bytes))).to eq(bytes)
    end

    it "refuses the wrong key rather than returning rubbish" do
      sealed = described_class.seal(key, "passport scan")

      expect { described_class.open(described_class.random_key, sealed) }
        .to raise_error(described_class::WrongKey)
    end

    # The reason for GCM: a database somebody has edited must not decrypt.
    it "refuses bytes that have been tampered with" do
      sealed = described_class.seal(key, "£100").dup
      sealed[20] = (sealed[20].ord ^ 0x01).chr

      expect { described_class.open(key, sealed) }.to raise_error(described_class::WrongKey)
    end

    it "refuses something far too short to be a sealed thing" do
      expect { described_class.open(key, "nope") }.to raise_error(described_class::WrongKey)
    end

    it "never produces the same ciphertext twice" do
      first = described_class.seal(key, "passport scan")
      second = described_class.seal(key, "passport scan")

      expect(first).not_to eq(second)
    end

    it "does not leave the plaintext lying in the ciphertext" do
      sealed = described_class.seal(key, "SUPERSECRET")

      expect(sealed).not_to include("SUPERSECRET")
    end
  end

  describe "deriving a key from a passphrase" do
    it "is repeatable for the same passphrase and salt" do
      salt = described_class.random_salt

      expect(described_class.derive("hunter2hunter2", salt))
        .to eq(described_class.derive("hunter2hunter2", salt))
    end

    it "differs for the same passphrase under a different salt" do
      expect(described_class.derive("hunter2hunter2", described_class.random_salt))
        .not_to eq(described_class.derive("hunter2hunter2", described_class.random_salt))
    end

    it "produces a key of the right length" do
      expect(described_class.derive("hunter2hunter2", described_class.random_salt).bytesize)
        .to eq(described_class::KEY_BYTES)
    end
  end

  describe "the recovery key" do
    it "is written in characters that survive being copied by hand" do
      key = described_class.generate_recovery_key

      # No I, L, O, U, 0 or 1 — the ones people mistranscribe.
      expect(key.delete("-")).to match(/\A[#{described_class::RECOVERY_ALPHABET}]+\z/)
      expect(key).to include("-")
    end

    it "carries enough entropy to be worth trusting" do
      expect(described_class.generate_recovery_key.delete("-").length)
        .to eq(described_class::RECOVERY_LENGTH)
    end

    it "is different every time" do
      keys = Array.new(20) { described_class.generate_recovery_key }

      expect(keys.uniq.size).to eq(20)
    end

    it "forgives how it was typed back in" do
      key = described_class.generate_recovery_key

      expect(described_class.normalise_recovery_key(key.downcase.gsub("-", " ")))
        .to eq(described_class.normalise_recovery_key(key))
    end
  end
end
