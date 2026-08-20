# frozen_string_literal: true

# A short-lived link that lets a phone draw a signature and send it back.
#
# Same shape as ScanSession: drawing with a finger beats drawing with a mouse,
# and the phone should not have to sign in to do it. The token can only add a
# signature — it cannot read, list or delete anything.
class SignatureSession
  class InvalidToken < StandardError; end

  DEFAULT_TTL = 15.minutes
  RECEIPT_TTL = 30.minutes

  attr_reader :user, :expires_at

  def self.create(user:, ttl: DEFAULT_TTL, base_url: nil)
    token = JwtService.encode_signature(user_id: user.id, expires_in: ttl)

    new(user: user, expires_at: ttl.from_now, token: token, base_url: base_url,
        jti: JwtService.decode_signature(token)["jti"])
  end

  def self.from_token(token)
    payload = JwtService.decode_signature(token)
    user = User.find_by(id: payload["sub"])
    raise InvalidToken, "unknown user" if user.nil?

    new(user: user, expires_at: Time.zone.at(payload["exp"]), token: token, jti: payload["jti"])
  end

  def initialize(user:, expires_at:, token:, base_url: nil, jti: nil)
    @user = user
    @expires_at = expires_at
    @token = token
    @base_url = base_url.presence || Rails.configuration.x.app_url
    @jti = jti
  end

  def url
    "#{@base_url.chomp("/")}/signature/#{@token}"
  end

  def qr_svg
    RQRCode::QRCode.new(url, level: :m).as_svg(
      module_size: 5, standalone: true, use_path: true, viewbox: true
    )
  end

  # The desktop polls for this, since the phone cannot talk to it directly.
  def record_signature(signature)
    return if @jti.blank?

    payload = { completed_at: Time.current.iso8601, signature_id: signature.id, name: signature.name }
    Sidekiq.redis { |redis| redis.set(receipt_key, payload.to_json, ex: RECEIPT_TTL.to_i) }
  rescue StandardError => e
    # Only drives a dialog; never fail a signature that was already saved.
    Rails.logger.error("[signature-session] receipt failed: #{e.class}: #{e.message}")
  end

  def receipt
    return nil if @jti.blank?

    raw = Sidekiq.redis { |redis| redis.get(receipt_key) }
    raw.present? ? JSON.parse(raw) : nil
  rescue StandardError
    nil
  end

  def to_h
    {
      url: url,
      expires_at: expires_at,
      expires_in_minutes: ((expires_at - Time.current) / 60).round
    }
  end

  private

  def receipt_key
    "signature:receipt:#{@jti}"
  end
end
