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
  SCOPE = "scan"

  attr_reader :user, :folder_id, :visibility, :expires_at

  def self.create(user:, folder_id: nil, visibility: "private", ttl: DEFAULT_TTL)
    expires_at = ttl.from_now

    token = JwtService.encode_scan(
      user_id: user.id,
      folder_id: folder_id,
      visibility: visibility,
      expires_in: ttl
    )

    new(user: user, folder_id: folder_id, visibility: visibility, expires_at: expires_at, token: token)
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
      token: token
    )
  end

  def initialize(user:, expires_at:, token:, folder_id: nil, visibility: "private")
    @user = user
    @folder_id = folder_id
    @visibility = visibility
    @expires_at = expires_at
    @token = token
  end

  def url
    "#{Rails.configuration.x.app_url}/scan/#{@token}"
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
      visibility: visibility
    }
  end
end
