# frozen_string_literal: true

module Api
  module V1
    # Photograph a document, get a filled-in form back.
    #
    # The pages become a PDF — which is what gets kept and what you would send
    # to somebody — and the same PDF is read for its text. One artefact, so the
    # thing attached to the record is exactly the thing that was read.
    #
    # Nothing is saved as a record here. This hands back a suggestion for a
    # person to check: it exists to save the typing, not to decide what is true
    # about somebody's passport.
    class DocumentCapturesController < BaseController
      MAX_PAGES = 10

      # GET /api/v1/document_captures/presets
      def presets
        render json: {
          presets: DocumentPresets::ALL.map(&:to_h),
          ocr_available: PdfOcr.available?
        }
      end

      # GET /api/v1/document_captures/page/:id — a photograph the phone left
      #
      # The signed id is minted by the scan and expires with it. Signing in is
      # still required, so a leaked id is worth nothing on its own.
      def page
        blob = ActiveStorage::Blob.find_signed!(params[:id])

        send_data blob.download, type: blob.content_type, disposition: "inline"
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
        render_error(message: "That scan is no longer available. Take the photo again.",
                     code: "scan_expired", status: :not_found)
      end

      # POST /api/v1/document_captures
      #
      # Params: pages[] (images) or file_id, preset, name, folder_id
      def create
        unless DocumentPresets.exists?(params[:preset])
          return render_error(message: "Pick what kind of document this is.",
                              code: "unknown_preset", status: :unprocessable_content)
        end

        stored = params[:file_id].present? ? existing_file : store_scan
        return if performed?

        suggestion = best_reading(stored.attachment.download)

        render json: suggestion.to_h.merge(
          file: { id: stored.id, name: stored.name, size: stored.size, mime_type: stored.mime_type },
          found_text: suggestion.text.present?
        ), status: :created
      rescue ImagePdfBuilder::Error => e
        render_error(message: e.message, code: "pdf_failed", status: :unprocessable_content)
      rescue FileUploader::QuotaExceeded => e
        render_error(message: e.message, code: "quota_exceeded", status: :content_too_large)
      end

      private

      # The text layer if the document has one, and the writing inside the
      # picture if it does not — which for a photographed passport is always.
      #
      # Two goes at a picture. The default segmentation expects a page of prose;
      # an identity card is a handful of short lines in several sizes and reads
      # far better when tesseract is told to expect one column of them. Trying
      # both costs the extra time only when the first attempt found nothing —
      # which is exactly when it is worth spending.
      def best_reading(bytes)
        extracted = PdfTextExtractor.new(bytes).call
        return reading(extracted.text) if extracted.any_text?

        first = reading(PdfOcr.new(bytes).call.text)
        return first if first.fields.any?

        second = reading(PdfOcr.new(bytes, layout: PdfOcr::CARD).call.text)
        second.fields.any? ? second : first
      end

      def reading(text)
        DocumentReader.new(text, params[:preset]).call
      end

      def existing_file
        file = StoredFile.active.find_by(id: params[:file_id])

        if file.nil? || !PermissionChecker.can_view?(current_user, file)
          render_error(message: "We couldn't find that file.", code: "not_found", status: :not_found)
          return nil
        end

        unless file.mime_type == "application/pdf"
          render_error(message: "#{file.name} isn't a PDF.", code: "not_a_pdf",
                       status: :unprocessable_content)
          return nil
        end

        file
      end

      def store_scan
        pages = Array(params[:pages]).compact_blank

        if pages.empty?
          render_error(message: "No pages were sent.", code: "no_pages", status: :bad_request)
          return nil
        end

        if pages.size > MAX_PAGES
          render_error(message: "A document of more than #{MAX_PAGES} pages is more than this reads.",
                       code: "too_many_pages", status: :unprocessable_content)
          return nil
        end

        images = pages.map do |page|
          bytes = page.read
          { name: page.original_filename.to_s, bytes: bytes,
            content_type: Marcel::MimeType.for(StringIO.new(bytes)) }
        end

        pdf = ImagePdfBuilder.new(images, page_size: "auto", margin: "none", title: scan_name).call

        FileUploader
          .new(user: current_user, family: current_family)
          .call(pdf_upload(pdf), folder: destination_folder, visibility: "private")
      end

      def scan_name
        base = params[:name].presence || DocumentPresets[params[:preset]]&.label || "Document"

        "#{base} #{Time.current.strftime('%-d %b %Y')}"
      end

      def pdf_upload(bytes)
        tempfile = Tempfile.new([ "capture", ".pdf" ], binmode: true)
        tempfile.write(bytes)
        tempfile.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile: tempfile, filename: "#{scan_name}.pdf", type: "application/pdf"
        )
      end

      def destination_folder
        return nil if params[:folder_id].blank?

        Folder.active.find_by(id: params[:folder_id], user_id: current_user.id)
      end
    end
  end
end
