# frozen_string_literal: true

# One record's knowledge of another: the house is insured by this policy, the
# electricity is billed to that account.
#
# The relation is a plain word rather than an id into a table of relation types,
# because the whole value of it is that a record page can read as a sentence.
class RecordLink < ApplicationRecord
  RELATIONS = %w[
    related_to owned_by lives_at insured_by billed_to mortgaged_with
    issued_by held_by covers replaces
  ].freeze

  belongs_to :vault_record
  belongs_to :linked_record, class_name: "VaultRecord"

  validates :relation, inclusion: { in: RELATIONS }
  validates :linked_record_id, uniqueness: { scope: :vault_record_id }
  validate :not_itself

  private

  def not_itself
    return unless vault_record_id.present? && vault_record_id == linked_record_id

    errors.add(:linked_record_id, "cannot be the record itself")
  end
end
