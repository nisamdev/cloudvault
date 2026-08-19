# frozen_string_literal: true

# CORS for the Vue SPA.
#
# Origins come from CORS_ORIGINS (comma-separated) so that adding a Railway
# domain, a preview environment or an ngrok tunnel is a variable change, never a
# code change. PHASE1_IMPLEMENTATION_GUIDE.md hardcodes the ngrok host here;
# reading it from the environment achieves the same thing without a redeploy.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(
      ENV.fetch("CORS_ORIGINS", "http://localhost:5173")
         .split(",")
         .map(&:strip)
         .reject(&:empty?)
    )

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      # Clients read pagination totals and the download filename from these.
      expose: %w[Authorization X-Total-Count X-Total-Pages X-Page Content-Disposition],
      credentials: true,
      max_age: 600
  end
end
