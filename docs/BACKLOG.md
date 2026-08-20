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

### Sharing and privacy
- **Strip EXIF from files served through public share links.** Photos carry GPS,
  so a shared holiday photo currently leaks where it was taken. Family members
  should keep the metadata; only the public path should be stripped.

### Bulk actions
- Multi-select with shift-click ranges, then download as ZIP, label, move,
  share or trash in one action

### Gallery
- Map view of photos that carry coordinates
- Slideshow in the lightbox
- Zoom and pan in the preview

### Screens still stubbed
- **Shared** — shared-with-me, plus managing every link in one place
- **Settings** — profile, password change, active sessions, family members,
  storage breakdown

### Deployment
- Railway config exists (`infra/railway/`) but has never been run
- TLS for phone access: Tailscale, or Caddy with a local CA. Needed before
  trusting this with passports over anything but localhost

---

## Shipped

- **PDF signing** (2026-08-20) — rebuilt as a full-page editor after review,
  following the LocalSign side project: tool palette, click-to-place fields
  (text, date, checkbox, signature, initials), drag and resize, draw/type/reuse
  signatures. `PdfFieldStamper`, `PdfPageRenderer`, `SignEditorView`.
  Still worth taking from LocalSign: assigning fields to other people and
  sending signing requests by email, plus the audit log it keeps.

---

## Notes

Anything touching PDFs should reuse the version history that already exists —
signing, merging and page edits are all destructive operations where keeping the
original matters more than saving space.
