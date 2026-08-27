# The Household Register

The plan for turning CloudVault from a place that keeps files into one that keeps
*facts* — which email the electricity account uses, when the visa expires, what
the gas meter number is.

Read version: <https://claude.ai/code/artifact/33493200-96d1-4175-86b5-0f0da2b0c307>
Agreed 26 August 2026. Update this file when the plan changes; it is the one
that lives with the code.

---

## I. The shift

Everything in CloudVault today is a file. That works for a scanned passport. It
does not work for "which email did I use for the electricity account", or "when
does the residence permit expire". Those aren't documents. They are **facts with
fields**.

So the model gains one new thing: a **record**. A record has a type, a set of
fields, some secrets, and any number of scans attached to it. Files stay exactly
as they are, and become something a record can hold.

Get this right and service credentials, property details, the password vault and
short-term sharing are all the same feature wearing different clothes. Get it
wrong and you end up with a folder called `Property` full of PDFs you have to
open to learn anything.

## II. How records work

Six parts make up a record:

| Part | What it is |
|---|---|
| **title** | What you'd call it out loud. "British Gas — electricity". "The house". |
| **type** | Decides which fields it starts with. A template, not a cage. |
| **fields** | The facts. Searchable, sortable, plain in the database. |
| **secrets** | Passwords and security answers. Encrypted, never searchable, never in a listing. |
| **attachments** | The scans that prove it. Ordinary CloudVault files. |
| **links** | Other records this one relates to. |

Five small tables. Fields live in JSONB so a type can grow without a migration.

```
vault_records
  id             bigint
  family_id      bigint      — whose register this belongs to
  user_id        bigint      — who added it
  record_type    string      — service_account | property | immigration | …
  title          string
  data           jsonb       — the fields, shaped by the type's template
  visibility     string      — private | family
  locked         boolean     — lives in the private section, same passphrase
  archived_at    timestamp
  search_vector  tsvector    — generated from title + data, GIN indexed

record_secrets              — separated on purpose: different rules, different key
  record_id      bigint
  key            string      — "password", "security_answer"
  sealed         bytea       — AES-256-GCM; nothing here says who holds the key
  kdf            jsonb       — parameters needed to open it, wherever that happens
  updated_at     timestamp

secret_versions             — the old password, for when a site says it changed and lied
  secret_id      bigint
  sealed         bytea
  replaced_at    timestamp

record_links
  record_id      bigint
  linked_id      bigint
  relation       string      — insured_by | billed_to | owned_by | lives_at

record_attachments
  record_id      bigint
  stored_file_id bigint      — the scan, as an ordinary CloudVault file
```

Secrets sit in their own table rather than inside `data` because they follow
different rules: encrypted, never searchable, never returned in a list, fetched
one at a time on "reveal". Mixing them into the same JSONB blob would mean every
listing query touches ciphertext it has no business touching.

## III. What a family keeps

A template says which of its own fields names the record, in `title_from`:
**Person** is named by `full_name`, **Login** by `name`. Typing "Aisha Rahman"
into a Title box and then again into Full name is the kind of small stupidity
that makes a register feel like paperwork.

A document is not named that way, and the field cannot be guessed from its
name — a passport also carries a full name, and naming the record after it
leaves somebody with four records all called their own name. So a scanned
document is named for whose it is *and* what it is: "Aisha Rahman — Passport".

Fourteen starting templates. Every record also takes custom fields invented on
the spot.

- **Login** — a plain website account: site, username, *password*
- **Service account** — provider, account email, username, website, customer ref,
  *password*, *security answers*
- **Immigration** — document type, country, document no., issued, **expires**,
  sponsor, application ref, conditions, scan
- **Property** — address, owned/rented, purchase date, title number, council tax
  ref, gas meter, electric meter, deed
- **Person** — full name, date of birth, national ID, blood group, relationship.
  Who somebody *is*. What they hold is a document of its own, linked back with
  `held_by`
- **Passport** — full name, passport no., nationality, date & place of birth,
  issued, **expires**, place of issue, authority, scan
- **Driving licence** — full name, licence no., date of birth, issued,
  **expires**, authority, entitlements, address, scan
- **Birth certificate** — full name, date & place of birth, entry no.,
  registered, district, mother, father, scan. Nothing on it expires
