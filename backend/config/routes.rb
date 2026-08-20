Rails.application.routes.draw do
  # Platform health probe (Railway healthcheckPath, compose healthcheck).
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # Also proves Postgres, Redis and storage are reachable from this process.
      get "health", to: "health#show"

      # --- Session lifecycle -------------------------------------------------
      post "auth/register", to: "auth#register"
      post "auth/login",    to: "auth#login"
      post "auth/refresh",  to: "auth#refresh"
      post "auth/logout",   to: "auth#logout"
      get  "auth/me",       to: "auth#me"

      # --- Families ----------------------------------------------------------
      resources :families, only: %i[create show update] do
        resources :invitations, only: %i[create destroy]
      end

      # Invitation acceptance is addressed by token, not by id: the recipient
      # may not have an account yet when they follow the link.
      get  "invitations/:token",        to: "invitations#show",   as: :invitation
      post "invitations/:token/accept", to: "invitations#accept", as: :accept_invitation

      # --- Files and images --------------------------------------------------
      resources :files, only: %i[index show create update destroy] do
        member do
          get    :download
          get    :preview
          get    :pages
          post   :sign
          post   :restore
          delete :purge
        end
        # Managing links for a file (owner side).
        resources :shares, only: %i[index create]
      end

      # Phone-as-scanner. create is authenticated (desktop); the token-addressed
      # actions are how the phone talks to us without signing in.
      post "scans", to: "scans#create"
      # A JWT contains dots, which Rails would otherwise read as a format
      # extension and truncate.
      scan_token = { token: %r{[^/]+} }
      get  "scans/:token", to: "scans#show", as: :scan, constraints: scan_token, format: false
      post "scans/:token", to: "scans#upload", as: :scan_upload, constraints: scan_token, format: false
      get  "scans/:token/status", to: "scans#status", as: :scan_status, constraints: scan_token, format: false

      resources :folders, only: %i[index show create update destroy] do
        collection do
          get :trashed
        end
        member do
          post :restore
          # Two steps: the SPA asks for a signed URL, the browser then navigates
          # to it so the ZIP downloads like any other file.
          post :download_url
          get  :download
        end
      end
      resources :labels, only: %i[index create update destroy]
      resources :signatures, only: %i[index create update destroy]

      # Drawing a signature on a phone, same pattern as scanning: the token in
      # the URL is the credential and can only add a signature.
      sig_token = { token: %r{[^/]+} }
      post "signatures/session", to: "signatures#session_create_link"
      get  "signatures/session/:token/status", to: "signatures#session_status", constraints: sig_token, format: false
      get  "signatures/session/:token", to: "signatures#session_show", constraints: sig_token, format: false
      post "signatures/session/:token", to: "signatures#session_create", constraints: sig_token, format: false

      resources :shares, only: %i[destroy]

      # Public share access — the token is the credential, so these are
      # addressed by token and reachable without a session.
      get  "shares/:token",          to: "shares#show",     as: :public_share
      post "shares/:token/download", to: "shares#download", as: :public_share_download
    end
  end
end
