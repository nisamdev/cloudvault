class CreateAccessGrantsAndCurrentFamily < ActiveRecord::Migration[8.1]
  def change
    # Sharing one thing with one person, without inventing a family to hold
    # them. The subject is a user or a family; the resource is a file or a
    # folder, and a grant on a folder reaches everything inside it.
    create_table :access_grants do |t|
      t.references :resource, polymorphic: true, null: false
      t.references :subject, polymorphic: true, null: false
      t.string :role, null: false, default: "viewer"
      t.references :granted_by, null: false, foreign_key: { to_table: :users }
      t.datetime :expires_at

      t.timestamps
    end

    # One grant per subject per resource: re-sharing changes the role rather
    # than stacking a second row nobody can see.
    add_index :access_grants,
              %i[resource_type resource_id subject_type subject_id],
              unique: true,
              name: "index_access_grants_on_resource_and_subject"

    # Which family the app is showing right now. A user may belong to several,
    # and uploads have to land somewhere predictable.
    add_reference :users, :current_family, foreign_key: { to_table: :families }, null: true
  end
end
