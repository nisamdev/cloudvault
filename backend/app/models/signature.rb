# frozen_string_literal: true

# A saved signature image, reusable across documents so it is drawn once rather
# than every time something needs signing.
class Signature < ApplicationRecord
  belongs_to :user

  has_one_attached :image

  validates :name, presence: true, length: { maximum: 60 },
            uniqueness: { scope: :user_id, case_sensitive: false }
  validate :image_present

  private

  def image_present
    errors.add(:image, "can't be blank") unless image.attached?
  end
end
