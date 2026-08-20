class NullifyCurrentFamilyOnDelete < ActiveRecord::Migration[8.1]
  # users.current_family_id only records which family the app is showing. When
  # a family goes away — an owner deletes it, or accepting an invitation
  # discards the empty one somebody was made to create — that pointer should
  # fall back to nothing, not block the delete.
  def up
    remove_foreign_key :users, column: :current_family_id
    add_foreign_key :users, :families, column: :current_family_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :users, column: :current_family_id
    add_foreign_key :users, :families, column: :current_family_id
  end
end
