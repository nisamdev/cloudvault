# frozen_string_literal: true

# Single source of truth for "may this user do that to this file?".
#
# Controllers must never re-implement these rules, and the frontend's role
# helpers are only for hiding buttons — every request is checked here.
#
# Access comes from exactly three places, checked in this order:
#
#   1. Ownership          — the person who uploaded it can do anything to it
#   2. A grant            — this file, or a folder above it, shared with them
#                           directly or with a family they are in
#   3. The file's family  — it lives in a family and they are a member of it,
#                           capped by their role there
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
      return false unless file.visibility == "family"

      member_with_role?(user, file.family_id, FamilyMember::ADMIN_ROLES)
    end

    # Handing access to somebody else is not something a guest may do, however
    # much they can edit: it would let shared access spread without the owner.
    def can_share?(user, file)
      return false if file.nil?
      return true if owner?(user, file)
      return false unless file.visibility == "family"

      member_with_role?(user, file.family_id, FamilyMember::EDITOR_ROLES)
    end

    # The strongest role this user has on this file, or nil for no access.
    def access(user, file)
      return nil if file.nil? || user.nil?
      return :owner if owner?(user, file)

      from_grant = granted_role(user, file)
      return from_grant if from_grant == :editor

      from_family = family_role(user, file)
      # Whichever is stronger, since neither one is more specific than nothing.
      [ from_grant, from_family ].compact.max_by { |role| role == :editor ? 1 : 0 }
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

    private

    def owner?(user, file)
      user.present? && file.user_id == user.id
    end

    # A grant on the file itself, or on any folder above it. The nearest one
    # wins, which is what makes "everything in here is read-only, except this"
    # expressible.
    def granted_role(user, file)
      direct = best_role(AccessGrant.for_subjects(user).where(resource: file))
      return direct if direct

      granted_on_folder(user, file.folder)
    end

    def granted_on_folder(user, folder)
      return nil if folder.nil?

      # Nearest first: the folder itself, then up the tree.
      chain = [ folder ] + folder.ancestors.reverse
      chain.each do |candidate|
        role = best_role(AccessGrant.for_subjects(user).where(resource: candidate))
        return role if role
      end

      nil
    end

    # A person named directly outranks a family they happen to be in.
    def best_role(scope)
      grants = scope.to_a
      return nil if grants.empty?

      direct = grants.select { |grant| grant.subject_type == "User" }
      chosen = direct.presence || grants

      chosen.any?(&:editor?) ? :editor : :viewer
    end

    def family_role(user, file)
      return nil unless file.visibility.in?(%w[family shared_link])
      return nil unless family_member?(user, file.family_id)

      member_with_role?(user, file.family_id, FamilyMember::EDITOR_ROLES) ? :editor : :viewer
    end

    def family_member?(user, family_id)
      return false if user.nil? || family_id.nil?

      FamilyMember.exists?(family_id: family_id, user_id: user.id)
    end

    def member_with_role?(user, family_id, roles)
      return false if user.nil? || family_id.nil?

      FamilyMember.exists?(family_id: family_id, user_id: user.id, role: roles)
    end
  end
end
