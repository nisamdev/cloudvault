# CloudVault

Secure cloud storage for a family's files and photos.

Rails 8 API + Vue 3 SPA, run locally as a Docker Compose stack. The design system
and product spec live in [`docs/`](./docs); this README covers running the thing.

---

## Quick start

Requires Docker with the Compose plugin. Nothing else — no local Ruby or Node.

```bash
cp .env.example .env
# Generate real secrets (the committed defaults are placeholders):
sed -i "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$(openssl rand -hex 64)|" .env
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -hex 64)|" .env

docker compose up -d
docker compose run --rm minio-init      # create the object storage bucket
docker compose exec api ./bin/rails db:seed
```

Then open **<http://localhost:5273>** and sign in as `dad@smith.com` /
`password123`.

### Where things listen

CloudVault deliberately avoids the default ports so it can run alongside other
local stacks. All of them are configurable in `.env`.

| Service | URL | Purpose |
|---|---|---|
| Web (Vue) | <http://localhost:5273> | The app |
| API (Rails) | <http://localhost:3100> | JSON API |
| MinIO console | <http://localhost:9101> | Browse uploaded objects |
| Mailpit | <http://localhost:8125> | Catches every outbound email |
| Postgres | `localhost:5532` | |
| Redis | `localhost:6479` | |

---

### Testing on a phone

The dev server accepts any Host, so a tunnel works out of the box:

```bash
cloudflared tunnel --url http://localhost:5273
```

Open the printed `https://….trycloudflare.com` URL on the phone. Scan links,
share links and QR codes are built from the origin the browser actually used, so
they point at the tunnel rather than at `localhost`.

To restrict which hosts the dev server answers, set `VITE_ALLOWED_HOSTS` to a
comma-separated list.

---

## Everyday commands

```bash
docker compose logs -f api           # follow the API
docker compose exec api bash         # shell in the API container
docker compose exec api ./bin/rails console
docker compose exec api ./bin/rails db:migrate
docker compose restart api worker    # after changing initializers or the Gemfile
docker compose down                  # stop
docker compose down -v               # stop and wipe all data
```

### Tests

```bash
docker compose exec -e RAILS_ENV=test \
  -e TEST_DATABASE_URL="postgres://cloudvault:cloudvault_dev_password@postgres:5432/cloudvault_test" \
  api bundle exec rspec
```

### Adding a gem

```bash
docker compose exec api bundle add <gem>
docker compose build api && docker compose up -d api worker
```

---

## Layout

```
backend/     Rails 8 API (api_only). Dockerfile has development + production targets.
frontend/    Vue 3 + Vite + Tailwind v4 SPA.
docs/        Design system, component specs, a11y guidelines, UI prototype.
infra/       Deployment notes (Railway).
```

---

## How it fits together

**Object storage, not local disk.** Uploads go to MinIO locally through the S3
API, and to Cloudflare R2 or AWS S3 in production. Same code path either way — a
mounted disk would not work anyway, since `api` and `worker` are separate
containers that both need the files.

**Config comes from the environment.** No host, credential or URL is hardcoded.
`.env.example` is the full contract; every variable in it is also a variable you
would set on a hosting platform.

**Services wait for their dependencies.** The entrypoint retries Postgres and
Redis rather than assuming start order, so the stack survives restarts and
platforms that have no `depends_on` equivalent.

**Migrations run once.** Only the `api` service has `RUN_MIGRATIONS=true`, so the
worker can never race it on the schema.

### Authentication

| Token | Lifetime | Stored | Notes |
|---|---|---|---|
| Access | 15 min | In memory in the SPA | JWT, sent as `Authorization: Bearer` |
| Refresh | 7 days | httpOnly cookie | Opaque, digest-only in the DB, rotated on every use |

The access token is deliberately **not** in `localStorage` — that would hand it
to any XSS on the page. Refresh tokens rotate, and replaying an already-rotated
token revokes the user's entire session chain on the assumption it was stolen.

Login and registration are rate limited (5 attempts / 20s per IP *and* per email).

---

## Status

**Working end to end**

- Compose stack: Postgres, Redis, MinIO, Mailpit, API, Sidekiq worker, Vue dev server
- **Auth** — register, login, refresh with rotation and replay detection, logout, rate limiting
- **Families** — create, view members, rename; role model (owner / admin / editor / viewer)
- **Invitations** — email invite via Mailpit, public preview page, acceptance, expiry and revocation
- **Files** — upload (drag-and-drop, per-file progress), list with search and pagination, download
  via presigned URL, soft delete and restore, automatic versioning on re-upload, quota accounting
