# Design: Device Sync and the Athenaeum protocol

> **Decision record:** [ADR-004](../adr/004-device-sync-and-athenaeum.md).
> That ADR decides *what* we build and why; this document specifies *how*. If
> the two disagree, the ADR wins and this document is wrong.

**Status: specification. Nothing here is built.**

## Vocabulary

| Term | Meaning |
| --- | --- |
| **Device Sync** | The user-facing feature. |
| **Athenaeum** | The store Device Sync talks to. Default `https://athenaeum.callerscompendium.com/`; user-editable. |
| **sync ID** | Diceware passphrase identifying one store. A bearer credential. |
| **device ID** | Random v4 UUID minted per installation, on opt-in. Classified `deviceScoped` — it is never synced as a record — while the same string travels in manifest envelopes and request paths as an opaque routing key. See "what `EgressClass` actually governs". |
| **epoch** | Opaque 128-bit random value the server stamps on a sync ID at creation. |
| **record** | One syncable row — a dance, program, tag, choreographer, published source, custom field def, venue, or a settings key. |
| **blob** | One record, serialised and content-addressed. |
| **manifest** | One device's map of record id → content hash. |
| **baseline** | The manifest a device last successfully synced, held locally. The merge base. |

## What travels

Device Sync holds no allow-list. It reads `EgressClass` from
[`field_registry.dart`][registry] and
[`settings_registry.dart`][settings], the same source of truth the CI ratchets
enforce and [data-classification.md](../dev/data-classification.md) renders.

[registry]: ../../packages/compendium_core/lib/src/privacy/field_registry.dart
[settings]: ../../packages/compendium_core/lib/src/privacy/settings_registry.dart

| Class | Behaviour |
| --- | --- |
| `shareable` | Serialised into blobs and uploaded. |
| `deviceLocal` | **Never serialised.** Omitted from the blob entirely — not nulled, not emptied: absent. |
| `deviceScoped` | Never serialised. |
| `derived` | Never serialised; rebuilt locally on arrival. |

A field with no classification cannot exist — the coverage ratchet fails CI — so
"unclassified" is not a state the serialiser must handle.

**A record whose every field is `deviceLocal` produces no blob at all.** No
current record is in that position; venues are the closest, and their identity
fields are `shareable`.

### Record kinds

Eight kinds produce blobs:

`dance` · `program` · `choreographer` · `tag` · `publishedSource` ·
`customFieldDef` · `venue` · `setting`

Join rows are **not** separate records. They ride inline with their parent
exactly as the archive codec already models them — a dance carries its
`authorIds`, `tagIds`, links, citations and custom-field values; a program
carries its slots. This keeps the merge unit equal to the thing a user edits.

Per-record blobs mirror the codec's existing shape rather than fighting it:
`archiveToJson` already emits choreographers, tags, published sources and venues
as **top-level arrays**, siblings of `dances`.

### Identity and collision reconciliation

Records sync under their existing UUID, so identity survives a rename — the name
is a field, not the key.

Three kinds carry `UNIQUE` natural keys — `choreographers.name`, `tags.name`,
`custom_field_defs.key` — so two devices that independently created "Bob Smith"
hold one entity under two UUIDs. Inserting the second violates the constraint and
fails the entire apply transaction. Applying a record of those kinds therefore:

1. **UUID known locally** → update, last-writer-wins on `updatedAt`. If the
   update would move the record's natural key onto a name another local row
   already holds, it collides exactly as an insert would. It does **not** merge
   silently: two local rows are involved and they may be two different people, so
   it routes to the review queue (see *`deviceLocal` fields must be coalesced*).
2. **UUID unknown, natural key matches a local row** → same entity, created
   independently. Reconcile silently: pick the survivor by the canonical
   tie-break, merge field values by recency, coalesce `deviceLocal` fields, remap
   every reference, drop the loser.
3. **Neither** → insert.

Step 2 is **silent** — no prompt, no review queue. At beta scale the collision is
routine and per-entity prompts would be noise.

#### The canonical tie-break

**The lexicographically smaller UUID always wins.** One rule, used by every
"which record survives" decision in this design — entity reconciliation here and
the fresh-attach dance merge alike.

The rule has to be *symmetric*: both devices must independently compute the same
survivor from the same pair. The natural implementation — "keep my local row, map
the incoming id onto it" — is not, and does not converge. A keeps X and maps
Y→X; B keeps Y and maps X→Y; neither manifest ever advertises the id the other
kept, so neither side can even detect the standoff, and the pair reconciles
forever. A third device attaching later picks a third outcome. Comparing UUIDs
costs nothing, needs no extra state, and gives every device the same answer.

Identity and content are chosen by **separate rules**, and both are needed:

| Decision | Rule |
| --- | --- |
| Which UUID survives | Lexicographically smaller — never `updatedAt` |
| Which field values survive | Last-writer-wins on `updatedAt` |
| Which `deviceLocal` values survive | Coalesce — see below |

Choosing *identity* by `updatedAt` would be unstable: `updatedAt` moves, so the
survivor could change on a later pass and the remap would never settle. Choosing
*content* by the tie-break rather than by recency would reintroduce the exact
defect the merge table exists to prevent — an older duplicate silently clobbering
a just-edited record. Device A edits a choreographer's `website` at 17:00; stale
device B holds an independently created row with the same name and a far older
`updatedAt`. That pair is handled **here, not by the merge table**, so the
recency rule has to be restated on this path or it does not apply at all.

##### Resolution rules must be symmetric

> **Every rule that decides which of two records survives, or how a conflict is
> broken, must be a pure symmetric function of the two records — never a
> function of "local" versus "incoming".**

Stated normatively for the same reason as the `updatedAt` invariant, and from the
same history: the device-relative rule has now been written three times, most
recently as a custom-field suffix rule introduced in the very revision that fixed
the other two. It is not obvious at the point of writing, because "keep mine,
file theirs under a new name" reads like a decision when it is really the same
non-decision taken twice — each device keeps its own and neither converges.

**A rule that has to say "local" or "incoming" to express which side wins is
wrong by construction.** Symmetry is checkable by inspection: swap the two
arguments and the answer must not change.

It implies a test shape too. **Every convergence test runs from both sides.** A
one-sided test passes against a non-convergent rule — which is exactly how the
custom-field suffix rule arrived with a test already written for it.

#### `deviceLocal` fields must be coalesced — but only for independent duplicates

`choreographers.email`, `choreographers.location` and `choreographers.deceased`
are `deviceLocal`. They are **never serialised**, so the peer's blob cannot carry
them and no copy exists anywhere else — not on the peer, not on the server.
Dropping the losing row destroys them outright.

This is not a corner case once the tie-break lands: a symmetric rule means the
incoming UUID wins about half the time, and those are exactly the cases where the
row holding the local `deviceLocal` values is the one dropped.

So **copy the loser's non-null `deviceLocal` fields onto the survivor before
dropping it**, preferring the survivor's value where both are non-null. The
values stay on the device that already held them; nothing new travels.

**This is safe in step 2 and only in step 2**, and the difference is structural
rather than a matter of likelihood:

- **Step 2 cannot blend two people's data.** The incoming blob carries no
  `deviceLocal` fields at all, so the only such values in play belong to the one
  local row. Coalescing preserves them onto whichever UUID survives; there is no
  second set to confuse them with.
- **Step 1 can.** A rename that collides involves **two local rows** — this
  device's synced copy of the renamed entity, on which its own user may have
  entered an email, and the pre-existing row it now collides with. Both may hold
  contact data, for what may well be two different real people.

Coalescing there would silently attach one non-consenting third party's email and
location to a row representing someone else — the precise data class this feature
exists to protect. **Step 1 therefore does not coalesce and does not merge
silently**: it routes to the existing review queue and asks. A rename that
happens to collide is rare, so this asks the user roughly never, and it never
fuses two people's contact details on a guess.

#### The remap is global, and durable

Reconciliation produces an **id remap** (`losing UUID → surviving UUID`) that
must be applied to more than the local join rows:

- **Local references** — `dance_authors`, `dance_tags`, `custom_field_values`,
  `dance_sources`.
- **Every inbound record in the same batch.** The peer's dances and programs
  reference the reconciled entity by whichever UUID *it* used, which is the
  losing one whenever the local id wins. Applying them unremapped writes a
  dangling `choreographer_id` — and `dance_authors` → `choreographers` is a hard
  FK with `onDelete: cascade`, so under `defer_foreign_keys` the violation
  surfaces at COMMIT, outside any per-record guard, **discarding the entire
  batch**.

The remap is **persisted** in an `id_aliases` table (`losing_id`,
`surviving_id`, `kind`), not re-derived each pass. Without it, a later blob still
referencing the losing id — from a device that has not yet reconciled, or from an
older manifest — reads as an unknown UUID and re-inserts the row the previous
pass just removed.

**Dance merges write aliases too.** The fresh-attach dance merge uses the same
tie-break and the same drop-the-loser pattern, so it inherits the same hazard:
`dance_links.target_dance_id` is a real FK to `Dances` (`tables.dart:271`), and a
third device holding a link to the merged-away dance would otherwise hit exactly
the dangling reference this table exists to prevent. Every "surviving record"
decision in the design writes its alias.

**Lookups chase the chain to a fixed point.** Aliases compose, and a single-hop
lookup is not enough:

1. B holds Y and C holds Z (Y < Z). They sync while A is offline → alias `Z→Y`.
2. A (holding X, X < Y) comes online and syncs with B → alias `Y→X`.
3. A stale blob referencing Z now needs `Z→Y→X` to reach a live row.

