# frozen_string_literal: true

# Whether a person decided where this file belongs.
#
# file_type is normally derived from the mime type, which puts every JPEG in the
# photo gallery — including the ones that are photographs *of documents*. A
# scanned certificate is a document to its owner however it was captured, so
# they can move it, and this records that the choice was theirs so a later
# re-upload does not quietly undo it.
class AddFileTypePinnedToStoredFiles < ActiveRecord::Migration[8.1]
  def change
    add_column :stored_files, :file_type_pinned, :boolean, null: false, default: false
  end
end
