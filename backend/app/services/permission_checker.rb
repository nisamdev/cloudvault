# frozen_string_literal: true

# Single source of truth for "may this user do that to this file?".
#
# Controllers must never re-implement these rules, and the frontend's role
# helpers are only for hiding buttons — every request is checked here.
#
# Access comes from exactly two places:
#
#   1. Ownership — the person who uploaded it can do anything to it
#   2. A grant   — this file, or a folder above it, shared with them by name or
#                  with a family they belong to
#
# Sharing a file with your family *is* a grant naming that family, so there is
# one mechanism rather than a `visibility` column and an ACL disagreeing about
# who can see what. What a member can do with something shared into a family is
# still capped by their role there: a family viewer stays a viewer.
#
# Between two grants the most specific wins: one naming the person beats one
# naming a family they belong to, which is the rule people already expect from
# Drive. Between a grant and plain family membership the stronger wins instead —
# being handed a read-only link to a file you can already edit as a member of
# its family should not quietly demote you.
class PermissionChecker
  # Ownership is the strongest role, not a separate track.
  EDIT = %i[owner editor].freeze

  class << self
    def can_view?(user, file)
      access(user, file).present?
    end

    def can_edit?(user, file)
      EDIT.include?(access(user, file))
    end

    # Deleting is deliberately stricter than editing: someone with edit access
    # to a shared folder should not be able to destroy another person's
    # passport. Only the owner, or an admin of the family the file lives in.
    def can_delete?(user, file)
      return false if file.nil?
      return true if owner?(user, file)

      # Standing in the family the file lives in, not a grant: a grant never
      # carries destruction.
      member_with_role?(user, file.family_id, FamilyMember::ADMIN_ROLES)
    end

    # Handing access to somebody else is not something a guest may do, however
    # much they can edit: it would let shared access spread without the owner.
    def can_share?(user, file)
      return false if file.nil?
      return true if owner?(user, file)

      member_with_role?(user, file.family_id, FamilyMember::EDITOR_ROLES)
    end

    # The strongest role this user has on this file, or nil for no access.
    def access(user, file)
      return nil if file.nil? || user.nil?
      return :owner if owner?(user, file)

      granted_role(user, file)
    end

    def can_view_folder?(user, folder)
      return false if folder.nil? || user.nil?
      return true if folder.user_id == user.id
      return true if granted_on_folder(user, folder).present?

      family_member?(user, folder.family_id)
    end

    # --- Family-level checks -------------------------------------------------

    def can_manage_family?(user, family)
      return false if family.nil?

      member_with_role?(user, family.id, FamilyMember::ADMIN_ROLES)
    end

    def can_upload_to_family?(user, family)
      return false if family.nil?

      member_with_role?(user, family.id, FamilyMember::EDITOR_ROLES)
    end

    # Whether the family's shared half is open to this person at all. Every
    # family-shaped answer above is gated on it.
    def uses_vault?(user, family_id)
      return false if user.nil? || family_id.nil?

      FamilyMember.find_by(family_id: family_id, user_id: user.id)&.can_use_vault? || false
    end

    private

    def owner?(user, file)
      user.present? && file.user_id == user.id
    end

    # A grant on the file itself, or on any folder above it. The nearest one
    # wins, which is what makes "everything in here is read-only, except this"
    # expressible.
    def granted_role(user, file)
      direct = best_role(user, AccessGrant.for_subjects(user).where(resource: file))
      return direct if direct

      granted_on_folder(user, file.folder)
    end

    def granted_on_folder(user, folder)
      return nil if folder.nil?

      # Nearest first: the folder itself, then up the tree.
      chain = [ folder ] + folder.ancestors.reverse
      chain.each do |candidate|
        role = best_role(user, AccessGrant.for_subjects(user).where(resource: candidate))
        return role if role
      end

      nil
    end

    # A person named directly outranks a family they happen to be in.
    def best_role(user, scope)
      grants = scope.to_a
      return nil if grants.empty?

      direct = grants.select { |grant| grant.subject_type == "User" }
      return direct.any?(&:editor?) ? :editor : :viewer if direct.any?

      roles = grants.filter_map { |grant| family_grant_role(user, grant) }
      return nil if roles.empty?

      roles.include?(:editor) ? :editor : :viewer
    end

    # A grant to a family reaches its members, but never gives them more than
    # their standing in that family allows — sharing a file into the family does
    # not promote its viewers to editors.
    def family_grant_role(user, grant)
      return nil unless family_member?(user, grant.subject_id)

      capped = member_with_role?(user, grant.subject_id, FamilyMember::EDITOR_ROLES)
      grant.editor? && capped ? :editor : :viewer
    end

    # Being in the family is not the same as the family's things being open to
    # you: the owner can shut somebody out without removing them.
    def family_member?(user, family_id)
      return false if user.nil? || family_id.nil?

      uses_vault?(user, family_id)
    end

    def member_with_role?(user, family_id, roles)
      return false if user.nil? || family_id.nil?

      FamilyMember.exists?(family_id: family_id, user_id: user.id, role: roles) &&
        uses_vault?(user, family_id)
    end
  end
end
