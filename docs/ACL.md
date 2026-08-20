# Access control

Who can do what, and why it is shaped this way.

## The shape

An account is personal and works on its own. Nothing forces a family at
sign-up, and everything in an account is private until it is deliberately
shared. A user may belong to **several** families — "Family", "Parents' house",
"Tax stuff with the accountant" — or to none.

Access to a file comes from exactly three places, checked in this order:

| Source | What it means |
| --- | --- |
| **Ownership** | The person who uploaded it. Can do anything to it, always. |
| **A grant** | This file, or a folder above it, shared with them by name or with a family they belong to. |
| **The file's family** | It lives in a family and they are a member, capped by their role there. |

## Resolving conflicts

Between two grants, **the most specific wins**: one naming the person beats one
naming a family they belong to, and one on the file beats one inherited from a
folder above it. That is what makes "everything in this folder is read-only,
except this one thing" expressible, and it is the rule people already know from
Drive.

Between a grant and plain family membership, **the stronger wins** instead.
Being handed a read-only link to a file you can already edit as a member of its
family should not quietly demote you.

## Families

You can be in several, or in none. A family is created from Settings when you
want one — nothing about signing up requires it, and an account with no family
is a normal, complete account whose contents are private.

`users.current_family_id` records only which one the app is showing, so uploads
land somewhere predictable. It is a view preference, not a permission: deleting
a family nulls it rather than being blocked by it.

The owner cannot leave their own family, since that would leave it ownerless.
Anyone else can, and the files they put there stay — those belong to the
family, not to their membership.

## Roles

Two different questions, kept apart on purpose. Mixing them is what makes an
ACL unreadable.

**Family role** — what you may do to the *family*: `owner`, `admin`, `editor`,
`viewer`. Admins and the owner invite people and change roles. It also caps
what you can do with content shared into that family.

**Grant role** — what you may do with *one file or folder*: `viewer` or
`editor`. A grant never carries the right to re-share or delete: access should
not spread without the owner, and someone with edit access to a shared folder
should not be able to destroy another person's passport.

## What a guest cannot do

Deleting and re-sharing are deliberately stricter than editing. Both need
ownership, or admin/editor standing in the family the file actually lives in —
never a grant alone.

## Using it

Sharing with a person or a family is the **People with access** section of a
file's share dialog, or `POST /api/v1/files/:id/grants` (and the same under
`/folders/:id`) with either an `email` or a `family_id`, plus a role. Re-sharing
with the same subject changes the role rather than adding a second row nobody
can see.

A grant needs somebody to point at: sharing with an address that has no account
fails rather than quietly creating one. Inviting a stranger into the vault is a
heavier decision than sharing a file, and a public link already covers the case
where they should not have an account at all.

## Where it lives

- `PermissionChecker` — the only place these rules exist. Controllers never
  re-implement them; the frontend's role helpers only hide buttons.
- `AccessGrant` — `resource` (a file or folder) → `subject` (a user or family)
  → `role`, optionally with an expiry.
- `FamilyMember` — membership and family role.
