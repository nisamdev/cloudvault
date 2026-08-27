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

        # A document being photographed for a record is not touched beyond what
        # it takes to open it on a computer: the phone is the camera, and the
        # trimming and reading happen on the desktop where they can be checked.
        # Colour mode is that minimum — it turns the EXIF rotation into real
        # pixels and caps the size, and changes nothing else.
        style = @session.for_record? ? "colour" : (params[:style].presence || "document")
        scanner = DocumentScanner.new(mode: style)
        processed = pages.map { |page| scanner.process(page.read) }

        if @session.for_record?
          return complete_record_scan(processed)
        end

        stored = params[:mode] == "images" ? store_as_images(processed, pages) : store_as_pdf(processed)

        files = Array(stored)
        # Leaves a receipt the desktop polls for, so the QR dialog knows when
        # the phone has finished.
        @session.record_upload(files: files)

        render json: {
          files: files.map { |file| { id: file.id, name: file.name, size: file.size } },
          page_count: processed.size
        }, status: :created
      rescue FileUploader::QuotaExceeded => e
        render_error(message: e.message, code: "quota_exceeded", status: :content_too_large)
      rescue FileUploader::Error => e
        render_error(message: e.message, code: "upload_failed", status: :unprocessable_content)
      end

      private

      # The photographs are held, not filed. Nothing goes in the vault until the
      # computer has trimmed them and the PDF has been built from what the
      # person actually approved, so these are unattached blobs with a
      # short-lived signed id rather than files anybody has to tidy up.
      def complete_record_scan(processed)
        held = processed.each_with_index.map do |bytes, index|
          blob = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new(bytes),
            filename: "scan-page-#{index + 1}.jpg",
            content_type: "image/jpeg"
          )

          { id: blob.signed_id(expires_in: HOLD_TTL), name: blob.filename.to_s, size: blob.byte_size }
        end

        chose = params[:preset].presence || @session.preset
        @session.record_upload(pages: held, chose: chose)

        render json: { pages: held, page_count: held.size, preset: chose }, status: :created
      end

      MAX_PAGES = 30
      # Long enough to walk back to the computer and take your time over the
      # crop; short enough that an intercepted id is worth nothing tomorrow.
      HOLD_TTL = 2.hours

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