Resolving Z one hop yields Y — a UUID with no local row — which reproduces the
dangling-reference batch discard the table was added to prevent. Resolution
therefore follows the chain until it reaches an id with a live row, and
**superseded entries are rewritten in place** (`Z→Y` becomes `Z→X` when `Y→X` is
recorded) so chains stay short and cycles cannot form. Rewriting on insert also
makes the fixed point reachable in one hop in the steady state, leaving the chase
as a correctness guarantee rather than a per-lookup cost.

**The table is bounded by pruning, against the right clock.** An alias is needed
while any peer might still reference the losing id, which is a **per-device**
bound and not the store's. The store TTL is rolling on aggregate activity —
`last_seen` is refreshed by *any* device's request — so two devices syncing weekly
keep the store alive indefinitely while a third sits offline for months, never
learning of a merge. Pruning on the store's clock would drop the alias while that
device still holds the losing id; when it returned, its records would resolve to
nothing and the merged-away duplicate would be silently re-inserted, which is the
exact failure the table exists to prevent.

Retention is therefore bounded by the **oldest attached device's last-sync
watermark**, which `GET /v1/store` already returns: an alias is kept while any
device's baseline predates the merge that created it. A misbehaving peer still
cannot grow the table without bound, because a device that never syncs eventually
ages out of the store itself and stops being counted.

`id_aliases` is **`deviceScoped`** — a local remap of local row identity,
meaningless on another device and never serialised. Like the baseline manifest it
is a schema change **beyond v22**, belonging to the sync implementation rather
than the migration, and it must be classified in the PR that creates it or the
coverage ratchet fails.

#### Rewriting a reference must advance `updatedAt`

A dance's `authorIds`, `tagIds` and `customFields` are **not columns on
`dances`**; they are hydrated from the join tables on read
(`dance_repository.dart:511-522`). Rewriting `dance_authors` therefore changes
the dance's serialised content while `dances.updated_at` stands still.

At equal `updatedAt` a peer **discards** the rewritten dance, and the two devices
stay diverged with no discriminator left to move. So **any reconciliation that
rewrites a referencing row must bump that record's `updated_at` and re-upload its
blob** — the general rule stated under *Content changes must move the
discriminator*, applied here.

#### Renames collide too

The constraint risk is not only an insert problem. A and B have both synced
choreographer X ("Bob Jones"); B separately holds Y ("Bob Smith" — a different
person). A renames X → "Bob Smith". On B this is step 1, because the UUID *is*
known, so a naive LWW update writes a name Y already holds and violates `UNIQUE`.

The apply transaction fails, and *Failure and offline* covers network and HTTP
faults only — so a retry fails identically forever and the device pair deadlocks
until a human renames one side. Step 1 must therefore test the incoming natural
key against other local rows **before** attempting the update.

**On collision it does not reconcile.** "Reconcile" throughout this document
means the silent step-2 mechanism — tie-break survivor, merge by recency,
coalesce `deviceLocal`, drop the loser — and that is exactly what must not happen
here, because two *pre-existing local* rows are involved and both may hold
contact data for different real people. The collision is queued for review
instead, per *`deviceLocal` fields must be coalesced*. The rename is not applied
and neither row is touched until a human rules.

#### Natural-key equality is an approximation, and it is the app's own

Reconciliation treats an equal natural key as an equal entity, so two different
real people named "Bob Smith" merge silently with no review path.

This is accepted because **it is the assumption the schema already makes**:
`choreographers.name` is `UNIQUE` (`tables.dart:83`), so one device cannot hold
two same-named choreographers today. Sync is not introducing the approximation,
only applying it across devices, and a review queue here would contradict what
the app already enforces locally. The failure mode is named rather than fixed.

**Custom-field definitions are the exception**, because merging them corrupts
data rather than merely conflating it. `decodeCustomFieldValue` does
`value = valueNum!` for a `number` field (`custom_field_repository.dart:176`), so
repointing a value stored as `valueText` at a def of type `number` throws **when
the dance is loaded** — a crash on read, far from the sync that caused it.

Defs therefore reconcile **only when `type` matches**. On a mismatch both defs
survive, and the **tie-break decides which keeps the bare key**: the
lexicographically smaller UUID keeps `skill_level`; the larger is renamed. "Keep
mine, file theirs under a suffix" would not converge — each device would keep its
own type under the bare key and file the peer's under the suffix, leaving the two
permanently swapped and every dance showing its values under the opposite key
from its peer.

The new key is **derived from the losing UUID**, not from a counter —
`skill_level_7f3a9c2b`, taking the loser's first eight hex digits. Both devices
compute the same key without coordinating, and a third device carrying a third
type yields a third distinct key instead of contending for the same one. A
counter would not be collision-safe: `custom_field_defs.key` is `UNIQUE`
(`tables.dart:208`), so minting a `skill_level_2` that already exists — created
by the user, or by an earlier reconciliation — violates the constraint, fails the
apply transaction, and fails every retry identically. That is precisely the
deadlock *Renames collide too* exists to prevent, and it would be reintroduced by
the mechanism meant to avoid a crash. Should a derived key collide even so — two
distinct losing UUIDs sharing a 32-bit prefix — the derivation lengthens the
prefix until it is free rather than routing back through reconciliation, which is
what produced the collision and would simply produce it again.

`venues` and `published_sources` have **no** `UNIQUE` natural key, so their UUIDs
cannot collide destructively. They insert without reconciliation, and the same
hall created on two devices arrives twice.

Reconciliation runs **inside the apply transaction, before** any record that
references the reconciled row, so no write ever lands against an id that is about
to be rewritten. It is re-evaluated against **every current peer manifest on
every pass**, the same way the content rule evaluates against all peers rather
than one — the alias table's self-healing depends on it, since a device that
learns of a merge late must still reconcile against it rather than treating the
losing id as unknown.

### The serialiser must filter — the codec does not

**This is the highest-risk detail in the design.**

The archive codec emits `deviceLocal` fields today, and it is right to:
`_choreographerToJson` writes `email` and `location`, and the venue serialiser
writes the address block and both contact blocks. A local backup *should*
contain them.

So a sync implementation that reaches for `encodeArchive` and uploads the result
would ship precisely the data this feature exists to keep off our
infrastructure — and it would look completely reasonable in review.

Device Sync therefore serialises through a **classification-filtered** path that
consults `EgressClass` per field, and the property test named under Testing
exists specifically to catch a regression here. The server's generated
allow-list is the second line; neither is sufficient alone, because the client
knows about new fields first while the server fails closed on anything it does
not recognise.

### The device ID, and what `EgressClass` actually governs

An earlier draft called the device ID `deviceScoped`; a review pointed out that
this contradicts the term, since the ID plainly travels. Over-correcting to
`shareable` would have been worse, and would have caused a real bug: settings
sync would then carry `device_id` into a settings blob, and the receiving device
would adopt the sender's ID — two devices writing the same manifest.

The resolution is a distinction the registry always implied but did not say, and
**the enum's own doc comment has been amended in this PR** to say it —
documentation being part of the change:

**`EgressClass` governs record *content*. Protocol envelopes are not records.**

The device ID, the epoch and the content hashes are routing metadata: they carry
no user data by construction, and they must travel or the protocol does not
function. The classification question — "may this field's value be included in a
synced record?" — is answered for `device_id` by **`deviceScoped`**, which is
correct and matches the enum's own wording ("a per-device marker"): a device must
never adopt another's ID.

So: `device_id` is classified `deviceScoped` and never appears in a blob. The
same string appears in manifest envelopes and request paths as an opaque routing
key. Both statements are true and they are about different things.

### Device Sync's own configuration never syncs

Every settings key Device Sync introduces is `deviceScoped`:

| Key | Why it must not travel |
| --- | --- |
| `sync_enabled` | Each installation opts in for itself. |
| `sync_endpoint` | Syncing it would let one device silently redirect another. |
| `sync_id` | The bearer credential. Uploading it to the store it authenticates is self-defeating. |
| `sync_device_id` | Two devices sharing an ID collide in the manifest namespace. |
| `sync_wifi_only` | A per-device network policy; a laptop and a phone want different answers. |
| `sync_exclude_imports` | Governs what *this* device uploads. |
| `sync_last_synced_at` | Local state. |

The rule is simple enough to state as one: **sync configuration is never itself
synced.** Anything else is a bootstrapping paradox at best and a redirection
vector at worst.

**Device Sync also introduces persisted state that is not a settings key**, and the
repository requires everything persisted to be classified in the PR that adds
it:

| State | Where | Classification |
| --- | --- | --- |
| The baseline manifest (~1.4 MB at 11,500 records) | Its own table, not `settings` — too large for a key/value row | `deviceScoped` |
| The store epoch | Alongside the baseline | `deviceScoped` |
| Per-record last-seen hashes | Baseline table | `deviceScoped` |
| Id aliases (`losing_id`, `surviving_id`, `kind`) | `id_aliases` | `deviceScoped` |
| Pending deletions (`kind`, `record_id`, `tombstoned_at`) | `pending_deletions` | `deviceScoped` |
| Deferred review items (`kind`, `record_id`, `counterpart_id`, `reason`, `queued_at`) | `review_queue` | `deviceScoped` |

Every row is per-installation protocol state, meaningless on another device, and
adding them means a schema change **beyond v22** — which the implementation issue
must account for rather than discover. Note also that the settings ratchet scans
only `app/lib/src`, so if the sync client lives elsewhere its keys are not
covered by the existing guard and the ratchet's scope must be widened.

#### State must be named where the mechanism is introduced

> **Any mechanism that needs state to survive a restart must name where that
> state lives, add it to the schema scope, and classify it — in the same
> revision that introduces the mechanism.**

The third normative invariant, adopted for the same reason as the other two: the
mistake has now been made three times. The baseline manifest and epoch were
introduced as behaviour with no storage; so was `id_aliases`; so was the pending
tombstone, in the same revision that documented the rule for `id_aliases` two
sections earlier.

