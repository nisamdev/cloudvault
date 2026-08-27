# frozen_string_literal: true

# The previous value of a secret, kept for when a site says it changed and lied.
class SecretVersion < ApplicationRecord
  belongs_to :record_secret

  validates :sealed, presence: true
  validates :replaced_at, presence: true

  scope :recent_first, -> { order(replaced_at: :desc) }
end
