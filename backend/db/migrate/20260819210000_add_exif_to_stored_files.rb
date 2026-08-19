class AddExifToStoredFiles < ActiveRecord::Migration[8.1]
  def change
    change_table :stored_files, bulk: true do |t|
      # When the photo was taken, which is not when it was uploaded — a holiday
      # album uploaded in one go would otherwise all land under "Today".
      t.datetime :taken_at

      # WGS84, from the EXIF GPS block. Six decimal places is roughly 10cm.
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6

      t.string :camera_make
      t.string :camera_model
    end

    # The gallery orders by capture date when it is known.
    add_index :stored_files, :taken_at
    add_index :stored_files, [ :latitude, :longitude ],
              where: "latitude IS NOT NULL AND longitude IS NOT NULL",
              name: "index_stored_files_on_coordinates"
  end
end
