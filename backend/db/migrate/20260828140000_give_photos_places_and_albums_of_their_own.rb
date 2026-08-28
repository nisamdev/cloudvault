# frozen_string_literal: true

# Two things the gallery was missing.
#
# A photograph can now be told where it was taken. One picture in eighty
# arrived with GPS still attached — phones strip it on sharing and anything
# that came through a messaging app has had it removed — so the only way this
# vault will ever know where a photograph was taken is if somebody says so.
# `place_name` is what that looks like, and it is what searching by place
# actually searches.
#
# And folders now say which cabinet they belong to. An album called "Holidays"
# has no business in the same tree as the folder holding the mortgage, and a
# gallery that shows every photograph at once stops being usable somewhere
# around the second year.
class GivePhotosPlacesAndAlbumsOfTheirOwn < ActiveRecord::Migration[8.1]
  def change
    # Where it was taken, as a person would say it.
    add_column :stored_files, :place_name, :string
    add_index :stored_files, :place_name

    add_column :folders, :kind, :string, null: false, default: "file"
    add_column :folders, :is_default, :boolean, null: false, default: false

    add_check_constraint :folders, "kind IN ('file', 'photo')", name: "folders_kind_check"
    add_index :folders, %i[user_id kind]
    # One default album per person per cabinet, and no more.
    add_index :folders, %i[user_id kind], unique: true,
              where: "is_default AND trashed_at IS NULL",
              name: "index_folders_one_default_per_kind"
  end
end