- **Folders** — nested to any depth and listed inline above the files, Drive style: opening one
  shows the subfolders and files inside it. Sidebar tree for navigation, breadcrumbs, inline rename,
  and **drag and drop** to reorganise (row → folder row, row → tree node, row → breadcrumb, row →
  "All files" to move back to the top). Deleting a folder trashes its whole branch.
- **Labels** — colour-coded tags shared across the family, applied per file, usable as a
  cross-cutting filter
- **Photos** — responsive gallery grouped by date (Today / Yesterday / Earlier this week / month),
  lazy-loaded thumbnails, infinite scroll, hover overlay, and the shared lightbox with ← → paging.
  Filter by date (including Today), uploader, visibility, shape, label and whether the photo carries
  a location; sort by date, name or size. Active filters show as removable chips with an
  "N of M match" count
- **EXIF** — capture date, GPS coordinates and camera are read on upload, from JPEG, TIFF **and
  HEIC/AVIF** (iPhone photos)
- **Details panel** — every date (uploaded, taken, modified, last opened, purge date), dimensions,
  megapixels, camera, coordinates with a map link, folder path, labels, visibility, checksum,
  version history and active share links
- **Trash** — restore files and whole folders, delete permanently to reclaim quota, empty the trash,
  with a per-item countdown; a nightly job removes anything past the retention window
- **Scan with your phone** — the desktop shows a QR code; the phone opens a capture page with no
  app and no sign-in, photographs each page, reorders them, and saves them as one PDF or separate
  images into the chosen folder. Pages are straightened by EXIF orientation, capped at 2400px and
  contrast-boosted for legibility
- **Preview** — click a file name (or the eye icon / context menu) to view it in place: images,
  PDFs, video, audio and text render inline; ← → step through the list, Escape closes
- **Context menus** — right-click any file, folder, tree node, label, or empty space; full keyboard
  navigation (arrows, Home/End, Enter, Escape)
- **Folder download** — a whole folder, including everything nested inside, streamed as a ZIP
- **Search** — PostgreSQL full-text over file names plus trigram partial matching and label names,
  scoped to what the caller may see
- **Family sharing** — choose "Only me" or "My family" at upload time, or change it afterwards from
  the share dialog; the file moves in and out of the family vault and its bytes move with it
- **Share links** — create from the file row or straight after upload, optional password and expiry,
  download limits, revocation, and a public landing page that needs no account
- **Images** — uploads classified automatically; Sidekiq generates 300×300 thumbnails with libvips
  and records dimensions
- **Permissions** — enforced server-side by `PermissionChecker` on every request
- **Screens** — sign in, register, family setup, invitation acceptance, dashboard (files)

329 backend specs and 19 frontend tests, all passing.

**Not built yet:** the Shared screen, the Settings screen, OAuth sign-in. Those screens are routed
placeholders that state what belongs on them. See
[`docs/PHASE1_IMPLEMENTATION_GUIDE.md`](./docs/PHASE1_IMPLEMENTATION_GUIDE.md) weeks 4–8.

### Notable design decisions

- **`StoredFile`, not `File`** — a model named `File` shadows Ruby's built-in class.
- **Active Storage over hand-rolled S3 keys** — presigned URLs and image variants come for free.
- **Two storage services** (`s3` and `s3_public` in `config/storage.yml`) — the API reaches MinIO at
  an internal address, but presigned URLs must be signed for the host the *browser* uses, since
  SigV4 covers the Host header and the URL cannot be rewritten afterwards.
- **Downloads return JSON, not a redirect** — the endpoint needs a bearer token that a plain
  `<a href>` cannot send.
- **Re-uploading a file versions it** rather than overwriting; retained versions count against quota.
- **Visibility is not a plain attribute** — it is tied to `family_id` and to the family's storage
  counter, so `FileVisibilityUpdater` moves all three inside one transaction.
- **Storage counters are incremental**, so `rails cloudvault:recalculate_storage` recomputes them
  from the records if they ever drift.
- **Search translates `_ - .` to spaces** before building the tsvector, otherwise
  `Mortgage_Agreement.pdf` is one opaque token and searching "mortgage" finds nothing. A trigram
  index backs the substring fallback for partial words.
- **Folder uniqueness uses `COALESCE(parent_id, 0)`** — Postgres treats NULLs as distinct, so a
  plain unique index never constrains folders at the root.
