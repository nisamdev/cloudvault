class CreateLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :labels do |t|
      # Creator. Kept even for family labels so we know who introduced it.
      t.references :user, null: false, foreign_key: true
      # Family labels are a shared vocabulary; personal labels have no family.
      t.references :family, foreign_key: true

      t.string :name, null: false
      t.string :color, null: false, default: "#6366F1"

      t.timestamps
    end

    # A name is unique within its scope — per family, or per user when personal.
    add_index :labels, [ :family_id, :name ], unique: true, where: "family_id IS NOT NULL"
    add_index :labels, [ :user_id, :name ], unique: true, where: "family_id IS NULL"
  end
end
