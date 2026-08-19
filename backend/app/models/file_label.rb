# frozen_string_literal: true

class FileLabel < ApplicationRecord
  belongs_to :stored_file
  belongs_to :label

  validates :label_id, uniqueness: { scope: :stored_file_id }
end
