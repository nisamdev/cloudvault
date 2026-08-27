# frozen_string_literal: true

# A short-lived, upload-only credential that lets a phone add documents without
# signing in — opened by scanning a QR code on the desktop.
#
# The token is a bearer credential travelling in a URL, so it is deliberately
# weak: it expires quickly, it can only upload, and it cannot list, read or
# delete anything. Losing it costs you an unwanted upload, nothing more.
class ScanSession
  class InvalidToken < StandardError; end

  DEFAULT_TTL = 20.minutes
  # Outlives the token slightly, so a desktop polling as it expires still sees
  # what arrived.
  RECEIPT_TTL = 30.minutes
  SCOPE = "scan"

  attr_reader :user, :folder_id, :visibility, :expires_at, :purpose, :preset

  # @param purpose ["files", "record"] what the phone is being asked for
  # @param preset [String, nil] which kind of document, when it is a record
  def self.create(user:, folder_id: nil, visibility: "private", ttl: DEFAULT_TTL, base_url: nil,
                  purpose: "files", preset: nil)
    expires_at = ttl.from_now

    token = JwtService.encode_scan(
      user_id: user.id,
      folder_id: folder_id,
      visibility: visibility,
      expires_in: ttl,
      purpose: purpose,
      preset: preset
    )

    new(user: user, folder_id: folder_id, visibility: visibility, expires_at: expires_at,
        token: token, base_url: base_url, jti: JwtService.decode_scan(token)["jti"],
        purpose: purpose, preset: preset)
  end

  def self.from_token(token)
    payload = JwtService.decode_scan(token)
    user = User.find_by(id: payload["sub"])
    raise InvalidToken, "unknown user" if user.nil?

    new(
      user: user,
      folder_id: payload["folder_id"],
      visibility: payload["visibility"].presence || "private",
      expires_at: Time.zone.at(payload["exp"]),
      token: token,
      jti: payload["jti"],
      purpose: payload["purpose"].presence || "files",
      preset: payload["preset"]
    )
  end

  def initialize(user:, expires_at:, token:, folder_id: nil, visibility: "private", base_url: nil,
                 jti: nil, purpose: "files", preset: nil)
    @user = user
    @folder_id = folder_id
    @visibility = visibility
    @expires_at = expires_at
    @token = token
    # The QR code is scanned by a phone, which cannot reach "localhost".
    @base_url = base_url.presence || Rails.configuration.x.app_url
    @jti = jti
    @purpose = purpose
    @preset = preset
  end

  def for_record? = purpose == "record"

  # The desktop cannot see what the phone did, so the phone leaves a receipt and
  # the desktop polls for it. Redis rather than a table: short-lived scratch
  # state that should expire along with the token.
  def record_upload(files, suggestion: nil)
    return if @jti.blank?

    payload = {
      completed_at: Time.current.iso8601,
      purpose: purpose,
      files: files.map { |f| { id: f.id, name: f.name, size: f.size } },
      # What the desktop should open when the phone is done: for a record, the
      # fields read off the document, waiting to be checked.
      suggestion: suggestion
    }.compact

    # to_i: the Redis client rejects an ActiveSupport::Duration.
    Sidekiq.redis { |redis| redis.set(receipt_key, payload.to_json, ex: RECEIPT_TTL.to_i) }
  rescue StandardError => e
    # The receipt only drives a progress dialog. Losing it must never fail an
    # upload that has already been stored.
    Rails.logger.error("[scan] could not record receipt: #{e.class}: #{e.message}")
  end

  def receipt
    return nil if @jti.blank?

    raw = Sidekiq.redis { |redis| redis.get(receipt_key) }
    raw.present? ? JSON.parse(raw) : nil
  rescue JSON::ParserError, StandardError => e
    Rails.logger.warn("[scan] could not read receipt: #{e.class}")
    nil
  end

  def receipt_key
    "scan:receipt:#{@jti}"
  end

  def url
    "#{@base_url.chomp("/")}/scan/#{@token}"
  end

  # SVG rather than PNG so it stays crisp at any size and needs no image
  # pipeline on the client.
  def qr_svg
    RQRCode::QRCode.new(url, level: :m).as_svg(
      module_size: 5,
      standalone: true,
      use_path: true,
      viewbox: true
    )
  end

  def family
    user.primary_membership&.family
  end

  def to_h
    {
      url: url,
      expires_at: expires_at,
      expires_in_minutes: ((expires_at - Time.current) / 60).round,
      folder_id: folder_id,
      visibility: visibility,
      purpose: purpose,
      preset: preset
    }
  end
end
