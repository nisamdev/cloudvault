# frozen_string_literal: true

# A fact the family keeps: an account, a house, a car, a permit.
#
# Named VaultRecord rather than Record because "record" already means a database
# row to everyone reading this, and StoredFile set the precedent for not
# shadowing a word the framework has taken.
class VaultRecord < ApplicationRecord
  VISIBILITIES = %w[private family].freeze

  belongs_to :user
  belongs_to :family, optional: true
  belongs_to :folder, optional: true

  has_many :record_attachments, dependent: :destroy
  has_many :stored_files, through: :record_attachments

  has_many :record_secrets, dependent: :destroy

  # Links point both ways in the UI but are stored once, so a record has to look
  # in both directions to answer "what is this connected to".
  has_many :record_links, dependent: :destroy
  has_many :linked_records, through: :record_links, source: :linked_record
  has_many :inbound_links, class_name: "RecordLink", foreign_key: :linked_record_id,
                           dependent: :destroy, inverse_of: :linked_record

  has_many :access_grants, as: :resource, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :record_type, inclusion: { in: RecordTemplates::TYPES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validate :family_visibility_requires_family
  validate :data_is_a_flat_object

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :of_type, ->(type) { RecordTemplates.exists?(type) ? where(record_type: type) : all }
  scope :recent, -> { order(updated_at: :desc) }

  # Same two-pronged search as files: the generated tsvector for words, ILIKE on
  # the title for the half-typed case ("mortg").
  scope :search, lambda { |term|
    term = term.to_s.strip
    next all if term.blank?

    tsquery = sanitize_sql_array([ "websearch_to_tsquery('english', ?)", term ])
    like = "%#{term.gsub(/[\\%_]/) { |c| "\\#{c}" }}%"

    where("vault_records.search_vector @@ #{tsquery} OR vault_records.title ILIKE :like", like: like)
  }

  # Records carrying a value in a given field — "everything under this email".
  scope :where_field, lambda { |key, value|
    next all if key.blank? || value.blank?

    where("vault_records.data ->> ? = ?", key.to_s, value.to_s)
  }

  def template = RecordTemplates[record_type]

  def archived? = archived_at.present?

  def archive! = update!(archived_at: Time.current)
  def unarchive! = update!(archived_at: nil)

  # The fields this record actually carries, in template order, with anything
  # its owner added afterwards on the end.
  def fields
    known = template&.fields || []
    extra = data.keys - known.map(&:key)

    known.filter_map { |f| { field: f, value: data[f.key] } if data[f.key].present? } +
      extra.filter_map do |key|
        next if data[key].blank?

        { field: RecordTemplates.field(key, key.humanize), value: data[key], custom: true }
      end
  end

  # Every date this record wants watching, as [field, date]. What the reminder
  # engine will read; harmless until then.
  def expiries
    (template&.expiry_fields || []).filter_map do |field|
      parsed = parse_date(data[field.key])
      [ field, parsed ] if parsed
    end
  end

  private

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue Date::Error
    nil
  end

  def family_visibility_requires_family
    return unless visibility == "family" && family_id.nil?

    errors.add(:visibility, "requires the record to belong to a family")
  end

  # data is a bag of fields, not a document tree. Nesting would defeat both the
  # search vector and every form that has to render it.
  def data_is_a_flat_object
    unless data.is_a?(Hash)
      errors.add(:data, "must be a set of fields")
      return
    end

    return if data.values.none? { |value| value.is_a?(Hash) || value.is_a?(Array) }

    errors.add(:data, "fields hold single values, not lists or nested objects")
  end
end
