# frozen_string_literal: true

module Api
  module V1
    # Saved signatures, so one is drawn once and reused.
    class SignaturesController < BaseController
      before_action :set_signature, only: :destroy

      MAX_IMAGE_BYTES = 2.megabytes
      ALLOWED_TYPES = %w[image/png image/jpeg image/webp].freeze

      # GET /api/v1/signatures
      def index
        signatures = current_user.signatures.order(:name)

        render json: { signatures: signatures.map { |s| serialize(s) } }
      end

      # POST /api/v1/signatures
      #
      # Accepts either an uploaded file or a data URL, which is what a canvas
      # produces when someone draws their signature with a finger.
      def create
        image = params[:image].presence || decode_data_url(params[:image_data])

        if image.blank?
          return render_error(message: "No signature image was given.",
                              code: "image_missing", status: :bad_request)
        end

        if image.size > MAX_IMAGE_BYTES
          return render_error(message: "That image is too large.",
                              code: "image_too_large", status: :content_too_large)
        end

        unless ALLOWED_TYPES.include?(image.content_type)
          return render_error(message: "A signature must be a PNG, JPEG or WebP image.",
                              code: "unsupported_type", status: :unsupported_media_type)
        end

        signature = current_user.signatures.new(name: params[:name].presence || default_name)
        signature.image.attach(io: image.tempfile, filename: "signature.png", content_type: image.content_type)
        signature.save!

        render json: { signature: serialize(signature) }, status: :created
      end

      # DELETE /api/v1/signatures/:id
      def destroy
        @signature.destroy!
        head :no_content
      end

      private

      def set_signature
        @signature = current_user.signatures.find_by(id: params[:id])

        return if @signature

        render_error(message: "We couldn't find that signature.",
                     code: "not_found", status: :not_found)
      end

      # "data:image/png;base64,iVBORw0…" from a <canvas>.
      def decode_data_url(value)
        return nil if value.blank?

        match = value.match(%r{\Adata:(?<type>image/[a-z+]+);base64,(?<data>.+)\z}m)
        return nil if match.nil?

        bytes = Base64.strict_decode64(match[:data])
        tempfile = Tempfile.new([ "signature", ".png" ], binmode: true)
        tempfile.write(bytes)
        tempfile.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile: tempfile, filename: "signature.png", type: match[:type]
        )
      rescue ArgumentError
        nil
      end

      def default_name
        "Signature #{current_user.signatures.count + 1}"
      end

      def serialize(signature)
        {
          id: signature.id,
          name: signature.name,
          created_at: signature.created_at,
          image_url: StorageUrl.for(signature.image, expires_in: 30.minutes)
        }
      end
    end
  end
end
