# frozen_string_literal: true

# The scan that proves a record: the deed, the policy, the permit.
#
# An ordinary StoredFile, so everything that already works on a file — preview,
# versions, the private section, the PDF tools — still works on it here.
class RecordAttachment < ApplicationRecord
  belongs_to :vault_record
  belongs_to :stored_file

  validates :stored_file_id, uniqueness: { scope: :vault_record_id }
end
