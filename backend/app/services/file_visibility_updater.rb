# frozen_string_literal: true

# Moves a file between "only me" and "shared with my family" after upload.
#
# This is not a plain attribute write. Sharing with a family *is* an AccessGrant
# naming that family — that grant is what PermissionChecker reads, and it is the
# only thing that decides who can see the file. StoredFile keeps that grant in
# step with the column, so this service only has to move the file and the
# storage accounting.
#
# `family_id` and the family's storage accounting move with it too, all inside
# one transaction.
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
    # Sharing is the owner's decision about their own file. Family visibility
    # already gives every member the right to *edit* what is there; it does not
    # make somebody else's private file theirs to publish.
    unless owns_it?
      raise Forbidden, "Only whoever uploaded #{file.name} can share it with the family."
    end

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

  # Taking it back out of the family. The owner may do it to their own file,
  # and so may somebody who runs the family — that is how a household removes
  # something it should not be holding. Either way it goes back to whoever put
  # it there; it does not become the remover's.
  def make_private
    unless owns_it? || runs_the_family?
      raise Forbidden, "Only whoever uploaded #{file.name}, or a family admin, can unshare it."
    end

    previous_family_id = file.family_id

    StoredFile.transaction do
      file.update!(visibility: "private", family: nil)
      adjust_family_storage(previous_family_id, -file.size) if previous_family_id
    end
  end

  def owns_it? = file.user_id == user.id

  def runs_the_family?
    file.family_id.present? &&
      PermissionChecker.can_manage_family?(user, Family.find_by(id: file.family_id))
  end

  def adjust_family_storage(family_id, bytes)
    Family.where(id: family_id)
          .update_all("family_storage_used = GREATEST(family_storage_used + #{bytes.to_i}, 0)")
  end
end
