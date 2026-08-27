# frozen_string_literal: true

# Who may see or change a household record.
#
# Records are simpler than files for now: ownership, family visibility, and
# role in that family. Grants on individual records arrive with short-term
# sharing in a later step.
class RecordPermissions
  EDIT = %i[owner editor].freeze

  class << self
    def can_view?(user, record)
      access(user, record).present?
    end

    def can_edit?(user, record)
      EDIT.include?(access(user, record))
    end

    def can_delete?(user, record)
      return false if record.nil?
      return true if owner?(user, record)

      member_with_role?(user, record.family_id, FamilyMember::ADMIN_ROLES)
    end

    def access(user, record)
      return nil if record.nil? || user.nil?
      return :owner if owner?(user, record)

      if record.visibility == "family" && family_member?(user, record.family_id)
        return :editor if member_with_role?(user, record.family_id, FamilyMember::EDITOR_ROLES)

        :viewer
      end
    end

    private

    def owner?(user, record)
      user.present? && record.user_id == user.id
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
