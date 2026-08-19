# CloudVault API — Rails 8 (API mode)
#
# Targets:
#   development  → used by docker compose; source is bind-mounted, gems baked in
#   production   → default target; self-contained image (this is what Railway builds)
#
# Railway builds the default (last) stage, so `production` must stay last.

ARG RUBY_VERSION=3.4

# ---------------------------------------------------------------- base
FROM ruby:${RUBY_VERSION}-slim AS base

ENV LANG=C.UTF-8 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_LOG_TO_STDOUT=true

# libvips = image_processing (thumbnails); libpq5 = pg; postgresql-client = pg_isready
RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y \
      curl \
      libjemalloc2 \
      libpq5 \
      libvips42 \
      postgresql-client \
 && rm -rf /var/lib/apt/lists/*

# jemalloc keeps Ruby's RSS down — matters on Railway's per-GB pricing.
ENV LD_PRELOAD=libjemalloc.so.2

WORKDIR /app

# ---------------------------------------------------------------- gems
FROM base AS builder

RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libpq-dev \
      pkg-config \
 && rm -rf /var/lib/apt/lists/*

# Default excludes dev/test gems; compose overrides it to "" for the dev target.
ARG BUNDLE_WITHOUT="development test"

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without "${BUNDLE_WITHOUT}" \
 && bundle install \
 && rm -rf "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# ---------------------------------------------------------------- development
FROM base AS development

# Kept so `bundle add <gem>` works inside the running dev container.
RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libpq-dev \
      pkg-config \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Source arrives via bind mount from compose.
ENV RAILS_ENV=development
EXPOSE 3000
ENTRYPOINT ["entrypoint.sh"]
CMD ["sh", "-c", "./bin/rails server -b 0.0.0.0 -p ${PORT:-3000}"]

# ---------------------------------------------------------------- production
FROM base AS production

ENV RAILS_ENV=production \
    RAILS_SERVE_STATIC_FILES=true \
    BUNDLE_WITHOUT="development test"

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . .
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh ./bin/* || true

# Bootsnap precompile trims boot time; SECRET_KEY_BASE_DUMMY lets the app load
# during build without a real secret.
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec bootsnap precompile --gemfile app/ lib/ || true

# Run unprivileged.
RUN groupadd --system --gid 1000 rails \
 && useradd --system --uid 1000 --gid 1000 --create-home rails \
 && mkdir -p log tmp storage \
 && chown -R rails:rails db log tmp storage
USER 1000:1000

# Railway injects PORT; default 3000 for plain `docker run`.
EXPOSE 3000
ENTRYPOINT ["entrypoint.sh"]
CMD ["sh", "-c", "./bin/rails server -b 0.0.0.0 -p ${PORT:-3000}"]
