require "rails_helper"

RSpec.describe PrivateVault do
  let(:user) { create(:user) }
  let(:passphrase) { "a good long passphrase" }

  def opened
    described_class.open_for(user, passphrase)
  end

  describe "setting one up" do
    it "hands back a recovery key, once" do
      _vault, recovery = opened

      expect(recovery).to be_present
      expect(recovery.delete("-").length).to eq(VaultCipher::RECOVERY_LENGTH)
    end

    it "stores nothing that could confirm a guess at the passphrase" do
      vault, recovery = opened
      stored = vault.attributes.values.map(&:to_s).join(" ")

      expect(stored).not_to include(passphrase)
      expect(stored).not_to include(recovery.delete("-"))
    end

    it "insists on a passphrase worth having" do
      expect { described_class.open_for(user, "short") }
        .to raise_error(described_class::WrongPassphrase, /at least/)
    end
  end

  describe "opening it again" do
    it "gives back the same vault key for the right passphrase" do
      vault, = opened
      first = vault.unlock(passphrase)

      expect(described_class.find(vault.id).unlock(passphrase)).to eq(first)
    end

    it "refuses the wrong passphrase" do
      vault, = opened

      expect { vault.unlock("not the passphrase") }
        .to raise_error(described_class::WrongPassphrase)
    end

    it "opens with the recovery key too, to the very same key" do
      vault, recovery = opened

      expect(vault.unlock_with_recovery(recovery)).to eq(vault.unlock(passphrase))
    end

    it "accepts a recovery key typed back in carelessly" do
      vault, recovery = opened

      expect(vault.unlock_with_recovery(recovery.downcase.tr("-", " ")))
        .to eq(vault.unlock(passphrase))
    end
  end

  describe "changing the passphrase" do
    # The point of sealing the key rather than encrypting with the passphrase:
    # changing it must not mean re-encrypting every file.
    it "keeps the same vault key, so nothing has to be re-encrypted" do
      vault, = opened
      before = vault.unlock(passphrase)

      vault.change_passphrase(current: passphrase, to: "an even better passphrase")

      expect(vault.unlock("an even better passphrase")).to eq(before)
    end

    it "stops the old passphrase working" do
      vault, = opened
      vault.change_passphrase(current: passphrase, to: "an even better passphrase")

      expect { vault.unlock(passphrase) }.to raise_error(described_class::WrongPassphrase)
    end

    it "refuses to change it without the current one" do
      vault, = opened

      expect { vault.change_passphrase(current: "wrong", to: "an even better passphrase") }
        .to raise_error(described_class::WrongPassphrase)
    end
  end

  describe "getting back in with the recovery key" do
    it "sets a new passphrase and keeps the files readable" do
      vault, recovery = opened
      before = vault.unlock(passphrase)

      vault.reset_with_recovery(recovery_key: recovery, passphrase: "the new passphrase")

      expect(vault.unlock("the new passphrase")).to eq(before)
    end

    # The old one has been used and is probably written on a piece of paper that
    # has been out of the drawer.
    it "issues a fresh recovery key and retires the old one" do
      vault, recovery = opened

      fresh = vault.reset_with_recovery(recovery_key: recovery, passphrase: "the new passphrase")

      expect(fresh).not_to eq(recovery)
      expect(vault.unlock_with_recovery(fresh)).to be_present
      expect { vault.unlock_with_recovery(recovery) }
        .to raise_error(described_class::WrongPassphrase)
    end

    it "refuses a recovery key that is not the one" do
      vault, = opened

      expect { vault.reset_with_recovery(recovery_key: VaultCipher.generate_recovery_key, passphrase: "x" * 12) }
        .to raise_error(described_class::WrongPassphrase)
    end
  end
end
