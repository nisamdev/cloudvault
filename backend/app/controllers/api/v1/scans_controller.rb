# frozen_string_literal: true

module Api
  module V1
    # Phone-as-scanner: the desktop creates a short-lived session and shows a QR
    # code; the phone opens it and posts photos straight in.
    #
    # The phone endpoints authenticate on the token alone, so they are strictly
    # upload-only. Nothing here lists, reads or deletes.
    class ScansController < BaseController
      allow_unauthenticated :show, :upload

      before_action :load_session, only: %i[show upload]

      # POST /api/v1/scans — desktop asks for a link to open on the phone
      def create
        folder = params[:folder_id].present? ? find_folder(params[:folder_id]) : nil

        if params[:folder_id].present? && folder.nil?
          return render_error(message: "We couldn't find that folder.",
                              code: "folder_not_found", status: :not_found)
        end

        visibility = params[:visibility] == "family" ? "family" : "private"
        if visibility == "family" && !PermissionChecker.can_upload_to_family?(current_user, current_family)
          return render_error(message: "You don't have permission to add files to the family vault.",
                              code: "forbidden", status: :forbidden)
        end

        session = ScanSession.create(
          user: current_user,
          folder_id: folder&.id,
          visibility: visibility,
          base_url: frontend_origin
        )

        render json: session.to_h.merge(qr_svg: session.qr_svg), status: :created
      end

      # GET /api/v1/scans/:token — what the phone shows before capturing
      def show
        render json: {
          valid: true,
          expires_at: @session.expires_at,
          destination: {
            folder: folder_name,
            visibility: @session.visibility,
            family: @session.family&.name
          },
          account: @session.user.full_name.presence || @session.user.email
        }
      end

      # POST /api/v1/scans/:token — the captured pages
      #
      # Params: pages[] (files), mode ("pdf" | "images"), style ("document" | "colour"), name
      def upload
        pages = Array(params[:pages]).compact_blank
        return render_error(message: "No pages were sent.", code: "no_pages", status: :bad_request) if pages.empty?

        if pages.size > MAX_PAGES
          return render_error(message: "Please send at most #{MAX_PAGES} pages at a time.",
                              code: "too_many_pages", status: :unprocessable_content)
        end

        scanner = DocumentScanner.new(mode: params[:style].presence || "document")
        processed = pages.map { |page| scanner.process(page.read) }

        stored = if params[:mode] == "images"
                   store_as_images(processed, pages)
                 else
                   store_as_pdf(processed)
                 end

        render json: {
          files: Array(stored).map { |file| { id: file.id, name: file.name, size: file.size } },
          page_count: processed.size
        }, status: :created
      rescue FileUploader::QuotaExceeded => e
        render_error(message: e.message, code: "quota_exceeded", status: :content_too_large)
      rescue FileUploader::Error => e
        render_error(message: e.message, code: "upload_failed", status: :unprocessable_content)
      end

      private

      MAX_PAGES = 30

      def load_session
        @session = ScanSession.from_token(params[:token])
      rescue ScanSession::InvalidToken, JwtService::InvalidToken
        render_error(
          message: "This scanning link has expired. Create a new one from CloudVault.",
          code: "invalid_scan_token",
          status: :unauthorized
        )
      end

      def uploader
        @uploader ||= FileUploader.new(user: @session.user, family: @session.family)
      end

      def store_as_pdf(pages)
        name = "#{params[:name].presence || default_name}.pdf"
        pdf = DocumentScanner.to_pdf(pages, title: name)

        uploader.call(
          upload_for(pdf, filename: name, type: "application/pdf"),
          folder: destination_folder,
          visibility: @session.visibility
        )
      end

      def store_as_images(processed, originals)
        processed.each_with_index.map do |bytes, index|
          name = originals.size == 1 ? "#{default_name}.jpg" : "#{default_name} (#{index + 1}).jpg"

          uploader.call(
            upload_for(bytes, filename: name, type: "image/jpeg"),
            folder: destination_folder,
            visibility: @session.visibility
          )
        end
      end

      # FileUploader expects an uploaded-file-like object; scans are built in
      # memory, so wrap them in the same shape.
      def upload_for(bytes, filename:, type:)
        tempfile = Tempfile.new([ "scan", File.extname(filename) ], binmode: true)
        tempfile.write(bytes)
        tempfile.rewind

        ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: filename, type: type)
      end

      def destination_folder
        return nil if @session.folder_id.blank?

        Folder.active.find_by(id: @session.folder_id)
      end

      def folder_name
        destination_folder&.name || "Top level"
      end

      def default_name
        params[:name].presence || "Scan #{Time.current.strftime('%-d %b %Y, %H:%M')}"
      end

      def find_folder(folder_id)
        own = Folder.active.find_by(id: folder_id, user_id: current_user.id)
        return own if own

        family_id = current_membership&.family_id
        return nil if family_id.nil?

        Folder.active.find_by(id: folder_id, family_id: family_id)
      end
    end
  end
end
