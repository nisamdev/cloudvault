# frozen_string_literal: true

# One person or one family, given access to one file or folder.
#
# This is what makes "send my accountant this folder, read only" possible
# without founding a family to hold them. A grant on a folder reaches
# everything inside it, so the common case is one row, not one per file.
class AccessGrant < ApplicationRecord
  ROLES = %w[viewer editor].freeze

  belongs_to :resource, polymorphic: true
  belongs_to :subject, polymorphic: true
  belongs_to :granted_by, class_name: "User"

  validates :role, inclusion: { in: ROLES }
  validates :resource_type, inclusion: { in: %w[StoredFile Folder] }
  validates :subject_type, inclusion: { in: %w[User Family] }

  scope :live, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }

  def self.for_subjects(user)
    # A family grant reaches every member, so both identities are looked up at
    # once — one query instead of one per family.
    live.where(subject: user).or(live.where(subject_type: "Family", subject_id: user.family_ids))
  end

  def editor? = role == "editor"
  def expired? = expires_at.present? && expires_at.past?
end
