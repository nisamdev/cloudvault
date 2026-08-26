# frozen_string_literal: true

# The private section: a passphrase-locked place for files and photos.
#
# Nothing here is a secret on its own. The vault key is stored twice, sealed —
# once with a key derived from the passphrase and once with one derived from the
# recovery key — and neither of those derived keys is ever written down. A copy
# of this table is worth nothing without one of the two things only the owner
# has.
class CreatePrivateVaults < ActiveRecord::Migration[8.1]
  def change
    create_table :private_vaults do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      # Raw bytes, base64 in the column. One salt per secret, so the two derived
      # keys cannot be attacked with a single table.
      t.string :passphrase_salt, null: false
      t.string :recovery_salt, null: false

      # The same vault key, sealed two ways.
      t.text :passphrase_sealed_key, null: false
      t.text :recovery_sealed_key, null: false

      # Prompting somebody to write the recovery key down is only fair once.
      t.datetime :recovery_key_shown_at
      t.datetime :unlocked_at

      t.timestamps
    end

    # Locked files are hidden from every listing unless the session has been
    # unlocked, so this is read on nearly every query.
    add_column :stored_files, :locked, :boolean, null: false, default: false
    add_index :stored_files, [ :user_id, :locked ]

    add_column :folders, :locked, :boolean, null: false, default: false
    add_index :folders, [ :user_id, :locked ]

    # The bytes in object storage are ciphertext once this is set; `size` on the
    # row stays the size of the file itself, which is what quotas and the UI
    # mean by it.
    add_column :stored_files, :encrypted, :boolean, null: false, default: false
  end
end
