# frozen_string_literal: true

# The kinds of document somebody photographs, and what to do with each.
#
# The person scanning says which one it is. That single choice removes the whole
# problem of working out what a document is from its text — which is the part
# machines are worst at — and leaves only the part they are good at: pulling
# known fields out of a known shape.
class DocumentPresets
  # A document can have more than one reader: a driving licence is a different
  # document in every country, and the only way to tell is to try.
  Preset = Struct.new(:key, :label, :hint, :icon, :record_type, :extractors, :maps,
                      keyword_init: true) do
    def to_h = { key: key, label: label, hint: hint, icon: icon, record_type: record_type }
  end

  # Extracted keys on the left, template fields on the right. A passport and a
  # driving licence both describe a person, so both fill a Person record — which
  # is why that template already holds both sets of numbers.
  ALL = [
    Preset.new(
      key: "passport", label: "Passport", icon: "fa-passport",
      hint: "Photograph the page with your photo and the two lines of <<< at the bottom",
      record_type: "passport", extractors: [ DocumentExtractors::Mrz ],
      maps: {
        "full_name" => "full_name",
        "date_of_birth" => "date_of_birth",
        "document_number" => "passport_number",
        "expires_on" => "expires_on",
        "country" => "nationality",
        "sex" => "sex"
      }
    ),

    Preset.new(
      key: "residence_permit", label: "Visa or residence permit", icon: "fa-id-card",
      hint: "Photograph the side with the three lines of <<< at the bottom",
      record_type: "immigration", extractors: [ DocumentExtractors::Mrz ],
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
      record_type: "driving_licence",
      extractors: [ DocumentExtractors::DrivingLicence, DocumentExtractors::CanadianLicence ],
      maps: {
        "full_name" => "full_name",
        "licence_number" => "licence_number",
        "date_of_birth" => "date_of_birth",
        "issued_on" => "issued_on",
        "expires_on" => "expires_on",
        "address" => "address",
        "categories" => "categories",
        "authority" => "authority"
      }
    ),

    Preset.new(
      key: "health_card", label: "Health card", icon: "fa-kit-medical",
      hint: "Photograph the side with the number on it",
      record_type: "health_card", extractors: [ DocumentExtractors::HealthCard ],
      maps: {
        "nhs_number" => "nhs_number",
        "full_name" => "full_name",
        "date_of_birth" => "date_of_birth"
      }
    ),

    Preset.new(
      key: "birth_certificate", label: "Birth certificate", icon: "fa-certificate",
      hint: "Photograph the whole certificate, flat and square on",
      record_type: "birth_certificate", extractors: [],
      maps: {
        "name" => "full_name",
        "date of birth" => "date_of_birth",
        "born" => "date_of_birth",
        "place of birth" => "place_of_birth",
        "district" => "district",
        "mother" => "mother",
        "father" => "father"
      }
    ),

    Preset.new(
      key: "other", label: "Something else", icon: "fa-file-lines",
      hint: "Anything with writing on it — it becomes a document you can name",
      record_type: "document", extractors: [],
      maps: {
        "name" => "full_name",
        "number" => "document_number",
        "reference" => "document_number",
        "issued" => "issued_on",
        "expires" => "expires_on",
        "expiry" => "expires_on",
        "issued by" => "authority"
      }
    )
  ].freeze

  BY_KEY = ALL.index_by(&:key).freeze

  def self.[](key) = BY_KEY[key.to_s]
  def self.exists?(key) = BY_KEY.key?(key.to_s)
end
