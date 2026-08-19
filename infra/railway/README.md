# Deploying CloudVault to Railway

**Railway does not run `docker-compose.yml`.** There is no Compose orchestrator on
the platform. Each service in our compose file becomes its own Railway service
inside one Railway project, connected by environment variables over Railway's
private network. Compose stays the local mirror of that topology.

Confirmed against Railway's own guide: Dockerfiles, images, volumes and env vars
map across cleanly, but **`depends_on` has no equivalent** — services boot in
arbitrary order and must tolerate a dependency not being ready yet.
See <https://docs.railway.com/guides/docker-compose>.

---

## Service map

| compose service | Railway service | Notes |
|---|---|---|
| `postgres` | **Managed Postgres** (add from the canvas) | Don't deploy the raw image; the managed one gets backups and metrics |
| `redis` | **Managed Redis** | Same reasoning |
| `api` | Docker service, root dir `backend/` | Public domain. Config: `backend/railway.json` |
| `worker` | Docker service, root dir `backend/` | **No** domain. Config path: `backend/railway.worker.json` |
| `web` | Docker service, root dir `frontend/` | Public domain. Config: `frontend/railway.json` |
| `minio` | **Cloudflare R2 or AWS S3** | See "Object storage" below |
| `mailpit` | **Resend / SendGrid / Postmark SMTP** | Mailpit is a dev-only mail trap |
| `minio-init` | — | One-shot bucket creation; do it once by hand |

Both backend services build the *same* Dockerfile and differ only in start
command, which is why `worker` needs its config file path pointed at
`railway.worker.json` (Service → Settings → Config as code).

---

## Step by step

### 1. Create the project and data stores

```bash
railway login
railway init -n cloudvault
```

In the project canvas: **+ New → Database → PostgreSQL**, then again for
**Redis**. Both expose reference variables (`${{Postgres.DATABASE_URL}}`,
`${{Redis.REDIS_URL}}`) that other services can point at.

### 2. Object storage

MinIO has no managed equivalent. Two options:

- **Recommended — Cloudflare R2** (S3-compatible, zero egress fees). Create a
  bucket and an API token, then set the `S3_*` variables. No code changes: the
  app already talks to S3 through `config/storage.yml`.
- **MinIO on Railway** — deploy `minio/minio`, attach a Volume at `/data`, and
  point `S3_ENDPOINT` at `minio.railway.internal:9000`. Works, but you own the
  backups, and Railway allows only one volume per service.

Create the bucket once after the API is deployed:

```bash
railway run --service api bundle exec rails cloudvault:ensure_bucket
```

### 3. Deploy the three app services

For each: **+ New → GitHub Repo → this repo**, then Settings → **Root Directory**
(`backend` or `frontend`). Railway reads the `railway.json` in that directory.

Generate a public domain for `api` and `web` only. The worker must not have one.

### 4. Variables

Set these on **api** and **worker** (identical, apart from the two marked):

| Variable | Value on Railway |
|---|---|
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` |
| `RAILS_ENV` | `production` |
| `SECRET_KEY_BASE` | `openssl rand -hex 64` — fresh, never the dev value |
| `JWT_SECRET` | `openssl rand -hex 64` — fresh |
| `RUN_MIGRATIONS` | `false` — migrations run via `preDeployCommand` instead, so they happen once per deploy rather than once per replica |
| `ENSURE_BUCKET` | `false` |
| `RUN_SIDEKIQ_IN_PROCESS` | `false` (see cost note below) |
| `S3_ENDPOINT` | R2/S3 endpoint |
| `S3_BUCKET`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | from your provider |
| `S3_FORCE_PATH_STYLE` | `true` for R2/MinIO, `false` for AWS S3 |
| `APP_URL` | `https://${{web.RAILWAY_PUBLIC_DOMAIN}}` |
| `API_URL` | `https://${{api.RAILWAY_PUBLIC_DOMAIN}}` |
| `CORS_ORIGINS` | `https://${{web.RAILWAY_PUBLIC_DOMAIN}}` |
| `ALLOWED_HOSTS` | `${{api.RAILWAY_PUBLIC_DOMAIN}}` |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USER_NAME`, `SMTP_PASSWORD` | from your mail provider |
| `SMTP_STARTTLS` | `true` |
| `MAIL_FROM` | e.g. `no-reply@yourdomain.com` |

On **web**, only two:

| Variable | Value |
|---|---|
| `API_URL` | `https://${{api.RAILWAY_PUBLIC_DOMAIN}}` |
| `APP_ENV` | `production` |

`web` needs no build-time variables. The API URL is written into `/config.js`
when the container starts, so the same image works in staging and production.

### 5. Verify

```bash
curl https://<api-domain>/up                 # 200 once boot succeeds
curl https://<api-domain>/api/v1/health      # checks Postgres, Redis and storage
curl https://<web-domain>/healthz            # nginx is serving
curl https://<web-domain>/config.js          # should show the API domain
```

---

## Things that will bite you

**Bind to `$PORT`.** Railway assigns the port at runtime; a hardcoded one makes
the container unreachable and the healthcheck fail. Both start commands already
read `$PORT`.

**No `depends_on`.** The API may boot before Postgres accepts connections.
`backend/docker/entrypoint.sh` retries both Postgres and Redis for up to two
minutes rather than crash-looping.

**Private networking is IPv6-only** and uses `<service>.railway.internal`, not
the bare service name that compose uses. Always use reference variables
(`${{Postgres.DATABASE_URL}}`) rather than typing hostnames.

**Healthchecks arrive over plain HTTP** on the internal address. `force_ssl` is
on in production but `/up` is excluded from the HTTPS redirect
(`config/environments/production.rb`) — without that exclusion every deploy fails
its healthcheck.

**Migrations belong in `preDeployCommand`**, already set in
`backend/railway.json`. Running them from the entrypoint means every replica
races to migrate on every boot.

**Cost.** `api` + `worker` + `web` + Postgres + Redis is five always-on services.
To run three instead, set `RUN_SIDEKIQ_IN_PROCESS=true` on the API and delete the
worker service — the entrypoint then starts Sidekiq beside Puma in the same
container. Fine for a demo; separate them again once upload volume grows.

**Volumes are one per service** and are not shared. This is why user uploads go
to object storage rather than a mounted disk — otherwise `api` and `worker`
couldn't both reach the same files.
