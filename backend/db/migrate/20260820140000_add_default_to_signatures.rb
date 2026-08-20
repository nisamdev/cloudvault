class AddDefaultToSignatures < ActiveRecord::Migration[8.1]
  def change
    # "default" is awkward in SQL, so the column says is_default.
    add_column :signatures, :is_default, :boolean, null: false, default: false

    # At most one default per user, enforced by the database rather than hoping
    # the callback always runs.
    add_index :signatures, :user_id, unique: true,
              where: "is_default = true",
              name: "index_signatures_one_default_per_user"
  end
end
