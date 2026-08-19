# frozen_string_literal: true

# A file or image in the vault.
#
# Named StoredFile rather than File: a model called `File` would shadow Ruby's
# built-in File class throughout the app.
#
# The bytes live in object storage via Active Storage, which handles presigned
# URLs and image variants for us, rather than the hand-rolled s3_key column
# sketched in the implementation guide.
class StoredFile < ApplicationRecord
  FILE_TYPES = %w[file image].freeze
  VISIBILITIES = %w[private family shared_link].freeze
  IMAGE_MIME_PREFIX = "image/"

  belongs_to :user
  belongs_to :family, optional: true
  belongs_to :folder, optional: true

  has_many :file_versions, dependent: :destroy
  has_many :shared_links, dependent: :destroy
  has_many :file_labels, dependent: :destroy
  has_many :labels, through: :file_labels

  has_one_attached :attachment
  # Thumbnails for the gallery grid (300x300 per the implementation guide).
  has_one_attached :thumbnail

  validates :name, presence: true, length: { maximum: 255 }
  validates :mime_type, presence: true
  validates :size, numericality: { greater_than_or_equal_to: 0 }
  validates :file_type, inclusion: { in: FILE_TYPES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  # A file shared with the family must actually belong to one.
  validate :family_visibility_requires_family

  scope :active, -> { where(trashed_at: nil) }
  scope :trashed, -> { where.not(trashed_at: nil) }
  scope :files, -> { where(file_type: "file") }
  scope :images, -> { where(file_type: "image") }
  scope :recent, -> { order(created_at: :desc) }

  # Full-text match on the name, plus a trigram-backed substring fallback so
  # partial words ("mortg") and mid-word matches still find things, plus labels.
  scope :search, lambda { |term|
    term = term.to_s.strip
    next all if term.blank?

    tsquery = sanitize_sql_array([ "websearch_to_tsquery('english', ?)", term ])
    like = "%#{term.gsub(/[\\%_]/) { |c| "\\#{c}" }}%"

    where(
      "stored_files.search_vector @@ #{tsquery} OR stored_files.name ILIKE :like OR EXISTS (
         SELECT 1 FROM file_labels fl
         JOIN labels l ON l.id = fl.label_id
         WHERE fl.stored_file_id = stored_files.id AND l.name ILIKE :like
       )",
      like: like
    )
  }

  # --- Gallery filters -------------------------------------------------------

  # Takes fully-resolved times, not dates: "today" depends on the viewer's
  # timezone, and only the controller knows whose gallery this is.
  scope :uploaded_between, lambda { |from, to|
    scope = all
    scope = scope.where(created_at: from..) if from
    scope = scope.where(created_at: ..to) if to
    scope
  }

  scope :by_owner, ->(user_id) { user_id.present? ? where(user_id: user_id) : all }

  scope :with_visibility, lambda { |visibility|
    VISIBILITIES.include?(visibility) ? where(visibility: visibility) : all
  }

  # Dimensions are filled in asynchronously, so anything not yet processed is
  # simply left out rather than guessed at.
  scope :with_orientation, lambda { |orientation|
    case orientation
    when "landscape" then where("image_width > image_height")
    when "portrait" then where("image_height > image_width")
    when "square" then where("image_width = image_height").where.not(image_width: nil)
    else all
    end
  }

  # Capture time when the file carries EXIF, upload time otherwise.
  CAPTURED_AT = Arel.sql("COALESCE(stored_files.taken_at, stored_files.created_at)")

  # Upload date is the default everywhere, because that is what the date filters
  # work on and the two must agree. Capture date is available as an explicit
  # choice rather than a silent override.
  scope :sorted_by, lambda { |key|
    case key
    when "oldest" then order(created_at: :asc)
    when "taken_newest" then order(Arel.sql("#{CAPTURED_AT} DESC"))
    when "taken_oldest" then order(Arel.sql("#{CAPTURED_AT} ASC"))
    when "name" then order(Arel.sql("LOWER(name) ASC"))
    when "largest" then order(size: :desc)
    when "smallest" then order(size: :asc)
    else order(created_at: :desc)
    end
  }

  scope :with_location, -> { where.not(latitude: nil).where.not(longitude: nil) }

  # The date the gallery should file this under.
  def captured_at
    taken_at || created_at
  end

  def location?
    latitude.present? && longitude.present?
  end

  def camera
    [ camera_make, camera_model ].compact_blank.join(" ").presence
  end

  scope :with_labels, lambda { |label_ids|
    ids = Array(label_ids).reject(&:blank?)
    next all if ids.empty?

    # Files carrying ALL of the requested labels, not any.
    joins(:file_labels)
      .where(file_labels: { label_id: ids })
      .group("stored_files.id")
      .having("COUNT(DISTINCT file_labels.label_id) = ?", ids.size)
  }

  def self.file_type_for(mime_type)
    mime_type.to_s.start_with?(IMAGE_MIME_PREFIX) ? "image" : "file"
  end

  def image? = file_type == "image"
  def trashed? = trashed_at.present?

  # Soft delete. Bytes stay in storage until the retention window expires so a
  # restore is possible (PATTERNS.md §Trash).
  def trash!
    update!(trashed_at: Time.current) unless trashed?
  end

  def restore!
    update!(trashed_at: nil) if trashed?
  end

  def purge_after
    return nil unless trashed?

    trashed_at + ENV.fetch("TRASH_RETENTION_DAYS", 30).to_i.days
  end

  private

  def family_visibility_requires_family
    return unless visibility == "family" && family_id.nil?

    errors.add(:visibility, "requires the file to belong to a family")
  end
end
