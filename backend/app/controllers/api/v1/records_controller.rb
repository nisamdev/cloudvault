# frozen_string_literal: true

module Api
  module V1
    class RecordsController < BaseController
      before_action :set_record, only: %i[show update destroy]

      # GET /api/v1/records
      def index
        scope = visible_records.active
        scope = params[:locked] == "true" ? only_locked(scope) : hide_locked(scope)
        scope = scope.of_type(params[:type]) if params[:type].present?
        scope = scope.search(params[:q]) if params[:q].present?

        pagy, records = pagy(
          scope.recent.includes(:user, :record_links, :linked_records, :record_secrets),
          limit: per_page
        )
        pagination_headers(pagy)

        render json: { records: records.map { |record| serialize(record) } }
      end

      # GET /api/v1/records/:id
      def show
        render json: { record: serialize(@record, detailed: true) }
      end

      # POST /api/v1/records
      def create
        record = VaultRecord.new(record_params)
        record.user = current_user
        record.family = family_for(record.visibility)
        record.data = cleaned_data(record.record_type, record.data)

        if record.locked? && !vault_unlocked?
          return render_error(message: "Unlock the private section before adding a private record.",
                              code: "vault_locked", status: :forbidden)
        end

        if record.visibility == "family" && !PermissionChecker.can_upload_to_family?(current_user, record.family)
          return render_error(message: "You don't have permission to add records to the family register.",
                              code: "forbidden", status: :forbidden)
        end

        VaultRecord.transaction do
          record.save!
          sync_attachments!(record, attachment_ids_param) if params.key?(:attachment_ids)
          sync_links!(record, links_param) if params.key?(:links)
          sync_secrets!(record, secrets_param) if params.key?(:secrets)
        end

        render json: { record: serialize(record.reload, detailed: true) }, status: :created
      end

      # PATCH /api/v1/records/:id
      def update
        unless RecordPermissions.can_edit?(current_user, @record)
          return render_error(message: "You don't have permission to change this record.",
                              code: "forbidden", status: :forbidden)
        end

        attrs = record_params
        if attrs.key?(:visibility)
          new_family = family_for(attrs[:visibility] || @record.visibility)
          attrs[:family_id] = new_family&.id
        end
        attrs[:data] = cleaned_data(@record.record_type, attrs[:data]) if attrs.key?(:data)

        if attrs[:locked] == true && !@record.locked? && !vault_unlocked?
          return render_error(message: "Unlock the private section before locking this record.",
                              code: "vault_locked", status: :forbidden)
        end

        VaultRecord.transaction do
          @record.update!(attrs)
          sync_attachments!(@record, attachment_ids_param) if params.key?(:attachment_ids)
          sync_links!(@record, links_param) if params.key?(:links)
          sync_secrets!(@record, secrets_param) if params.key?(:secrets)
        end

        render json: { record: serialize(@record.reload, detailed: true) }
      end

      # DELETE /api/v1/records/:id — archive, not purge.
      def destroy
        unless RecordPermissions.can_delete?(current_user, @record)
          return render_error(message: "You don't have permission to remove this record.",
                              code: "forbidden", status: :forbidden)
        end

        @record.archive!
        head :no_content
      end

      # GET /api/v1/records/upcoming
      #
      # What is running out, for the register and for the settings screen —
      # where it doubles as a preview of exactly what would be posted.
      def upcoming
        dues = UpcomingExpiries.for_user(current_user)

        render json: {
          upcoming: dues.map(&:to_h),
          reminders: {
            enabled: current_user.reminders_enabled,
            scope: current_user.reminder_scope,
            email: current_user.email,
            # Only some dates write; the rest just count down.
            would_write_about: dues.count { |due| due.field.reminds? }
          }
        }
      end

      private

      def visible_records
        own = VaultRecord.where(user_id: current_user.id)
        return own unless current_family

        own.or(VaultRecord.where(family_id: current_family.id, visibility: "family"))
      end

      def set_record
        record = visible_records.includes(record_secrets: :secret_versions).find_by(id: params[:id])
        if record.nil? || (record.locked? && !vault_unlocked?) ||
           !RecordPermissions.can_view?(current_user, record)
          render_error(message: "We couldn't find what you were looking for.",
                       code: "not_found", status: :not_found)
          return
        end

        @record = record
      end

      def record_params
        params.require(:record).permit(:record_type, :title, :visibility, :locked, :folder_id, data: {})
      end

      def attachment_ids_param
        Array(params[:attachment_ids]).map(&:to_i).uniq
      end

      def links_param
        Array(params[:links]).filter_map do |link|
          next unless link.is_a?(ActionController::Parameters) || link.is_a?(Hash)

          h = link.to_unsafe_h.symbolize_keys
          next if h[:linked_record_id].blank?

          { linked_record_id: h[:linked_record_id].to_i, relation: h[:relation].presence || "related_to" }
        end
      end

      def secrets_param
        return nil unless params.key?(:secrets)

        raw = params[:secrets]
        hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
        hash.stringify_keys
      end

      def family_for(visibility)
        visibility == "family" ? current_family : nil
      end

      # What actually gets stored in `data`.
      #
      # Two things are stripped. Secrets, because they belong in record_secrets
      # under encryption and must never reach a column that feeds the search
      # vector. And blanks, because a form posts every field it drew — keeping
      # them would fill the register with empty strings, pad the search vector
      # with nothing, and lose the distinction between a field somebody filled
      # in and one the template merely offered.
      #
      # Keys the template has never heard of are kept: a record is allowed to
      # grow a field its owner invented.
      def cleaned_data(type, data)
        return {} if data.blank?

        hash = data.respond_to?(:to_unsafe_h) ? data.to_unsafe_h : data.to_h
        secret_keys = RecordTemplates[type]&.secret_fields&.map(&:key) || []

        hash.stringify_keys
            .except(*secret_keys)
            .reject { |_key, value| value.respond_to?(:blank?) ? value.blank? : value.nil? }
      end

      def sync_secrets!(record, secrets)
        RecordSecretsSync.new(record, vault_key: vault_key).call(secrets)
      rescue RecordSecretsSync::VaultLocked
        record.errors.add(:base, "Unlock the private section before saving passwords.")
        raise ActiveRecord::RecordInvalid, record
      end

      def sync_attachments!(record, ids)
        return if ids.nil?

        validate_attachments!(record, ids)
        record.record_attachments.destroy_all
        return if ids.empty?

        ids.each_with_index do |file_id, index|
          record.record_attachments.create!(stored_file_id: file_id, position: index)
        end
      end

      def sync_links!(record, links)
        return if links.nil?

        record.record_links.destroy_all
        links.each do |link|
          target = visible_records.find_by(id: link[:linked_record_id])
          next unless target

          record.record_links.create!(
            linked_record: target,
            relation: link[:relation]
          )
        end
      end

      def visible_attachable_files
        scope = hide_locked(StoredFile.active.where(user_id: current_user.id))
        return scope unless current_family

        scope.or(
          hide_locked(StoredFile.active.where(family_id: current_family.id, visibility: "family"))
        )
      end

      def validate_attachments!(record, ids)
        return if ids.blank?

        found = visible_attachable_files.where(id: ids).count
        return if found == ids.size

        record.errors.add(:base, "One or more files could not be linked from My Files.")
        raise ActiveRecord::RecordInvalid, record
      end

      def per_page
        [ params.fetch(:per_page, 50).to_i, 200 ].min
      end

      def serialize(record, detailed: false)
        template = record.template
        payload = {
          id: record.id,
          record_type: record.record_type,
          type_label: template&.label,
          type_icon: template&.icon,
          title: record.title,
          website: record.data["website"].presence,
          visibility: record.visibility,
          locked: record.locked?,
          archived_at: record.archived_at,
          created_at: record.created_at,
          updated_at: record.updated_at,
          # The kind travels with the value: without it a card cannot tell a
          # policy number from a renewal date, and renders both as grey text.
          highlights: record.fields.first(3).map do |row|
            { label: row[:field].label, value: row[:value], kind: row[:field].kind }
          end,
          # The soonest date this record is counting down to, so the register can
          # say "18 days left" instead of "2026-09-14".
          next_expiry: next_expiry_for(record),
          owner: { id: record.user_id, name: record.user.full_name || record.user.email },
          permissions: {
            can_edit: RecordPermissions.can_edit?(current_user, record),
            can_delete: RecordPermissions.can_delete?(current_user, record)
          }
        }

        return payload unless detailed

        payload.merge(
          data: record.data,
          fields: record.fields.map { |row| serialize_field(row) },
          secrets: serialize_secrets(record),
          expiries: record.expiries.map { |field, date| { key: field.key, label: field.label, date: date.iso8601 } },
          links: serialize_links(record),
          attachments: serialize_attachments(record),
          template: template&.to_h
        )
      end

      # Soonest first, and dates that have already gone still count — an expired
      # permit is the most urgent thing on the page, not the least.
      def next_expiry_for(record)
        soonest = record.expiries.min_by { |_field, date| date }
        return nil if soonest.nil?

        field, date = soonest
        { key: field.key, label: field.label, date: date.iso8601, days: (date - Date.current).to_i }
      end

      def serialize_secrets(record)
        template = record.template
        return [] unless template

        stored = record.record_secrets.index_by(&:key)
        template.secret_fields.map do |field|
          secret = stored[field.key]
          {
            key: field.key,
            label: field.label,
            hint: field.hint,
            set: secret.present?,
            updated_at: secret&.updated_at,
            history_count: secret&.secret_versions&.size || 0
          }
        end
      end

      def serialize_field(row)
        {
          key: row[:field].key,
          label: row[:field].label,
          kind: row[:field].kind,
          value: row[:value],
          custom: row[:custom] == true
        }
      end

      def serialize_links(record)
        record.record_links.includes(:linked_record).map do |link|
          linked = link.linked_record
          {
            id: link.id,
            relation: link.relation,
            record: {
              id: linked.id,
              title: linked.title,
              record_type: linked.record_type,
              type_label: linked.template&.label
            }
          }
        end
      end

      def serialize_attachments(record)
        record.record_attachments.includes(stored_file: :user).order(:position).map do |attachment|
          file = attachment.stored_file
          next unless PermissionChecker.can_view?(current_user, file)

          {
            id: attachment.id,
            file_id: file.id,
            name: file.name,
            mime_type: file.mime_type,
            size: file.size
          }
        end.compact
      end
    end
  end
end
