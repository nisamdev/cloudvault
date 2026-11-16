#!/usr/bin/env bash
# Copy CloudVault data from the Mac's local stack to the home server.
#
#   ./deploy/migrate-from-mac.sh path/to/server.env
#
# server.env = the variables you pasted into Coolify (POSTGRES_*, S3_*).
# The Mac side is read from ./.env.
#
# Prerequisites
#   - Mac:    `docker compose up -d postgres minio` (Docker Desktop running)
#   - Server: CloudVault deployed once in Coolify (empty DB + bucket exist)
#   - `ssh yegstack` works without a password prompt (key + agent)
#
# What it does
#   1. Opens an SSH tunnel to the server's Postgres and MinIO (both bound to
#      127.0.0.1 there, never public).
#   2. pg_dump the Mac database -> pg_restore into the server (--clean: the
#      server's empty schema is replaced by the Mac's, rows and all).
#   3. mc mirror every object in the Mac bucket -> server bucket.
#   4. Prints row/object counts from both sides so you can compare.
#
# Files are copied byte-for-byte, so locked-folder encryption (keys derived
# from each user's passphrase, salts in the DB) keeps working unchanged.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_ENV="${1:?usage: $0 path/to/server.env}"
SSH_HOST="${SSH_HOST:-yegstack}"
TUNNEL_DB_PORT=25532      # local end of the tunnel
TUNNEL_MINIO_PORT=29100

val() { grep -E "^$2=" "$1" | head -1 | cut -d= -f2-; }

MAC_PG_USER=$(val "$ROOT/.env" POSTGRES_USER)
MAC_PG_PASS=$(val "$ROOT/.env" POSTGRES_PASSWORD)
MAC_PG_DB=$(val "$ROOT/.env" POSTGRES_DB)
MAC_PG_PORT=$(val "$ROOT/.env" POSTGRES_PORT); MAC_PG_PORT=${MAC_PG_PORT:-5432}
MAC_S3_KEY=$(val "$ROOT/.env" S3_ACCESS_KEY_ID)
MAC_S3_SECRET=$(val "$ROOT/.env" S3_SECRET_ACCESS_KEY)
MAC_S3_PORT=$(val "$ROOT/.env" MINIO_PORT); MAC_S3_PORT=${MAC_S3_PORT:-9000}
BUCKET=$(val "$ROOT/.env" S3_BUCKET); BUCKET=${BUCKET:-cloudvault}

SRV_PG_USER=$(val "$SERVER_ENV" POSTGRES_USER)
SRV_PG_PASS=$(val "$SERVER_ENV" POSTGRES_PASSWORD)
SRV_PG_DB=$(val "$SERVER_ENV" POSTGRES_DB)
SRV_S3_KEY=$(val "$SERVER_ENV" S3_ACCESS_KEY_ID)
SRV_S3_SECRET=$(val "$SERVER_ENV" S3_SECRET_ACCESS_KEY)

PG_IMAGE=postgres:16-alpine
MC_IMAGE=bitnamilegacy/minio:latest   # ships the `mc` client
H=host.docker.internal                # containers reach the Mac (and the tunnel) here

echo "==> Opening SSH tunnel to $SSH_HOST (Postgres :15532, MinIO :19100)"
ssh -N -o ExitOnForwardFailure=yes \
  -L "$TUNNEL_DB_PORT:127.0.0.1:15532" \
  -L "$TUNNEL_MINIO_PORT:127.0.0.1:19100" \
  "$SSH_HOST" &
TUNNEL_PID=$!
trap 'kill $TUNNEL_PID 2>/dev/null || true' EXIT
sleep 3
kill -0 $TUNNEL_PID 2>/dev/null || { echo "SSH tunnel failed to start" >&2; exit 1; }

psql_mac() { docker run --rm -e PGPASSWORD="$MAC_PG_PASS" $PG_IMAGE psql -h $H -p "$MAC_PG_PORT" -U "$MAC_PG_USER" -d "$MAC_PG_DB" -tAc "$1"; }
psql_srv() { docker run --rm -e PGPASSWORD="$SRV_PG_PASS" $PG_IMAGE psql -h $H -p $TUNNEL_DB_PORT -U "$SRV_PG_USER" -d "$SRV_PG_DB" -tAc "$1"; }

echo "==> Checking both databases are reachable"
echo "    Mac:    $(psql_mac 'select count(*) from active_storage_blobs') stored files (blobs), $(psql_mac 'select count(*) from users') users"
echo "    Server: $(psql_srv 'select count(*) from active_storage_blobs') stored files (blobs), $(psql_srv 'select count(*) from users') users"

echo
read -r -p "Replace the SERVER database and bucket with the Mac's data? Type 'yes': " ok
[ "$ok" = "yes" ] || { echo "Aborted, nothing changed."; exit 1; }

DUMP_DIR="$(mktemp -d)"
echo "==> Dumping Mac database"
docker run --rm -e PGPASSWORD="$MAC_PG_PASS" -v "$DUMP_DIR:/dump" $PG_IMAGE \
  pg_dump -h $H -p "$MAC_PG_PORT" -U "$MAC_PG_USER" -d "$MAC_PG_DB" -Fc -f /dump/cloudvault.dump
echo "    $(du -h "$DUMP_DIR/cloudvault.dump" | cut -f1) dump written"

echo "==> Restoring into server database"
docker run --rm -e PGPASSWORD="$SRV_PG_PASS" -v "$DUMP_DIR:/dump" $PG_IMAGE \
  pg_restore -h $H -p $TUNNEL_DB_PORT -U "$SRV_PG_USER" -d "$SRV_PG_DB" \
  --clean --if-exists --no-owner --no-acl --single-transaction /dump/cloudvault.dump

echo "==> Copying files (bucket '$BUCKET')"
docker run --rm --entrypoint sh $MC_IMAGE -c "
  export MC_CONFIG_DIR=/tmp/.mc
  mc alias set mac http://$H:$MAC_S3_PORT '$MAC_S3_KEY' '$MAC_S3_SECRET' >/dev/null
  mc alias set srv http://$H:$TUNNEL_MINIO_PORT '$SRV_S3_KEY' '$SRV_S3_SECRET' >/dev/null
  mc mb -p srv/$BUCKET >/dev/null
  mc mirror --overwrite --preserve mac/$BUCKET srv/$BUCKET
  echo
  echo \"    Mac objects:    \$(mc ls -r mac/$BUCKET | wc -l)  (\$(mc du mac/$BUCKET | awk '{print \$1}'))\"
  echo \"    Server objects: \$(mc ls -r srv/$BUCKET | wc -l)  (\$(mc du srv/$BUCKET | awk '{print \$1}'))\"
"

echo "==> Verifying database"
echo "    Mac:    $(psql_mac 'select count(*) from active_storage_blobs') blobs, $(psql_mac 'select count(*) from users') users"
echo "    Server: $(psql_srv 'select count(*) from active_storage_blobs') blobs, $(psql_srv 'select count(*) from users') users"

rm -rf "$DUMP_DIR"
echo
echo "Done. Now restart CloudVault in Coolify so the API and worker reconnect."
