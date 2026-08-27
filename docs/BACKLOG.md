# CloudVault backlog

Running list of what is asked for but not yet built, newest requests first.
Items move out of here as they ship.

---

## Requested, not started

### Utility area — document tools
The Tools section exists. Remaining tools, in the order they are planned:

- ~~**Sign a PDF**~~ — shipped.
- ~~**Merge PDFs**~~ — shipped.
- ~~**Photos to PDF**~~ — shipped, as part of the scanner.
- ~~**Rearrange pages**~~ — shipped.
- ~~**Split a PDF**~~ — shipped.
- ~~**Read a document**~~ — shipped.
- ~~**OCR**~~ — shipped: Read a document falls back to tesseract when a PDF has
  no text layer (scans). Needs `tesseract-ocr` in the API image.

### Household register (Steps 4+ — see HOUSEHOLD_REGISTER.md)
Plan: [HOUSEHOLD_REGISTER.md](./HOUSEHOLD_REGISTER.md). Done through Step 3.

- **Next: Step 4** — polish remaining record types (Person, Property, Immigration,
  Vehicle, Money, Subscription, Emergency) the way Login was done
- Links UI — `record_links` exists in the API; no picker on the record page yet
- Step 5 — password generator in the web app
- Step 6 — expiry reminders
- Steps 7–14 — vault permissions, short-term sharing, TOTP, TLS, browser-side
  encryption, Chrome extension, `vault:backup:images`, admin

### Files
- Multi-select with shift-click ranges, then download as ZIP, label, move,
  share or trash in one action

### Gallery
- Map view of photos that carry coordinates
- Slideshow in the lightbox
- Zoom and pan in the preview

### Deployment
- Railway config exists (`infra/railway/`) but has never been run
- TLS for phone access: Tailscale, or Caddy with a local CA. Needed before
  trusting this with passports over anything but localhost

---

## Shipped

- **`vault:backup` — the cheap half** (2026-08-26) — Step 3 of the household
  register plan. `bin/rails vault:backup` writes an encrypted `.vault` file:
  full Postgres dump plus document blobs (`file_type: file`), not the photo
  gallery. Passphrase via `BACKUP_PASSPHRASE` or a prompt; output under
  `tmp/backups` or `BACKUP_OUTPUT_DIR`. Envelope encryption reuses `VaultCipher`.
  `vault:backup:images` is still Step 13.

- **Household register Steps 1–2** (2026-08-26) — records as facts, not just
  files. Tables (`vault_records`, attachments, links, `record_secrets`,
  `secret_versions`), eight household templates plus a **Login** type (name,
  site URL, username, password), Register card grid with favicons/initials,
  create/detail pages, link/upload from My Files, reveal/copy/history for
  secrets sealed with the private-section vault key (key-agnostic `kdf`
  format). Routes under `/household` so they do not collide with auth signup.

- **Private section** (2026-08-26) — passphrase-locked place for files and
  folders; AES-256-GCM with a vault key sealed by scrypt; unlock token in
  `X-Vault-Key` (memory only, not a cookie). Settled as real encryption, not
  a soft hide.

- **Read a document** (2026-08-26) — the text inside a PDF, and the handful of
  things in it worth reading: labelled fields, dates, amounts, references,
  emails and phone numbers, each copyable on its own. Running headers, page
  numbers and boilerplate paragraphs are dropped, which is the difference
  between this and a page of extracted text. `PdfTextExtractor` (pdf-reader),
  `KeyDetails`, `GET /files/:id/text`, `PdfTextTool`. The PDF preview grew a
  "Copy the text" button off the same endpoint.
  It only reads text that is *in* the file; a scan has none, and says so.

- **Split a PDF** (2026-08-26) — a run of pages out as a document of its own,
  chosen by clicking the pages. Writes a new file and leaves the original
  alone, which is the opposite of what rearranging does and deliberately so.