It is easy to miss because the mechanism reads as complete — "hold the tombstone
pending" describes a behaviour fully, and only a second reading asks *where the
pending flag is written*. Two things make the omission expensive here rather than
merely untidy: the coverage ratchet walks `db.allTables` and fails CI on any
unclassified column, so the gap surfaces late; and an unclassified field has no
egress ruling, which is the difference between a bookkeeping oversight and a
leak.

The check is mechanical. For each new mechanism, ask what it must remember across
a restart, and if the answer is anything at all, it appears in the table above
before the revision lands.

## Wire format

All payloads are UTF-8 JSON. All requests and responses may use
`Content-Encoding: gzip`.

### Record blob

A blob is the record as the existing archive codec emits it, restricted to
`shareable` fields, plus a small envelope:

```json
{
  "v": 1,
  "kind": "dance",
  "id": "8f14e45f-ceea-467a-9f8c-1f3f9a2b7c11",
  "updatedAt": "2026-08-03T04:11:22.000Z",
  "deletedAt": null,
  "body": { }
}
```

- `v` — blob envelope version. Unknown values are refused by the client, not
  guessed at.
- `kind` — which repository owns the record.
- `updatedAt` — the conflict discriminator. UTC, millisecond precision.
- `deletedAt` — non-null means a **tombstone**: the record is deleted, and this
  blob is how that fact travels.
- `body` — archive-codec output for the record, `shareable` fields only.

Reusing the archive codec matters: it is already hardened (bounded, clamping,
parse-never-fails) and already round-trip tested. Device Sync must not grow a second
serialiser.

### Settings records

Each settings key is its own blob, `kind: "setting"`, with the key as the record
id. Per-key rather than one settings document, so two devices changing different
preferences never collide.

**The per-key registry overrides the column classification, and that precedence
is normative here rather than implied.** `settings.value_json` is classified
`deviceLocal` at the column level — deliberately, so a blanket sync of the
settings table cannot happen by accident. Read literally against the "What
travels" table, the only `shareable` column on a setting is `key`, and a
`custom_dialects` blob would ship as `{"key":"custom_dialects"}` with no value,
silently breaking the promise that dialects and themes travel.

So: for `kind: "setting"`, the **per-key classification in
`settings_registry.dart` governs**, and `settings.value_json`'s column-level
`deviceLocal` is what stops the *table* being synced wholesale. A key classified
`shareable` ships its value; a `deviceScoped` key is not serialised at all.

Note also that settings whose value is an entire collection —
`custom_dialects`, `custom_themes`, `shorthand_mappings`,
`walkthrough_snippets` — collide as a unit: a changed/changed conflict discards
one device's whole set. Accepted; see ADR-004 consequences.

This requires a schema change: `settings` is `(key, value_json)` with **no
timestamp and no tombstone**, so neither the conflict rule nor deletion can reach
it. **Schema v22** adds `updated_at` *and* `deleted_at`, stamping existing rows
at migration time. Both need classifying like any other column, and the coverage
ratchet will require it.

`deleted_at` is not optional. `SettingsRepository.remove` is a hard delete today,
so without a tombstone a removed setting cannot be expressed on the wire: the
peer still holds it, "absence never deletes" preserves it, and the next sync
**downloads it back**. The deletion would reverse every time, permanently.

#### The real scope of v22

An earlier draft called v22 "one column on `settings`". Under first-class records
it is six tables and twelve columns:

| Table | Adds |
| --- | --- |
| `settings` | `updated_at`, `deleted_at` |
| `choreographers` | `updated_at`, `deleted_at` |
| `tags` | `updated_at`, `deleted_at` |
| `published_sources` | `updated_at`, `deleted_at` |
| `custom_field_defs` | `updated_at`, `deleted_at` |
| `venues` | `updated_at`, `deleted_at` |

Plus **six `_db.delete(` call sites** converted from hard to soft delete across
five repositories.

`Dances` and `Programs` already have both columns and need no change.

##### `DanceRepository` is not the pattern to copy

An earlier draft said to copy `DanceRepository`. That is wrong, and the
difference is not cosmetic: dances are the **parent** in every one of these
cascades, and the five kinds converting here are on the other side of them. Each
needs a per-kind decision, and two of them carry an app-behaviour regression if
converted naively.

**`TagRepository.delete` relies on the FK cascade** to clear `dance_tags` — its
own comment says so (`tag_repository.dart:36`). A soft delete is an `UPDATE`, so
**the cascade never fires**: the join rows survive, and because `dance_tags`
gains no `deleted_at` in v22, nothing filters them. The tag would vanish from the
tag manager while staying silently attached to every dance. The same applies to
`custom_field_values` and `dance_sources`.

> **Every read that joins through to a soft-deletable parent must filter
> `parent.deleted_at IS NULL`.** This is a change to existing query paths, not
> only to the sync code, and it is the part of v22 most likely to be missed —
> the migration passes, the tests pass, and the defect only shows on a screen.

**Deletes that are referential guards must keep guarding.**
`ChoreographerRepository.delete` throws while the entity is still credited
(`choreographer_repository.dart:48-58`); `VenueRepository` and
`PublishedSourceRepository` mirror it. Tombstone propagation appears to require
relaxing them — but relaxing them means a dance can credit a tombstoned
choreographer, with no defined UI treatment.

Instead, **the referential guard is kept and the tombstone is held pending.** A
tombstone applies immediately where the entity is unreferenced. Where it is still
cited, the receiving device **records the deletion as pending, keeps the row live
locally, and does not republish it**; it applies the deletion once its last
citation goes away.

The "keeps it live and republishes it" formulation an earlier draft used is
wrong, and wrong in a way that silently reverses user intent. Republishing bumps
`updatedAt` under *Content changes must move the discriminator*, so the still-
citing device would out-rank the deleting device's tombstone; the deleting device
downloads its own deletion back, and since the user has already deleted the
entity once, nothing re-tombstones it. The entity would be live everywhere,
permanently, with no signal that the deletion had been undone.

Holding the tombstone pending instead means the deletion is never out-ranked and
never republished. The two devices are legitimately divergent — one still needs
the row, and says so only to itself — and they converge as soon as the last
citation is removed. The inverse ordering is covered by the same rule: a device
that tombstones a tag and then receives a dance citing it revives the row and
re-marks the tombstone pending, rather than writing a join row against a
tombstoned parent.

This preserves the property the guard exists for — no dance ever credits a
tombstone — without achieving it by resurrecting deleted data. The cost is real
and is disclosed rather than hidden: a deletion can sit unapplied on another
device indefinitely, and the user is not told why. See the Consequences section.

**A local edit cancels the pending tombstone — and nothing else does.** If the
user on the holding device edits the entity while a deletion is pending, that is
a deliberate act on a record they can see, and it revives the entity: the
tombstone is discarded and the row is republished as live. Without this rule the
mechanism has a hole, because the edit would be published anyway, advance
`updatedAt`, out-rank the tombstone and resurrect the entity through the back
door.

**The gate is the provenance of the write, not the resulting timestamp.**
Phrasing the rule as "a newer `updatedAt` out-ranks the tombstone" would make
every mechanism that bumps `updatedAt` a cancellation path, and the design
requires several: reference rewriting after reconciliation, merge-by-recency, and
the dance merge's scalar recency all advance the discriminator without a user
touching anything. A third device silently reconciling a same-named duplicate
would otherwise reverse another device's deletion, with nobody having edited the
record on any device. Cancellation therefore keys off a **user-initiated edit
flag carried through the write**, and a sync-initiated write never sets it,
however new the resulting timestamp.

**A pending-held row is excluded from what the device advertises.** It stays live
locally, but its manifest entry is withheld: the holding device does not publish
the entity, so the deleting device cannot download its own deletion back. This is
the load-bearing half of the mechanism — without it, "does not republish" is a
statement of intent that the upload path silently contradicts.

**The baseline is not advanced for a pending-held record.** Advancing it would
leave the local row permanently differing from baseline, so `changed`/`same`
would fire every pass and the device would republish its stale live blob
indefinitely — the same resurrection reached through upload rather than download.
The pending marker in `pending_deletions` is the durable record of the deferred
state, so the baseline does not need to carry it.

**A purge must not cascade off live records.** `DanceRepository.purgeDeleted`
guards its hard delete with `_cleanupDanglingReferences` and a GC that never
weakens the delete-guards. A choreographer or tag purged by its own repository
has no such guard, and the hard delete would cascade `dance_authors` /
`dance_tags` / `dance_sources` / `custom_field_values` off **live** dances
(`tables.dart:108, 255, 302, 230`) — silent loss of authorship, tags, citations
and custom values. Every purge added here must refuse to hard-delete an entity
still referenced by a live record.

#### Land the migration first, before any other sync work

**Schema v22 should ship ahead of every other piece of this programme**, on its
own, before the protocol, the client or the server exist.

Three reasons, and the third is the one that matters most:

1. **It is the only schema change in the whole programme.** Getting it out of the
   way leaves the rest as pure feature work with no migration risk, and lets the
   migration be reviewed as what it is — a small, independently testable change
   with its own fixture and red-run proof — rather than as one commit inside a
   large feature.
2. **It is independently sensible.** A modification timestamp on settings is
   defensible on its own terms; nothing about it presumes Device Sync ships, so nothing
   is wasted if the programme stalls.
3. **It defuses the one-time ordering effect.** The known wart is that each
   device stamps `updated_at` at *its own* migration time, so the device that
   upgrades last wins every settings conflict on first sync. That is only true
   while the stamps still reflect *migration order*. Ship v22 early and users
   spend the intervening releases actually changing settings — and every real
   change overwrites the migration stamp with a genuine one. By the time Device Sync
   arrives, `updated_at` largely reflects real recency, which is what the
   conflict rule assumes. Ship it *with* Device Sync and every device syncs for the
   first time carrying stamps that mean nothing but "when I upgraded".

