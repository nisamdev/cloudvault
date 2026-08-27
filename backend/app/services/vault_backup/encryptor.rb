# frozen_string_literal: true

module VaultBackup
  # Encrypts the inner archive so a copy can sit on an external drive.
  #
  # Outer layout: magic | version | metadata JSON | AES-256-GCM(zip bytes)
  # The random archive key is sealed with a key derived from the backup passphrase.
  class Encryptor
    class Error < StandardError; end

    def initialize(input_path:, output_path:, passphrase:, backup_type:)
      @input_path = input_path
      @output_path = output_path
      @passphrase = passphrase.to_s
      @backup_type = backup_type
    end

    def call
      raise Error, "Backup passphrase is required." if @passphrase.blank?
      raise Error, "Backup passphrase must be at least 8 characters." if @passphrase.length < 8

      archive_key = VaultCipher.random_key
      salt = VaultCipher.random_salt
      wrapping_key = VaultCipher.derive(@passphrase, salt)

      metadata = {
        v: Format::VERSION,
        backup_type: @backup_type,
        created_at: Time.current.iso8601,
        rails_env: Rails.env,
        kdf: {
          scheme: "scrypt",
          N: VaultCipher::SCRYPT_N,
          r: VaultCipher::SCRYPT_R,
          p: VaultCipher::SCRYPT_P
        },
        salt: VaultCipher.pack(salt),
        sealed_archive_key: VaultCipher.pack(VaultCipher.seal(wrapping_key, archive_key))
      }

      File.open(@output_path, "wb") do |out|
        out.write(Format::MAGIC)
        out.write([ Format::VERSION ].pack("C"))
        json = metadata.to_json
        out.write([ json.bytesize ].pack("N"))
        out.write(json)
        encrypt_body(@input_path, out, archive_key)
      end

      @output_path
    end

    # Returns the Tempfile itself, not its path.
    #
    # A Tempfile deletes itself when it is garbage collected, so handing back
    # only the path means the archive can vanish underneath a restore that is
    # still reading it. The caller holds the object and closes it when done.
    #
    # @return [Tempfile] the decrypted inner archive; caller calls close!
    def self.decrypt(input_path:, passphrase:)
      metadata, body = read_envelope(input_path)
      archive_key = open_archive_key(metadata, passphrase)

      temp = Tempfile.new([ "vault-backup", ".zip" ], binmode: true)
      decrypt_body(body, temp, archive_key)
      temp.close
      temp
    end

    def self.read_envelope(path)
      File.open(path, "rb") do |io|
        magic = io.read(4)
        raise Error, "not a CloudVault backup file" unless magic == Format::MAGIC

        version = io.read(1)&.unpack1("C")
        raise Error, "unsupported backup version" unless version == Format::VERSION

        json_len = io.read(4)&.unpack1("N")
        metadata = JSON.parse(io.read(json_len))
        [ metadata, io.read ]
      end
    end

    def self.open_archive_key(metadata, passphrase)
      salt = VaultCipher.unpack(metadata.fetch("salt"))
      sealed = VaultCipher.unpack(metadata.fetch("sealed_archive_key"))
      wrapping_key = VaultCipher.derive(passphrase, salt)
      VaultCipher.open(wrapping_key, sealed)
    end

    def self.decrypt_body(body, output_io, key)
      bytes = body.to_s.b
      iv = bytes[0, VaultCipher::IV_BYTES]
      tag = bytes[-VaultCipher::TAG_BYTES, VaultCipher::TAG_BYTES]
      ciphertext = bytes[VaultCipher::IV_BYTES...-VaultCipher::TAG_BYTES]

      decipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      decipher.key = key
      decipher.iv = iv
      decipher.auth_tag = tag
      output_io.write(decipher.update(ciphertext) + decipher.final)
      output_io.flush
    end

    private

    def encrypt_body(input_path, output_io, key)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = key
      iv = cipher.random_iv
      output_io.write(iv)

      File.open(@input_path, "rb") do |input|
        while (chunk = input.read(1_048_576))
          output_io.write(cipher.update(chunk))
        end
        output_io.write(cipher.final)
      end

      output_io.write(cipher.auth_tag(VaultCipher::TAG_BYTES))
    end
  end
end