- **Rearrange pages** (2026-08-26) — reorder, turn and drop pages inside a PDF.
  The API takes the finished layout rather than a list of moves, so the two
  sides cannot drift apart, and the result lands as a new *version* of the same
  file — the note at the bottom of this file, applied. `PdfPageArranger`,
  `PATCH /files/:id/pages`, `PdfPagesTool`.

- **A photographed document is a document** (2026-08-26) — `file_type` followed
  the mime type, so a scanned certificate lived in the photo gallery for ever.
  Right-click → "This is a document" moves it to My Files (and back), keeping
  its thumbnail, and `file_type_pinned` stops a later re-upload undoing the
  choice.

- **Scanner** (2026-08-26) — photographs of a document into a scan: a crop with
  draggable corners that straightens perspective, an auto-guess at where the
  page is, four looks (including shadow removal, which is what makes a photo
  read as a scan), page reordering, and a save as one PDF or as PNGs. The
  imaging runs in the browser so the preview and the saved file come out of the
  same code; the API only assembles the document (`ImagePdfBuilder`,
  `utilities#images_to_pdf`). Photos already in the vault can be pulled into it,
  which needed `files#preview?via=proxy` — a canvas cannot read back pixels it
  drew from another origin.
  Not done: the phone capture page (`/scan/:token`) still uploads originals for
  the server to process, rather than using this editor.

- **Inline renaming** (2026-08-26) — files rename in the row, as folders
  already did, with the extension left out of the selection. `InlineName` is
  now shared by both.

- **Inviting a family member from Settings** (2026-08-20) — there was no way to
  do it outside the one-time setup flow, which itself said "do it from
  Settings". The link is now returned once on creation and shown to copy, not
  only emailed: this is a home server where SMTP may not exist. It is built from
  the origin the browser used, so an invite opened on a phone works.

- **EXIF stripped from public links** (2026-08-20) — a photo sent to someone
  outside the family no longer says where it was taken. JPEG and PNG are edited
  at the container level so nothing is recompressed; HEIC has no encoder in this
  libvips build, so it is re-encoded to JPEG and both the filename and the share
  page say so. Family downloads are untouched.

- **Settings screen** (2026-08-20) — profile, password change, signed-in
  devices, family roles and a storage breakdown. Changing a password ends every
  other session; each device can be signed out on its own, which is what a lost
  phone needs. Ownership is deliberately not a role you can pick from the
  dropdown. Last stubbed screen.

- **Storage URLs that work off this machine** (2026-08-20) — presigned URLs were
  always signed for `S3_PUBLIC_ENDPOINT` (`localhost:9100`), which is the
  visitor's own machine over a tunnel, so every download, preview and thumbnail
  failed from outside. `StorageUrl` now decides per request: presign when
  storage is genuinely reachable, otherwise stream through
  `Api::V1::BlobsController`. Serving user bytes from our own origin means
  uploads that could run script (html, svg) are forced to download.

- **Shared screen** (2026-08-20) — two tabs, because "shared" means two
  different things: what the family put here that I did not
  (`GET /files?shared_with_me=true`), and every public link I have out
  (`GET /shares`) with expiry, download count and revoke. Link URLs are not
  shown — they are returned once, at creation, and only a digest is stored.

- **PDF signing** (2026-08-20) — rebuilt as a full-page editor after review,
  following the LocalSign side project: tool palette, click-to-place fields
  (text, date, checkbox, signature, initials), drag and resize, draw/type/reuse
  signatures. `PdfFieldStamper`, `PdfPageRenderer`, `SignEditorView`.
  Still worth taking from LocalSign: assigning fields to other people and
  sending signing requests by email, plus the audit log it keeps.
- **Signature management + phone capture** (2026-08-20) — defaults, rename,
  delete, and a QR link to draw one with a finger.

---

## Notes

Anything touching PDFs should reuse the version history that already exists —
signing, merging and page edits are all destructive operations where keeping the
original matters more than saving space.

The private section chose real encryption (vault key + passphrase). A forgotten
passphrase without the recovery key loses those files for good — that is the
trade, and it is intentional.
