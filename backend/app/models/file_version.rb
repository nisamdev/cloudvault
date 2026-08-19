# frozen_string_literal: true

# A previous revision of a StoredFile. Only the most recent N are kept
# (FILE_VERSIONS_KEPT, default 3) — older ones are pruned on upload.
class FileVersion < ApplicationRecord
  belongs_to :stored_file
  belongs_to :created_by, class_name: "User"

  has_one_attached :attachment

  validates :version_number, presence: true,
            uniqueness: { scope: :stored_file_id },
            numericality: { greater_than: 0 }

  scope :newest_first, -> { order(version_number: :desc) }

  def self.versions_kept
    ENV.fetch("FILE_VERSIONS_KEPT", 3).to_i
  end
end
