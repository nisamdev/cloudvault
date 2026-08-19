class AddSearchToStoredFiles < ActiveRecord::Migration[8.1]
  def up
    # Full-text search over the file name (implementation guide, week 5).
    #
    # Separators are translated to spaces first: without that,
    # "Mortgage_Agreement.pdf" tokenises as one opaque term and searching for
    # "mortgage" finds nothing.
    execute <<~SQL
      ALTER TABLE stored_files
      ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (
        to_tsvector('english', translate(coalesce(name, ''), '_-.', '   '))
      ) STORED
    SQL

    execute "CREATE INDEX index_stored_files_on_search_vector ON stored_files USING gin(search_vector)"

    # Supports the ILIKE substring fallback for partial words.
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")
    execute "CREATE INDEX index_stored_files_on_name_trgm ON stored_files USING gin(name gin_trgm_ops)"

    execute "CREATE INDEX index_folders_on_name_trgm ON folders USING gin(name gin_trgm_ops)"
  end

  def down
    execute "DROP INDEX IF EXISTS index_folders_on_name_trgm"
    execute "DROP INDEX IF EXISTS index_stored_files_on_name_trgm"
    execute "DROP INDEX IF EXISTS index_stored_files_on_search_vector"
    execute "ALTER TABLE stored_files DROP COLUMN IF EXISTS search_vector"
  end
end
