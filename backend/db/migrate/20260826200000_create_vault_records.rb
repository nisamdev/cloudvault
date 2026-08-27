# frozen_string_literal: true

# Records: the facts a family keeps, as opposed to the documents it stores.
#
# "Which email is the electricity account under", "when does the permit expire",
# "what is the gas meter number" — none of those are files, and keeping them as
# files is what makes a folder called Property useless.
#
# Named vault_records rather than records for the same reason StoredFile is not
# called File: `Record` is a word Rails and everyone talking about Rails already
# uses for something else.
class CreateVaultRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :vault_records do |t|
      t.references :user, null: false, foreign_key: true
      t.references :family, foreign_key: true
      t.references :folder, foreign_key: true

      t.string :record_type, null: false
      t.string :title, null: false

      # The fields themselves. JSONB rather than a table per type, because a
      # household thinks of a new thing to write down every other week and a
      # migration per idea is how a register stops being used.
      t.jsonb :data, null: false, default: {}

      t.string :visibility, null: false, default: "private"
      # Lives in the private section, on the same passphrase as everything else
      # there. Secrets arrive in the next step; this is already meaningful
      # without them, because a permit number is not for guests either.
      t.boolean :locked, null: false, default: false

      t.datetime :archived_at

      t.timestamps
    end

    add_index :vault_records, %i[user_id record_type]
    add_index :vault_records, %i[family_id archived_at]
    add_index :vault_records, %i[user_id locked]
    # Searching and filtering inside the JSON — "every record whose provider is
    # British Gas" — without a column per field.
    add_index :vault_records, :data, using: :gin

    # Same shape as stored_files: a generated column so nothing has to remember
    # to reindex, over the title and the values people actually search by.
    execute <<~SQL
      ALTER TABLE vault_records
        ADD COLUMN search_vector tsvector
        GENERATED ALWAYS AS (
          to_tsvector('english',
            coalesce(title, '') || ' ' ||
            coalesce(jsonb_path_query_array(data, '$.*')::text, '')
          )
        ) STORED
    SQL
    add_index :vault_records, :search_vector, using: :gin

    # What a record points at: the deed, the policy, the certificate. Ordinary
    # CloudVault files, so everything that already works on them still does.
    create_table :record_attachments do |t|
      t.references :vault_record, null: false, foreign_key: true
      t.references :stored_file, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :record_attachments, %i[vault_record_id stored_file_id], unique: true

    # What a record knows about other records. The relation is a plain word so
    # the page can read as a sentence rather than a table.
    create_table :record_links do |t|
      t.references :vault_record, null: false, foreign_key: true
      t.references :linked_record, null: false, foreign_key: { to_table: :vault_records }
      t.string :relation, null: false, default: "related_to"
      t.timestamps
    end
    add_index :record_links, %i[vault_record_id linked_record_id], unique: true
  end
end
