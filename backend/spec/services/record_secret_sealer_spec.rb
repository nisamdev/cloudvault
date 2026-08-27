require "rails_helper"

RSpec.describe RecordSecretSealer do
  let(:vault_key) { VaultCipher.random_key }

  it "seals and opens with the vault key scheme" do
    packed = described_class.seal("my password", vault_key)

    expect(packed[:kdf]).to eq("v" => 1, "scheme" => "vault_key")
    expect(described_class.open(sealed: packed[:sealed], kdf: packed[:kdf], vault_key: vault_key))
      .to eq("my password")
  end

  it "refuses to seal without a vault key" do
    expect { described_class.seal("x", nil) }
      .to raise_error(described_class::VaultLocked)
  end
end
