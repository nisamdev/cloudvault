# frozen_string_literal: true

# A colour-coded tag applied to files.
#
# Scope: a label created by someone in a family belongs to the family, so the
# whole household shares one vocabulary. Users without a family get personal
# labels instead.
class Label < ApplicationRecord
  belongs_to :user
  belongs_to :family, optional: true

  has_many :file_labels, dependent: :destroy
  has_many :stored_files, through: :file_labels

  # Matches the palette in DESIGN_TOKENS.md.
  COLORS = %w[#4F46E5 #9333EA #EC4899 #10B981 #F59E0B #EF4444 #3B82F6 #6B7280].freeze

  validates :name, presence: true, length: { maximum: 40 }
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "must be a hex colour" }
  validate :name_unique_in_scope

  normalizes :name, with: ->(name) { name.to_s.strip.squeeze(" ") }

  scope :for_user, lambda { |user|
    family_id = user.primary_membership&.family_id
    if family_id
      where(family_id: family_id).or(where(family_id: nil, user_id: user.id))
    else
      where(family_id: nil, user_id: user.id)
    end
  }

  def personal? = family_id.nil?

  private

  # Enforced in the database by two partial unique indexes; this turns the
  # collision into a validation error instead of a 500.
  def name_unique_in_scope
    return if name.blank?

    scope = family_id ? Label.where(family_id: family_id) : Label.where(family_id: nil, user_id: user_id)
    scope = scope.where.not(id: id) if persisted?

    errors.add(:name, "is already in use") if scope.exists?([ "LOWER(name) = ?", name.downcase ])
  end
end
