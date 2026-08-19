class CreateSharedLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :shared_links do |t|
      t.references :stored_file, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      # Only the digest is stored; the raw token lives in the shared URL alone.
      t.string :token_digest, null: false
      # Optional password gate (bcrypt), per the prototype's share modal.
      t.string :password_digest

      t.datetime :expires_at
      t.datetime :revoked_at
      t.integer :download_count, null: false, default: 0
      t.integer :max_downloads
      t.datetime :last_accessed_at

      t.timestamps
    end

    add_index :shared_links, :token_digest, unique: true
    add_index :shared_links, [ :stored_file_id, :revoked_at ]
  end
end
