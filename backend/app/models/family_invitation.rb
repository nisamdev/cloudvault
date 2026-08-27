# frozen_string_literal: true

class FamilyInvitation < ApplicationRecord
  # The owner role is never handed out by invitation; it transfers explicitly.
  ROLES = %w[admin editor viewer].freeze
  EXPIRES_AFTER = 7.days

  belongs_to :family
  belongs_to :invited_by, class_name: "User"

  # Set only when the invitation is created, so the mailer can send it. Never
  # persisted — the database keeps the digest alone.
  attr_reader :raw_token

  validates :email, presence: true, format: { with: User::EMAIL_FORMAT }
  validates :role, inclusion: { in: ROLES }

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  scope :pending, lambda {
    where(accepted_at: nil, revoked_at: nil, declined_at: nil).where(expires_at: Time.current..)
  }

  # Waiting for one particular person to answer, whether or not they have an
  # account yet.
  scope :addressed_to, ->(email) { pending.where(email: email.to_s.strip.downcase) }

  before_validation :generate_token, on: :create
  before_validation :set_expiry, on: :create

  def self.find_by_raw_token(token)
    return nil if token.blank?

    find_by(token_digest: digest_for(token))
  end

  def self.digest_for(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def pending? = accepted_at.nil? && revoked_at.nil? && declined_at.nil? && !expired?
  def declined? = declined_at.present?
  def expired? = expires_at.past?

  private

  def generate_token
    @raw_token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest_for(@raw_token)
  end

  def set_expiry
    self.expires_at ||= EXPIRES_AFTER.from_now
  end
end
