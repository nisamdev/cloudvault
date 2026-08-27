# frozen_string_literal: true

# Whether to write to somebody, and about whose things.
#
# On by default: a register that knows a permit runs out in a fortnight and says
# nothing is worth less than the paper it replaced. But it has to be one switch
# away, because the fastest way to make somebody ignore a reminder is to send
# one they did not want.
class AddReminderSettingsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :reminders_enabled, :boolean, null: false, default: true
    # "own" — only records I added. "family" — those and whatever the household
    # shares, which is the useful default: the car insurance is nobody's in
    # particular until it lapses.
    add_column :users, :reminder_scope, :string, null: false, default: "family"
  end
end