The gap between the two releases is doing the work here, so earlier is strictly
better and there is no reason to wait.

### Content hash

`hash = lowercase-hex(SHA-256(canonical-json(blob)))`

Canonical JSON means keys sorted lexicographically, no insignificant whitespace,
and a pinned number form. Two devices that hold an identical record **must**
produce an identical hash, or delta sync degrades to full sync.

**This is entirely new code.** The archive codec emits keys in *insertion* order,
not lexicographic, and there is no SHA-256 anywhere in `packages/`. "Reuse the
archive codec" applies to the record *body*; the canonicalisation and hashing
layer is built for sync.

Three concrete divergences the golden tests must pin, each of which silently
degrades delta sync to full sync by giving two devices different hashes for the
same record:

- **Numbers.** `encodeCustomFieldValue` forces `.toDouble()`, so an integer `8`
  reaches the wire as `8.0`. An RFC 8785 canonicaliser rewrites that back to `8`.
  Pick one form and pin it.
- **Absent versus null.** The codec *omits* `deletedAt` when null; the blob
  envelope above shows `"deletedAt": null` present. Same record, two hashes.
  Policy: the envelope's fields are always present, `null` where empty; the
  body follows the sender rule in "Applying a record" — explicit `null` for
  empty `shareable` fields, omission only for `deviceLocal`.
- **Key order.** Lexicographic, applied recursively, regardless of what the
  codec produced.

A change to canonicalisation is a wire-format break and needs a `v` bump.

### Manifest

```json
{
  "v": 1,
  "deviceId": "b31f...",
  "epoch": "9c4a...",
  "writtenAt": "2026-08-03T04:11:22.000Z",
  "records": {
    "8f14e45f-ceea-467a-9f8c-1f3f9a2b7c11": "e3b0c442...",
    "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed": "a1c2f3d4..."
  }
}
```

`records` includes tombstones. A record absent from a manifest was never known
to that device — it is **not** a deletion. See "Absence never deletes".

## HTTP contract

Base path `/v1`. TLS required; the client refuses a non-`https` endpoint except
`http://localhost` and `http://127.0.0.1`, which self-hosters need for testing.

### Authentication

The sync ID travels in the standard HTTP `Authorization` request header using
the `Bearer` scheme, with the sync ID as the credential — **never in a URL**.

> Written as prose rather than as a literal header line on purpose: credential
> scanners in review tooling and terminals redact anything shaped like an auth
> header, which made an earlier draft of this section display as `******` and
> drew a review comment asking what the scheme was. The scheme is `Bearer`.

Credentials in URLs leak into server logs, proxy logs, browser history and
`Referer` headers (CWE-598). Paths are therefore scoped implicitly by the
authenticated sync ID and contain no secret.

The server does not "look up an account". The sync ID *is* the namespace: it is
derived into a storage key with **`HMAC-SHA256(pepper, syncID)`**, so the
plaintext ID is never written to disk.

**Why HMAC rather than a bare hash.** The sync ID is deliberately low-entropy —
memorable by design, with a floor of ~2⁴⁰ for user-chosen IDs. Exhausting 2⁴⁰
SHA-256 candidates is minutes on a commodity GPU, so a bare hash would let anyone
with a stolen database recover working credentials. The pepper lives in server
configuration, never in the database, so the database alone is useless.

This is **server-side only**. The client sends the sync ID over TLS and computes
no MAC; it neither needs nor should hold the pepper, since the entire value of
the scheme is that the key lives somewhere a stolen database does not. The
client's cryptography is therefore unchanged from what the app ships today.

### Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/store` | Store metadata: epoch, device list, quota usage. Creates the store if absent. |
| `DELETE` | `/v1/store` | Detach-and-wipe. Deletes everything under the sync ID. |
| `GET` | `/v1/manifests/{deviceId}` | Fetch one device's manifest. `ETag` / `If-None-Match`. |
| `PUT` | `/v1/manifests/{deviceId}` | Publish this device's manifest. |
| `GET` | `/v1/blobs/{hash}` | Fetch one blob. Immutable; long `Cache-Control`. |
| `PUT` | `/v1/blobs/{hash}` | Upload one blob. Idempotent. |
| `POST` | `/v1/blobs/missing` | Given a list of hashes, return the subset the store lacks. |
| `DELETE` | `/v1/manifests/{deviceId}` | Remove a device's manifest — for a lost or reinstalled device. Without it a dead device holds one of 32 slots forever and its unique blobs never GC, with a whole-store wipe the only remedy. |

`POST /v1/blobs/missing` is the only non-REST-shaped call and it earns its place:
without it, a device with 11,500 records issues 11,500 `HEAD` requests to find
out what to upload.

### Status codes

| Code | Meaning |
| --- | --- |
| `200` | OK. |
| `201` | Blob or manifest created. |
| `204` | Deleted. |
| `304` | Manifest unchanged (`If-None-Match` matched). |
| `400` | Malformed request. |
| `401` | Missing or malformed `Authorization`. |
| `403` | Sync ID below the entropy floor (see Security). |
| `404` | No such blob, manifest or device. |
| `409` | **Epoch mismatch** — the client's epoch is not the store's. |
| `413` | Payload exceeds a cap. |
| `422` | **Payload rejected by the allow-list** — a key not classified `shareable` for that kind was present. |
| `429` | Rate limited. `Retry-After` set. |
| `507` | Store quota exhausted. |

There is deliberately **no distinct "expired" status.** An earlier draft had a
`410` for it, which was wrong twice: `GET /v1/store` creates the store when
absent, so a client starting every sync there would never observe it — it sees a
new epoch and re-attaches via `409` — and for the server to tell "expired" from
"never existed" it would have to **remember reaped sync IDs**, which is the exact
persistent-metadata-past-expiry problem used to rule out monotonic epochs. The
same objection applies to both, and it was missed here first time.

So: the other endpoints return `404` when the store is absent, indistinguishable
from a missing blob, and the client recovers by calling `GET /v1/store`, which
creates it and returns a fresh epoch. Reset detection is the epoch's job alone,
and the epoch needs no server memory to do it.

`422` should never occur in normal operation. It fires only when a client bug
would otherwise put a venue address on our infrastructure, so it is a **loud**
failure: surfaced to the user, logged, never silently retried.

## Client algorithm

### Off by default

**Device Sync is disabled on every installation until the user turns it on.** No sync
setting is populated, no endpoint is contacted, no device ID is minted. An app
that has never been configured for Device Sync makes no sync-related network call of any
kind, which keeps "the app works fully offline and phones home to nobody" true by
construction for every user who does not opt in — not merely true by policy.

Device Sync gets its **own top-level blade in Settings**, not a row buried under
General. It is the one feature that sends a user's collection off the device, so
it is surfaced at the same level as the decision it represents, showing the
endpoint URL, the sync ID, paired-device count and last-sync status in one place.

Turning it off again stops all network activity and detaches. Detach forgets the
sync ID entirely, so re-enabling is a fresh attach.

### Attach

1. User enters or accepts a sync ID and confirms the endpoint.
2. `GET /v1/store`. Server creates the store if it does not exist, returning its
   epoch.
3. **Fresh attach**, always, on first attach for this ID, on re-attach after
   detach, and on `409`. Detaching **forgets the sync ID entirely**: no
   list of previously-attached IDs is kept, so re-attaching cannot resurrect a
   stale baseline.
4. Upload every local record; download every remote record.
5. **Union**, then dedupe (below). No deletion occurs during a fresh attach —
   there is no baseline to justify one. Where two peers advertise the **same id
   with different content**, there is likewise no baseline to compare against, so
   the higher `updatedAt` wins — the same rule as a steady-state conflict, minus
   the baseline that normally distinguishes "changed" from "not caught up".

   Pending tombstones make this routine rather than rare: a device holding a
   deletion pending advertises nothing for that record, by design and possibly
   for a long time, while another advertises it live. An attaching device
   therefore sees one id present on some peers and absent from others, which
   *is* the ordinary union case and correctly yields the live record. It has no
   citation of its own to justify keeping it and no future tombstone will correct
   it, so the attaching device queues it for review rather than adopting it
   silently.
6. Persist the epoch and the resulting manifest as the new baseline.

### Fresh-attach dedupe

Union matches on record id. Two devices that imported the same dance separately
hold different ids for it, so union alone yields duplicates.

**Silent merge** where both hold:

1. exact normalized-title match (`normalizeTitle`), and
2. `_choreographyEquals` — form, formation, progression, phrase structure,
   figures *including params*, hook, calling notes, level, mixed level, tunes.

Everything else that the existing `DedupeIndex` flags is **deferred for review**.

#### The review queue needs durable storage; today it has none

An earlier draft said these go "to the review queue, through the import
pipeline's plan → review → commit flow." That overstates what exists, in the same
way an earlier draft overstated `_resolveAuthors`, and the claim is worth
correcting precisely because it reads as reuse of proven machinery.

The review *UI* does exist and is not the problem:
`app/lib/src/screens/import_review_screen.dart` shipped as the adapter-agnostic
import review-queue UI. What is missing is **storage**. It is a synchronous
screen driven by a user who has just started an import, and the batch it works
from is `ImportSession`, whose own doc comment says it is "Deliberately NOT a
persisted table … a durable cross-session undo log's shape depends on the
review-queue UX". There is no `review_queue` table in `tables.dart` today.

That is the mismatch, and it is not small. Sync runs non-interactively — on app
start, and debounced after a change — with nobody watching, so there is no
in-progress import to attach a decision to and no session to scope it to. Fresh
attach is the worst case rather than an edge one: pairing two independently built
collections can flag a large number of ambiguous pairs at once, none of which can
block the sync that found them.

