# frozen_string_literal: true

module Api
  module V1
    class LabelsController < BaseController
      before_action :set_label, only: %i[update destroy]

      # GET /api/v1/labels
      def index
        labels = Label.for_user(current_user)
                      .left_joins(:file_labels)
                      .group("labels.id")
                      .select("labels.*, COUNT(file_labels.id) AS files_count")
                      .order(:name)

        render json: { labels: labels.map { |label| serialize(label, label.files_count) } }
      end

      # POST /api/v1/labels
      def create
        label = Label.new(label_params)
        label.user = current_user
        # Members of a family share one vocabulary; solo users get personal labels.
        label.family = current_family
        label.save!

        render json: { label: serialize(label, 0) }, status: :created
      end

      # PATCH /api/v1/labels/:id
      def update
        @label.update!(label_params)
        render json: { label: serialize(@label, @label.file_labels.count) }
      end

      # DELETE /api/v1/labels/:id
      # Removes the label from every file; the files themselves are untouched.
      def destroy
        @label.destroy!
        head :no_content
      end

      private

      def set_label
        @label = Label.for_user(current_user).find_by(id: params[:id])

        return if @label.nil? == false && authorized_to_manage?

        if @label.nil?
          render_error(message: "We couldn't find what you were looking for.",
                       code: "not_found", status: :not_found)
        else
          render_error(message: "Only family owners and admins can change shared labels.",
                       code: "forbidden", status: :forbidden)
        end
      end

      # Anyone may create labels, but editing or deleting a shared one affects
      # the whole family, so that is limited to editors and above.
      def authorized_to_manage?
        return true if @label.personal? && @label.user_id == current_user.id
        return false if @label.personal?

        PermissionChecker.can_upload_to_family?(current_user, @label.family)
      end

      def label_params
        params.require(:label).permit(:name, :color)
      end

      def serialize(label, files_count)
        {
          id: label.id,
          name: label.name,
          color: label.color,
          shared: !label.personal?,
          files_count: files_count
        }
      end
    end
  end
end
