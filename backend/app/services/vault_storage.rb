# frozen_string_literal: true

# Encrypting a file's bytes on the way into storage, and back on the way out.
#
# Whole-file rather than streamed: a family's documents are megabytes, not
# gigabytes, and a streaming AEAD format would mean inventing a chunked one and
# getting the framing right. Holding a passport scan in memory for the length of
# one request is the cheaper trade.
module VaultStorage
  class TooLarge < StandardError; end

  # Above this, encrypting in memory stops being reasonable. Locked files are
  # documents; the ordinary vault takes anything.
  MAX_BYTES = 80 * 1024 * 1024

  module_function

  # Replaces an attachment's bytes with their encrypted form.
  def encrypt!(record, attachment_name, vault_key)
    attachment = record.public_send(attachment_name)
    return false unless attachment.attached?
    raise TooLarge, "That file is too big for the private section." if attachment.byte_size > MAX_BYTES

    plaintext = attachment.download
    replace(record, attachment_name, VaultCipher.seal(vault_key, plaintext), attachment)
    true
  end

  # And back again, for a file leaving the private section.
  def decrypt!(record, attachment_name, vault_key)
    attachment = record.public_send(attachment_name)
    return false unless attachment.attached?

    plaintext = VaultCipher.open(vault_key, attachment.download)
    replace(record, attachment_name, plaintext, attachment)
    true
  end

  # @return [String] the file itself
  def read(attachment, vault_key)
    VaultCipher.open(vault_key, attachment.download)
  end

  def replace(record, attachment_name, bytes, attachment)
    filename = attachment.filename.to_s
    content_type = attachment.content_type

    attachment.purge
    record.public_send(attachment_name).attach(
      io: StringIO.new(bytes), filename: filename, content_type: content_type
    )
  end
  private_class_method :replace
end