Device Sync therefore **specifies the durable queue** rather than assuming it:
a `review_queue` table (`kind`, `record_id`, `counterpart_id`, `reason`,
`queued_at`), classified `deviceScoped`, a schema change beyond v22 alongside
`id_aliases`. The existing screen is the natural surface for it, so the work is
storage plus a way in, not a new UI. Deferring an item is a write, not a prompt;
the user is shown a count and works through it whenever they choose.

Two properties it has to have, both of which follow from sync being repeated
rather than one-shot:

- **Queuing is idempotent.** An item is keyed by the pair it concerns, so a
  collision that is still unresolved after the next pass updates the existing row
  rather than adding a second. Without this, an unattended device accumulates a
  duplicate per sync indefinitely.
- **A queued pair is not re-resolved behind the user's back.** While an item is
  pending, neither record is silently merged or dropped by a later pass; the
  deferral holds until it is answered.

This is a genuine addition to the programme's scope and is named as one. It is
not new work *caused* by Device Sync, though — the dance dedupe path has depended
on it since the first draft, which no earlier round caught, and the same gap
would have surfaced on the first fresh attach.

Device Sync **calls** `_choreographyEquals` rather than reimplementing it. Two
definitions of "the same dance" would drift, and the drift would be silent.

Deliberately stricter than import: import treats title + author-overlap as
confident even when choreography differs, which is right for re-importing a
source record and wrong here — that case is a dance edited differently on each
device, and merging it silently would discard one side.

On silent merge the surviving record is chosen by the **canonical tie-break** —
the lexicographically smaller UUID, the same rule entity reconciliation uses, so
both devices independently pick the same survivor. The id-collections
`_choreographyEquals` ignores — tags, custom fields, links, citations — are
**unioned**, since they are additive and neither side is more correct.

**The scalars `_choreographyEquals` does not compare are resolved by recency, not
taken from the survivor.** It compares form, formation, progression, phrase
structure, figures, hook, calling notes, level, mixed-level and tunes — so
`walkthrough`, `rating`, `status`, `composedOn` and `revisedOn` fall outside both
the equality test and the union. Taking them from the tie-break survivor would
discard a caller's own walkthrough notes and their rating on an arbitrary UUID
comparison, with no prompt and no recovery. The merge is silent precisely because
the *choreography* matched, which says nothing about these. They follow the same
rule as every other field value: last-writer-wins on `updatedAt`.

**`program_slots.dance_id` must be rewired to the survivor.** It is
`onDelete: KeyAction.setNull` (`tables.dart:193`), so removing the losing
duplicate silently nulls every local program slot pointing at it: a caller's
program loses its link to a dance that still exists under the surviving id, with
no error and no prompt. This is the common case rather than an exotic one —
import the same source on two devices, build programs on both, then pair. The
merge therefore rewires `program_slots.dance_id` exactly as the entity path
rewires its join rows, and bumps the affected programs' `updated_at` per
*Content changes must move the discriminator*.

The user is told the count afterwards ("merged 412 duplicates"), not asked.

### Steady-state sync

1. `GET /v1/store`. **Epoch differs → fresh attach.** Stop.
2. Compute the local manifest.
3. `GET /v1/manifests/{peer}` for each peer, with `If-None-Match`.
4. Per record, compare local / remote / baseline hashes **and `updatedAt`**:

   | Local vs baseline | Remote vs baseline | Action |
   | --- | --- | --- |
   | same | same | nothing |
   | changed | same | upload |
   | same | changed | download **only if `remote.updatedAt > local.updatedAt`** |
   | changed | changed | **conflict** → higher `updatedAt` wins |
   | absent from baseline, present locally | — | upload (new here) |
   | — | absent from baseline, present remotely | download (new elsewhere) |

   **`updatedAt` is load-bearing, not a tiebreak.** An earlier draft compared
   hashes alone and downloaded whenever the remote differed from the baseline.
   That is wrong in a way that silently destroys work: a peer which has *not
   caught up* is indistinguishable from a peer which *edited*, so a stale
   manifest deterministically rolls a newer local record backwards. Requiring
   `remote.updatedAt > local.updatedAt` distinguishes them.

   With **N peers**, evaluate against all of them and take the newest
   `updatedAt`; the baseline is per-device and one baseline against several peers
   is otherwise undefined.

   This rule is only universally applicable because of the record model: all
   eight syncable kinds carry `updatedAt` — the five that lacked it, plus
   `settings`, gain it in schema v22. A kind without a modification timestamp
   cannot participate in this rule at all, which is why v22 is a prerequisite
   rather than a convenience.

#### Content changes must move the discriminator

Because the download gate is `remote.updatedAt > local.updatedAt`, the whole
merge rests on one invariant:

> **Any operation that changes a record's serialised content must also advance
> its `updatedAt`.**

An operation that violates it produces a record whose hash differs from its
peers' while the discriminator says nothing changed — so peers discard the new
content, the divergence is permanent, and no later pass can repair it because
there is nothing left to compare.

This is stated normatively because the design has already broken it twice, by two
unrelated mechanisms: once through an inline-entity model where renaming a nested
entity moved the parent's hash but not its timestamp, and once through
reconciliation rewriting join rows that a dance's `authorIds` are derived from.
Neither was obvious from the mechanism itself. **Any new write path must be
checked against this invariant before it ships**, and the derived-content case is
the one to check hardest: a record's serialised form includes fields hydrated
from other tables, so a write that never touches the record's own row can still
change what it publishes.

5. `POST /v1/blobs/missing` with the hashes to upload; `PUT` only what is
   missing.
6. `GET /v1/blobs/{hash}` for each needed hash. **Verify the hash before
   applying.**
7. Apply in one transaction, **read-modify-write** (below). Rebuild derived
   indexes.
8. `PUT /v1/manifests/{self}`.
9. Store the new baseline.

### Absence never deletes

A record present in the baseline and absent from a peer's manifest means that
peer never had it, or has not synced since. It is **never** a deletion.

Deletions travel only as tombstones — a blob with `deletedAt` set. The schema
already carries `deletedAt` and the Recently Deleted screen already surfaces it,
so this reuses the existing soft-delete rather than inventing a parallel one.

The invariant, stated so it can be tested: **a device honours a deletion only
when it can trace it to a tombstone within the same epoch.**

### Applying a record must not erase what it omits

**This is the symmetric twin of the serialiser hazard, and it is the more
dangerous of the two.** The serialiser leaking a device-local field exposes data;
the deserialiser *dropping* one destroys it, on the device that owns it, silently.

A blob correctly omits `deviceLocal` fields. The repositories' `upsert` methods
write **every** column — `VenueRepository.upsert` uses `insertOnConflictUpdate`
with `address1`, `city`, the contact blocks and the rest — and the archive
decoder maps an absent key to `null`. Composed naively, a remote edit to a
venue's *website* nulls its address and both contact blocks locally.

So sync does **not** use the repository `upsert` path. Apply is
**read-modify-write, inside the apply transaction**:

1. read the local record;
2. overlay only the fields the blob actually carries;
3. write the merged result.

Both halves of that matter:

**Inside the transaction.** SQLite serialises writers, so a user edit landing
mid-apply blocks rather than interleaving. Outside a transaction the read and the
write straddle a window in which the user can edit, and the write silently
reverts them.

**"Carries" must be unambiguous.** The codec omits null fields today
(`if (v.website != null)`), so on the wire *absent* means either "device-local,
preserve the local value" or "shareable but empty, clear the local value".
Read-modify-write cannot act on an ambiguous signal, so both ends are pinned:

- the **sender** emits an explicit `null` for a `shareable` field that is empty,
  and omits **only** `deviceLocal` fields;
- the **receiver** independently consults the registry to decide which absences
  mean *preserve*, rather than trusting the sender to have been careful.

Two mechanisms that cross-check. A sender bug that wrongly omits a shareable
field does not silently clear it, because the receiver knows that field was
supposed to be there.

#### The receiver must also reject keys that are *present*

Absence is only half of it. Nothing above stops a blob that **includes** a key it
should not — an inline choreographer `email`, a venue `contact1Email` — and since
apply overlays whatever the blob carries, those values would be written straight
onto the victim's record. That plants or overwrites exactly the private contact
data the classification exists to keep off the wire.

Relying on the server to catch it is not enough, and the design says so itself:
the client serialiser is the control and "neither is sufficient alone". A
self-hosted server, a `localhost` endpoint with TLS waived, an older server, or a
hostile operator all leave no client-side gate at all.

So **before overlaying, the receiver drops any inbound key not classified
`shareable`** for its record kind and nesting context — symmetric with the
sender, and enforced client-side.

**Settings need a second check, on the key rather than the field.** For
`kind: "setting"` the egress decision is per settings key, but every setting blob
has the same field shape (`key`, `value`, `updatedAt`), so a field-level
allow-list cannot tell a `shareable` setting from a `deviceScoped` one. Without a
key-level check, a peer holding the shared sync ID can push `update_auto_check`,
`update_beta_channel` or `update_dismissed_version` — all `deviceScoped`
(`_installState`) — and have the victim apply them, **suppressing update checks
or pinning a dismissed version**. That is a patch-suppression primitive, and it
sits outside the disclosed trust boundary, which covers a second person writing
*shareable records* rather than altering another device's update policy.

On applying a `setting`, therefore, look the record id up in
`settingsClassifications` and **refuse anything not `shareable`**, independently
of the server.

### Apply ordering

Records carry references to rows that must exist first. `dance_authors` has a
hard foreign key to `choreographers` with `onDelete: cascade`, and violations
under `defer_foreign_keys` surface at COMMIT — outside any per-record guard —
discarding the entire batch.

Apply therefore proceeds in dependency order within the transaction:

1. **Reconcile `UNIQUE`-key collisions first**, building the global id remap
   described under *The remap is global, and durable*.
