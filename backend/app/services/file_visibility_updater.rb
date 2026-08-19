# frozen_string_literal: true

# Moves a file between "only me" and "shared with my family" after upload.
#
# This is not a plain attribute write. Visibility is tied to `family_id` (a
# family-visible file must belong to a family) and to the family's storage
# accounting, so both have to move with it — inside one transaction.
class FileVisibilityUpdater
  class Error < StandardError; end
  class Forbidden < Error; end
  class QuotaExceeded < Error; end

  def initialize(file:, user:)
    @file = file
    @user = user
  end

  def call(visibility)
    raise Error, "Unknown visibility" unless StoredFile::VISIBILITIES.include?(visibility)
    return file if file.visibility == visibility

    case visibility
    when "family" then share_with_family
    when "private" then make_private
    else
      raise Error, "Visibility '#{visibility}' cannot be set directly"
    end

    file
  end

  private

  attr_reader :file, :user

  def share_with_family
    membership = user.primary_membership
    raise Forbidden, "You don't belong to a family yet." if membership.nil?

    family = membership.family
    unless PermissionChecker.can_upload_to_family?(user, family)
      raise Forbidden, "You don't have permission to share files with your family."
    end

    # The bytes start counting against the family's quota once they are shared.
    if family.storage_remaining < file.size
      raise QuotaExceeded, "Your family doesn't have enough storage space left."
    end

    StoredFile.transaction do
      file.update!(family: family, visibility: "family")
      adjust_family_storage(family.id, file.size)
    end
  end

  def make_private
    previous_family_id = file.family_id

    StoredFile.transaction do
      file.update!(visibility: "private", family: nil)
      adjust_family_storage(previous_family_id, -file.size) if previous_family_id
    end
  end

  def adjust_family_storage(family_id, bytes)
    Family.where(id: family_id)
          .update_all("family_storage_used = GREATEST(family_storage_used + #{bytes.to_i}, 0)")
  end
end
