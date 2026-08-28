# Memories, lists, money and dates

A plan for four things the household asked for, in the order they are worth
building. Written after looking at what is actually in the vault, because two
of the obvious ideas turn out to be unbuildable here and one turns out to be
nearly free.

## What the photographs already know

```
80 images
80 have taken_at          — every one
 1 has latitude/longitude — one
 0 labels in use          — the feature exists and nobody has touched it
earliest photograph: April 2024
```

Three things follow from that, and they decide most of the plan.

**Time is the only reliable axis.** Every photograph knows when it was taken.
Anything built on `taken_at` will work on the whole library from the first day.

**Places is not worth building.** One photograph in eighty has a location.
Phones strip GPS on sharing and every picture that arrived through WhatsApp has
had it removed. A map view would open on an empty map. Revisit it if that ever
changes; do not start there.

**Labels went unused because they are a filing tool, not a memory.** Nobody
tags a holiday. They *name* it. That is an album, and it is a different thing.

## I. The gallery

A family's photographs are doing two unrelated jobs, and the gallery currently
treats them the same. There is the beach, and there is the photograph of the
boiler serial number. One is a memory and one is evidence, and mixing them is
why a family gallery becomes unusable by about year three.

The app already knows the difference exists — a picture can be filed as a
document, moving it out of Photos and into My Files. So the first job is not to
add a feature, it is to make that distinction easy and habitual.

In the order I would build them:

### 1. Albums — a day
The highest value thing here, and the least clever. A named collection somebody
made on purpose: "Cornwall 2025", "Ihaan's birthdays", "The old house". A
photograph can be in several. Nothing automatic, nothing to correct.

Shareable with the family, or on a timed link — the sharing built for records
works unchanged, so grandparents who are not in the vault can be sent an album
that stops working in a month.

### 2. On this day — half a day
A strip on the dashboard: *"Three years ago today"*. It is one query against
`taken_at` and it is the single highest return per line of code in this
document. A vault nobody opens is a vault nobody trusts; this is the thing that
makes somebody open it.

### 3. Moments — a day
Photographs cluster in time without being told to. Twenty pictures across two
days in August with a fortnight of silence either side is a trip, and the
database already knows it. Group by gaps in `taken_at`, show them as "August
bank holiday — 34 photos", and offer one button: **name it**, which turns the
moment into an album.

Suggestion, never fact. It proposes; a person names it or ignores it. No
machine learning, no service, no guessing at what a photograph contains.

### 4. Favourites — half a day
One column, one star. The cheapest curation there is, and what makes an album
possible to assemble at all.

### 5. People, by hand — 1–2 days
Tag a photograph with a person, and the person is a **Person record in Family
records**, not a new list of names. Then Ihaan's record page grows a strip of
his photographs, and the register and the gallery stop being two separate
apps.

Manual tagging only. Face recognition means either a model in the image or
photographs leaving the house, and the whole point of this vault is that they
do not.

### 6. Not a memory — half a day
A one-tap "this is a document, not a memory" that files a picture into My
Files. The mechanism exists; it needs to be one tap from the gallery. This is
what keeps everything above from silting up.

**Skip:** places, face recognition, auto-captioning, anything that needs a
model or a third party.

## II. Lists

Groceries, packing, the school list. A list is not a document and does not
belong in the register.

- A list belongs to the family and anybody in it can tick things off
- Items reorder, tick, untick, and old ticked items fall away on their own
- **Templates** — "the weekly shop" regenerates rather than being retyped
- Assign an item to a person, using the same Person records
- A list can carry a date, which is what connects it to IV

Two days, and genuinely useful from the first afternoon.

## III. Money

**This is not one feature, it is an application.** Budgets, accounts, ledgers,
categories, reconciliation, statements — it is the size of everything built so
far. I would not start it as part of this work.

There is a narrow slice worth taking now, because the data is already there.
The register holds **Subscriptions** with costs and billing cycles, and
**Service accounts** with providers and references. A single screen —
*what the household is committed to, per month and per year, and what renews
next* — is a day's work, needs no new domain, and answers the question a family
actually asks out loud.

If that screen gets used, it will tell you what the real financial section
should be. If it does not, you have lost a day rather than a month.

## IV. Dates, and getting them into Google and Apple

The register already computes what is running out — MOT, insurance, passports,
visas — and already writes to people about it. A calendar view of those dates
is mostly a rendering job over `UpcomingExpiries`, which exists and is tested.

Add household events on top of that: birthdays, term dates, the bin day.

### The part worth getting right

**Do not integrate with Google Calendar and Apple Calendar.** That is two
OAuth flows, two APIs, two sets of tokens to refresh, and two things to break.

Publish a **signed iCal feed** instead — one read-only `.ics` URL per person,
which both Google Calendar and Apple Calendar subscribe to natively, along with
Outlook and everything else. No accounts, no tokens, no vendor. The expiries
and events appear on every phone in the house and update themselves.

One endpoint, revocable like any other share link, and it is done. Half a day
against a fortnight.

## The order

| # | Thing | Size |
|---|---|---|
| 1 | On this day | half a day |
| 2 | Favourites | half a day |
| 3 | Albums, shareable | 1 day |
| 4 | Moments, offering to become albums | 1 day |
| 5 | "Not a memory" | half a day |
| 6 | People, tagged by hand, joined to Person records | 1–2 days |
| 7 | Lists | 2 days |
| 8 | Calendar over the expiries that already exist | 1 day |
| 9 | iCal feed for Google, Apple and the rest | half a day |
| 10 | What the household is committed to, monthly | 1 day |

Ten days of work, and the first two are done by lunchtime on day one.

Money proper, if it is ever wanted, comes after all of this and gets its own
plan.
