# CloudVault backlog

Running list of what is asked for but not yet built, newest requests first.
Items move out of here as they ship.

---

## Requested, not started

### Utility area — document tools
A dedicated section for acting on documents rather than just storing them.

- ~~**Sign a PDF**~~ — shipped. Signatures are drawn on a canvas and reused;
  pages render server-side through libvips/poppler so the browser needs no PDF
  library; the unsigned original is kept as a version.
- Merge several PDFs into one, split a PDF, reorder or delete pages
- Rotate pages, compress a PDF, convert images to PDF outside the scan flow
- Extract text (OCR) so scans become searchable — tesseract, and it would feed
  the existing full-text search

### Bulk actions
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