- **Health card** — full name, NHS or health number, date of birth, GP, blood
  group, **expires** (a GHIC does; an NHS number does not), scan
- **Document** — the catch-all: what it is, held by, reference, issued,
  **expires**, issued by. Somewhere to put a marriage certificate without
  inventing a template for it
- **Vehicle** — registration, make & model, VIN, **insurance renewal**, **MOT
  due**, V5C
- **Money** — institution, account name, sort code, account no., policy no.,
  maturity date
- **Subscription** — service, cost, billing cycle, next charge, paid with,
  cancel by
- **In case of emergency** — where the will is, executor, solicitor, key holders,
  who to call

## IV. Records that know about each other

This is what makes it a register rather than a list. A house is not one record —
it is a knot of them:

```
"The house"
  owned by        → Nisam & family              (Person)
  mortgaged with  → Halifax, account 4471-8829  (Money)
  insured by      → Northgate, renews 1 April   (Money)
  billed to       → British Gas                 (Service account)
  billed to       → Yorkshire Water             (Service account)
  documents       → Title deed · Survey · Schedule
```

Each link is one row and the relation is a plain word, so the record page reads
as a sentence rather than a table. Because the insurance renewal is a `date`
field on a linked record, the reminder engine finds it without anyone tagging
anything.

## V. Where secrets live

Record secrets use the private section's existing vault key and unlock. One
passphrase, one mental model — *private means passphrase*, whether it's a scan or
a password.

Because the Chrome extension is happening, **the ciphertext must not care who
holds the key**. Every sealed secret carries its own parameters and nothing that
assumes the server did the sealing. Moving to browser-side encryption is then a
change to *who unlocks*, not a migration that re-encrypts every password.

That format decision goes in from the first commit. It costs nothing now and is
the difference between the extension being a feature and being a rewrite.

**Limits, honestly:** someone with the disk or the database gets nothing — that
is real and already tested. Someone on the running server while the section is
unlocked can reach the key. That is the limit of server-side decryption, and
exactly the limit browser-side encryption removes.

## VI. Sharing a password for a while

Two shapes, because they are different problems.

**To someone in the family, until a date.** The access grant that already shares
files, with an `expires_at`. While your section is unlocked the secret is opened
and re-sealed for the recipient, so the share stands on its own — they never
touch your key, and revoking does not need you online. Audited: who has what,
until when.

**To someone outside, once.** A burn-after-reading link, built on the shared-link
machinery that already carries expiry and download limits. The secret is sealed
with a random key that lives in the URL fragment — the `#…` part browsers never
send to the server. CloudVault stores ciphertext it cannot open. The link *is*
the key.

**The honest part:** an expiring share stops *future* access. It cannot un-see a
password someone already read. When a share on something that matters ends, the
real answer is to rotate it — which is why "share expired → generate a new one →
update the record" should be three clicks.

## VII. Making passwords

In the extension and in the web app, because credentials get created in both.

- **random** — length slider, character classes, and an option to drop the
  look-alikes (`l 1 I O 0`) for when it has to be read aloud or typed into a
  television
- **passphrase** — four or five words, a separator, optional capitals and a
  number, for the handful a human has to remember
- **strength** — shown as how long it would take to guess, not a coloured bar
  with no units
- **history** — replacing a password keeps the old one; sites reject changes more
  often than they admit

Generated in the browser with `crypto.getRandomValues`, using rejection
sampling — a byte taken modulo 26 makes the first six letters likelier than the
rest, which quietly costs entropy. Nothing reaches the server until it has been
chosen and saved.

The wordlist is 1,996 short, common, unambiguous words — about 11 bits each,
which is better than the EFF short list. Six words is the default and works out
at roughly 75 bits, or thousands of years of guessing at ten billion a second.
Capitalising every word adds nothing an attacker has to guess, and the strength
figure says so rather than flattering it.

## VIII. Who can use the vault

Adults for certain, and choosable even among adults. A switch per person in
Family settings:

```
family_members
  role            string   — owner | editor | viewer  (already exists)
  can_use_vault   boolean  — defaults: owner ✓  editor ✓  viewer ✗
  vault_note      string   — why it was turned off, for the owner's memory
```

