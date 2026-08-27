# frozen_string_literal: true

# What each kind of record starts out knowing about itself.
#
# A template is a starting point, not a schema. Every record can grow fields
# nobody anticipated, because a household thinks of a new thing to write down
# every other week. What a template buys is that adding the electricity account
# does not begin with a blank page.
#
# Field kinds are about *what the value is for*, not what it looks like: an
# `expiry` is a date the reminder engine watches, a `reference` is the number
# nobody can remember and everybody has to copy, a `secret` never comes back in
# a listing. The UI reads the kind to decide the input, the formatting and the
# copy button.
module RecordTemplates
  KINDS = %w[text multiline email url phone date expiry number money reference secret].freeze

  # How far ahead to write about a date, in days.
  #
  # Not every expiry deserves an email. A subscription's next charge comes round
  # every month and mailing about it would be noise you learn to ignore — so it
  # shows a countdown on screen and says nothing. `remind` is what turns a date
  # into a letter, and the gaps say how much notice the thing actually needs.
  DEFAULT_REMINDERS = [ 42, 7 ].freeze
  # Renewing a permit or a passport is months of work, not an afternoon's.
  LONG_REMINDERS = [ 180, 90, 30 ].freeze
  SHORT_REMINDERS = [ 30, 7 ].freeze

  Field = Struct.new(:key, :label, :kind, :hint, :remind, keyword_init: true) do
    def secret? = kind == "secret"
    def expiry? = kind == "expiry"

    # Every expiry counts down on screen; only some of them write to you.
    def reminds? = expiry? && remind.present?

    def to_h = { key: key, label: label, kind: kind, hint: hint, remind: remind }.compact
  end

  Template = Struct.new(:type, :label, :icon, :summary, :fields, :title_hint, :title_from,
                        keyword_init: true) do
    def field(key) = fields.find { |f| f.key == key }
    def expiry_fields = fields.select(&:expiry?)
    def reminding_fields = fields.select(&:reminds?)
    def secret_fields = fields.select(&:secret?)

    def to_h
      {
        type: type, label: label, icon: icon, summary: summary,
        title_hint: title_hint, title_from: title_from, fields: fields.map(&:to_h)
      }
    end
  end

  # An expiry gets the default schedule unless one is named, and `remind: []`
  # means "count it down, but do not write about it".
  def self.field(key, label, kind = "text", hint = nil, remind: :default)
    schedule =
      if kind != "expiry" then nil
      elsif remind == :default then DEFAULT_REMINDERS
      else Array(remind).presence
      end

    Field.new(key: key, label: label, kind: kind, hint: hint, remind: schedule)
  end

  ALL = [
    Template.new(
      type: "login",
      label: "Login",
      icon: "fa-key",
      summary: "A site, a username and a password — named so you can find it.",
      title_hint: "Netflix",
      title_from: "name",
      fields: [
        field("name", "Name", "text", "What you'd search for — Netflix, Gmail, the router…"),
        field("website", "Site URL", "url"),
        field("username", "Username", "text", "Email or username for this site"),
        field("password", "Password", "secret")
      ]
    ),

    Template.new(
      type: "service_account",
      label: "Service account",
      icon: "fa-right-to-bracket",
      summary: "Which email, which password, which reference.",
      title_hint: "British Gas — electricity",
      fields: [
        field("provider", "Provider"),
        field("account_email", "Account email", "email", "The address this account is under"),
        field("username", "Username"),
        field("website", "Website", "url"),
        field("customer_ref", "Customer reference", "reference"),
        field("phone", "Their phone number", "phone"),
        field("password", "Password", "secret"),
        field("security_answers", "Security answers", "secret"),
        field("renews_on", "Renews", "expiry"),
        field("notes", "Notes", "multiline")
      ]
    ),

    Template.new(
      type: "passport",
      label: "Passport",
      icon: "fa-passport",
      summary: "The book you cannot travel without, and the date it stops working.",
      title_hint: "Aisha's passport",
      fields: [
        field("full_name", "Full name", "text", "As printed, not as used"),
        field("passport_number", "Passport number", "reference"),
        field("nationality", "Nationality"),
        field("date_of_birth", "Date of birth", "date"),
        field("place_of_birth", "Place of birth"),
        field("sex", "Sex"),
        field("issued_on", "Issued", "date"),
        # Many countries want six months left on a passport before they let you
        # in, so the first reminder comes long before the date itself.
        field("expires_on", "Expires", "expiry", "Reminders start six months out", remind: LONG_REMINDERS),
        field("place_of_issue", "Place of issue"),
        field("authority", "Issuing authority", "text", "HM Passport Office, consulate…"),
        field("notes", "Notes", "multiline")
      ]
    ),

    Template.new(
      type: "driving_licence",
      label: "Driving licence",
      icon: "fa-id-card",
      summary: "The card, its number, and when the photo runs out.",
      title_hint: "Aisha's driving licence",
      fields: [
        field("full_name", "Full name"),
        field("licence_number", "Licence number", "reference"),
        field("date_of_birth", "Date of birth", "date"),
        field("issued_on", "Issued", "date"),
        field("expires_on", "Expires", "expiry", remind: SHORT_REMINDERS),
        field("authority", "Issuing authority", "text", "DVLA, DVA…"),
        field("categories", "Entitlements", "text", "The vehicle categories on the back"),
        field("address", "Address on the card", "multiline"),
        field("notes", "Notes", "multiline")
      ]
    ),

    Template.new(
      type: "birth_certificate",
      label: "Birth certificate",
      icon: "fa-certificate",
      summary: "The document everything else is proved from. It never expires.",
      title_hint: "Aisha's birth certificate",
      fields: [
        field("full_name", "Full name"),
        field("date_of_birth", "Date of birth", "date"),
        field("place_of_birth", "Place of birth"),
        field("registration_number", "Entry or registration number", "reference"),
        field("registered_on", "Registered", "date"),
        field("district", "Registration district"),
        field("mother", "Mother"),
        field("father", "Father"),
        field("notes", "Notes", "multiline")
      ]
    ),

    Template.new(
      type: "health_card",
      label: "Health card",
      icon: "fa-kit-medical",
      summary: "The number a surgery asks for, and the card that carries it.",
      title_hint: "Aisha's NHS number",
      fields: [
        field("full_name", "Full name"),
        field("nhs_number", "NHS or health number", "reference"),
        field("date_of_birth", "Date of birth", "date"),
        field("gp_practice", "GP or clinic"),
        field("blood_group", "Blood group"),
        # An NHS number is for life; a GHIC or an insurance card is not.
        field("expires_on", "Expires", "expiry", "Only some cards run out — a GHIC does", remind: SHORT_REMINDERS),
        field("notes", "Notes", "multiline")
      ]
    ),

    Template.new(
      type: "immigration",
      label: "Immigration",
      icon: "fa-passport",
      summary: "Visas, permits and citizenship — every one carries a date.",
      title_hint: "Skilled Worker visa — UK",
      fields: [
        field("document_kind", "Document", "text", "Visa, residence permit, citizenship…"),
        field("country", "Country"),
        field("document_number", "Document number", "reference"),
        field("holder", "Held by"),
        field("issued_on", "Issued", "date"),
        field("expires_on", "Expires", "expiry", "Reminders start six months out", remind: LONG_REMINDERS),
        field("sponsor", "Sponsor or employer"),
        field("application_ref", "Application reference", "reference"),
        field("conditions", "Conditions", "multiline", "Work restrictions, no recourse to public funds…"),
        field("notes", "Notes", "multiline")
      ]
    ),


    Template.new(
      type: "document",
      label: "Document",
      icon: "fa-file-lines",
      summary: "Anything official that doesn't have a shelf of its own yet.",
      title_hint: "Marriage certificate",
      fields: [
        field("document_kind", "What it is", "text", "Marriage certificate, degree, NI card…"),
        field("full_name", "Held by"),
        field("document_number", "Reference or number", "reference"),
        field("issued_on", "Issued", "date"),
        field("expires_on", "Expires", "expiry", "Leave blank if it doesn't run out"),
        field("authority", "Issued by"),
        field("notes", "Notes", "multiline")
      ]
    ),

    Template.new(
      type: "property",
      label: "Property",
      icon: "fa-house",
      summary: "The house, and everything the house implies.",
      title_hint: "The house",
      fields: [
        field("address", "Address", "multiline"),
        field("tenure", "Owned or rented"),
        field("purchased_on", "Purchase date", "date"),
        field("title_number", "Title number", "reference"),
        field("council_tax_ref", "Council tax reference", "reference"),
        field("council_tax_band", "Council tax band"),
        field("gas_meter", "Gas meter number", "reference"),
        field("electric_meter", "Electricity meter number", "reference"),
        field("water_meter", "Water meter number", "reference"),
        field("notes", "Notes", "multiline")
      ]
    ),

    Template.new(
      type: "person",
      label: "Person",
      icon: "fa-user",
      summary: "Who somebody is. What they hold goes in a document of its own.",
      title_hint: "Aisha Rahman",
      title_from: "full_name",
      fields: [
        field("full_name", "Full name"),
        field("date_of_birth", "Date of birth", "date"),
        field("national_id", "National insurance / ID", "reference"),
        field("blood_group", "Blood group"),
        field("relationship", "Relationship", "text", "Mum, son, myself…"),
        field("notes", "Notes", "multiline")
      ]
    ),

    Template.new(
      type: "vehicle",
      label: "Vehicle",
      icon: "fa-car",
      summary: "Registration, and the dates that cost money when missed.",
      title_hint: "The blue Golf",
      fields: [
        field("registration", "Registration", "reference"),
        field("make_model", "Make and model"),
        field("vin", "VIN", "reference"),
        field("bought_on", "Bought", "date"),
        field("insurance_renews_on", "Insurance renews", "expiry"),
        field("mot_due_on", "MOT due", "expiry", remind: SHORT_REMINDERS),
        field("tax_due_on", "Road tax due", "expiry", remind: SHORT_REMINDERS),
        field("notes", "Notes", "multiline")
      ]
    ),

    Template.new(
      type: "money",
      label: "Money",
      icon: "fa-building-columns",
      summary: "Accounts and policies — reference numbers, not banking logins.",
      title_hint: "Halifax — joint current account",
      fields: [
        field("institution", "Institution"),
        field("account_name", "Account name"),
        field("kind", "Kind", "text", "Current, savings, ISA, pension, policy…"),
        field("sort_code", "Sort code", "reference"),
        field("account_number", "Account number", "reference"),
        field("iban", "IBAN", "reference"),
        field("policy_number", "Policy number", "reference"),
        field("renews_on", "Renews or matures", "expiry"),
        field("notes", "Notes", "multiline")
      ]
    ),

    Template.new(
      type: "subscription",
      label: "Subscription",
      icon: "fa-arrows-rotate",
      summary: "What leaves the account every month.",
      title_hint: "Netflix",
      fields: [
        field("service", "Service"),
        field("cost", "Cost", "money"),
        field("billing_cycle", "Billed", "text", "Monthly, yearly…"),
        # Comes round every month; a countdown on screen is plenty.
        field("next_charge_on", "Next charge", "expiry", remind: []),
        field("paid_with", "Paid with", "text", "Which card or account"),
        # This one you cannot afford to miss.
        field("cancel_by", "Cancel by", "expiry", remind: SHORT_REMINDERS),
        field("notes", "Notes", "multiline")
      ]
    ),

    Template.new(
      type: "emergency",
      label: "In case of emergency",
      icon: "fa-kit-medical",
      summary: "Where things are, and who to call.",
      title_hint: "If something happens to me",
      fields: [
        field("will_location", "Where the will is", "multiline"),
        field("executor", "Executor"),
        field("solicitor", "Solicitor"),
        field("key_holders", "Who has keys", "multiline"),
        field("who_to_call", "Who to call", "multiline"),
        field("documents_kept", "Where documents are kept", "multiline"),
        field("notes", "Notes", "multiline")
      ]
    )
  ].freeze

  BY_TYPE = ALL.index_by(&:type).freeze
  TYPES = ALL.map(&:type).freeze

  def self.[](type) = BY_TYPE[type.to_s]
  def self.exists?(type) = BY_TYPE.key?(type.to_s)

  # Keys a template knows about. Anything else a record carries is a field
  # somebody added themselves, which is allowed and kept.
  def self.known_keys(type) = self[type]&.fields&.map(&:key) || []
end
