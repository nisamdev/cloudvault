# frozen_string_literal: true

# Builds storage URLs that a browser can actually reach.
#
# Active Storage signs URLs with the endpoint the *server* uses. In compose that
# is http://minio:9000, which no browser can resolve; in production the API may
# reach storage over a private network. Signing with the public endpoint instead
# keeps the SigV4 signature valid for the host the browser connects to.
#
# But "the public endpoint" is only public relative to somebody. S3_PUBLIC_ENDPOINT
# is http://localhost:9100 in compose, which is right for a browser on the same
# machine and wrong for every other browser in the world: over a cloudflared
# tunnel or from a phone on the LAN, `localhost` is the *visitor's* machine and
# the download fails. So the choice is made per request:
#
#   - storage endpoint is genuinely public (R2, S3)  -> presign, bytes skip the app
#   - browser reached us on the storage host          -> presign, same as before
#   - anything else (tunnel, LAN, phone)              -> stream through the API
#
# Streaming costs Puma the bytes, which is the price of the file arriving at all.
module StorageUrl
  module_function

  def for(attachment, expires_in: 15.minutes, disposition: "inline", filename: nil)
    return nil unless attachment&.attached?

    for_blob(attachment.blob, expires_in: expires_in, disposition: disposition, filename: filename)
  end

  # Same signing, for a blob we already hold — a processed variant, for example.
  def for_blob(blob, expires_in: 15.minutes, disposition: "inline", filename: nil)
    return nil if blob.nil?

    name = filename || blob.filename.to_s

    if presignable?
      service.url(
        blob.key,
        expires_in: expires_in,
        disposition: disposition,
        filename: ActiveStorage::Filename.new(name),
        content_type: blob.content_type
      )
    else
      proxy_url(blob, expires_in: expires_in, disposition: disposition, filename: name)
    end
  end

  # A URL on our own origin that streams the bytes back (Api::V1::BlobsController).
  def proxy_url(blob, expires_in:, disposition:, filename:)
    token = JwtService.encode_blob(
      key: blob.key,
      disposition: disposition,
      filename: filename,
      content_type: blob.content_type,
      expires_in: expires_in
    )

    "#{origin}/api/v1/blobs/#{token}"
  end

  # Can the browser that is asking reach object storage directly?
  def presignable?
    return true if ENV["STORAGE_DELIVERY"] == "presigned"
    return false if ENV["STORAGE_DELIVERY"] == "proxy"

    host = endpoint_host
    # No S3 endpoint at all (Disk service, as in test): nothing to reach.
    return true if host.blank?
    # A real public hostname works from anywhere, which is the production case.
    return true if public_host?(host)

    # Otherwise it only works from the machine storage is bound to.
    origin_host == host
  end

  def endpoint_host
    raw = ENV["S3_PUBLIC_ENDPOINT"].presence || ENV["S3_ENDPOINT"].presence
    return nil if raw.blank?

    URI.parse(raw).host
  rescue URI::InvalidURIError
    nil
  end

  # Loopback, RFC1918, .local and bare container names are all reachable only
  # from inside one network.
  def public_host?(host)
    return false if host.in?(%w[localhost 127.0.0.1 ::1 0.0.0.0])
    return false if host.end_with?(".local", ".internal")
    return false unless host.include?(".")
    return false if host.match?(/\A(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.)/)

    true
  end

  def origin
    Current.request_origin.presence || Rails.configuration.x.app_url
  end

  def origin_host
    URI.parse(origin).host
  rescue URI::InvalidURIError
    nil
  end

  # Falls back to the default service when no public endpoint is configured —
  # the case when the API and the browser share one address.
  def service
    ActiveStorage::Blob.services.fetch(:s3_public) { ActiveStorage::Blob.service }
  rescue KeyError
    ActiveStorage::Blob.service
  end
end