2. **Apply the remap to every inbound record in the batch**, so no record is
   inserted holding a reference to a UUID that reconciliation just retired.
3. **Apply parent records by UUID** — entities before the dances and programs
   that cite them.
4. **Apply join rows last.**

A record whose reference cannot be resolved is skipped and reported, never
applied with a dangling id.

### Failure and offline

Device Sync is best-effort and never blocks the UI. Any failure leaves local data
untouched and the baseline unchanged, so the next attempt retries cleanly.

- Network unreachable, DNS failure, TLS failure, `5xx` → retry with exponential
  backoff and jitter, cap 6 hours.
- `429` → honour `Retry-After`.
- `401` / `403` → stop, surface to the user. Do not retry.
- `422` → **stop and surface loudly.** A client bug tried to upload a
  device-local field.
- `507` → surface a **size breakdown by category**, with the *exclude imported
  dances* toggle offered inline, since imports are usually the bulk and that
  setting is the lever.
- Partial upload → harmless. Blobs are content-addressed and immutable; the
  manifest is written last, so a half-finished sync publishes nothing.

**The manifest is written last, always.** That single ordering rule is what
makes an interrupted sync a no-op instead of a corruption.

### Triggers

- On app start, once, after any pending migration completes.
- Debounced 30s after a local change.
- Manually via "Sync now" — a **delta pass**, identical to an automatic one. A
  **full re-verify** (rehash every local record, reconcile against every peer)
  is available behind a long-press or a Settings action, because on 11,500
  dances a full rehash is real work and the ordinary button must stay quick.

**Metered connections.** A setting, *Sync only on WiFi*, defaults to **on**, in
the manner of any app with downloadable content. While it is on and the
connection is metered, automatic sync does not run — and a manual "Sync now"
does not silently override it. Instead it surfaces a snackbar explaining why,
with a tap-through to the setting, so the data-usage decision is made once and
stays made rather than being re-decided per press.

The first sync of a large library is ~17 MB; every subsequent one is kilobytes.

## Server implementation

**Dart + `shelf`**, one container, SQLite plus a blob directory, in a new
top-level `server/` package with a path dependency on `compendium_core`.

The path dependency is the point: the server reads the **same** classification
registry as the client, so the allow-list is generated from one definition.

### Storage layout

```
data/
  athenaeum.sqlite      stores, devices, blob refcounts, quota, activity
  blobs/<aa>/<bb>/<hash>
```

Blobs are fanned out two levels to keep directory sizes sane.

**Every handler validates `{hash}` against `^[0-9a-f]{64}$` before touching the
filesystem.** An earlier draft argued traversal-safety from the hash being
"verified" — but verification happens on `PUT`, where the body is hashed. On
`GET` and `DELETE` the hash is attacker-controlled path input fanned into
`blobs/<aa>/<bb>/<hash>` with nothing checking it. The guard belongs on every
handler, not on the one that happens to compute a hash.

```sql
CREATE TABLE stores (
  id_key      TEXT PRIMARY KEY,   -- HMAC-SHA256(pepper, syncID); never plaintext
  epoch       TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  last_seen   INTEGER NOT NULL,   -- any request refreshes it; drives the TTL
  bytes_used  INTEGER NOT NULL
);
CREATE TABLE manifests (
  id_key TEXT NOT NULL, device_id TEXT NOT NULL,
  etag TEXT NOT NULL, written_at INTEGER NOT NULL, body BLOB NOT NULL,
  PRIMARY KEY (id_key, device_id)
);
CREATE TABLE blob_refs (
  id_key TEXT NOT NULL, hash TEXT NOT NULL, size INTEGER NOT NULL,
  PRIMARY KEY (id_key, hash)
);
```

Blobs are namespaced per store. Cross-store deduplication would be a privacy
leak: an attacker could probe whether *anyone* holds a given dance by uploading
it and watching whether storage grew.

### TTL

A sweeper runs hourly:

```sql
DELETE FROM stores WHERE last_seen < (now - 30 days);
```

then cascades manifests, blob refs and blob files.

`last_seen` is updated by **any** authenticated request for the store, so this
is a rolling TTL on activity rather than an absolute age cap: a store synced
weekly persists indefinitely, and that is intended.

Retention obligations are covered by two paths rather than by the sweeper alone
— abandoned stores reap themselves, and an owner can wipe an active store at any
time with `DELETE /v1/store`. Neither requires an operator to act on a request.

### Garbage collection

A blob is reachable while any manifest for its store references it. After each
manifest `PUT`, and during the sweep, unreferenced blobs for that store are
deleted. Mark-and-sweep scoped to one store is cheap; no global scan.

### The break-glass access log

Athenaeum is opaque in normal operation: the operator sees store sizes, device
counts and activity timestamps, never content. Content is plaintext, so this is
policy rather than capability — and the policy is enforced by making access
leave a record.

Break-glass access for abuse investigation writes to a **separate database**,
not the store's, holding exactly two things:

| Column | |
| --- | --- |
| `id_key` | `HMAC-SHA256(pepper, syncID)` — **the same derivation the store uses**, never the plaintext. **Nulled after 30 days.** |
| `accessed_at` | Timestamp. Retained. |

Derived rather than plaintext for a specific reason: the sync ID is a bearer
credential, and the store already avoids holding it in the clear so that a stolen
copy yields nothing usable. A plaintext access log would undo exactly that, and
would be worse than the store, because the log is meant to outlive the stores it
describes. Correlation is unaffected — to find entries for a store under
investigation, derive its key and match.

**The identifier expires; the fact of access does not.** Even a peppered
identifier is a linkable pseudonymous identifier, so it cannot be held
indefinitely under the same reasoning that bounds everything else here. After 30
days `id_key` is nulled, leaving a timestamp-only row.

The split is deliberate, because the audit value is two different things:

- *"Did the operator open store X?"* — linkable, and expires on schedule.
- *"How often is break-glass used at all?"* — an aggregate about our own conduct,
  with no data subject, which survives.

The second is what matters for accountability over time, and it is the one that
costs nothing to keep.

The log is deliberately minimal: it records **that** access happened and to
which store, not why. Justification lives in whatever incident process wraps it,
not in a field nobody validates.

It is a **separate database** so that reaping a store cannot destroy the evidence
of access to it. Its retention is therefore not the 30-day disuse TTL — an audit
log that expires with its subject is not an audit log — and needs its own stated
period in the privacy policy.

### Allow-list validation

On `PUT /v1/blobs/{hash}` the server:

1. rejects any `{hash}` not matching `^[0-9a-f]{64}$` **before touching the
   filesystem** — see Security;
2. checks the size cap **before** reading the body;
3. streams and hashes, aborting if the running total exceeds the cap;
4. rejects with `400` if the computed hash differs from the path;
5. parses as JSON with a depth cap (a server-side bound — the codec's
   `kMaxMeanwhileDepth` guards figure nesting, not parse depth);
6. **validates every key against a per-kind allow-list, rejecting anything not
   on it** with `422`.

#### Why an allow-list, and why the first attempt was worse than useless

An earlier draft specified a **deny-list** of known-forbidden keys, chosen for
forward-compatibility: unknown keys pass, so a server one release behind does not
reject a newer client. That design failed **open**, and did so in a way no amount
of care in the handler would have caught — because the two key spaces do not
intersect.

The registry is keyed `table.column` in **SQL** names, and says so explicitly:
`venues.contact1_email`. The codec emits **bare camelCase** field names:
`contact1Email`. A deny-list built from registry keys, applied to codec output,
matches **nothing**. A blob carrying a venue's complete address book would have
returned `200 OK`.

The spec's own test fixture used `contact1_email` — a string the codec **cannot
emit** — so the single test proving the backstop worked was **vacuous by
construction**, which is precisely the failure mode this repository's guide warns
about.

The allow-list inverts the failure: an unrecognised key is **rejected**, so a
mapping error becomes a loud `422` instead of a silent pass. The cost is real and
accepted — a server older than its clients rejects valid uploads until it is
updated — and it is the right way round, because the alternative failure is
silent and permanent.

#### The mapping must be generated, and proven

The allow-list is **generated from the registry**, not hand-written, with the
SQL-name-to-wire-name mapping declared once. A hand-maintained list would drift
from the codec exactly as the deny-list did.

Two CI tests, neither of which can be satisfied by a fixture someone invented:

1. **Mapping completeness.** The registry-to-wire mapping is a **declared,
   reviewed artifact**, not a name transform, because the relationship is
   structural: `dances.figures_json` → `figures`; `formation_shape` +
   `formation_detail` → one nested `formation`; `value_text` + `value_num` → one
   `value`; join tables → bare `authorIds`/`tagIds`. Two `shareable` registry
   keys are **never emitted at all** — `dance_authors.position` and
   `dance_sources.position`, whose ordering rides implicitly in the array order.

   So the test is not "every key round-trips" — that is unsatisfiable and an
   earlier draft was wrong to specify it. It is: **every `shareable` registry key
   has an entry in the mapping, either to a wire key or to an explicit,
   commented exception; and every wire key the codec emits maps back to a
   classified registry key.** An unmapped key on either side fails the build.

   The exception list is small, security-relevant, and reviewed like code — which
   is the honest version of "generated". Pretending the mapping is mechanical is
   what produced the original defect.
2. **No device-local field reaches the wire.** Build a record with **every**
   field populated, including every `deviceLocal` one, run it through the real
   sync serialiser, and assert that none of those values appears anywhere in the
   output. Driven off the registry, so a newly classified field is covered
   automatically.

Both operate on **real `encodeArchive`-shaped output**. Neither takes a
hand-written key string, because that is how the first attempt convinced itself
it worked.

The server check remains a backstop; the client's classification-filtered
serialiser is the control.

## Security

