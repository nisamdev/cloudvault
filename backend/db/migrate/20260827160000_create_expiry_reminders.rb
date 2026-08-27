# frozen_string_literal: true

# What has already been written about, so nothing is written about twice.
#
# Without this, a reminder set six weeks out would send every morning for the
# next thirty-five days and be filtered to spam by the second week.
#
# `due_on` is part of what makes a reminder unique on purpose: renew the permit,
# put the new date in, and the whole schedule starts again — which is exactly
# what should happen.
class CreateExpiryReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :expiry_reminders do |t|
      t.references :vault_record, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.string :field_key, null: false
      t.date :due_on, null: false
      # Which step of the schedule this was — 180, 90, 30, 7…
      t.integer :threshold, null: false

      t.datetime :sent_at, null: false

      t.timestamps
    end

    add_index :expiry_reminders,
              %i[vault_record_id user_id field_key due_on threshold],
              unique: true,
              name: "index_expiry_reminders_on_what_was_sent"
  end
end
