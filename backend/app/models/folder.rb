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

  KINDS = %w[file photo].freeze

  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(trashed_at: nil) }
  scope :roots, -> { where(parent_id: nil) }
  # Which cabinet this belongs to. An album has no business in the tree that
  # holds the mortgage.
  scope :of_kind, ->(kind) { where(kind: KINDS.include?(kind.to_s) ? kind.to_s : "file") }

  # Where loose photographs live until somebody files them somewhere better.
  # Made when it is first needed rather than at sign-up, so an account that
  # never opens the gallery never grows one.
  # Deliberately personal, whatever family the person is in. Given a family it
  # would be scoped to one, and folder names are unique within a family — so
  # the second person in a household to open the gallery could not have an
  # album called "All photos", and got a validation error instead of a
  # gallery. Sharing an album is a grant, not a shelf everybody stands on.
  def self.default_for(user, kind: "photo", family: nil)
    existing = active.of_kind(kind).find_by(user_id: user.id, is_default: true)
    return existing if existing

    folder = create!(user: user, family: nil, kind: kind, is_default: true,
                     name: kind == "photo" ? "All photos" : "All files")
    adopt_loose_photos(user, folder) if kind == "photo"
    folder
  end

  # Everything already in the gallery predates having anywhere to put it, so
  # the first album takes them in. Only once, when it is made.
  def self.adopt_loose_photos(user, folder)
    StoredFile.images.active
              .where(user_id: user.id, folder_id: nil)
              .update_all(folder_id: folder.id, updated_at: Time.current)
  end

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

  # Every folder beneath this one. Public because sharing a folder has to
  # reach what is inside it (see GrantedResources).
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
end
