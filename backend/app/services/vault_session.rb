# frozen_string_literal: true

# Keeps the private section open for a while after the passphrase is given.
#
# The awkward part is where to keep the vault key in the meantime. Redis is the
# obvious place and the wrong one: it is configured with an append-only file, so
# anything put there is written to the same disk the encryption is supposed to
# protect against.
#
# So Redis holds the vault key *sealed*, under a fresh random secret that is
# handed to the browser and kept nowhere else — the same bargain the access
# token already makes. A copy of the disk yields the sealed key and no way in;
# only a request carrying the token can put the two halves back together.
class VaultSession
  PREFIX = "vault:unlock"
  # Long enough to do a task, short enough that a walked-away-from laptop
  # relocks itself. Each use pushes it back.
  TTL = 20.minutes

  class << self
    # @return [String] the token for the browser: "<id>.<secret>"
    def open(user:, vault_key:)
      id = SecureRandom.urlsafe_base64(18)
      secret = VaultCipher.random_key

      payload = {
        user_id: user.id,
        sealed_key: VaultCipher.pack(VaultCipher.seal(secret, vault_key))
      }

      redis { |r| r.set(key_for(id), payload.to_json, ex: TTL.to_i) }

      "#{id}.#{Base64.urlsafe_encode64(secret, padding: false)}"
    end

    # @return [String, nil] the vault key, or nil if the token is gone, expired,
    #   malformed, or belongs to somebody else
    def vault_key(token, user)
      id, secret = split(token)
      return nil if id.nil? || user.nil?

      raw = redis { |r| r.get(key_for(id)) }
      return nil if raw.blank?

      payload = JSON.parse(raw)
      return nil unless payload["user_id"] == user.id

      key = VaultCipher.open(secret, VaultCipher.unpack(payload["sealed_key"]))
      # Still working, so still unlocked.
      redis { |r| r.expire(key_for(id), TTL.to_i) }

      key
    rescue VaultCipher::WrongKey, JSON::ParserError
      nil
    rescue StandardError => e
      Rails.logger.error("[vault] could not read the session: #{e.class}")
      nil
    end

    def close(token)
      id, = split(token)
      return if id.nil?

      redis { |r| r.del(key_for(id)) }
    rescue StandardError => e
      Rails.logger.error("[vault] could not close the session: #{e.class}")
    end

    private

    def split(token)
      id, secret = token.to_s.split(".", 2)
      return [ nil, nil ] if id.blank? || secret.blank?

      [ id, Base64.urlsafe_decode64(secret) ]
    rescue ArgumentError
      [ nil, nil ]
    end

    def key_for(id) = "#{PREFIX}:#{id}"

    def redis(&block) = Sidekiq.redis(&block)
  end
end
