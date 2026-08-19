# frozen_string_literal: true

# A public link to one file.
#
# The token is the credential, so it is stored as a digest only — a database
# leak must not hand out working share URLs. Optionally gated by a password and
# an expiry, and revocable at any time.
class SharedLink < ApplicationRecord
  belongs_to :stored_file
  belongs_to :user

  has_secure_password :password, validations: false

  # Present only on the instance that created the link, so it can be returned
  # once to the person sharing.
  attr_reader :raw_token

  validates :max_downloads, numericality: { greater_than: 0 }, allow_nil: true

  scope :active, -> { where(revoked_at: nil) }

  before_validation :generate_token, on: :create

  def self.digest_for(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_by_raw_token(token)
    return nil if token.blank?

    find_by(token_digest: digest_for(token))
  end

  def expired? = expires_at.present? && expires_at.past?
  def revoked? = revoked_at.present?
  def exhausted? = max_downloads.present? && download_count >= max_downloads
  def password_protected? = password_digest.present?

  def usable?
    !revoked? && !expired? && !exhausted?
  end

  # Why a link cannot be used — the public endpoint turns this into a message.
  def unusable_reason
    return "revoked" if revoked?
    return "expired" if expired?
    return "exhausted" if exhausted?

    nil
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end

  def record_download!
    increment!(:download_count)
    update_column(:last_accessed_at, Time.current)
  end

  def url
    return nil if raw_token.nil?

    "#{Rails.configuration.x.app_url}/share/#{raw_token}"
  end

  private

  def generate_token
    @raw_token = SecureRandom.urlsafe_base64(24)
    self.token_digest = self.class.digest_for(@raw_token)
  end
end
