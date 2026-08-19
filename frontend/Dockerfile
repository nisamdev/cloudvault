# CloudVault web — Vue 3 + Vite
#
# Targets:
#   development  → Vite dev server with HMR (docker compose)
#   production   → static build served by nginx (this is what Railway builds)
#
# The production image is environment-agnostic: the API URL is injected at
# container start into /config.js, not baked in by Vite. One image, any stage.

ARG NODE_VERSION=24

# ---------------------------------------------------------------- development
FROM node:${NODE_VERSION}-alpine AS development

WORKDIR /app
ENV NODE_ENV=development

COPY package.json package-lock.json ./
RUN npm ci

# Source arrives via bind mount from compose.
EXPOSE 5173
CMD ["sh", "-c", "npm run dev -- --host 0.0.0.0 --port ${PORT:-5173}"]

# ---------------------------------------------------------------- build
FROM node:${NODE_VERSION}-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

# ---------------------------------------------------------------- production
FROM nginx:1.27-alpine AS production

COPY --from=builder /app/dist /usr/share/nginx/html
COPY docker/nginx.conf.template /etc/nginx/templates/cloudvault.conf.template
COPY docker/40-cloudvault-runtime-config.sh /docker-entrypoint.d/40-cloudvault-runtime-config.sh

# nginx's own entrypoint ships templating that would clobber $uri in our config;
# the numbered script above does the substitution we actually want.
RUN chmod +x /docker-entrypoint.d/40-cloudvault-runtime-config.sh \
 && rm -f /etc/nginx/conf.d/default.conf

ENV PORT=80
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT:-80}/healthz" || exit 1
