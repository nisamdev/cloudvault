# frozen_string_literal: true

# Single source of truth for "may this user do that to this file?".
#
# Controllers must never re-implement these rules, and the frontend's role
# helpers are only for hiding buttons — every request is checked here.
#
# Visibility model (QUICK_REFERENCE.md):
#   private      — only the owner
#   family       — every member of the file's family, subject to their role
#   shared_link  — anyone holding a valid link (checked separately by token)
class PermissionChecker
  class << self
    def can_view?(user, file)
      return false if file.nil?
      return true if owner?(user, file)

      case file.visibility
      when "family"
        family_member?(user, file.family_id)
      when "shared_link"
        # Link holders are authorised by the token itself, not by identity.
        # A signed-in non-member gets no implicit access here.
        family_member?(user, file.family_id)
      else
        false
      end
    end

    def can_edit?(user, file)
      return false if file.nil?
      return true if owner?(user, file)
      return false unless file.visibility == "family"

      member_with_role?(user, file.family_id, FamilyMember::EDITOR_ROLES)
    end

    # Deleting is deliberately stricter than editing: only the owner or a family
    # admin can trash someone else's upload.
    def can_delete?(user, file)
      return false if file.nil?
      return true if owner?(user, file)
      return false unless file.visibility == "family"

      member_with_role?(user, file.family_id, FamilyMember::ADMIN_ROLES)
    end

    def can_share?(user, file)
      return false if file.nil?
      return true if owner?(user, file)
      return false unless file.visibility == "family"

      member_with_role?(user, file.family_id, FamilyMember::EDITOR_ROLES)
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
