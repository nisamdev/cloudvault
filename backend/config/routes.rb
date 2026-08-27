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
      resources :families, only: %i[index create show update] do
        member do
          post :select
          delete :leave
        end
        resources :invitations, only: %i[create destroy]
        resources :members, only: %i[update destroy]
      end

      # --- This account ------------------------------------------------------
      get   "account",          to: "account#show"
      patch "account",          to: "account#update"
      patch "account/password", to: "account#update_password"

      # A refresh token is what keeps a device signed in, so the list of them is
      # the list of sessions.
      resources :sessions, only: %i[index destroy] do
        collection do
          delete "/", action: :destroy_all
        end
      end

      # Invitation acceptance is addressed by token, not by id: the recipient
      # may not have an account yet when they follow the link.
      get  "invitations/:token",        to: "invitations#show",   as: :invitation
      post "invitations/:token/accept", to: "invitations#accept", as: :accept_invitation

      # --- The private section -----------------------------------------------
      # A passphrase-locked place for files and photos. Unlocking hands back a
      # token that has to be sent with every request that touches it.
      get    "vault",              to: "vaults#show"
      post   "vault",              to: "vaults#create"
      post   "vault/unlock",       to: "vaults#unlock"
      delete "vault/unlock",       to: "vaults#lock"
      patch  "vault/passphrase",   to: "vaults#change_passphrase"
      post   "vault/recover",      to: "vaults#recover"
      post   "vault/recovery_key_seen", to: "vaults#recovery_key_seen"

      # Empty the whole bin in one request (files + folders).
      delete "trash", to: "trash#destroy"

      # --- Files and images --------------------------------------------------
      resources :files, only: %i[index show create update destroy] do
        collection do
          # Multi-select download: ask for a URL, then navigate to stream the ZIP.
          post :zip_url
          get  :zip
        end
        member do
          get    :download
          get    :content
          get    :preview
          get    :pages
          # Same noun, so the same path: GET renders the pages, PATCH rewrites
          # them.
          patch  :pages, action: :rearrange
          get    :text
          post   :split
          post   :sign
          post   :restore
          delete :purge
          # Moving a single file into the private section (and back out).
          post   :lock
          delete :lock, action: :unlock
          # Rebuild a missing gallery thumbnail.
          post   :reprocess
        end
        # Managing links for a file (owner side).
        resources :shares, only: %i[index create]
        # Sharing with a person or a family, as opposed to a public link.
        resources :grants, only: %i[index create]
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

      resources :grants, only: %i[update destroy]

      resources :folders, only: %i[index show create update destroy] do
        resources :grants, only: %i[index create]
        collection do
          get :trashed
        end
        member do
          post :restore
          # Moving a folder into the private section and back out again.
          post   :lock
          delete :lock, action: :unlock
          # Two steps: the SPA asks for a signed URL, the browser then navigates
          # to it so the ZIP downloads like any other file.
          post :download_url
          get  :download
        end
      end
      # Tools that act on documents rather than store them.
      post "utilities/merge", to: "utilities#merge"
      post "utilities/images_to_pdf", to: "utilities#images_to_pdf"

      resources :labels, only: %i[index create update destroy]
      resources :signatures, only: %i[index create update destroy]

      # --- Household register -----------------------------------------------
      resources :record_templates, only: %i[index]
      # Photograph a document, get a filled-in form back to check.
      get  "document_captures/presets", to: "document_captures#presets"
      post "document_captures",         to: "document_captures#create"

      resources :records, only: %i[index show create update destroy] do
        get "secrets/:key/reveal", to: "record_secrets#reveal"
        get "secrets/:key/history", to: "record_secrets#history"
        get "secrets/:key/history/:version_id/reveal", to: "record_secrets#reveal_version"
      end

      # Drawing a signature on a phone, same pattern as scanning: the token in
      # the URL is the credential and can only add a signature.
      sig_token = { token: %r{[^/]+} }
      post "signatures/session", to: "signatures#session_create_link"
      get  "signatures/session/:token/status", to: "signatures#session_status", constraints: sig_token, format: false
      get  "signatures/session/:token", to: "signatures#session_show", constraints: sig_token, format: false
      post "signatures/session/:token", to: "signatures#session_create", constraints: sig_token, format: false

      # The token is a JWT, which contains dots — Rails would otherwise read the
      # last segment as a format.
      get "blobs/:token", to: "blobs#show", constraints: { token: %r{[^/]+} }, format: false

      get "shares", to: "shares#mine"
      resources :shares, only: %i[destroy]

      # Public share access — the token is the credential, so these are
      # addressed by token and reachable without a session.
      get  "shares/:token",          to: "shares#show",     as: :public_share
      post "shares/:token/download", to: "shares#download", as: :public_share_download
    end
  end
end
