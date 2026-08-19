#!/usr/bin/env bash
set -euo pipefail

# CloudVault API entrypoint.
#
# Railway has no `depends_on`, so nothing guarantees Postgres/Redis are reachable
# when this container starts — on Railway *or* after a compose restart. We wait
# and retry here rather than relying on orchestration.

log() { echo "[entrypoint] $*"; }

# A container that is restarted (rather than recreated) keeps its tmp directory,
# and Puma refuses to boot while a stale pidfile from the dead process is there.
if [ -f tmp/pids/server.pid ]; then
  log "removing stale pidfile"
  rm -f tmp/pids/server.pid
fi

wait_for() {
  local name="$1" check="$2" attempts="${3:-60}" i=1
  until eval "$check" >/dev/null 2>&1; do
    if [ "$i" -ge "$attempts" ]; then
      log "ERROR: $name still unreachable after $attempts attempts; giving up."
      return 1
    fi
    log "waiting for $name ($i/$attempts)..."
    i=$((i + 1))
    sleep 2
  done
  log "$name is up."
}

if [ -n "${DATABASE_URL:-}" ]; then
  wait_for "postgres" 'pg_isready -d "$DATABASE_URL" -q'
fi

if [ -n "${REDIS_URL:-}" ]; then
  # Must run under Bundler — the redis gem is not on the default load path.
  wait_for "redis" 'bundle exec ruby -e "require \"redis\"; Redis.new(url: ENV[\"REDIS_URL\"]).ping"'
fi

# Migrations run on the API service only. The worker skips them so two services
# booting together cannot race each other on the schema.
if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
  log "running database migrations..."
  # db:prepare creates the database if it does not exist yet, then migrates.
  ./bin/rails db:prepare
fi

if [ "${SEED_ON_BOOT:-false}" = "true" ]; then
  log "seeding database..."
  ./bin/rails db:seed
fi

# Make sure the object storage bucket exists (MinIO locally; a no-op that logs a
# warning if the credentials cannot create buckets, as on R2/S3 in production).
if [ "${ENSURE_BUCKET:-false}" = "true" ]; then
  log "ensuring S3 bucket '${S3_BUCKET:-cloudvault}' exists..."
  ./bin/rails cloudvault:ensure_bucket || log "WARN: could not ensure bucket; create it manually."
fi

# Cost escape hatch for Railway's hobby tier: run the worker beside the web
# server in this container instead of paying for a second always-on service.
# Compose leaves this false — it runs a real `worker` service.
if [ "${RUN_SIDEKIQ_IN_PROCESS:-false}" = "true" ]; then
  log "RUN_SIDEKIQ_IN_PROCESS=true — starting sidekiq alongside the web server"
  bundle exec sidekiq -C config/sidekiq.yml &
  sidekiq_pid=$!

  # If either process dies the container should die too, so the platform
  # restarts it rather than leaving a half-running service.
  trap 'kill -TERM "$sidekiq_pid" 2>/dev/null || true' TERM INT
fi

log "starting: $*"
exec "$@"
