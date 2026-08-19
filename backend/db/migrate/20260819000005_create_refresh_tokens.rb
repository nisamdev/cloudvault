class CreateRefreshTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :refresh_tokens do |t|
      t.references :user, null: false, foreign_key: true

      # Digest only: a database leak must not yield usable session tokens.
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at

      # Rotation chain — lets us detect replay of an already-used token.
      t.references :replaced_by, foreign_key: { to_table: :refresh_tokens }

      # Shown on the "Active sessions" screen in Settings.
      t.string :user_agent
      t.string :ip_address
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :refresh_tokens, :token_digest, unique: true
    add_index :refresh_tokens, [ :user_id, :revoked_at ]
  end
end
