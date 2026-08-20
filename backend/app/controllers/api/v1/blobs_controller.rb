# frozen_string_literal: true

module Api
  module V1
    # Streams one blob back through the API.
    #
    # Only used when object storage is not reachable from wherever the browser
    # is — over a tunnel, or from a phone on the LAN (see StorageUrl). The URL
    # has to work in <img src>, <object data> and a plain navigation, none of
    # which can carry an Authorization header, so the short-lived token in the
    # path is the entire credential. It names one blob and expires, which is the
    # same bargain Active Storage's own signed ids make.
    class BlobsController < ApplicationController
      include ActiveStorage::Streaming

      def show
        payload = JwtService.decode_blob(params[:token])
        blob = ActiveStorage::Blob.find_by(key: payload["key"])
        return head :not_found if blob.nil?

        if request.headers["Range"].present?
          send_blob_byte_range_data(blob, request.headers["Range"], disposition: disposition_for(blob, payload))
        else
          stream_whole(blob, payload)
        end
      rescue JwtService::InvalidToken
        head :not_found
      end

      private

      # Active Storage's own send_blob_stream, with one change: the filename
      # comes from the token. The blob is named after whatever was uploaded,
      # which is not always what the file is called now — renames, versions and
      # signed copies all share a blob with a name that has moved on.
      def stream_whole(blob, payload)
        response.headers["Accept-Ranges"] = "bytes"
        response.headers["Content-Length"] = blob.byte_size.to_s
        # Private: this passes through Cloudflare on the way to a phone, and a
        # passport has no business in a shared cache.
        response.headers["Cache-Control"] = "private, max-age=300"

        send_stream(
          filename: ActiveStorage::Filename.new(payload["filename"].presence || blob.filename.to_s).sanitized,
          disposition: disposition_for(blob, payload),
          type: blob.content_type_for_serving
        ) do |stream|
          blob.download { |chunk| stream.write(chunk) }
        rescue ActiveStorage::FileNotFoundError
          expires_now
          head :not_found
        end
      end

      # These bytes now come from our own origin, where the refresh-token cookie
      # lives — so an HTML or SVG upload rendered inline would be running script
      # in our security context. Active Storage already keeps a list of what is
      # safe to display; defer to it and let everything else download instead.
      def disposition_for(blob, payload)
        blob.forced_disposition_for_serving || payload["disposition"].presence || "inline"
      end
    end
  end
end
