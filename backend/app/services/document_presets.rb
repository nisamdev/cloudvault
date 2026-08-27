# frozen_string_literal: true

# The kinds of document somebody photographs, and what to do with each.
#
# The person scanning says which one it is. That single choice removes the whole
# problem of working out what a document is from its text — which is the part
# machines are worst at — and leaves only the part they are good at: pulling
# known fields out of a known shape.
class DocumentPresets
  Preset = Struct.new(:key, :label, :hint, :icon, :record_type, :extractor, :maps, keyword_init: true) do
    def to_h = { key: key, label: label, hint: hint, icon: icon, record_type: record_type }
  end

  # Extracted keys on the left, template fields on the right. A passport and a
  # driving licence both describe a person, so both fill a Person record — which
  # is why that template already holds both sets of numbers.
  ALL = [
    Preset.new(
      key: "passport", label: "Passport", icon: "fa-passport",
      hint: "Photograph the page with your photo and the two lines of <<< at the bottom",
      record_type: "person", extractor: DocumentExtractors::Mrz,
      maps: {
        "full_name" => "full_name",
        "date_of_birth" => "date_of_birth",
        "document_number" => "passport_number",
        "expires_on" => "passport_expires_on"
      }
    ),

    Preset.new(
      key: "residence_permit", label: "Visa or residence permit", icon: "fa-id-card",
      hint: "Photograph the side with the three lines of <<< at the bottom",
      record_type: "immigration", extractor: DocumentExtractors::Mrz,
      maps: {
        "document_number" => "document_number",
        "expires_on" => "expires_on",
        "country" => "country",
        "full_name" => "holder"
      }
    ),

    Preset.new(
      key: "driving_licence", label: "Driving licence", icon: "fa-car",
      hint: "Photograph the front of the card, with the numbered lines",
      record_type: "person", extractor: DocumentExtractors::DrivingLicence,
      maps: {
        "licence_number" => "licence_number",
        "expires_on" => "licence_expires_on",
        "date_of_birth" => "date_of_birth"
      }
    ),

    Preset.new(
      key: "health_card", label: "Health card", icon: "fa-kit-medical",
      hint: "Photograph the side with the number on it",
      record_type: "person", extractor: DocumentExtractors::HealthCard,
      maps: {
        "nhs_number" => "nhs_number",
        "full_name" => "full_name",
        "date_of_birth" => "date_of_birth"
      }
    ),

    Preset.new(
      key: "birth_certificate", label: "Birth certificate", icon: "fa-certificate",
      hint: "Photograph the whole certificate, flat and square on",
      record_type: "person", extractor: nil,
      maps: { "name" => "full_name", "date of birth" => "date_of_birth", "born" => "date_of_birth" }
    ),

    Preset.new(
      key: "other", label: "Something else", icon: "fa-file-lines",
      hint: "Anything with writing on it — the details it finds go in a record you choose",
      record_type: nil, extractor: nil, maps: {}
    )
  ].freeze

  BY_KEY = ALL.index_by(&:key).freeze

  def self.[](key) = BY_KEY[key.to_s]
  def self.exists?(key) = BY_KEY.key?(key.to_s)
end
