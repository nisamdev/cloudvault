# frozen_string_literal: true

class Folder < ApplicationRecord
  belongs_to :user
  belongs_to :family, optional: true
  belongs_to :parent, class_name: "Folder", optional: true

  has_many :children, class_name: "Folder", foreign_key: :parent_id,
           inverse_of: :parent, dependent: :destroy
  has_many :stored_files, dependent: :nullify

  validates :name, presence: true, length: { maximum: 255 }
  validate :parent_must_not_be_self_or_descendant
  validate :name_unique_among_siblings

  scope :active, -> { where(trashed_at: nil) }
  scope :roots, -> { where(parent_id: nil) }

  # Breadcrumb trail, root first.
  def ancestors
    chain = []
    node = parent
    # Guard against a cycle that slipped past validation: a corrupted tree must
    # not hang the request.
    while node && chain.size < 50
      chain.unshift(node)
      node = node.parent
    end
    chain
  end

  def path
    (ancestors + [ self ]).map(&:name).join("/")
  end

  private

  # Backed by partial unique indexes, which the database enforces properly for
  # root folders too (see FixFolderNameUniqueness). This turns a collision into
  # a 422 instead of a 500.
  def name_unique_among_siblings
    return if name.blank? || trashed_at.present?

    scope = Folder.active.where(parent_id: parent_id)
    scope = family_id ? scope.where(family_id: family_id) : scope.where(family_id: nil, user_id: user_id)
    scope = scope.where.not(id: id) if persisted?

    errors.add(:name, "is already used here") if scope.exists?([ "LOWER(name) = ?", name.to_s.downcase ])
  end

  def parent_must_not_be_self_or_descendant
    return if parent_id.nil?

    if parent_id == id
      errors.add(:parent_id, "cannot be the folder itself")
      return
    end

    errors.add(:parent_id, "cannot be one of its own subfolders") if descendant_ids.include?(parent_id)
  end

  def descendant_ids
    return [] if new_record?

    ids = []
    queue = children.pluck(:id)
    until queue.empty?
      ids.concat(queue)
      queue = Folder.where(parent_id: queue).pluck(:id)
    end
    ids
  end
end
