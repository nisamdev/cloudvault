class CreateFileVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :file_versions do |t|
      t.references :stored_file, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.integer :version_number, null: false
      t.bigint :size, null: false, default: 0
      t.string :checksum

      t.timestamps
    end

    add_index :file_versions, [ :stored_file_id, :version_number ], unique: true
  end
end
