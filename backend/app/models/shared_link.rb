# frozen_string_literal: true

# A public link to one file, or to one household record and its documents.
#
# The token is the credential, so it is stored as a digest only — a database
# leak must not hand out working share URLs. Optionally gated by a password and
# an expiry, and revocable at any time.
#
# A record share is read-only and never carries a secret: passwords live
# encrypted under a passphrase this link does not have and could not hand over
# if it did.
class SharedLink < ApplicationRecord
  belongs_to :stored_file, optional: true
  belongs_to :vault_record, optional: true
  belongs_to :user

  has_secure_password :password, validations: false

  # Present only on the instance that created the link, so it can be returned
  # once to the person sharing.
  attr_reader :raw_token

  validates :max_downloads, numericality: { greater_than: 0 }, allow_nil: true
  validate :points_at_one_thing

  scope :active, -> { where(revoked_at: nil) }

  before_validation :generate_token, on: :create

  def self.digest_for(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_by_raw_token(token)
    return nil if token.blank?

    find_by(token_digest: digest_for(token))
  end

  def for_record? = vault_record_id.present?

  # The thing being shared, whichever kind it is.
  def subject = vault_record || stored_file

  # A link outlives what it points at, so every use has to ask. A file goes to
  # the trash and a record is archived; either way the link is dead.
  def subject_gone?
    return true if subject.nil?
    return subject.archived_at.present? if for_record?

    subject.trashed?
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

  def url(base_url = nil)
    return nil if raw_token.nil?

    base = base_url.presence || Rails.configuration.x.app_url
    "#{base.chomp("/")}/share/#{raw_token}"
  end

  private

  def generate_token
    @raw_token = SecureRandom.urlsafe_base64(24)
    self.token_digest = self.class.digest_for(@raw_token)
  end

  def points_at_one_thing
    return if stored_file_id.present? ^ vault_record_id.present?

    errors.add(:base, "A share link points at one file or one record.")
  end
end