Threat model, following OWASP. The store holds plaintext choreography by design
(ADR-004: no confidentiality crypto), so confidentiality rests entirely on the
sync ID.

### An attacker who has a sync ID

...can read, modify and delete the whole collection. That is inherent to a
bearer credential with no accounts, and ADR-004 accepts it. Mitigations are
about making acquisition hard, not about limiting the blast radius:

- Generated IDs are four EFF-wordlist words, ~2⁵². At 1,000 guesses/second an
  exhaustive search is ~10⁵ years; rate limiting makes it far worse.
- **Two checks, not one.** The **format** is fixed at four hyphen-separated
  words, which rejects `isaac-banner-dances` structurally. A **strength floor of
  ~2⁴⁰**, scored on the actual string, then rejects four *weak* words that
  satisfy the pattern. Both are server-enforced with `403`; a client-side check
  alone would be bypassable, and a warning alone would have stopped neither.
- The ID never appears in a URL, so it does not reach logs or `Referer`.
- The server stores only `HMAC-SHA256(pepper, syncID)`, with the pepper in
  configuration rather than the database, so a stolen database yields no IDs. A
  **bare** hash would not achieve this: at the ~2⁴⁰ floor, exhausting the space
  is minutes of GPU time.

### What a peer can do to another peer

The bearer model has a consequence beyond read access, and it is worth stating
as plainly as the read case. `PUT /v1/manifests/{deviceId}` accepts a
**caller-chosen** device id, and the same shared bearer authorises
`DELETE /v1/store`. So anyone holding the sync ID can publish a manifest as
another device, or destroy the entire store.

This is inherent to "one credential, no accounts", which ADR-004 chose knowingly.
It is not mitigated here; it is disclosed, because the write case destroys data
while the read case only exposes it. A user sharing a sync ID with a second
person is granting exactly this.

### Enumeration

`GET /v1/store` creates a store if absent, so a probe cannot distinguish "exists"
from "does not exist" by status code. Creation is cheap and the sweeper reaps
unused stores after 30 days of disuse.

Rate limits are per-IP and per-ID-hash, with a global cap on store creation per
IP per hour.

### Input validation

Every limit is enforced **before** allocation, streaming-abort style, following
`update_fetcher.dart` and `artifact_downloader.dart`:

| Limit | Value | Why |
| --- | --- | --- |
| Blob size | 1 MB | A dance is ~1.5 KB; a large program with notes is far under. |
| Manifest size | 16 MB | 11,500 records ≈ 1.4 MB uncompressed. |
| Blobs per store | 100,000 | ~8x the largest known corpus. |
| Bytes per store | 250 MB | ~15x a full Caller's Box import. |
| Devices per store | 32 | Generous for a person; bounds manifest fan-out. |
| JSON parse depth | 32 | **New bound.** The codec has no general depth cap; `kMaxMeanwhileDepth` (4) bounds *figure* nesting only, so the server needs its own guard against deeply-nested JSON. |
| Decompressed size | 10x compressed, cap 32 MB | Decompression bomb. |
| Request rate | per-IP and per-store | Brute force. |

Text arriving from a peer is passed through `sanitizeImportedText`, exactly as
imported text is. A peer is not more trusted than an import source: a shared
sync ID means a second person can write to the store.

**"Parse never fails" does not hold for peer input, and this was verified rather
than assumed.** `decodeArchive` catches `on Exception` and deliberately lets Dart
`Error`s escape, on the reasoning that an `Error` signals a bug. But
`PartialDate.parse` throws **`ArgumentError`** — an `Error`, not an `Exception` —
for a well-shaped but invalid date. A blob containing `"composedOn":
"0000-13-99"` escapes the decoder uncaught. Confirmed by direct execution against
a valid archive: five such inputs (`0000-13-99`, `2026-13-01`, `2026-02-30`,
`0000`, `2026-04-31`) all escaped as `ArgumentError` while the same archive
decoded cleanly without them — a remotely triggerable crash from a peer blob.

The sync apply path therefore catches `Error` as well as `Exception` around
per-record decode, and reports the record as rejected rather than letting it
abort the batch. This applies to the sync boundary only; the existing archive
path's stance is deliberate and unchanged.

### Transport

