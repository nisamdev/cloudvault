# frozen_string_literal: true

namespace :records do
  # A Person used to carry a passport number, a licence number and an NHS
  # number. Each of those is a document with its own expiry, its own scan and
  # its own life, so each becomes a record — linked back to whoever holds it.
  #
  # Safe to run twice: a person with nothing left to move is skipped.
  desc "Move document numbers off Person records onto documents of their own"
  task split_person_documents: :environment do
    splits = {
      "passport" => { "passport_number" => "passport_number", "passport_expires_on" => "expires_on" },
      "driving_licence" => { "licence_number" => "licence_number", "licence_expires_on" => "expires_on" },
      "health_card" => { "nhs_number" => "nhs_number" }
    }

    moved = 0

    VaultRecord.where(record_type: "person").find_each do |person|
      data = person.data.dup
      name = data["full_name"].presence || person.title

      splits.each do |type, mapping|
        carried = mapping.filter_map { |from, to| [ to, data[from] ] if data[from].present? }.to_h
        next if carried.empty?

        # The date of birth belongs on both: it is on the document as printed,
        # and it is who the person is.
        carried["full_name"] = name
        carried["date_of_birth"] = data["date_of_birth"] if data["date_of_birth"].present?

        document = VaultRecord.create!(
          user_id: person.user_id,
          family_id: person.family_id,
          folder_id: person.folder_id,
          record_type: type,
          visibility: person.visibility,
          title: "#{name} — #{RecordTemplates[type].label}",
          data: carried
        )

        RecordLink.create!(vault_record: document, linked_record: person, relation: "held_by")

        data = data.except(*mapping.keys)
        moved += 1
        puts "  #{person.title} → #{document.title}"
      end

      person.update!(data: data) if data != person.data
    end

    puts moved.zero? ? "Nothing to move." : "Moved #{moved} document(s) off Person records."
  end
end
