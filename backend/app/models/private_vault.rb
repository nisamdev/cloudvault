# frozen_string_literal: true

# One person's private section.
#
# Holds the vault key sealed two ways and nothing that could confirm a guess at
# either secret: a wrong passphrase is found out by AES-GCM refusing to
# authenticate, not by comparing against anything stored here.
class PrivateVault < ApplicationRecord
  class WrongPassphrase < StandardError; end

  belongs_to :user

  MIN_PASSPHRASE = 8

  # Sets up a vault and returns it with the recovery key, which is the only time
  # that key exists anywhere.
  #
  # @return [Array(PrivateVault, String)] the vault, and the recovery key to
  #   show the owner once
  def self.open_for(user, passphrase)
    raise WrongPassphrase, "Choose a passphrase of at least #{MIN_PASSPHRASE} characters." if
      passphrase.to_s.length < MIN_PASSPHRASE

    vault_key = VaultCipher.random_key
    recovery_key = VaultCipher.generate_recovery_key

    vault = new(user: user)
    vault.seal_with_passphrase(vault_key, passphrase)
    vault.seal_with_recovery(vault_key, recovery_key)
    vault.save!

    [ vault, recovery_key ]
  end

  # @return [String] the vault key
  # @raise [WrongPassphrase]
  def unlock(passphrase)
    open_sealed(passphrase_sealed_key, passphrase_salt, passphrase)
  end

  # @return [String] the vault key
  # @raise [WrongPassphrase]
  def unlock_with_recovery(recovery_key)
    open_sealed(
      recovery_sealed_key, recovery_salt, VaultCipher.normalise_recovery_key(recovery_key)
    )
  end

  # Re-seals the same vault key under a new passphrase. Nothing is re-encrypted:
  # the files never knew about the passphrase in the first place.
  def change_passphrase(current:, to:)
    key = unlock(current)
    replace_passphrase(key, to)
  end

  # The way back in when the passphrase is gone. Proves ownership with the
  # recovery key, then sets a new passphrase — and issues a new recovery key,
  # because the old one has now been used and written down somewhere.
  #
  # @return [String] the new recovery key
  def reset_with_recovery(recovery_key:, passphrase:)
    key = unlock_with_recovery(recovery_key)
    replace_passphrase(key, passphrase)

    fresh = VaultCipher.generate_recovery_key
    seal_with_recovery(key, fresh)
    update!(recovery_key_shown_at: nil)

    fresh
  end

  def seal_with_passphrase(vault_key, passphrase)
    salt = VaultCipher.random_salt
    self.passphrase_salt = VaultCipher.pack(salt)
    self.passphrase_sealed_key =
      VaultCipher.pack(VaultCipher.seal(VaultCipher.derive(passphrase, salt), vault_key))
  end

  def seal_with_recovery(vault_key, recovery_key)
    salt = VaultCipher.random_salt
    self.recovery_salt = VaultCipher.pack(salt)
    self.recovery_sealed_key = VaultCipher.pack(
      VaultCipher.seal(VaultCipher.derive(VaultCipher.normalise_recovery_key(recovery_key), salt), vault_key)
    )
  end

  private

  def replace_passphrase(vault_key, passphrase)
    raise WrongPassphrase, "Choose a passphrase of at least #{MIN_PASSPHRASE} characters." if
      passphrase.to_s.length < MIN_PASSPHRASE

    seal_with_passphrase(vault_key, passphrase)
    save!
  end

  def open_sealed(sealed, salt, secret)
    VaultCipher.open(
      VaultCipher.derive(secret, VaultCipher.unpack(salt)),
      VaultCipher.unpack(sealed)
    )
  rescue VaultCipher::WrongKey
    raise WrongPassphrase, "That doesn't open the private section."
  end
end
