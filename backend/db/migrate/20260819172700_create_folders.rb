class CreateFolders < ActiveRecord::Migration[8.1]
  def change
    create_table :folders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :family, foreign_key: true
      # Self-referencing tree; deleting a parent cascades in the model, not here,
      # so the storage accounting can be updated as children go.
      t.references :parent, foreign_key: { to_table: :folders }
      t.string :name, null: false
      t.datetime :trashed_at

      t.timestamps
    end

    # Two folders with the same name cannot live in the same place.
    add_index :folders, [ :user_id, :parent_id, :name ], unique: true,
              where: "trashed_at IS NULL",
              name: "index_folders_unique_name_per_parent"
  end
end
