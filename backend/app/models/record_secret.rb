# frozen_string_literal: true

# One encrypted value on a record — a password, a security answer.
#
# Plaintext never touches the database. Listing endpoints return only whether a
# key is set, not what it holds.
class RecordSecret < ApplicationRecord
  belongs_to :vault_record
  has_many :secret_versions, dependent: :destroy

  validates :key, presence: true, uniqueness: { scope: :vault_record_id }
  validates :sealed, presence: true
  validates :kdf, presence: true

  scope :ordered, -> { order(:key) }
end
