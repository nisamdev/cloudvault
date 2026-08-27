# frozen_string_literal: true

# Reads a scanned document and offers what it found, for a person to check.
#
# It never saves anything. Everything here is a suggestion on a form that
# somebody confirms — the point is to save the typing, not to decide what is
# true about somebody's passport.
class DocumentReader
  Result = Struct.new(:preset, :record_type, :fields, :verified, :format, :text, keyword_init: true) do
    def to_h
      {
        preset: preset.key,
        record_type: record_type,
        title: title,
        fields: fields,
        # Which of these the document itself confirms, by check digit or by two
        # parts of it agreeing. The screen marks these differently: a value the
        # document vouches for deserves less squinting than one that was guessed.
        verified: verified,
        read_as: format
      }
    end

    # A document is named for whose it is and what it is. Four of somebody's
    # documents all called their name would be four rows you have to open.
    def title
      name = fields["full_name"] || fields["holder"] || fields["title"]
      return name if name.blank? || preset.record_type.nil?

      "#{name} — #{preset.label}"
    end
  end

  def initialize(text, preset_key)
    @text = text.to_s
    @preset = DocumentPresets[preset_key] || DocumentPresets["other"]
  end

  def call
    extracted = run_extractor
    mapped = map_fields(extracted[:fields])

    Result.new(
      preset: @preset,
      record_type: @preset.record_type,
      fields: mapped,
      verified: extracted[:verified].filter_map { |key| @preset.maps[key] },
      format: extracted[:format],
      text: @text
    )
  end

  private

  # A preset with a parser of its own uses it; everything else falls back to the
  # labelled-field reader that already serves "Read a document".
  def run_extractor
    if @preset.extractor
      found = @preset.extractor.parse(@text)
      return found if found
    end

    { fields: labelled_fields, verified: [], format: nil }
  end

  # KeyDetails finds "Label: value" pairs; this turns the labels it found into
  # the keys a preset knows how to place.
  def labelled_fields
    details = KeyDetails.new([ { number: 1, text: @text } ]).call

    details[:details].each_with_object({}) do |detail, found|
      key = detail[:label].to_s.downcase.strip
      found[key] ||= detail[:value]
    end
  end

  def map_fields(extracted)
    return {} if extracted.blank?

    @preset.maps.each_with_object({}) do |(from, to), mapped|
      value = extracted[from]
      mapped[to] = value if value.present?
    end
  end
end
