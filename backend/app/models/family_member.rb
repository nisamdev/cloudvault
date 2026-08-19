# frozen_string_literal: true

class FamilyMember < ApplicationRecord
  ROLES = %w[owner admin editor viewer].freeze
  # Roles that may upload, rename and delete files.
  EDITOR_ROLES = %w[owner admin editor].freeze
  # Roles that may invite or remove members.
  ADMIN_ROLES = %w[owner admin].freeze

  belongs_to :family
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :family_id }
  validate :single_owner_per_family

  scope :editors, -> { where(role: EDITOR_ROLES) }
  scope :admins, -> { where(role: ADMIN_ROLES) }

  def can_edit? = EDITOR_ROLES.include?(role)
  def can_share? = EDITOR_ROLES.include?(role)
  def can_manage_family? = ADMIN_ROLES.include?(role)
  def owner? = role == "owner"

  private

  def single_owner_per_family
    return unless role == "owner"

    existing = FamilyMember.where(family_id: family_id, role: "owner")
    existing = existing.where.not(id: id) if persisted?
    return unless existing.exists?

    errors.add(:role, "is already held by another member")
  end
end