**Two things that are easy to confuse.** Your own private section is yours alone;
nobody sees inside it without your passphrase — not the owner, not an admin, not
this setting. That is arithmetic, not policy. This setting governs *shared family
credentials*: whether a member can be given the household logins, and whether the
vault appears for them at all.

## IX. The Chrome extension

Talking to your own server, on your own network. Fill, capture, generate, unlock.

**The app works entirely without it.** Records, secrets, the generator, sharing,
reminders, scanning — all of it, on any browser including a phone, with nothing
installed. The extension adds one thing: filling and capturing logins on *other*
websites, where the web app cannot reach. Browser-side encryption does not change
that either — the web app is a browser too, and unlocks the same way.

Adds to the server: a stable local origin, CORS for the extension id, and a
pairing flow that isn't "paste your password into a popup and hope".

## X. Decisions

Settled:

- **Fields stored as JSONB + a template per type.** Adding "biometric appointment"
  to Immigration in month two is a code change, not a migration.
- **Built-in templates, custom fields anywhere.** A full type builder is a rabbit
  hole; custom fields cover nearly all of it.
- **Key-agnostic sealed format from the first commit**, because the extension is
  confirmed.

## XI. Signing in

An authenticator app on login, nothing more. A TOTP secret per user, one-time
recovery codes shown once at enrolment, and turning it off requires the current
code. About a day with `rotp`.

This is a **different lock from the private section**: TOTP protects the account,
the passphrase protects the encrypted records. Someone who steals a session still
cannot open the vault. Keep that separation.

Other services' TOTP seeds are deliberately *not* stored — a second factor kept
in the same box as the first is not a second factor.

## XII. Expiry reminders

The feature that turns a filing cabinet into something useful. Mark a date field
as an expiry; a nightly job emails whoever should care.

`Read a document` already extracts dates from PDFs and OCR makes it work on
scans, so most of this exists. Immigration dates get the longest runway — six
months, then three, then one. A permit renewal is not a fortnight's job.

## XIII. Backups, on command

Manual. Nothing scheduled.

| Command | What it does |
|---|---|
| `bin/rails vault:backup` | Everything but the images — database, sealed keys, records, folders, documents. Small and quick. Run it whenever. |
| `bin/rails vault:inspect FILE=…` | Opens the manifest and stops. Tells you the passphrase is right *before* anything is touched. |
| `bin/rails vault:restore FILE=…` | Puts it back. Refuses a database that already has users unless `FORCE=1`. |
| `bin/rails vault:backup:images` | The photo library, as its own archive. The expensive one. Run occasionally, keep fewer copies. |

Files are archived under a path a person can read — `files/12/deed.pdf`, not
`files/<random key>` — so the archive is useful opened by hand. The manifest
carries the path-to-blob map, which is what lets a restore put each one back
under the key the restored database expects.

**Proven, not assumed:** the round trip has been run — back up, wipe, restore
into an empty database, and an encrypted record secret still decrypts. Two bugs
turned up doing it, both invisible until a restore was attempted: the inner
archive was never flushed (every backup truncated), and the decrypted archive
was deleted mid-restore by Ruby's Tempfile finalizer.

Both encrypted on the way out, so a copy can sit on an external drive or anywhere
else without having to trust where it lands.

Splitting them was the right instinct: the half holding passwords, deeds and
permit numbers costs nothing to copy, so it can be copied often.

## XIV. The admin section

Last. Everything it does works from a Rails console until it doesn't.

When it comes: list families and users, change storage quotas, suspend an
account, see real storage use, read an audit trail. Separate from the family UI —
different sign-in, different layout, **no access to file contents**. An admin who
can reset quotas but cannot open a private section is a much safer thing to
build, and once the extension holds the key that stops being a promise.

---

## Scanning a document into a record

Photograph a passport, pick what it is, and get a filled-in form to check. No
model involved, and none needed.

**You say what the document is.** That single choice removes the hardest part —
working out what a document is from its text — and leaves the part machines are
good at: pulling known fields out of a known shape.

**The documents worth filing are machine-readable by design.** A passport or a
residence permit carries a machine-readable zone: fixed columns and *check
digits*. It can be parsed exactly and then verified, so the document itself says
whether it was read correctly. A UK licence number encodes the surname, birth
date and sex of the holder, so the card carries its own second opinion. An NHS
number has a modulus-11 check digit. An LLM would be less accurate here, and
could not check itself.

