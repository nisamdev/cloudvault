# frozen_string_literal: true

# Seals and opens record secrets in a key-agnostic format.
#
# Today the vault key from an unlock token does the work. Later a browser or
# extension can seal with the same layout and a different kdf scheme — nothing
# in the stored bytes assumes who held the key when they were written.
module RecordSecretSealer
  class Error < StandardError; end
  class UnsupportedScheme < Error; end
  class VaultLocked < Error; end

  SCHEME_VAULT_KEY = "vault_key"
  VERSION = 1

  module_function

  # @return [Hash] :sealed (binary), :kdf (Hash)
  def seal(plaintext, vault_key)
    raise VaultLocked, "unlock the private section first" if vault_key.blank?

    {
      sealed: VaultCipher.seal(vault_key, plaintext.to_s),
      kdf: { "v" => VERSION, "scheme" => SCHEME_VAULT_KEY }
    }
  end

  # @raise [VaultCipher::WrongKey] when the key does not open this
  def open(sealed:, kdf:, vault_key:)
    raise VaultLocked, "unlock the private section first" if vault_key.blank?

    scheme = kdf.is_a?(Hash) ? kdf["scheme"] || kdf[:scheme] : nil
    raise UnsupportedScheme, "unknown sealing scheme" unless scheme == SCHEME_VAULT_KEY

    VaultCipher.open(vault_key, sealed)
  end
end