- **Searching or filtering by label ignores the current folder**, because both are cross-cutting
  questions ("everything tagged Taxes"), not folder-local ones.
- **Permanent deletion goes through `FilePurger`**, not `destroy`, because storage counters are
  maintained incrementally and have to be adjusted in the same transaction. Restoring a file whose
  folder is still in the trash returns it to the root rather than to a folder nobody can reach.
- **PDFs use `<object>`, not `<iframe>`, and are never sandboxed.** Chrome refuses to run its PDF
  viewer inside a sandboxed frame ("This page has been blocked by Chrome"), and `<object>` renders
  its child content as a fallback when the browser has no viewer at all. No sandbox is needed: the
  file is served from object storage on a different origin.
- **Preview serves text through the API, media by URL.** Media gets a short-lived *inline*
  presigned URL the browser loads directly; text is returned in the response body, because reading
  it with `fetch()` would require CORS configured on the storage bucket in every environment.
  SVG is shown as text, not rendered as an image, since it can carry script.
- **ZIP downloads stream** with `zip_kit`, one entry at a time straight from object storage, so a
  large folder never buffers in memory or on disk. Already-compressed types are stored, not
  deflated again.
- **The ZIP link carries a short-lived scoped token** (5 min, bound to one folder id) because a
  browser navigation cannot send an Authorization header. Archive paths are sanitised against
  zip-slip.
- **Links are built from the request's origin**, not from `APP_URL`. A QR code containing
  `localhost` cannot be scanned from a phone, and a share link created through a tunnel has to be
  reachable by whoever receives it. `APP_URL` remains the fallback, which is all a mailer has.
- **The scan token is deliberately weak.** It travels in a URL, so it expires in 20 minutes and can
  only upload — it cannot list, read or delete, and ordinary endpoints reject it because it is not
  an access token. Losing it costs an unwanted upload, nothing more.
- **`<input capture>` rather than `getUserMedia`.** The native camera works over plain HTTP on a
  LAN; `getUserMedia` requires a secure context and would refuse to start on `http://192.168.x.x`.
- **HEIC and TIFF previews are converted to JPEG on demand.** No mainstream browser but Safari
  renders HEIC, so the preview would be a broken image. Active Storage keeps the rendition, so the
  conversion is paid once per photo, and a failed conversion falls back to the original rather than
  breaking the preview. AVIF is served as-is — browsers handle it.
- **The browser's Content-Type is not trusted.** Chrome sends an empty string or
  `application/octet-stream` for `.heic` wherever the OS has no registration for it, which filed
  iPhone photos as documents so they never reached the gallery. Marcel re-detects from the magic
  bytes server-side. `rails cloudvault:reclassify_files` repairs anything already misfiled.
- **EXIF is best-effort.** It is absent from screenshots and PNGs, and messaging apps strip it, so
  every failure path returns nothing rather than raising. Cameras with a dead clock battery report
  1970-era dates, which are rejected. EXIF carries no timezone, so times are read as UTC rather
  than inventing an offset.
- **Dates mean upload time throughout** — filters, sorting and the gallery's date headings all use
  it, so they always agree. Capture date is shown in the details panel and offered as an explicit
  "Newest taken" sort rather than silently changing what a date means.
- **Date filters resolve in the viewer's timezone** (`users.timezone`), because the gallery's
  "Today" heading uses the browser's clock — interpreting the filter in UTC would disagree with the
  heading for anyone east of Greenwich.
- **Files and Photos are separate listings**, as the docs specify — documents in My Files, images in
  the gallery. Search deliberately spans both, since "where did I put that" does not care which
  section something lives in.
- **Confirmations and prompts are in-app dialogs**, not `window.confirm` / `window.prompt`: the
  native ones cannot be styled, are inconsistent across browsers, and block the event loop.
  `useDialog()` keeps the promise-based call shape, so call sites still read as one line.
- **Drag state lives in a shared composable**, not in the dragged component: a drag starts in the
  listing and often ends in the sidebar, and `dataTransfer` cannot be read during `dragover` —
  exactly when the drop target has to decide whether to accept.
- **Share tokens are digest-only** and the URL is returned exactly once, at creation. Unknown,
  expired, revoked and exhausted links all get one identical response, so probing tokens reveals
  nothing.

## Deployment

See [`infra/railway/README.md`](./infra/railway/README.md). Short version:
Railway does not run `docker-compose.yml` — each service becomes its own Railway
service, and this stack was built so that lift is configuration only.
