# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password validations: false

  ROLES = %w[owner admin editor viewer].freeze

  has_many :refresh_tokens, dependent: :destroy
  # Files stay with the family when a member leaves, so this is not dependent.
  has_many :stored_files, dependent: nil, inverse_of: :user
  has_one :private_vault, dependent: :destroy, inverse_of: :user
  has_many :folders, dependent: nil, inverse_of: :user
  has_many :signatures, dependent: :destroy
  has_many :family_memberships, class_name: "FamilyMember", dependent: :destroy
  has_many :families, through: :family_memberships, source: :family
  belongs_to :current_family, class_name: "Family", optional: true
  has_many :access_grants, as: :subject, dependent: :destroy
  has_many :owned_families, class_name: "Family", foreign_key: :owner_id,
           inverse_of: :owner, dependent: :restrict_with_error

  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  validates :email, presence: true, uniqueness: { case_sensitive: false },
            format: { with: EMAIL_FORMAT, message: "is not a valid email address" }
  validates :full_name, length: { maximum: 120 }, allow_blank: true
  validates :storage_quota, :storage_used, numericality: { greater_than_or_equal_to: 0 }

  # OAuth users have no password; everyone else must have one.
  validates :password, length: { minimum: 8 }, allow_nil: true
  validate :password_or_oauth_identity

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  # The family the app is currently showing. A user may belong to several, or
  # to none at all — an account is useful on its own, and everything in it is
  # private until it is deliberately shared.
  def current_membership
    return nil if family_memberships.empty?

    from_choice = family_memberships.find_by(family_id: current_family_id) if current_family_id
    from_choice || family_memberships.includes(:family).order(:created_at).first
  end

  # Kept as the old name so the many call sites that mean "the family I am
  # working in" keep working while the rest catches up.
  alias primary_membership current_membership

  def storage_remaining
    [ storage_quota - storage_used, 0 ].max
  end

  def storage_percent_used
    return 0 if storage_quota.zero?

    ((storage_used.to_f / storage_quota) * 100).round(1)
  end

  def oauth?
    oauth_provider.present?
  end

  private

  def password_or_oauth_identity
    return if password_digest.present? || oauth?

    errors.add(:password, "can't be blank")
  end
end
