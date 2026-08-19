class CreateFamilyInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :family_invitations do |t|
      t.references :family, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.string :email, null: false
      t.string :role, null: false, default: "viewer"

      # Only the digest is stored; the raw token exists solely in the invite email.
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :family_invitations, :token_digest, unique: true
    # One pending invite per email per family; re-inviting replaces the old one.
    add_index :family_invitations, [ :family_id, :email ], unique: true,
              where: "accepted_at IS NULL AND revoked_at IS NULL",
              name: "index_family_invitations_pending"
    add_check_constraint :family_invitations,
      "role IN ('admin', 'editor', 'viewer')",
      name: "family_invitations_role_check"
  end
end
