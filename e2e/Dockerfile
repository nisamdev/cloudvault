# Playwright, with Chromium already installed. The tag tracks @playwright/test
# in package.json — the browsers in the image only match that exact release.
#
# Tests are not part of `docker compose up`. Run them with:
#   docker compose --profile e2e run --rm e2e
FROM mcr.microsoft.com/playwright:v1.65.0-noble

WORKDIR /work

# The image already has the browsers. Don't let npm ci download them again.
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
# Shares the web container's network (see docker-compose.yml), so Vite is on
# the loopback. Loopback is what lets Chromium store the Secure refresh cookie.
ENV PLAYWRIGHT_BASE_URL=http://127.0.0.1:5173

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN chmod +x bin/docker-entrypoint.sh

ENTRYPOINT ["bin/docker-entrypoint.sh"]
