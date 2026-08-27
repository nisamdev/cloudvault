# frozen_string_literal: true

# A note of what has already been written about.
#
# Without it a reminder set six weeks out would send every morning for the next
# thirty-five days, and be filtered to spam by the second week.
class ExpiryReminder < ApplicationRecord
  belongs_to :vault_record
  belongs_to :user

  # Changing the date is how you renew something, and a renewed thing deserves
  # its whole schedule again — so due_on is part of what makes a note unique.
  def self.already_sent?(user:, due:)
    exists?(
      user_id: user.id,
      vault_record_id: due.record.id,
      field_key: due.field.key,
      due_on: due.date,
      threshold: due.threshold
    )
  end

  def self.note!(user:, due:)
    create!(
      user: user,
      vault_record: due.record,
      field_key: due.field.key,
      due_on: due.date,
      threshold: due.threshold,
      sent_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    # Two runs overlapping is not worth failing a send that already happened.
    nil
  end
end
