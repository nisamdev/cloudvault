#!/bin/sh
set -eu

# Runs from nginx's /docker-entrypoint.d/ before nginx starts.
#
# Two jobs, both of which exist so ONE built image can serve ANY environment:
#
#   1. Render the listen port. Railway assigns $PORT at runtime; a port baked in
#      at build time would make the container unreachable.
#   2. Write /config.js from the environment. Vite normally inlines VITE_* values
#      at build time, which would mean rebuilding the image per environment.
#      The app reads window.__CLOUDVAULT_CONFIG__ instead.

PORT="${PORT:-80}"
API_URL="${API_URL:-http://localhost:3000}"
APP_ENV="${APP_ENV:-production}"

echo "[cloudvault] listening on ${PORT}, API at ${API_URL}"

sed "s|__PORT__|${PORT}|g" \
  /etc/nginx/templates/cloudvault.conf.template \
  > /etc/nginx/conf.d/default.conf

# Escape anything that could break out of the JS string literal.
escaped_api_url=$(printf '%s' "${API_URL}" | sed 's|\\|\\\\|g; s|"|\\"|g')
escaped_app_env=$(printf '%s' "${APP_ENV}" | sed 's|\\|\\\\|g; s|"|\\"|g')

cat > /usr/share/nginx/html/config.js <<EOF
// Generated at container start. Do not edit — see docker/40-cloudvault-runtime-config.sh
window.__CLOUDVAULT_CONFIG__ = {
  apiUrl: "${escaped_api_url}",
  appEnv: "${escaped_app_env}"
};
EOF
