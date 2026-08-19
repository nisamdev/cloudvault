class CreateFamilies < ActiveRecord::Migration[8.1]
  def change
    create_table :families do |t|
      t.string :name, null: false
      t.text :description
      t.references :owner, null: false, foreign_key: { to_table: :users }

      t.bigint :family_storage_quota, null: false, default: 2_147_483_648  # 2 GB
      t.bigint :family_storage_used, null: false, default: 0

      t.timestamps
    end
  end
end
