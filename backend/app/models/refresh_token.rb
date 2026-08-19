# frozen_string_literal: true

# A refresh token is a rotating, single-use credential stored as a digest.
#
# Rotation means each refresh issues a new token and revokes the old one. If a
# token that was already rotated shows up again, it was stolen (or replayed), and
# `detect_replay!` revokes the whole chain.
class RefreshToken < ApplicationRecord
  belongs_to :user
  belongs_to :replaced_by, class_name: "RefreshToken", optional: true

  attr_reader :raw_token

  scope :active, -> { where(revoked_at: nil).where(expires_at: Time.current..) }

  before_validation :generate_token, on: :create
  before_validation :set_expiry, on: :create

  def self.digest_for(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_by_raw_token(token)
    return nil if token.blank?

    find_by(token_digest: digest_for(token))
  end

  def active? = revoked_at.nil? && expires_at.future?

  def revoke!(at: Time.current)
    update!(revoked_at: at) if revoked_at.nil?
  end

  # Reuse of a rotated token means it leaked; end every session for that user.
  def detect_replay!
    return false if replaced_by_id.nil?

    user.refresh_tokens.active.find_each { |token| token.revoke! }
    true
  end

  private

  def generate_token
    @raw_token = SecureRandom.urlsafe_base64(48)
    self.token_digest = self.class.digest_for(@raw_token)
  end

  def set_expiry
    self.expires_at ||= ENV.fetch("JWT_REFRESH_TTL_DAYS", 7).to_i.days.from_now
  end
end
