class CreateSignatures < ActiveRecord::Migration[8.1]
  def change
    create_table :signatures do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      # Drawn on a canvas or uploaded; the image itself is an Active Storage
      # attachment so it lives with everything else in object storage.
      t.timestamps
    end

    add_index :signatures, [ :user_id, :name ], unique: true
  end
end
