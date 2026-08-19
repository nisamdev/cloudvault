class CreateFileLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :file_labels do |t|
      t.references :stored_file, null: false, foreign_key: true
      t.references :label, null: false, foreign_key: true

      t.timestamps
    end

    add_index :file_labels, [ :stored_file_id, :label_id ], unique: true
  end
end
