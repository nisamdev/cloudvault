# frozen_string_literal: true

# A saved signature image, reusable across documents so it is drawn once rather
# than every time something needs signing.
class Signature < ApplicationRecord
  belongs_to :user

  has_one_attached :image

  validates :name, presence: true, length: { maximum: 60 },
            uniqueness: { scope: :user_id, case_sensitive: false }
  validate :image_present

  scope :default_first, -> { order(is_default: :desc, name: :asc) }

  # The first signature a user saves becomes their default, so the picker always
  # has something preselected.
  after_create :become_default_if_only_one
  after_destroy :promote_another_default

  def make_default!
    Signature.transaction do
      # The partial unique index would reject two defaults; clear the old one
      # inside the same transaction.
      user.signatures.where.not(id: id).update_all(is_default: false)
      update!(is_default: true)
    end
  end

  private

  def become_default_if_only_one
    update_column(:is_default, true) if user.signatures.count == 1
  end

  # Deleting the default would otherwise leave a user with none set.
  def promote_another_default
    return unless is_default?

    user.signatures.order(:created_at).first&.update_column(:is_default, true)
  end

  def image_present
    errors.add(:image, "can't be blank") unless image.attached?
  end
end
