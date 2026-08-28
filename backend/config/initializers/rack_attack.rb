# frozen_string_literal: true

# Rate limiting for authentication endpoints (Week 9 of the implementation
# guide, brought forward — an unthrottled login is a credential-stuffing target
# from day one).
class Rack::Attack
  # Cache backend: Redis in every environment so limits are shared across
  # replicas rather than per-process.
  self.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
    namespace: "rack_attack"
  )

  ### Throttles ###

  # Login: 5 attempts per 20 seconds per IP.
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/api/v1/auth/login" && req.post?
  end

  # Login: 5 attempts per 20 seconds per email, so rotating IPs doesn't help an
  # attacker grind one account.
  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if req.path == "/api/v1/auth/login" && req.post?
      begin
        JSON.parse(req.body.string)["email"].to_s.strip.downcase.presence
      rescue JSON::ParserError, NoMethodError
        nil
      ensure
        req.body.rewind
      end
    end
  end

  # Registration: 10 accounts per hour per IP.
  throttle("registrations/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.path == "/api/v1/auth/register" && req.post?
  end

  # General API ceiling. Bulk photo uploads legitimately fan out into many
  # requests (upload + per-photo thumbnail reprocess/status polling), so this
  # needs enough headroom for that, not just a trickle of normal browsing.
  throttle("api/ip", limit: 1500, period: 5.minutes) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # Health checks must never be throttled — the platform would mark the service
  # unhealthy and restart it.
  safelist("health-checks") do |req|
    req.path == "/up" || req.path == "/api/v1/health"
  end

  ### Response ###

  self.throttled_responder = lambda do |request|
    retry_after = (request.env["rack.attack.match_data"] || {})[:period]

    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [ {
        error: {
          message: "Too many attempts. Please wait a moment and try again.",
          code: "rate_limited",
          details: {}
        }
      }.to_json ]
    ]
  end
end

# rack-attack inserts its middleware through its own Railtie, so conditionally
# calling `middleware.use` would not keep it out of the stack. `enabled` is the
# real switch: specs exercise login repeatedly and must not trip the throttle.
Rack::Attack.enabled = !Rails.env.test?
