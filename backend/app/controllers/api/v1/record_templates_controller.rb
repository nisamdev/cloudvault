# frozen_string_literal: true

module Api
  module V1
    class RecordTemplatesController < BaseController
      # GET /api/v1/record_templates
      def index
        render json: { templates: RecordTemplates::ALL.map(&:to_h) }
      end
    end
  end
end
