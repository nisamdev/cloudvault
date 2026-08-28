# frozen_string_literal: true

# What each kind of thing does when somebody leaves the family.
#
# One rule for everything was wrong in both directions. Keeping it all meant the
# person who took a photograph lost it to whoever removed them; sending it all
# home meant a household lost the deed somebody had scanned for it. A holiday
# photo and a scanned deed are not the same kind of thing and do not want the
# same answer.
#
# "home" — back to whoever shared it, unshared, still theirs.
# "stay" — remains with the household, and passes to whoever owns the family.
class LetAFamilySayWhatLeavesWithPeople < ActiveRecord::Migration[8.1]
  CHOICES = %w[home stay].freeze

  def change
    add_column :families, :on_departure_photos, :string, null: false, default: "home"
    add_column :families, :on_departure_files, :string, null: false, default: "stay"
    add_column :families, :on_departure_records, :string, null: false, default: "stay"

    %i[on_departure_photos on_departure_files on_departure_records].each do |column|
      add_check_constraint :families,
                           "#{column} IN (#{CHOICES.map { |c| "'#{c}'" }.join(', ')})",
                           name: "families_#{column}_check"
    end
  end
end
