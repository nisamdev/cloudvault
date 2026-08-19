class CreateStoredFiles < ActiveRecord::Migration[8.1]
  def change
    # Named stored_files, not files: `File` would shadow Ruby's built-in class.
    create_table :stored_files do |t|
      t.references :user, null: false, foreign_key: true
      t.references :family, foreign_key: true
      t.references :folder, foreign_key: true

      t.string :name, null: false
      t.string :mime_type, null: false
      t.bigint :size, null: false, default: 0
      # 'file' or 'image' — drives which screen the item appears on.
      t.string :file_type, null: false, default: "file"
      t.string :checksum

      # Image metadata, populated asynchronously after upload.
      t.integer :image_width
      t.integer :image_height

      # 'private' | 'family' | 'shared_link'
      t.string :visibility, null: false, default: "private"
      t.integer :version_number, null: false, default: 1

      t.datetime :trashed_at
      t.datetime :last_accessed_at

      t.timestamps
    end

    add_index :stored_files, [ :user_id, :trashed_at ]
    add_index :stored_files, [ :family_id, :created_at ]
    add_index :stored_files, [ :file_type, :created_at ]
    add_check_constraint :stored_files,
      "file_type IN ('file', 'image')", name: "stored_files_file_type_check"
    add_check_constraint :stored_files,
      "visibility IN ('private', 'family', 'shared_link')", name: "stored_files_visibility_check"
  end
end
