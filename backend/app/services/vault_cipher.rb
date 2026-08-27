# frozen_string_literal: true

# The cryptography behind the private section.
#
# Envelope encryption. One random 256-bit *vault key* encrypts the files; that
# key is itself sealed twice, once with a key derived from the owner's
# passphrase and once with a key derived from their recovery key. Either opens
# it, and neither is ever stored. Changing the passphrase re-seals the vault key
# rather than re-encrypting a single file.
#
# AES-256-GCM throughout, so every decryption is authenticated: a wrong key is
# refused rather than returning plausible rubbish, which is also how a wrong
# passphrase is detected without storing anything that could confirm a guess.
module VaultCipher
  class WrongKey < StandardError; end

  KEY_BYTES = 32
  IV_BYTES = 12
  TAG_BYTES = 16
  SALT_BYTES = 16

  # scrypt rather than PBKDF2: it needs memory as well as time, which is what
  # makes a stolen database expensive to attack with a rack of GPUs.
  #
  # N=2^14 with r=8 costs 128*N*r = 16 MiB and something under a tenth of a
  # second per attempt. 2^15 would be better still and is exactly OpenSSL's
  # default memory ceiling, which it then refuses to work at.
  SCRYPT_N = 16_384
  SCRYPT_R = 8
  SCRYPT_P = 1

  module_function

  def random_key = SecureRandom.random_bytes(KEY_BYTES)
  def random_salt = SecureRandom.random_bytes(SALT_BYTES)

  # @param secret [String] a passphrase or a recovery key
  # @param salt [String] raw bytes, one per secret and per vault
  def derive(secret, salt)
    OpenSSL::KDF.scrypt(
      secret.to_s, salt: salt, N: SCRYPT_N, r: SCRYPT_R, p: SCRYPT_P, length: KEY_BYTES
    )
  end

  # @return [String] binary: iv | ciphertext | tag
  def seal(key, plaintext)
    cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
    cipher.key = key
    iv = cipher.random_iv

    ciphertext = cipher.update(plaintext.to_s.b) + cipher.final

    iv + ciphertext + cipher.auth_tag(TAG_BYTES)
  end

  # @raise [WrongKey] when the key is wrong or the bytes have been tampered with
  def open(key, sealed)
    bytes = sealed.to_s.b
    raise WrongKey, "not enough data to be encrypted" if bytes.bytesize < IV_BYTES + TAG_BYTES

    decipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
    decipher.key = key
    decipher.iv = bytes[0, IV_BYTES]
    decipher.auth_tag = bytes[-TAG_BYTES, TAG_BYTES]

    body = bytes[IV_BYTES...-TAG_BYTES]
    decipher.update(body.to_s) + decipher.final
  rescue OpenSSL::Cipher::CipherError, ArgumentError, TypeError
    # GCM failing to authenticate is the normal way a wrong passphrase is found
    # out, so it is not worth a log line of its own.
    raise WrongKey, "that key does not open this"
  end

  # Base64 for the columns that hold sealed keys and salts.
  def pack(bytes) = Base64.strict_encode64(bytes.to_s.b)

  def unpack(text)
    Base64.strict_decode64(text.to_s)
  rescue ArgumentError
    raise WrongKey, "that is not something we stored"
  end

  # The recovery key, as something a person can write on paper.
  #
  # No I, L, O, U or 0/1: they are the characters people mistranscribe, and this
  # is going to be copied by hand under stress. 30 characters of a 32-letter
  # alphabet is 150 bits, and 32 divides 256 exactly so drawing bytes and taking
  # them modulo the alphabet introduces no bias.
  RECOVERY_ALPHABET = "23456789ABCDEFGHJKMNPQRSTVWXYZ".freeze
  RECOVERY_LENGTH = 30
  RECOVERY_GROUP = 6

  def generate_recovery_key
    alphabet = RECOVERY_ALPHABET
    characters = SecureRandom.random_bytes(RECOVERY_LENGTH)
                             .unpack("C*")
                             .map { |byte| alphabet[byte % alphabet.length] }

    characters.each_slice(RECOVERY_GROUP).map(&:join).join("-")
  end

  # Typed back in with spaces, lower case, or the dashes left out.
  def normalise_recovery_key(input)
    input.to_s.upcase.gsub(/[^#{RECOVERY_ALPHABET}]/, "")
  end
end
