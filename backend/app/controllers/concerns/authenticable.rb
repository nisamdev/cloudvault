# frozen_string_literal: true

# Bearer-token authentication for API controllers.
module Authenticable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
  end

  class_methods do
    # Marks endpoints reachable without a session (login, register, public shares).
    def allow_unauthenticated(*actions)
      skip_before_action :authenticate_user!, only: actions, raise: false
    end
  end

  private

  def authenticate_user!
    return if current_user

    render_error(
      message: "You need to sign in to continue.",
      code: "unauthenticated",
      status: :unauthorized
    )
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = begin
      payload = JwtService.decode(bearer_token)
      User.find_by(id: payload["sub"])
    rescue JwtService::InvalidToken
      nil
    end
  end

  def current_membership
    return @current_membership if defined?(@current_membership)

    @current_membership = current_user&.primary_membership
  end

  def current_family
    current_membership&.family
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    header.start_with?("Bearer ") ? header.delete_prefix("Bearer ").strip : nil
  end
end
