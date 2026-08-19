# frozen_string_literal: true

class ApplicationController < ActionController::API
  # Needed for the httpOnly refresh-token cookie; API mode excludes it by default.
  include ActionController::Cookies
end
