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

      private

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
      # first and usually the one they think of it as.
      def output_name(files)
        base = File.basename(files.first.name, ".*")
        "#{base} (merged).pdf"
      end

      def save_result(bytes, name:)
        tempfile = Tempfile.new([ "utility", ".pdf" ], binmode: true)
        tempfile.write(bytes)
        tempfile.rewind

        upload = ActionDispatch::Http::UploadedFile.new(
          tempfile: tempfile, filename: name, type: "application/pdf"
        )

        # Lands in the caller's own space, private, whatever the sources were:
        # a merge of family documents is a new document, and its author decides
        # who sees it.
        FileUploader.new(user: current_user, family: current_family)
                    .call(upload, folder: destination_folder, visibility: "private")
      end

      def destination_folder
        return nil if params[:folder_id].blank?

        Folder.active.find_by(id: params[:folder_id], user_id: current_user.id)
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
