# Helpers for request specs that need a signed-in user.
module AuthHelpers
  def auth_headers_for(user)
    token = JwtService.encode({ sub: user.id, email: user.email })
    { "Authorization" => "Bearer #{token}" }
  end

  # The refresh cookie is encrypted, so specs can't forge one — log in and let
  # Rails set it on the integration session.
  def login_as(user, password: "password123")
    post "/api/v1/auth/login", params: { email: user.email, password: password }, as: :json
    JSON.parse(response.body)
  end

  def json
    JSON.parse(response.body)
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
