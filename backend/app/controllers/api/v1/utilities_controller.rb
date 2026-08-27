# frozen_string_literal: true

module Api
  module V1
    # Tools that act on documents rather than just storing them.
    #
    # Everything here reads files the caller can already see and writes the
    # result back into the vault as a new file, so nothing leaves and nothing is
    # overwritten by accident.
    class UtilitiesController < BaseController
      # POST /api/v1/utilities/merge
      def merge
        ids = Array(params[:file_ids]).map(&:to_i)
        files = ordered_files(ids)
        return if performed?

        not_pdf = files.reject { |f| f.mime_type == "application/pdf" }
        if not_pdf.any?
          return render_error(
            message: "#{not_pdf.first.name} isn't a PDF.",
            code: "not_a_pdf",
            status: :unprocessable_content
          )
        end

        bytes = PdfMerger.new(files.map { |f| { name: f.name, bytes: f.attachment.download } }).call
        stored = save_result(bytes, name: output_name(files))

        render json: { file: serialize_result(stored) }, status: :created
      rescue PdfMerger::Error => e
        render_error(message: e.message, code: "merge_failed", status: :unprocessable_content)
      rescue FileUploader::QuotaExceeded => e
        render_error(message: e.message, code: "quota_exceeded", status: :content_too_large)
      end

      # POST /api/v1/utilities/images_to_pdf
      #
      # The pages arrive as images, in the order they should appear. They have
      # already been cropped and enhanced in the browser, where the user could
      # see what they were getting, so what is sent is exactly what the document
      # should contain.
      def images_to_pdf
        pages = Array(params[:pages]).compact_blank
        if pages.empty?
          return render_error(message: "No images were sent.", code: "no_images", status: :bad_request)
        end

        # Checked before anything is read. Rack has already spilled the parts to
        # tempfiles, so their sizes are free — but reading sixty of them to find
        # out they were too big is how one request takes the process with it.
        too_big = pages.size > ImagePdfBuilder::MAX_PAGES ||
                  pages.sum { |page| page.size.to_i } > ImagePdfBuilder::MAX_TOTAL_BYTES
        if too_big
          return render_error(message: "That's more than this tool can take at once.",
                              code: "too_much", status: :content_too_large)
        end

        visibility = requested_visibility
        return if performed?

        images = pages.map do |page|
          bytes = page.read
          # What the bytes say, not what the client claims — Prawn will choke on
          # a mislabelled file and the error would be far less clear.
          { name: page.original_filename.to_s, bytes: bytes, content_type: sniff(bytes) }
        end

        bytes = ImagePdfBuilder.new(
          images,
          page_size: params[:page_size],
          orientation: params[:orientation],
          margin: params[:margin],
          title: params[:name]
        ).call

        stored = save_result(bytes, name: pdf_name(params[:name]), visibility: visibility)

        render json: { file: serialize_result(stored) }, status: :created
      rescue ImagePdfBuilder::Error => e
        render_error(message: e.message, code: "pdf_failed", status: :unprocessable_content)
      rescue FileUploader::QuotaExceeded => e
        render_error(message: e.message, code: "quota_exceeded", status: :content_too_large)
      rescue FileUploader::FileTooLarge => e
        render_error(message: e.message, code: "file_too_large", status: :content_too_large)
      end

      private

      def sniff(bytes)
        Marcel::MimeType.for(StringIO.new(bytes))
      end

      # A tool writes a new file, so it is the caller who decides who sees it —
      # nothing is inherited from the sources.
      def requested_visibility
        return "private" unless params[:visibility] == "family"

        unless PermissionChecker.can_upload_to_family?(current_user, current_family)
          render_error(message: "You don't have permission to add files to the family vault.",
                       code: "forbidden", status: :forbidden)
          return nil
        end

        "family"
      end

      # The name is typed by a person, who will not think to add the extension
      # and may well have added it twice.
      def pdf_name(raw)
        base = File.basename(raw.to_s.strip.tr("/\\", "-"), ".pdf")
        base = "Scan #{Time.current.strftime('%-d %b %Y, %H.%M')}" if base.blank?

        "#{base}.pdf"
      end

      # Loads them in the order the caller listed, and refuses quietly missing
      # ones rather than silently merging fewer pages than were asked for.
      def ordered_files(ids)
        found = StoredFile.active.where(id: ids).index_by(&:id)
        files = ids.map { |id| found[id] }

        if files.any?(&:nil?) || files.any? { |f| !PermissionChecker.can_view?(current_user, f) }
          render_error(message: "We couldn't find one of those files.",
                       code: "not_found", status: :not_found)
          return []
        end

        empty = files.reject { |f| f.attachment.attached? }
        if empty.any?
          render_error(message: "#{empty.first.name} has no contents.",
                       code: "not_found", status: :not_found)
          return []
        end

        files
      end

      # Named after the first document, since that is the one the user picked
      # first and usually the one they think of it as. Merging a merge does not
      # stack the suffix — "Passport (merged) (merged) (merged).pdf" tells you
      # nothing that "Passport (merged).pdf" does not.
      def output_name(files)
        base = File.basename(files.first.name, ".*").sub(/\s*\(merged\)\z/, "")
        "#{base} (merged).pdf"
      end

      def save_result(bytes, name:, visibility: "private")
        tempfile = Tempfile.new([ "utility", ".pdf" ], binmode: true)
        tempfile.write(bytes)
        tempfile.rewind

        upload = ActionDispatch::Http::UploadedFile.new(
          tempfile: tempfile, filename: name, type: "application/pdf"
        )

        # Lands in the caller's own space, and private unless they said
        # otherwise, whatever the sources were: a merge of family documents is a
        # new document, and its author decides who sees it.
        FileUploader.new(user: current_user, family: current_family)
                    .call(upload, folder: destination_folder, visibility: visibility)
      end

      # Their own folders, or a family folder they can already see — the same
      # reach an upload has.
      def destination_folder
        return nil if params[:folder_id].blank?

        own = Folder.active.find_by(id: params[:folder_id], user_id: current_user.id)
        return own if own

        family_id = current_membership&.family_id
        return nil if family_id.nil?

        Folder.active.find_by(id: params[:folder_id], family_id: family_id)
      end

      def serialize_result(file)
        {
          id: file.id,
          name: file.name,
          size: file.size,
          mime_type: file.mime_type,
          file_type: file.file_type,
          folder: file.folder && { id: file.folder_id, name: file.folder.name },
          created_at: file.created_at
        }
      end
    end
  end
end
