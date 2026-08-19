class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest
      t.string :full_name
      t.string :avatar_url

      # Quotas are seeded from env so they can be tuned per deployment.
      t.bigint :storage_quota, null: false, default: 268_435_456   # 256 MB
      t.bigint :storage_used, null: false, default: 0

      t.string :oauth_provider
      t.string :oauth_id

      t.boolean :two_factor_enabled, null: false, default: false
      t.string :two_factor_secret

      t.string :timezone, null: false, default: "UTC"
      t.datetime :last_signed_in_at

      t.timestamps
    end

    # Emails are stored downcased, so a plain unique index is enough.
    add_index :users, :email, unique: true
    # A provider identity maps to exactly one user.
    add_index :users, [ :oauth_provider, :oauth_id ], unique: true,
              where: "oauth_provider IS NOT NULL"
  end
end
