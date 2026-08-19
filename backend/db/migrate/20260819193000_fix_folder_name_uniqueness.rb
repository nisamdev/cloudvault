class FixFolderNameUniqueness < ActiveRecord::Migration[8.1]
  def up
    # The old index was (user_id, parent_id, name). In Postgres two NULLs are
    # distinct, so it never constrained folders at the root — where parent_id is
    # NULL. COALESCE gives root folders a real value to collide on.
    remove_index :folders, name: "index_folders_unique_name_per_parent", if_exists: true

    # Family folders share one namespace across the household...
    execute <<~SQL
      CREATE UNIQUE INDEX index_folders_unique_name_in_family
      ON folders (family_id, COALESCE(parent_id, 0), LOWER(name))
      WHERE trashed_at IS NULL AND family_id IS NOT NULL
    SQL

    # ...personal folders are namespaced per user.
    execute <<~SQL
      CREATE UNIQUE INDEX index_folders_unique_name_personal
      ON folders (user_id, COALESCE(parent_id, 0), LOWER(name))
      WHERE trashed_at IS NULL AND family_id IS NULL
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_folders_unique_name_in_family"
    execute "DROP INDEX IF EXISTS index_folders_unique_name_personal"

    add_index :folders, [ :user_id, :parent_id, :name ], unique: true,
              where: "trashed_at IS NULL",
              name: "index_folders_unique_name_per_parent"
  end
end
