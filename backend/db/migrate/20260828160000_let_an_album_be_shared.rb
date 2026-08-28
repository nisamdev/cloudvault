# frozen_string_literal: true

# A link can now point at an album, as well as at one file or one record.
#
# Sharing a photograph at a time is not how anybody shares a holiday. The
# grant machinery already carries a folder's access down to the files inside
# it — `PermissionChecker` reads it and the listing query honours it — so the
# family half of this needs no new idea, only a way to ask for it. The public
# half needs a link that knows about albums.
class LetAnAlbumBeShared < ActiveRecord::Migration[8.1]
  def change
    add_reference :shared_links, :folder, foreign_key: true, null: true
    add_index :shared_links, [ :folder_id, :revoked_at ]

    # A link points at exactly one thing. Two, or none, is a link nobody can
    # follow — and there are three kinds of thing now, so the old either/or
    # cannot express it.
    remove_check_constraint :shared_links,
                            "(stored_file_id IS NULL) <> (vault_record_id IS NULL)",
                            name: "shared_links_one_subject"
    add_check_constraint :shared_links,
                         "num_nonnulls(stored_file_id, vault_record_id, folder_id) = 1",
                         name: "shared_links_one_subject"
  end
end
