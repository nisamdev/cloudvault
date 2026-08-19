# frozen_string_literal: true

# Builds presigned URLs that a browser can actually reach.
#
# Active Storage signs URLs with the endpoint the *server* uses. In compose that
# is http://minio:9000, which no browser can resolve; in production the API may
# reach storage over a private network. Signing with the public endpoint instead
# keeps the SigV4 signature valid for the host the browser connects to.
module StorageUrl
  module_function

  def for(attachment, expires_in: 15.minutes, disposition: "inline", filename: nil)
    return nil unless attachment&.attached?

    blob = attachment.blob

    service.url(
      blob.key,
      expires_in: expires_in,
      disposition: disposition,
      filename: filename ? ActiveStorage::Filename.new(filename) : blob.filename,
      content_type: blob.content_type
    )
  end

  # Falls back to the default service when no public endpoint is configured —
  # the case when the API and the browser share one address.
  def service
    ActiveStorage::Blob.services.fetch(:s3_public) { ActiveStorage::Blob.service }
  rescue KeyError
    ActiveStorage::Blob.service
  end
end
