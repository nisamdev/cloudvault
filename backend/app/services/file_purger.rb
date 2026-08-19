# frozen_string_literal: true

# Deletes a file for good: its versions, its blobs and its share links, and
# gives the storage back to whoever it was charged to.
#
# Storage accounting is the reason this is a service rather than `destroy` —
# the counters are maintained incrementally, so they have to be adjusted in the
# same transaction that removes the rows.
class FilePurger
  def initialize(stored_file)
    @file = stored_file
  end

  def call
    user_id = @file.user_id
    family_id = @file.family_id
    # Versions occupy storage too, and they go with the file.
    bytes = @file.size.to_i + @file.file_versions.sum(:size).to_i

    StoredFile.transaction do
      @file.destroy!
      release(user_id, family_id, bytes)
    end
  end

  private

  def release(user_id, family_id, bytes)
    User.where(id: user_id)
        .update_all("storage_used = GREATEST(storage_used - #{bytes.to_i}, 0)")

    return if family_id.nil?

    Family.where(id: family_id)
          .update_all("family_storage_used = GREATEST(family_storage_used - #{bytes.to_i}, 0)")
  end
end
