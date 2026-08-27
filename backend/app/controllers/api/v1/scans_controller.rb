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

      before_action :load_session, only: %i[show upload status]

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

        purpose = params[:purpose] == "record" ? "record" : "files"
        if purpose == "record" && params[:preset].present? && !DocumentPresets.exists?(params[:preset])
          return render_error(message: "Pick what kind of document this is.",
                              code: "unknown_preset", status: :unprocessable_content)
        end

        session = ScanSession.create(
          user: current_user,
          folder_id: folder&.id,
          visibility: visibility,
          base_url: frontend_origin,
          purpose: purpose,
          preset: params[:preset].presence
        )

        render json: session.to_h.merge(qr_svg: session.qr_svg), status: :created
      end

      # GET /api/v1/scans/:token — what the phone shows before capturing
      def show
        render json: {
          valid: true,
          purpose: @session.purpose,
          preset: @session.preset,
          # The phone offers these when it is being asked for a document rather
          # than for pages to keep.
          presets: @session.for_record? ? DocumentPresets::ALL.map(&:to_h) : nil,
          expires_at: @session.expires_at,
          destination: {
            folder: folder_name,
            visibility: @session.visibility,
            family: @session.family&.name
          },
          account: @session.user.full_name.presence || @session.user.email
        }
      end

      # GET /api/v1/scans/:token/status — polled by the desktop while the QR is up
      def status
        render json: {
          expires_at: @session.expires_at,
          expired: @session.expires_at.past?,
          receipt: @session.receipt
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

        # A page that is going to be *read* is left alone. Document mode lifts
        # contrast with a histogram stretch, which makes a photo legible to a
        # person and — on an already-crisp page — clips it to the point where
        # tesseract sees nothing at all. Pages being kept still get the
        # treatment; pages being read do not.
        style = @session.for_record? ? "colour" : (params[:style].presence || "document")
        scanner = DocumentScanner.new(mode: style)
        processed = pages.map { |page| scanner.process(page.read) }

        stored = if @session.for_record?
                   # A document is always one PDF: it is what gets attached to
                   # the record and what gets read for its fields.
                   store_as_pdf(processed)
        elsif params[:mode] == "images"
                   store_as_images(processed, pages)
        else
                   store_as_pdf(processed)
        end

        files = Array(stored)
        suggestion = @session.for_record? ? read_document(files.first) : nil
        # Leaves a receipt the desktop polls for, so the QR dialog knows when
        # the phone has finished.
        @session.record_upload(files, suggestion: suggestion)

        render json: {
          files: files.map { |file| { id: file.id, name: file.name, size: file.size } },
          page_count: processed.size,
          suggestion: suggestion
        }.compact, status: :created
      rescue FileUploader::QuotaExceeded => e
        render_error(message: e.message, code: "quota_exceeded", status: :content_too_large)
      rescue FileUploader::Error => e
        render_error(message: e.message, code: "upload_failed", status: :unprocessable_content)
      end

      private

      # Reads the scan the phone just sent, so the desktop has something to check
      # rather than an empty form.
      def read_document(file)
        return nil if file.nil?

        preset = params[:preset].presence || @session.preset.presence || "other"
        bytes = file.attachment.download
        extracted = PdfTextExtractor.new(bytes).call
        text = extracted.any_text? ? extracted.text : PdfOcr.new(bytes).call.text

        DocumentReader.new(text, preset).call.to_h.merge(
          file: { id: file.id, name: file.name, size: file.size },
          found_text: text.present?
        )
      rescue StandardError => e
        # A document that cannot be read still gets kept; the desktop opens an
        # empty form instead of nothing at all.
        Rails.logger.error("[scan] could not read: #{e.class}: #{e.message}")
        nil
      end

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
