# frozen_string_literal: true

# Encodes and decodes the short-lived access token.
#
# Only the access token is a JWT. Refresh tokens are opaque random strings
# stored as digests (see RefreshToken) so that they can be revoked server-side —
# a stateless refresh token cannot be.
class JwtService
  ALGORITHM = "HS256"

  class InvalidToken < StandardError; end

  class << self
    def encode(payload, expires_in: access_ttl)
      now = Time.current

      claims = payload.merge(
        iat: now.to_i,
        exp: (now + expires_in).to_i,
        # Distinguishes token types so a refresh token can never be replayed as
        # an access token.
        typ: "access",
        jti: SecureRandom.uuid
      )

      JWT.encode(claims, secret, ALGORITHM)
    end

    def decode(token)
      payload, = JWT.decode(token, secret, true, algorithm: ALGORITHM, verify_expiration: true)

      raise InvalidToken, "unexpected token type" unless payload["typ"] == "access"

      payload
    rescue JWT::ExpiredSignature
      raise InvalidToken, "token expired"
    rescue JWT::DecodeError => e
      raise InvalidToken, e.message
    end

    # One-off token for a browser navigation that cannot carry an Authorization
    # header — a folder ZIP download opened as a plain link. Scoped to a single
    # resource and short-lived, so a leaked URL is worth very little.
    def encode_download(user_id:, scope:, expires_in: 5.minutes)
      now = Time.current

      JWT.encode(
        {
          sub: user_id,
          scope: scope,
          typ: "download",
          iat: now.to_i,
          exp: (now + expires_in).to_i,
          jti: SecureRandom.uuid
        },
        secret,
        ALGORITHM
      )
    end

    def decode_download(token, expected_scope:)
      payload, = JWT.decode(token, secret, true, algorithm: ALGORITHM, verify_expiration: true)

      raise InvalidToken, "unexpected token type" unless payload["typ"] == "download"
      # Without this a token for one folder would open any other.
      raise InvalidToken, "scope mismatch" unless payload["scope"] == expected_scope

      payload
    rescue JWT::ExpiredSignature
      raise InvalidToken, "token expired"
    rescue JWT::DecodeError => e
      raise InvalidToken, e.message
    end

    # Credential for streaming one blob back through the API.
    #
    # Used when object storage is not reachable from wherever the browser is
    # (see StorageUrl). It goes in a URL that <img>, <object> and plain
    # navigations can use, so it carries no session — the token is the whole
    # authorisation, which is why it names one blob and dies quickly.
    def encode_blob(key:, disposition:, filename:, content_type: nil, expires_in: 15.minutes)
      now = Time.current

      JWT.encode(
        {
          key: key,
          disposition: disposition,
          filename: filename,
          content_type: content_type,
          typ: "blob",
          iat: now.to_i,
          exp: (now + expires_in).to_i
        },
        secret,
        ALGORITHM
      )
    end

    def decode_blob(token)
      payload, = JWT.decode(token, secret, true, algorithm: ALGORITHM, verify_expiration: true)

      raise InvalidToken, "unexpected token type" unless payload["typ"] == "blob"

      payload
    rescue JWT::ExpiredSignature
      raise InvalidToken, "token expired"
    rescue JWT::DecodeError => e
      raise InvalidToken, e.message
    end

    # Upload-only credential for the phone capture page. Carries where the
    # documents should land so the phone needs no further input.
    def encode_scan(user_id:, folder_id:, visibility:, expires_in:)
      now = Time.current

      JWT.encode(
        {
          sub: user_id,
          typ: "scan",
          folder_id: folder_id,
          visibility: visibility,
          iat: now.to_i,
          exp: (now + expires_in).to_i,
          jti: SecureRandom.uuid
        },
        secret,
        ALGORITHM
      )
    end

    def decode_scan(token)
      payload, = JWT.decode(token, secret, true, algorithm: ALGORITHM, verify_expiration: true)

      # Without this an access token could be replayed as a scan token.
      raise InvalidToken, "unexpected token type" unless payload["typ"] == "scan"

      payload
    rescue JWT::ExpiredSignature
      raise InvalidToken, "token expired"
    rescue JWT::DecodeError => e
      raise InvalidToken, e.message
    end

    # Lets a phone add one signature and nothing else.
    def encode_signature(user_id:, expires_in:)
      now = Time.current

      JWT.encode(
        { sub: user_id, typ: "signature", iat: now.to_i, exp: (now + expires_in).to_i, jti: SecureRandom.uuid },
        secret,
        ALGORITHM
      )
    end

    def decode_signature(token)
      payload, = JWT.decode(token, secret, true, algorithm: ALGORITHM, verify_expiration: true)
      raise InvalidToken, "unexpected token type" unless payload["typ"] == "signature"

      payload
    rescue JWT::ExpiredSignature
      raise InvalidToken, "token expired"
    rescue JWT::DecodeError => e
      raise InvalidToken, e.message
    end

    def access_ttl
      ENV.fetch("JWT_ACCESS_TTL_MINUTES", 15).to_i.minutes
    end

    private

    def secret
      # Deliberately not falling back to secret_key_base: a missing JWT_SECRET
      # should fail loudly at boot, not silently sign with a different key.
      ENV.fetch("JWT_SECRET")
    end
  end
end
