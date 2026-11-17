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
#   - `ssh yegstack` works (password or key; you'll be prompted once)
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
SERVER_ENV="${1:?usage: $0 path/to/server.env [--files-only]}"
# --files-only: skip the database entirely and just copy any files the server
# is missing (mc mirror only transfers what differs). Safe to re-run any time.
FILES_ONLY=0; [ "${2:-}" = "--files-only" ] && FILES_ONLY=1
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

# -f: ssh asks for the password in the FOREGROUND, and only backgrounds itself
# once the login succeeded and the forwards are listening. -M/-S give us a
# control socket so we can check, reopen and close exactly this tunnel.
CTL_SOCK="${TMPDIR:-/tmp}/cv-migrate-$$.sock"
SSH_LOG="${TMPDIR:-/tmp}/cv-migrate-ssh.log"
tunnel_up() { ssh -S "$CTL_SOCK" -O check "$SSH_HOST" 2>/dev/null; }
open_tunnel() {
  tunnel_up && return 0
  echo "==> Opening SSH tunnel to $SSH_HOST (Postgres :15532, MinIO :19100)"
  echo "    (enter your SSH password if asked; run 'ssh-copy-id $SSH_HOST' once to stop the prompts)"
  rm -f "$CTL_SOCK"
  ssh -f -N -M -S "$CTL_SOCK" -E "$SSH_LOG" \
    -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=8 -o TCPKeepAlive=yes \
    -L "$TUNNEL_DB_PORT:127.0.0.1:15532" \
    -L "$TUNNEL_MINIO_PORT:127.0.0.1:19100" \
    "$SSH_HOST" || { echo "SSH tunnel failed to start (see $SSH_LOG)" >&2; return 1; }
  echo "    tunnel up"
}
trap 'ssh -S "$CTL_SOCK" -O exit "$SSH_HOST" 2>/dev/null || true' EXIT
open_tunnel || exit 1

psql_mac() { docker run --rm -e PGPASSWORD="$MAC_PG_PASS" $PG_IMAGE psql -h $H -p "$MAC_PG_PORT" -U "$MAC_PG_USER" -d "$MAC_PG_DB" -tAc "$1"; }
psql_srv() { docker run --rm -e PGPASSWORD="$SRV_PG_PASS" $PG_IMAGE psql -h $H -p $TUNNEL_DB_PORT -U "$SRV_PG_USER" -d "$SRV_PG_DB" -tAc "$1"; }

echo "==> Checking both databases are reachable"
# Abort here rather than ask for confirmation against a side we can't see.
mac_blobs=$(psql_mac 'select count(*) from active_storage_blobs') || { echo "Cannot reach the MAC database (is 'docker compose up -d postgres minio' running?)" >&2; exit 1; }
srv_blobs=$(psql_srv 'select count(*) from active_storage_blobs') || { echo "Cannot reach the SERVER database through the tunnel (is CloudVault's postgres running in Coolify?)" >&2; exit 1; }
echo "    Mac:    $mac_blobs stored files (blobs), $(psql_mac 'select count(*) from users') users"
echo "    Server: $srv_blobs stored files (blobs), $(psql_srv 'select count(*) from users') users"

if [ "$FILES_ONLY" -eq 0 ]; then
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
  rm -rf "$DUMP_DIR"
else
  echo "==> --files-only: database untouched, copying missing files only"
fi

# One mc container per step, both aliases set each time.
mc_sh() {
  docker run --rm --entrypoint sh -e MC_CONFIG_DIR=/tmp/.mc $MC_IMAGE -c "
    mc alias set mac http://$H:$MAC_S3_PORT '$MAC_S3_KEY' '$MAC_S3_SECRET' >/dev/null &&
    mc alias set srv http://$H:$TUNNEL_MINIO_PORT '$SRV_S3_KEY' '$SRV_S3_SECRET' >/dev/null &&
    $1"
}

# Verify: mc diff must succeed with NO errors and list no '<' (Mac-only) lines.
# Any error (tunnel down, auth) is a failure, never "0 missing".
verify_files() {
  mc_sh "
    mc diff mac/$BUCKET srv/$BUCKET >/tmp/diff 2>/tmp/err; rc=\$?
    if [ \$rc -ne 0 ] || [ -s /tmp/err ]; then echo '    check FAILED (could not compare):'; head -3 /tmp/err 2>/dev/null; exit 3; fi
    n=\$(grep -c '^<' /tmp/diff || true)
    echo \"    Mac: \$(mc ls -r mac/$BUCKET | wc -l) files   Server: \$(mc ls -r srv/$BUCKET | wc -l) files   missing on server: \$n\"
    [ \"\$n\" -eq 0 ] || { grep '^<' /tmp/diff | head -5; exit 2; }
  "
}

# mc mirror only sends objects that are missing or differ, so each pass picks up
# where the last one stopped. The tunnel is checked (and reopened) every pass.
echo "==> Copying files (bucket '$BUCKET')"
copied=0
for pass in 1 2 3 4 5 6 7 8 9 10; do
  open_tunnel || { sleep 5; continue; }
  echo "    pass $pass"
  mc_sh "mc mb -p srv/$BUCKET >/dev/null; mc mirror --overwrite --retry mac/$BUCKET srv/$BUCKET" || true
  open_tunnel || continue
  if verify_files; then copied=1; break; fi
  [ -s "$SSH_LOG" ] && { echo "    ssh said: $(tail -1 "$SSH_LOG")"; }
  echo "    not complete yet, next pass in 5s..."; sleep 5
done
if [ "$copied" -ne 1 ]; then
  echo "File copy still incomplete after 10 passes. Re-run with --files-only." >&2
  exit 2
fi
echo "    OK: every Mac file is on the server (verified)"

open_tunnel || exit 1
echo "==> Verifying database"
echo "    Mac:    $(psql_mac 'select count(*) from active_storage_blobs') blobs, $(psql_mac 'select count(*) from users') users"
echo "    Server: $(psql_srv 'select count(*) from active_storage_blobs') blobs, $(psql_srv 'select count(*) from users') users"

echo
if [ "$FILES_ONLY" -eq 0 ]; then
  echo "Done. Now Redeploy CloudVault in Coolify so the API and worker reconnect."
else
  echo "Done. No restart needed: files are picked up immediately."
fi
