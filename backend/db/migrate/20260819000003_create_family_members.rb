class CreateFamilyMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :family_members do |t|
      t.references :family, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "viewer"
      t.datetime :joined_at

      t.timestamps
    end

    # One membership per user per family.
    add_index :family_members, [ :family_id, :user_id ], unique: true
    add_check_constraint :family_members,
      "role IN ('owner', 'admin', 'editor', 'viewer')",
      name: "family_members_role_check"
  end
end