Proved on a photographed page with no text layer: tesseract misread `UTO` as
`UT0`, and the check digits still produced the right date of birth.

**It suggests; it never files.** Everything comes back as a form to confirm. That
means imperfect reading is still worth having — correcting two fields beats
typing eleven — and a wrong guess is never quietly saved.

The pages become a PDF, which is both what gets attached to the record and what
gets read. One artefact, so the thing kept is exactly the thing that was read,
and it is already in the format you would send to somebody.

**The phone is the camera; the computer does the rest.** The register has its
own QR code. The phone opens it, asks which document this is, takes the
photograph and sends it — and stops there. The desktop opens the right form on
its own, and that form runs the whole finish: straighten the pages, build the
PDF, read it, fill itself in, and show the scan beside the fields to check
against.

Splitting it there is the whole point. Trimming a photograph and deciding
whether a machine read a passport number correctly are both things somebody has
to *look* at, and a phone is the worst screen in the house to look at them on.
Nothing is filed until the person has been through it: the pages wait as
unattached blobs behind a signed id that expires in two hours, and a nightly
sweep releases whatever nobody came back for.

Two things this cost, both found by testing rather than by reading:

- The phone's "document" style lifts contrast with a histogram stretch, which
  helps a person read a photo and clips a crisp page until tesseract sees
  nothing. Pages being kept still get it; pages being read do not.
- A licence number cannot be looked for by its edges. OCR puts a space where the
  card prints one and hangs a stray letter off the end where the card has a
  border, so a pattern anchored on word boundaries finds nothing on a real
  photograph. It is found instead by sliding a sixteen-character window along
  the long runs until one has the right shape.

The card carries no check digit, so "confirmed" can only mean the number
agreeing with what is printed beside it — the licence number encodes the date of
birth and the surname, and those two readings agreeing is as close to a check
digit as the document gets. Where they disagree, the value is still offered and
simply not vouched for.

`DocumentPresets`, `DocumentExtractors::{Mrz,DrivingLicence,HealthCard}`,
`DocumentReader`, `POST /document_captures`, `GET /document_captures/page/:id`,
`purpose` on the scan session, and `PurgeHeldScansJob`.

## Still open, outside the numbered steps

- **The design pass stopped halfway.** Records, their forms and the type picker
  were rebuilt; the register grid, Private, Tools and My Files still carry the
  older look. Two visual languages in one app.
- **`RecordPermissions` duplicates `PermissionChecker`.** It reads roles and
  visibility directly, which is what commit `cfe02ad` removed everywhere else.
  Fold it back when step 8 adds grants to records.
- **`vault:backup:images` is a stub** that aborts. Step 13.
- **`dad@smith.com` holds test data** — nine records and a private section whose
  passphrase came from a test script. Wipe before using that account for real.

## The order

| # | Step | Size | Status |
|---|---|---|---|
| 1 | The records model — tables, templates, the record page ✅ | 2–3 days | **Done** (2026-08-26) — plus Login type, attachments, Register grid |
| 2 | Secrets in records — reveal, copy, history, key-agnostic format ✅ | 1–2 days | **Done** (2026-08-26) |
| 3 | `vault:backup` + `vault:restore` — the cheap half, both directions ✅ | half a day | **Done** (2026-08-26) |
| 4 | All nine types ✅ — each one created and read back, expiry dates parse | 1–2 days | **Done** (2026-08-27) |
| 5 | The generator ✅ — in every secret field, and standalone in Tools | half a day | **Done** (2026-08-27) |
| 6 | Expiry reminders | 1–2 days | **Parked** — schema + per-field schedules in, nothing sends yet |
| 7 | Who can use the vault — the per-person switch | half a day | |
| 8 | Short-term sharing — expiring grants, burn-after-reading links | 2 days | |
| 9 | TOTP on login | 1 day | |
| 10 | TLS for phone access | half a day | |
| 11 | Browser-side encryption | 3–4 days | |
| 12 | The Chrome extension | 1 week | |
| 13 | `vault:backup:images` | half a day | |
| 14 | Admin section | 2–3 days | |

Also still open after Steps 1–2: **links UI** on the record page (`record_links`
API exists; no picker yet).