- TLS required, except `localhost`/`127.0.0.1` for self-hosters.
- **Redirects are followed manually with per-hop validation**, mirroring
  `artifact_downloader.dart:370` — https only, no userinfo, default port, hop
  cap. The `package:http` default `followRedirects = true` is not used. This is
  a **recurring** defect class in this codebase — found and fixed once in the
  ContraDB search path (#765), still open in the update-manifest fetcher (#784)
  — so the sync client adopts the hardened pattern from the start rather than
  becoming the third instance.
- The user-configured endpoint is validated on entry: https (or localhost), no
  userinfo, no fragment, no query.
- A custom endpoint is a **deliberate trust decision** by the user, so the
  client must show the host prominently when one is set, and warn on change.

### What the server operator can see

Everything in the store: plaintext choreography, programs, tags, settings. Not
venue addresses or contacts — those never leave the device. The privacy policy
must say this plainly rather than implying sync is opaque to us.

## Testing

- **Canonical-JSON goldens.** Two devices must agree on a hash byte-for-byte.
- **Merge table**, every row, both directions.
- **Absence never deletes** — a peer manifest missing records must not delete
  them locally. Mutation-proved by making absence delete and watching it go red.
- **Epoch mismatch → fresh attach, never deletion.** The catastrophic case; it
  gets an explicit test that a stale-baseline device reconnecting to a re-seeded
  store loses nothing.
- **`deviceLocal` never serialised** — property test over the registry: for
  every field classified `deviceLocal`, a record carrying a value there produces
  a blob not containing it. This is the test that must never be allowed to
  become vacuous.
- **Interrupted sync is a no-op** — kill after blob upload, before manifest
  `PUT`; assert peers see nothing.
- **Fresh-attach union and silent merge** — `{B,C}` joining `{A,B}` yields
  `{A,B,C}`; identical-choreography duplicates merge without a prompt;
  same-title-same-author-different-figures reaches the review queue.
- **Server caps** — each limit rejected at the boundary, not after allocation.
- **≥3-device convergence** — three devices, interleaved edits, all reach the
  same state. Two devices cannot exercise the max-`updatedAt`-across-N rule.
- **A stale peer does not roll back newer data** — the B2 case: peer publishes an
  old manifest, local record is newer, local wins. Mutation-proved by removing
  the `updatedAt` comparison and watching it go red.
- **Inbound apply preserves device-local columns** — apply a venue blob that
  changes only `website`; assert the address block and both contact blocks are
  untouched. This is the data-loss guard.
- **Inbound apply rejects present non-shareable keys** — a hand-built blob
  carrying `contact1Email` (the **wire** spelling, which is the point) is
  stripped by the receiver, not merely by the server.
- **A peer cannot push a `deviceScoped` setting** — applying a `setting` blob for
  `update_auto_check` is refused client-side. Guards the update-suppression
  primitive.
- **Collision reconciliation** — two devices create the same choreographer name
  under different UUIDs; after sync there is one row, references are rewritten,
  and no `UNIQUE` violation aborts the batch.
- **Reconciliation converges from both sides.** Run reconciliation on device A
  *and* on device B from the same pair and assert they select the **same
  survivor**. Mutation-proved by replacing the tie-break with "keep the local
  row" — the naive implementation — and watching both devices keep their own id.
  This is the guard that would have caught R3-1; a one-sided test passes happily
  against the non-convergent implementation.
- **Inbound references to the losing UUID are remapped** — apply a batch
  containing a dance whose `authorIds` cite the *losing* choreographer id, in
  both tie-break directions. Assert the batch commits and the credit survives.
  Without the global remap this fails at COMMIT and discards everything.
- **Reconciliation preserves `deviceLocal` fields** — the losing row carries
  `email` and `location`; assert both are present on the survivor afterwards.
  Run it in the direction where the **incoming** UUID wins, which is the
  direction that destroys them if the coalesce is missing.
- **Reconciliation respects recency** — a stale peer's independently created
  duplicate must not overwrite a just-edited local `website`. This is the merge
  table's rule applied on the reconciliation path, and it needs its own test
  because the merge table never sees this pair.
- **Rewriting a reference advances `updatedAt`** — after reconciliation rewrites
  `dance_authors`, assert the affected dance's `updated_at` moved and its blob
  was re-uploaded. Mutation-proved by removing the bump: a peer at equal
  `updatedAt` then discards the rewritten dance.
- **Rename into an existing name** — device A renames a synced choreographer onto
  a name device B already holds under a different UUID. Assert B reconciles
  rather than throwing, and that a retry is never needed. Guards the deadlock.
- **Custom-field type mismatch does not crash on read** — same key, `text` on one
  device and `number` on the other; assert both defs survive, that the
  lexicographically smaller UUID keeps the bare key, and that loading every
  affected dance succeeds. **Run from both sides** and assert the two devices
  agree on which def keeps the bare key — the one-sided version of this test
  passes against the non-convergent "keep mine, suffix theirs" rule, which is how
  that rule reached review with a test already written for it. Mutation-proved by
  reconciling mismatched types anyway and watching `decodeCustomFieldValue` throw.
- **A minted suffix never collides** — reconcile a type mismatch on a device that
  already holds the key the suffix would produce; assert the apply commits.
  Mutation-proved by switching the derivation to a `_2` counter, which violates
  `UNIQUE` and fails every retry identically.
- **Alias chains resolve transitively** — build `Z→Y` then `Y→X` across three
  devices, then apply a blob referencing Z; assert it reaches X's live row.
  Mutation-proved by resolving a single hop, which lands on a UUID with no row
  and discards the batch.
- **A pending tombstone is never republished** — device B still cites a
  choreographer A deleted; assert B holds the deletion pending, does **not**
  re-upload the entity as live, and applies the deletion once its last citation
  goes. Mutation-proved by republishing instead: A then downloads its own
  deletion back and the entity is live everywhere, permanently.
- **Only a deliberate edit resurrects** — editing an entity while its tombstone
  is pending cancels the tombstone and republishes; merely continuing to
  reference it does not. Both halves asserted, since the mechanism is only sound
  if the second never happens.
- **A sync-initiated write never cancels a tombstone** — a third device
  reconciles a same-named duplicate onto a record another device holds pending,
  advancing its `updatedAt` past the tombstone. Assert the tombstone stands.
  Mutation-proved by gating cancellation on `updatedAt` rather than on the
  user-edit flag, which resurrects the record with nobody having edited it.
- **A pending-held row is never advertised** — assert the holder's manifest omits
  it and its baseline entry is not advanced. Without both, the deleting device
  downloads its own deletion back; the manifest half fails via download and the
  baseline half via a perpetual re-upload.
- **Queuing a review item is idempotent** — run three passes over the same
  unresolved collision; assert one row, not three. Guards the unattended device
  that syncs for a week before anyone looks.
- **A queued pair is not resolved behind the user** — assert neither record is
  merged or dropped by a later pass while the item is pending.
- **Alias retention outlives the oldest device** — merge on A, let the store stay
  alive through A and B for longer than the TTL, then return C from a long
  absence still holding the losing id. Assert C's records resolve and no
  duplicate is re-inserted. Mutation-proved by pruning on the store's clock
  instead of the oldest device watermark.
- **A rename collision is not silently merged** — assert it reaches the review
  queue and that no `deviceLocal` field from either row is copied onto the other.
  This is the guard against blending two people's contact data.
- **The dance merge preserves uncompared scalars by recency** — two copies of a
  dance with identical choreography but different `walkthrough` and `rating`;
  assert the newer values survive rather than the tie-break survivor's.
- **Dance merge rewires `program_slots`** — build a program on the device whose
  duplicate loses the merge; assert the slot points at the survivor rather than
  `NULL`.
- **Soft delete does not leave live join rows** — soft-delete a tag, then assert
  it no longer appears on any dance. Mutation-proved by omitting the
  `deleted_at IS NULL` filter on the join read, which is the regression the
  cascade previously prevented.
- **A referenced entity cannot be tombstoned away** — a device still crediting a
  choreographer keeps it live and re-publishes; assert no dance is left citing a
  tombstone.
- **Purge refuses to cascade off live records** — purge a tombstoned
  choreographer still credited by a live dance; assert the purge declines and the
  authorship survives.
- **Identity survives a rename** — renaming a choreographer on one device
  propagates as a field change rather than creating a second entity.
- **Tombstone purge versus resurrection** — delete, purge the tombstone, reattach
  a stale peer; assert the documented behaviour rather than an accident.
- **Allow-list bijection and no-device-local-on-the-wire**, both over real
  `encodeArchive`-shaped output. Never a hand-written key string.
- **Canonical JSON determinism** — integer/float form, absent-versus-null, key
  order. Two independently constructed identical records hash identically.
- **Hostile peer blob** — the `ArgumentError` case; a malformed date rejects one
  record and does not abort the batch or escape the isolate.

## Resolved since first draft

Recorded so the reasoning is not re-litigated.

| Question | Ruling |
| --- | --- |
| Settings merge granularity | Per-key blobs, plus an `updated_at` column on `settings` at **schema v22**, stamping existing rows at migration time. |
| Entropy floor | Format fixed at **four hyphen-separated words**; strength floor **~2⁴⁰** scored on the string. |
| Imported dances | **Full sync.** Reference-and-refetch demoted to a revisit trigger. *Exclude imported dances* ships in v1. |
| Operator visibility | Opaque by design, with a **logged break-glass path** for abuse, disclosed in the privacy policy. |
| `programs.venue` label | Stays `shareable` — a label the user typed, and a program is meaningless without it. |
| "Sync now" | Delta pass; full re-verify behind a long-press or Settings action. |
| Metered connections | *Sync only on WiFi*, default on; manual attempts route to the setting via a snackbar. |
| Quota exhaustion | Size breakdown by category with the exclude-imports toggle inline. |
| Naming | **Athenaeum** — the earlier "Athanaeum" was a typo; DNS corrected and verified. |
| Default state | **Off on every installation.** Opt-in only; an unconfigured app makes no sync network call at all. Device Sync gets its own top-level Settings blade. |
| Access log | **Separate database**, holding a derived sync-ID key and a timestamp. Separate so reaping a store cannot destroy evidence of access to it. |
| Identifier derivation | **`HMAC-SHA256(pepper, syncID)`**, server-side only — a bare hash is brute-forceable at the ~2⁴⁰ floor. No client-side change; the app's cryptography is unchanged. |
| Access-log retention | Identifier **nulled at 30 days**, timestamp retained — the linkable part expires, the non-linkable aggregate survives. |

### The settings migration has a one-time ordering effect

Each device stamps `updated_at` at *its own* migration time, so the device that
upgrades last carries the newest settings and wins every settings conflict on the
first sync afterwards. Deterministic, one-time, and recoverable by re-setting a
preference — but it is a real effect and should not be discovered in the field.

An alternative was considered and rejected: stamping a fixed sentinel so all
devices agree. That makes every settings row tie, leaving the conflict rule with
no discriminator at all, which is worse.

## Recorded limitations and operational prerequisites

Held here rather than in issues: ADR-004 is still `Proposed`, and filing
implementation-shaped issues against an unagreed design presumes the agreement.
These become issues when the ADR is accepted. Nothing below is resolved.

### Dance dedupe runs only at fresh attach, so a dance can fork permanently

Content-based dance dedupe is an attach-time pass. Steady-state sync has no
per-record dedupe, so two dances that become identical *after* attach — or a
device attaching later that merges a pair a third device already merged
differently — stay forked with no mechanism to reconcile them afterwards.

This is materially worse than the disclosed venue and published-source
duplication, and the difference is worth stating: those two kinds never had an
identity claim, so two rows are simply two rows. Dances do have one, but only
sometimes — the tie-break gives a *deterministic* survivor for any pair that is
compared, and nothing guarantees every pair is compared. The gap is in coverage,
not in the rule.

Not fixed here because a steady-state content dedupe pass is a different piece of
machinery from the merge, with its own cost at 11,500 records, and inventing it
inside a design that cannot yet be tested would be speculative. Recorded so it is
a known limitation rather than a surprise.

### Simultaneous rename into the same name does not deadlock — checked

Recorded because it looks like it should, and the question keeps recurring.

If A renames X → "Bob" while B simultaneously renames Y → "Bob", one of two
things is true. If both devices already know both entities, the **local** `UNIQUE`
constraint rejects the second rename before sync is involved at all — the app
will not let a user create the collision in the first place. If they do not
both know both entities, the rename arrives as an ordinary reconciliation and
the tie-break settles it symmetrically.

There is no third case, so no deadlock. Stated here as answered rather than
left for each reader to re-derive.

### Pepper rotation is impossible for inactive stores, as specified

Storage keys are `HMAC-SHA256(pepper, syncID)` and the server retains **only the
derived key** — plaintext sync IDs are deliberately not stored. So re-deriving a
key under a new pepper needs an input the server does not have:

- **Active stores** can be re-keyed lazily: the next authentication supplies the
  plaintext, so the new key can be computed then.
- **Inactive stores can never be re-keyed.** There is no input until a client
  returns, and if none does the entry is orphaned.

That leaves a bad choice at rotation: keep the old pepper and preserve whatever
exposure prompted the rotation, or drop it and make those stores permanently
unreachable.

Proposed resolution — **versioned peppers with lazy re-keying**: store a pepper
version beside each derived key; hold predecessors while still referenced;
re-derive on next authentication; drop a version once unreferenced. Orphans are
bounded by the ordinary 30-day disuse TTL rather than being indefinite, though a
forced-reset path is still needed for a pepper that must be retired faster than
that.

Rejected: never rotating (not a plan — a secret leaks eventually); storing
plaintext IDs so any pepper can re-derive (defeats the purpose); forcing every
store to re-attach (correct but user-hostile — every device does a fresh attach
with a dedupe review, for an operational event they did not cause).

### Operational prerequisites — real before shipping, not before deciding

- **`422` has nowhere to be loud.** The design calls it a loud failure; on the
  client it surfaces, on the server nothing pages anyone. If a client bug starts
  pushing venue addresses, that is the event we most want to know about within
  minutes. Also worth alerting: `409` rate (clients re-attaching means something
  reset), sweeper failure (the retention promise silently stops being kept),
  quota exhaustion, and a `422` rate hitting *everything at once* — the signature
  of a codec change breaking the allow-list mapping.
- **The retention guarantee has no proof.** "Nothing survives 30 days of disuse"
  is prose, and this repository's position is that prose does not hold. It needs
  a test that the sweeper reaps and an assertion that it ran.
- **Break-glass authorisation is undefined**, and the log is bypassable: content
  sits in ordinary SQLite and filesystem storage, so an operator can read a store
  without the instrumented path and can then edit the log. Append-only or
  independently-administered storage would make the record meaningful rather than
  advisory.
- **Boot invariants.** A server started with no pepper must **refuse to boot**,
  not default to empty — an empty pepper reduces every derived key to a bare
  hash, which is the weakness the pepper exists to remove. Version skew should
  also be detectable, since a server older than its clients now rejects valid
  uploads by design and would otherwise present as mysterious `422`s.
- **Lost-ID support has no answer.** "No recovery, no revocation" is honestly
  stated, but *"I lost my ID"* and *"my dances vanished after five weeks"* are
  predictable inbound. The second is not a fault at all — it is the disuse TTL
  working — and it will read as data loss.

## Open questions

None outstanding at the design level.
