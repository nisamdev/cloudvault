# frozen_string_literal: true

# A share link used to be a link to one file. A household record is the other
# thing worth handing to somebody outside the family — the passport's details
# and the passport's scan travel together, and sending the PDF alone leaves
# them reading a number off a photograph.
class ShareARecordAsWellAsAFile < ActiveRecord::Migration[8.1]
  def change
    add_reference :shared_links, :vault_record, foreign_key: true, null: true
    change_column_null :shared_links, :stored_file_id, true

    add_index :shared_links, [ :vault_record_id, :revoked_at ]

    # A link points at one thing. Two, or none, is a link nobody can follow.
    add_check_constraint :shared_links,
                         "(stored_file_id IS NULL) <> (vault_record_id IS NULL)",
                         name: "shared_links_one_subject"
  end
end
