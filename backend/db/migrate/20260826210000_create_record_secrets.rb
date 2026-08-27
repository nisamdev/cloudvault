# frozen_string_literal: true

# Passwords and security answers live apart from the searchable fields.
#
# Same rules as the plan: encrypted, never in a listing, fetched one at a time
# on reveal. The kdf column carries whatever is needed to open the sealed bytes,
# without assuming the server did the sealing — so browser-side encryption later
# is a change to who unlocks, not a migration.
class CreateRecordSecrets < ActiveRecord::Migration[8.1]
  def change
    create_table :record_secrets do |t|
      t.references :vault_record, null: false, foreign_key: true
      t.string :key, null: false
      t.binary :sealed, null: false
      t.jsonb :kdf, null: false, default: {}
      t.timestamps
    end
    add_index :record_secrets, %i[vault_record_id key], unique: true

    create_table :secret_versions do |t|
      t.references :record_secret, null: false, foreign_key: true
      t.binary :sealed, null: false
      t.datetime :replaced_at, null: false
      t.timestamps
    end
    add_index :secret_versions, %i[record_secret_id replaced_at]
  end
end
