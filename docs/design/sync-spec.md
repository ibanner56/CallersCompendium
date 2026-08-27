# Specification: Device Sync and the Athenaeum protocol

*Normative companion to [ADR-004](../adr/004-device-sync-and-athenaeum.md) and
[design/sync.md](sync.md). Version 1 of the wire protocol.*

## 1. Status and scope

This document specifies what a conforming Device Sync client and a conforming
Athenaeum server must do. It is the implementable artifact: schema, wire format,
HTTP contract, algorithms, limits and conformance tests.

It deliberately carries **no rationale**. Every rule here was argued somewhere,
and that argument lives in [sync.md](sync.md), which records the alternatives
considered, the defects each rule prevents, and the reasoning behind every
choice. Where the two disagree, the ADR governs the decision, this document
governs the behaviour, and `sync.md` explains why — a disagreement between them
is a defect in one of them and should be reported rather than resolved locally.

It also carries **no schedule**. The order in which these sections are built,
what may proceed in parallel, and the checkpoints between are in
[sync-implementation.md](sync-implementation.md), which is a plan rather than a
contract: nothing there constrains a conforming implementation.

**Conformance language.** MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are used as
in RFC 2119. A requirement stated without one of those words is descriptive.

**Out of scope:** end-to-end encryption, local-network discovery, server-side
merging, user accounts, and any sharing of fields not classified `shareable`.

## 2. Terminology

| Term | Meaning |
| --- | --- |
| **sync ID** | A diceware passphrase identifying one store. A bearer credential. |
| **store** | Everything held under one sync ID. |
| **device** | One installation. Holds a baseline and publishes one manifest. |
| **peer** | Any other device attached to the same store. |
| **blob** | One record, serialised, content-addressed. |
| **manifest** | One device's map of record id → content hash. |
| **baseline** | A device's record of what it last agreed with its peers. |
| **epoch** | An opaque 128-bit value identifying one incarnation of a store. |
| **pass** | One complete sync cycle. |
| **quarantine** | Local state of a record whose timestamps are implausible. |
| **detach** | Stop syncing on *this* device: forget the sync ID and the baseline locally. Purely local. It sends no request, leaves this device's manifest and every blob on the server, and affects no peer. |
| **wipe** | Destroy the whole store server-side via `DELETE /v1/store`, for every device at once. Not reversible, and not what the Settings detach control does. |
| **report** | Surface a condition to the user as a non-blocking notice that survives the pass which raised it. Reporting MUST NOT block a write, gate a pass, or require a gesture to clear. Distinct from `review_queue`, which holds candidate *records* awaiting a decision: a report names a condition, not a pending choice. |
| **tick** | The smallest interval the timestamp storage representation can distinguish. Currently **one second**: `DateTimeColumn` persists as a unix second count, so a sub-second increment does not survive a write. Every `+ 1 tick` in this document means this quantity, not a fixed millisecond. |

## 3. Data model

### 3.1 Schema migration

**This section is implemented.** It landed as schema **v25** (PR #901, with a
follow-up in #903), before any other Device Sync work and on its own, as
required below. It is recorded here in the imperative because it states the
contract the shipped migration must continue to satisfy, not because it is
outstanding.

The migration MUST land before any other Device Sync work, on its own.

Eight tables, twenty columns:

| Table | Adds |
| --- | --- |
| `settings` | `updated_at`, `deleted_at`, `existence_at` |
| `choreographers` | `updated_at`, `deleted_at`, `existence_at` |
| `tags` | `updated_at`, `deleted_at`, `existence_at` |
| `published_sources` | `updated_at`, `deleted_at`, `existence_at` |
| `custom_field_defs` | `updated_at`, `deleted_at`, `existence_at` |
| `venues` | `updated_at`, `deleted_at`, `existence_at` |
| `dances` | `existence_at` |
| `programs` | `existence_at` |

`dances` and `programs` already carry `updated_at` and `deleted_at`.

Six `_db.delete(` call sites across six repositories MUST convert from hard to
soft delete: `settings`, `choreographers`, `tags`, `published_sources`,
`custom_field_defs`, and `VenueRepository.delete`. The `restore()` paths on
every kind MUST stamp `existence_at`.

`VenueRepository.hardDelete` is **deliberately excluded** and stays a hard
delete. It exists solely to revert a just-committed import batch, where the
caller has already removed the referencing programs, and converting it would
leave an undone import visible as tombstones. `DanceRepository` and
`ProgramRepository` set the precedent: both keep a hard-delete path on a kind
that already soft-deletes.

**The generic hard-delete hatch.** The shipped migration also added a
`permanent: true` parameter to `delete()`/`remove()` on five repositories —
`settings`, `choreographers`, `published_sources`, `custom_field_defs` and
`venues` — which bypasses the tombstone and removes the row outright. Two of
those kinds (`venue`, `choreographer`) produce blobs (§4.3).

A hard delete is permitted **only** where the record can never have been
published to a peer. A tombstone is worth its storage only when there is
somebody to inform; conversely, a row a peer holds live cannot be removed
locally without the next pass taking the "absent from baseline, present remotely
→ download" path (§6.3) and restoring it, reversing the deletion on every pass.

That condition is currently **assumed, not enforced**. Its production callers
divide in two:

- **Safe by construction** — the editor draft keys (`editor_draft:<id>`,
  `program_editor_draft:<id>`), which are never published because they carry no
  `shareable` classification at all (§3.3).
- **Not enforced** — import undo, on choreographers (`import_pipeline.dart`) and
  venues (`compendium_archive_import.dart`,
  `callers_companion_usr_import.dart`). `ImportSession` is in memory, so the
  undo window lasts as long as the user leaves the screen open, and nothing
  excludes a sync pass from landing inside it.

A client implementation MUST therefore either suspend sync for the duration of
an undoable import session, or treat publication as forfeiting the right to hard
delete — falling back to a tombstone for any record this device has ever named
in a manifest it `PUT`. The sibling case has already shipped as a real defect
once: an import undo left a *revived* row live (#903), which would have
outranked that deletion on every peer once a client exists.

A client taking the forfeiture route MUST evaluate that predicate against the
durable marker in §3.2, written at §6.3 step 8, and MUST NOT evaluate it against
the baseline. A baseline entry advances only where a peer was observed to carry
this device's content hash (§6.3 step 9), so it records *confirmed agreement*,
not *exposure*. Exposure begins one step earlier, at the `PUT`, so a baseline
test leaves a window between one pass's step 8 and the next pass's step 9 in
which the bytes are already reachable server-side while the check still answers
"never published" — a narrower version of the hole this rule exists to close.

**Backfill.** `updated_at` is stamped at migration time. `existence_at` MUST be
backfilled as:

| Row state at migration | `existence_at` |
| --- | --- |
| live | a single constant `T₀`, identical for every live row |
| already soft-deleted | that row's `deleted_at` |

`existence_at` MUST NOT be backfilled from `updated_at`.

**Per-kind delete semantics.** Converting to soft delete changes behaviour that
`DanceRepository` does not model, because dances are the parent in these
cascades:

- Every read that joins through to a soft-deletable parent MUST filter
  `parent.deleted_at IS NULL`. Soft delete does not fire the FK cascade that
  previously cleared `dance_tags`, `custom_field_values` and `dance_sources`.
- The referential guards in `ChoreographerRepository`, `VenueRepository` and
  `PublishedSourceRepository` MUST be kept. A tombstone applies only where the
  entity is unreferenced; see §6.8.
- Any purge added here MUST refuse to hard-delete an entity still referenced by
  a live record.

### 3.2 Sync-local tables

These are a schema change **beyond** the migration in §3.1, belonging to the
sync implementation. Every one is `deviceScoped` except where noted, and each
MUST be classified in the PR that creates it or the coverage ratchet fails.

| Table | Columns | Classification |
| --- | --- | --- |
| baseline | epoch, per-record wire hash, per-record `body` hash | `deviceScoped` |
| `id_aliases` | `losing_id`, `surviving_id`, `kind` | `deviceScoped` |
| `pending_deletions` | `kind`, `record_id`, `tombstoned_at`, `tombstone_hash` | `deviceScoped` |
| `pending_deletions` | `tombstone_blob` | **`shareable`** |
| `review_queue` | `kind`, `record_id`, `counterpart_id`, `reason`, `candidate_blob`, `candidate_hash`, `queued_at` | `deviceScoped` |
| `published_records` | `kind`, `record_id` | `deviceScoped` |
| `normalisation_skips` | `table`, `column`, `record_id` | `deviceScoped` |

`tombstone_blob` is `shareable` because it is record content that is
re-transmitted, not device bookkeeping.

**Lifecycle.** All are scoped to the store identity except `published_records`
and `normalisation_skips`, which are treated separately below. `id_aliases` and
`review_queue` clear with the baseline. `pending_deletions` MUST survive an
epoch reset and MUST clear on detach; after a restore its rows MUST be
revalidated against the restored data.

`normalisation_skips` records `(table, column, record_id)` for every row §4.1's
pass left un-normalised because its target value is occupied. It is
`deviceScoped` as bookkeeping rather than as content: it stores no name, only
the address of a row, and unlike `pending_deletions`' `tombstone_blob` nothing
in it is ever re-transmitted. Storing the target value would make part of the
row `shareable` for no gain, since §4.1 requires retry to re-derive the target
from the live column anyway.

Its primary key is `(table, column, record_id)`, for the reason §4.1 gives: a
duplicate entry would make a row block itself. Growth is bounded by the number
of rows the pass could not repair, which is bounded in turn by the number of
`UNIQUE` collisions the user's own library contains — normally zero, and each
entry is one row address rather than content. It shrinks as repairs land, so
unlike `published_records` it needs no monotonic-growth argument.

**It is the only entry here that is not store state at all**, and an
implementer who copies the nearest visible precedent will get it wrong in a way
that loses data repairs silently. `id_aliases` and `review_queue` record
conclusions drawn *about a particular store*, so clearing them with the baseline
is right. A local `UNIQUE` collision between two Unicode forms is a property of
**this device's library**: it is equally true before the device ever attaches,
while it is attached, and after it detaches, and no epoch reset makes it false.
So `normalisation_skips` MUST NOT be cleared on an epoch reset and MUST NOT be
cleared on detach — clearing it on a `409` would silently drop owed repairs and
leave rows un-normalised for the life of the install, with the completion marker
still asserting the work was done.

Individual entries also retire when the row they name is hard-deleted, which
§4.1 assigns to retry rather than to the delete paths. Restore is the one event
that clears the table wholesale, and §4.1 gives the reason: a
restore introduces rows the pass never scanned, which entry-by-entry
revalidation cannot discover. Both the marker and this table clear together so
the pass runs again.

`published_records` is required only of clients taking §3.1's forfeiture route.
It is **not** store-scoped bookkeeping and does **not** share
`pending_deletions`' lifecycle: it MUST NOT be cleared on an epoch reset, on
detach, or on restore. It is monotonic — an entry is written and never removed.

It records an irreversible physical event, that a record's bytes left this
device, and no local action can make that false. An epoch reset un-publishes
nothing: the peers that already downloaded a record still hold it live, and that
liveness is exactly what forfeiture guards against. **Detach un-publishes
nothing either**, and it is worth being precise about why, because a
store-scoped reading is the intuitive one. Detach forgets the sync ID *locally*
(§6.2 step 3); it does not `DELETE /v1/manifests/{self}`, so this device's
manifest remains on the server, and by §7.3 a blob is reachable while any
manifest for its store references it. The record therefore stays downloadable by
every peer for as long as the store lives, and a re-attach — which is a union
that deletes nothing (§6.2) — restores it against a device that kept no
tombstone. Clearing on detach would convert "the deletion sticks" into "the
deletion silently reverts", which is the defect this rule exists to prevent.

Restore needs no revalidation for the same reason it needs no clearing: the
marker's only consumer is the forfeiture check at hard-delete time, so a row
naming a record the restore removed is never read, and one naming a record the
restore brought back is still correct.

**No retirement rule, deliberately.** `id_aliases` retires on a content bound —
no current peer manifest lists the losing id (§6.6) — and that bound is not
available here. This device's own manifest is one of the manifests keeping the
record reachable, and it survives detach; retiring against peer manifests alone
would ignore it. The failure modes are also asymmetric, which is what settles
it: a wrongly-retired alias skips and reports one record, while a
wrongly-retired marker silently resurrects a deletion. Growth is bounded by the
number of records ever published rather than by activity: one
`(kind, record_id)` pair per record. Each row is smaller than the baseline entry
for the same record, which additionally carries a hash — but the row *counts*
diverge, because the baseline is rebuilt on an epoch reset and drops purged
records while this table is rebuilt by nothing. On a device with churn this
table MUST be expected to hold more rows than the baseline. The bound is
therefore absolute rather than relative: tens of bytes per pair, so a device
that has published 100,000 records over its lifetime carries a few megabytes.
An entry MUST be retained even after its record is tombstoned and purged.

`review_queue` requires a new review surface: `import_review_screen.dart`
reviews dances only. A generic keep-both-or-merge list suffices; no per-kind
editors are required.

### 3.3 Classification dependency

Device Sync holds no allow-list of its own. It reads `EgressClass` from the
privacy registry (`field_registry.dart`, `settings_registry.dart`).

- `shareable` — MAY travel.
- `deviceLocal`, `deviceScoped`, `derived` — MUST NOT be serialised into a blob.

The serialiser MUST filter by classification; the archive codec does not do this
and MUST NOT be relied on for it. The registry uses snake_case `table.column`
and the codec emits bare camelCase, so a generated mapping is required, and it
MUST be proven by test rather than hand-maintained.

**Keys with no entry.** A `settings` key may be constructed at runtime
(`editor_draft:<id>`, `program_editor_draft:<id>`), so resolution MUST go
through `classifySettingsKey`, which matches an exact `settingsClassifications`
entry first and the longest matching `settingsPrefixClassifications` prefix
second. A serialiser that reads the exact map alone is non-conforming: it
resolves every prefix-keyed classification to nothing.

`classifySettingsKey` returns null for a key matching neither map, so a
persisted key can still carry no classification at all. The serialiser MUST
fail closed: a key with no classification MUST NOT be serialised, exactly as if
it were `deviceLocal`.

Filtering MUST therefore be expressed as an allow-list of keys classified
`shareable`, never as a denylist of the other three classes. A denylist admits
every key the lookup fails to resolve, and an unresolved `settings` key can hold
unsaved user-authored dance and program content — which is exactly what the
editor draft keys held for as long as they went unclassified, until #973.
§7.2's server-side rejection is not a substitute: it happens after the bytes
have crossed the wire.

## 4. Wire format

All payloads are UTF-8 JSON.

**Compression.** Requests and responses MAY use `Content-Encoding: gzip`; it is
optional on both sides, so a conforming implementation MUST accept an
uncompressed body and MUST NOT require the header. A receiver that accepts a
compressed body MUST enforce the decompression limits in §5.4 while inflating —
aborting as soon as a running total is exceeded, never after inflating to
completion. Compression is a transport encoding only: it MUST NOT change the
bytes that the content hash in §4.2 is computed over.

### 4.1 Canonical JSON

Canonical JSON means:

- **RFC 8785 (JCS)** for key ordering, number form and string escaping. This is
  adopted by reference rather than restated: it fixes key sorting to UTF-16 code
  unit order applied recursively, numbers to the ECMAScript shortest
  round-tripping form (which emits integers without a fractional part, so `8`
  never serialises as `8.0`), and string escaping to the minimal ECMAScript set
  with non-ASCII emitted as raw UTF-8 rather than `\uXXXX`;
- no insignificant whitespace;
- envelope fields always present, `null` where empty;
- body fields: explicit `null` for an empty `shareable` field, omission **only**
  for a field that is not `shareable`;
- **timestamps emitted at exactly one-tick precision** (§2), UTC, with the
  sub-tick component always zero;
- **all strings in Unicode NFC**, normalised on write as described below.

RFC 8785 leaves the last of these out of scope, so it MUST be stated separately
and it MUST be applied before hashing. Titles and
`custom_field_values.value_text` are arbitrary user text, and a title pasted
from a macOS filename arrives in NFD while the same title typed on Android
arrives in NFC. Both display identically and hash differently, which under §6.3
is a permanent `changed`/`changed` for two records that are the same record.

**Unicode normalisation applies to every write path, not only to sync.** A
conforming client MUST normalise a `shareable` string column to NFC on **every**
path that can populate it — local edits, every import adapter, and inbound sync
alike — and MUST NOT skip it on the assumption that a sender normalised.

Satisfying that by normalising in each writer is possible and inadvisable. It is
an enumeration, and enumerations fail by omission: the next import adapter is
correct only if its author remembers. Normalise instead at the single repository
write path each kind already funnels through — in this codebase every dance
write, local or imported, reaches `DanceRepository._upsert` — so a new caller
inherits the rule rather than restating it. This specification requires the
property, not the placement; it names the placement because the property is
cheap to hold this way and expensive to hold any other.

The scope is wider than the timestamp rule below, and the difference is
load-bearing rather than stylistic. A timestamp is stored in a representation
that *physically cannot* hold sub-tick precision, so normalising inbound values
is belt-and-braces: no local write can reintroduce the problem. **A TEXT column
enforces nothing.** If normalisation were scoped to ingest, a device's
pre-existing library would never be normalised at all — §6.2 step 4 uploads it
verbatim, and the device re-serialises from that same unchanged local storage on
every subsequent pass, so an NFD title stays NFD forever. A peer ingesting it
normalises to NFC. The two devices then hold one record id and two byte strings
permanently, which is precisely the `changed`/`changed` this rule exists to
prevent. §6.10's dedupe carries the same assumption: it treats its inputs as
already NFC, and at fresh attach one side of every comparison is a local library
that arrived through no sync path.

**Normalising on write does not reach a row that is never written again.** A
title imported two years ago and never edited is repaired by none of the paths
above, and it is exactly the population the previous paragraph describes — §6.2
step 4 uploads it verbatim on first attach. A conforming client MUST therefore
run a **one-time normalisation pass** over every existing `shareable` string
column when it first upgrades to a normalising build. That pass MUST NOT modify
`updated_at`, `existence_at` or `deleted_at`.

Leaving the stamps untouched is what makes the pass safe to run independently
on each device, at whatever time each device happens to upgrade. Two devices
that normalise the same NFD row arrive at identical bytes *and* identical
stamps, so the row presents as `same` on the next pass and no conflict arises.
Bumping `updated_at` instead would hand every such row to whichever device
upgraded last — a mass, silent, direction-arbitrary resolution over rows nobody
edited.

This is a deliberate, bounded exception to invariant I1 (§6.5), which otherwise
requires any change to serialised content to advance `updatedAt`. It holds
because the pass satisfies I1's exception condition in §6.5 and for no other
reason. NFC is a pure, idempotent function of the stored string, and the pass
consults no clock, device identity or external state; where it does read beyond
the row being written — the collision check below — it does so under the bounded
carve-out §6.5 states, and any divergence that carve-out admits is **always
reported and never silently resolved**. Every constraint below exists to keep
that true.

**The scope is `shareable` string columns that are not record identity.** A
column whose value *is* the record's id MUST be excluded: `settings.key` is a
`shareable` string, but §4.4 makes it the settings record's identity, so
normalising it would rename the record rather than repair its content. Today
this is a no-op — settings keys are ASCII app constants, for which NFC is the
identity function — but the exclusion is stated because the pass is defined over
a classification, and the classification does not know which columns are ids.

**Normalising can collide.** `choreographers.name`, `tags.name` and
`custom_field_defs.key` are `UNIQUE` (§6.6), so two rows differing only in
Unicode form collapse onto one string and the write fails.

**Collisions MUST be detected against a pre-pass snapshot, not by attempting the
write.** The pass MUST first compute the target value for every in-scope row,
group the rows by that target, and only then write. Any group with more than one
member MUST be skipped whole, leaving **every** member in its stored form.

**The grouping key is `(table, column, target)`, not the target alone.** The
in-scope rows span three tables with three independent `UNIQUE` indexes —
`choreographers.name`, `tags.name` and `custom_field_defs.key` — and a tag and a
choreographer bearing the same name do not collide at the database level.
Grouping by target alone would treat them as colliding and skip both
permanently: unlike a real collision, a cross-table one never stops colliding,
so the retry below can never repair it. Two conforming implementations would
then diverge on ordinary input.

Detecting collisions by catching the `UNIQUE` violation instead is
order-dependent and produces the wrong outcome. If two rows are stored in
different decompositions that normalise to the same target, the first is written
successfully — nothing holds the target yet, because the second is still in its
own un-normalised form — and only the second fails. That normalises one member
of a pair the rule requires to be left alone, and *which* member depends on
row-processing order, which no rule fixes. Two devices could then normalise
opposite members of the same pair. Grouping before writing removes the ordering
question entirely rather than answering it.

Grouping MUST include soft-deleted rows, because a tombstone continues to
occupy its natural key: soft delete is an `UPDATE`, and none of the three
`UNIQUE` indexes is filtered on `deleted_at`. A tombstone can therefore block a
live row.

The pass MUST NOT merge colliding rows. Merging is excluded on the same grounds
§6.6 step 1 excludes it for two pre-existing local rows: whether two
similarly-named choreographers are one person is a judgement, and the rows may
differ in fields beyond the name. It is also excluded by the exemption this pass
depends on — a *user* resolving the same pair differently on two devices is
exactly the divergence I1 orders.

**A skip MUST be recorded and retried, not treated as final.** The pass MUST
record every skipped row in `normalisation_skips` (§3.2) and MUST re-attempt the
recorded rows on each subsequent open, clearing an entry once its row is
written. Re-attempting is bounded by the number of recorded rows rather than by
the size of the library, so it is not a repeated full scan.

**Recording MUST be idempotent, and `normalisation_skips` MUST carry a primary
key on `(table, column, record_id)`.** The pass commits its row rewrites and its
skips together, and an interrupted pass re-runs from the start rather than
resuming, so recording MUST be an upsert. A duplicate entry
is uniquely harmful for this table, because condition (a) of the retry test asks
whether any *other recorded row* derives the same target: a second entry for a
row is, read literally, another recorded row deriving that row's target, so the
row blocks itself permanently for a collision that does not exist, and a
duplicate can never stop colliding with its own twin. The other tables in §3.2
also state columns without keys, but none of them turns a duplicate into a
self-blocking condition.

**The spelling of `table` and `column` MUST be pinned, and MUST come from a
single generated source shared by both writers.** The table has two independent
writers — the one-time pass and the write-path carve-out below — and retry's
condition (a) correlates their entries by grouping on `(table, column)`. If the
two writers spell the same column differently, their entries never group,
condition (a) silently stops correlating them, and collision detection degrades
with no error raised and nothing to notice: the failure is invisible unless
someone compares spellings across two call sites. The values MUST be the
snake_case `table.column` form the classification registry already uses
(`'choreographers.name'`), not the Dart-side accessor names, since that is the
form the in-scope column set is defined over — but the point is the shared
source rather than the choice: §3.3 requires a generated mapping *"proven by
test rather than hand-maintained"* for the same class of mismatch between
registry and codec spellings, and the same standard applies here. That source
has to be built, because nothing importable exists today: the registry's
identifiers are inline string literals used directly as map keys
(`'tags.name': _choreography`), not exported constants, and the
carve-out lives at a separate call site in each of the three in-scope
repositories. The concrete requirement is therefore named rather than left to
inference — the identifiers MUST be declared once, as constants or generated
symbols, and imported at all four sites. Two hand-typed literals reconciled
after the fact by a test would catch drift once someone thought to write that
test, which is not the same as making the two spellings the same object. Note
that this is not a convergence concern: the table is `deviceScoped` and never
transmitted, so the damage is confined to a single install, which is why
nothing downstream would ever surface it.

**Retry MUST apply the same grouping test as the initial pass, re-derived from
live state.** A recorded row MUST be written only when both conditions hold: no
*other recorded row* in the same `(table, column)` currently derives the same
target, and the live `UNIQUE` column holds no occupant other than the row
itself. If either fails the row stays recorded. Both conditions are
load-bearing, and each catches a case the other misses.

Testing live occupancy alone would split a mutually-colliding pair. Rows `A`
and `C` recorded together, both stored NFD and both deriving target `T`, occupy
nothing: `A` holds its own NFD bytes, and so does `C`. `T` therefore reads as
unoccupied for `A`, which is written; `T` is then occupied for `C`, which stays
skipped. The pair the initial pass deliberately left whole is split, and *which*
member is normalised depends on the order the client walks
`normalisation_skips` — an order no rule fixes. Two devices could then normalise
opposite members of the same pair, which is the divergence grouping exists to
prevent, reintroduced at retry time.

Testing recorded-row grouping alone would raise. Suppose `A` and `C` are
recorded as above, and a later unrelated row `D` is created carrying `T` already
in NFC: that write succeeds, because `A` and `C` still hold their own
un-normalised bytes and nothing yet occupies the value. The user then renames
`C`. `A` is now the only recorded row deriving `T` — a singleton by the grouping
test — so a client consulting only the recorded set would write `A` and raise
against `D`. Judged also against the live column, `A`'s target is plainly
occupied and `A` stays recorded.

This is why an entry stores only `(table, column, record_id)` and neither the
target value nor the membership of the group it was skipped with: both are
snapshots of a moment, and the test above re-derives each from live state on
every attempt. The cost bound is unchanged — the grouping is computed over the
recorded rows and the occupancy check is one indexed lookup per row, neither
scaling with the size of the library.

The two conditions together are equivalent to the initial pass's pre-pass
snapshot, and the reason is worth stating because it is what makes a test over
the recorded set sufficient: **every un-normalised in-scope row is recorded.**
The initial pass records every row it skips, the write-path carve-out below
records any later write it cannot normalise, and the two events that introduce
rows no pass has judged both re-run the full scan. An in-scope row that is *not*
recorded therefore already holds its own target, which is exactly what the
occupancy condition observes.

The first such event is a restore, which clears the marker and the table
(§6.11). The second is **a change to the in-scope column set itself**: a column
reclassified to `shareable`, or a new `shareable` column added, brings rows
into scope that the completed scan never judged, while the marker goes on
asserting the work is done. That is not a hypothetical — §7.2 treats a new
`shareable` field as an anticipated, recurring event — and left unhandled it
reproduces exactly the failure the one-time pass exists to close, since
normalising on write never reaches a row that is never written again. **The
completion marker MUST therefore record the set of columns the scan covered,
and the pass MUST re-run whenever the live in-scope set differs from that
recorded set.** The obligation is stated over the *comparison*, not over a
migration, because only one of the two triggers involves a migration at all:
adding a column does, but reclassifying one is an edit to a plain map entry in
`field_registry.dart` — changing `egress` there touches no schema, bumps no
schema version, and runs no migration step. An implementation that satisfies
this rule by clearing a boolean marker from a migration hook would therefore
satisfy it *vacuously* for reclassification, leaving the newly in-scope rows
un-normalised behind a standing marker, which is the failure this paragraph
exists to close. Comparing the recorded set against the live one at open
catches both triggers with one mechanism and needs no migration to remember
anything. Re-running is a no-op for every already-normalised row, so the cost
falls on the change that altered the set rather than on ordinary opens.

**The comparison MUST be inequality, not containment**, which is worth stating
because containment is the tempting form and is subtly directional. A pure
removal shrinks the live set, so it is contained in the recorded one and would
trip nothing; the recorded set therefore never contracts and becomes a
high-water mark. A column reclassified *out* of `shareable` and later back *in*
would then still be contained, and the re-run would stay silent — while during
the interval the column was out of scope, the write-path rule did not apply to
it, so its rows could accrue NFD through ordinary edits, unrecorded, because the
carve-out records only writes it cannot normalise and an out-of-scope column is
not normalised at all. On re-entry those rows are in scope, un-normalised and
unrecorded, which is precisely the completeness invariant above. Inequality
closes it at the price of one harmless no-op scan after a removal, which
refreshes the recorded set so that a later re-entry is seen. Contracting the
recorded set without rescanning would save that scan, and is rejected: it is a
second bookkeeping path that must itself be crash-safe, added to avoid a scan
that happens at most once per reclassification.

**The live in-scope set MUST be derived, not enumerated by hand.** It is
defined as `shareable` string columns that are not record identity, and that
predicate cannot be read off the classification registry alone:
`DataClassification` carries `term`, `subject`, `egress` and `note`
(`data_classification.dart:185`–`:205`) and no column type, so *string* is a
fact about the schema rather than about the registry. The set MUST therefore be
computed by reflecting over the schema's column types intersected with
`fieldClassifications`, **and with identity columns excluded by reflection
too** — `Table.primaryKey` is declared throughout the schema and is the
mechanical form of the third criterion. All three criteria MUST be mechanised,
and the identity one is the criterion most easily left in prose while the other
two are automated, which would be worse than not mechanising any of them: a
literal *string ∩ `shareable`* set pulls in **every primary key in the
schema**, because `_key` is classified `shareable` and identity columns use it
(`'dances.id': _key`, `'tags.id': _key`) as ordinary text columns.
`settings.key` is the sharpest case — separately classified `shareable`, and
*is* its record's identity (`primaryKey => {key}`) — so an implementation that
normalises it renames records instead of repairing them, contradicting both
this section's own scope sentence and §9's vector that `settings.key` is not
rewritten.

That derivation MUST be backed by a ratchet in the same family as the existing
coverage test, and it MUST assert the identity exclusion specifically. The
coverage test as it stands cannot: it compares `table.column` names for presence
and staleness and inspects neither column type nor primary-key membership, so it
would pass unchanged if the derivation leaked in every primary key in the
schema. A ratchet that checks only what the existing one checks would look like
coverage for this rule without being it. That test already walks
`db.allTables` and each table's `$columns` to build exactly the snake_case
`table.column` keys this rule needs, and Drift's columns are typed, so a string
column is identifiable rather than assumed; the two tables it has to read
untyped through `pragma_table_info` are the derived full-text indexes, which
are rebuilt rather than scanned and are not in scope here. The alternative is
the hand-maintained list §3.3 forbids elsewhere, and here it does something
worse than drift: a newly `shareable` column missing from a stale hand-list
never enters the live set, so the comparison never differs, and the safety net
this paragraph exists to provide is disabled by the way its own input is
computed.

Recording a column set turns the marker from a presence latch into a settings
value carrying structured content, which is mechanically ordinary — sweep
markers already store JSON — but worth one note on classification. Sweep markers
sit outside the settings classification ratchet: it matches declarations named
`k…Key`, and every marker is named `…DoneKey` or `…RequiredKey`, so none is
captured. That is pre-existing and deliberate rather than something this design
introduces, and §3.3's fail-closed rule contains it — an unclassified key is
treated as `deviceLocal` and never serialised. The content here is a list of
schema identifiers, which carries no user data in any case. The marker is
install state, not store state, and is not part of §3.2's inventory.

Raise-safety does not rest on this argument. A retry write can only raise if
some row already holds the target, and condition (b) observes that occupant
whether or not it is recorded. Completeness is what condition (a) needs, and
condition (a) is what prevents divergence; the two conditions fail
independently, which is why both are stated.

Retry is what keeps every blocking condition resolvable, and it is the reason
this specification does not need a special case for tombstones. A blocked row
unblocks when the user renames or deletes the row occupying its target, when a
blocking tombstone is purged, or when reconciliation renames one side — and in
each case the next open completes the repair with no further rule. Without
retry, a live row could be left permanently un-normalised by a tombstone the
user cannot see, cannot list and cannot act on, which is strictly worse than the
live-pair case and would be invisible in support.

**An entry whose row has been hard-deleted MUST be retired.** An entry is
cleared when its row is written; it MUST also be discarded when the row it names
no longer exists. Hard deletion is a shipped path, not a hypothesis:
`ImportPipeline.undo` rolls back a just-committed import with
`delete(id, permanent: true)` on `choreographers`, one of the three in-scope
tables. Without retirement the entry names a `record_id` that no longer exists,
can never be written and so never clears — bookkeeping accumulating from an
ordinary user flow — and retry's instruction to recompute the target from the
row's current stored value has no value to read.

Retirement MUST be performed by retry, which discards any entry whose row is
absent, rather than by the delete paths. This is a decision rather than a
constraint, and the reason is that the table is polymorphic — one `record_id`
column spanning three tables — so it cannot carry an `ON DELETE CASCADE`
foreign key, and the alternative is an obligation on every present and future
hard-delete path in three repositories. Placing it in retry makes the table
self-healing against deletions nobody remembered to account for, which is the
failure mode that actually occurs. Retiring an entry is not a repair and MUST
NOT count as a write for the index-rebuild rule below.

**Soft-deleted rows MUST NOT be retired.** A tombstone is an `UPDATE` and
continues to occupy its natural key, exactly as the grouping rule above states;
retiring its entry would drop a repair that is still owed and still blocked.
Only the disappearance of the row itself retires an entry.

**Both the existence check and retry's value read MUST use a lookup that does
not filter `deleted_at`, and no such lookup exists today.** This is a new query,
not an existing accessor, and the distinction is the difference between the two
rules above working and one of them silently destroying repairs. All three
in-scope repositories expose a `getById` that filters on `deleted_at`
(`choreographer_repository.dart:67`, `tag_repository.dart:82`,
`custom_field_repository.dart:74`), and none takes an `includeDeleted`
parameter. Such a lookup returns `null` for a tombstone *and* for a hard-deleted
row, so an implementer reaching for the obvious accessor retires exactly the
entries the rule above forbids retiring — the quiet loss this section is written
to prevent, reached by writing the natural implementation rather than a careless
one. The same lookup is what retry reads the current stored value from, and a
recorded row may legitimately be a tombstone, since grouping deliberately
includes soft-deleted rows.

The trap is sharpened by an inconsistency in the codebase rather than by
anything in this design: `DanceRepository.getById` *does* take
`includeDeleted` (`dance_repository.dart:685`), so the pattern looks uniform
from the one place it is implemented and is not. Implementations MUST therefore
distinguish three outcomes, not two: a live row, a tombstoned row, and no row.

**A later ordinary write to a row whose target is occupied MUST NOT fail.**
§4.1's write-path rule requires every write to normalise, which would re-attempt
the colliding value. The write MUST instead store the value un-normalised and
record the row in `normalisation_skips`. A user's edit is never rejected to
satisfy a normalisation rule.

**A restore (§6.11) MUST clear both the completion marker and
`normalisation_skips`, so that the pass runs again over the restored library.**
The marker asserts that a scan completed over *a* library, and a restore writes
rows the scan never saw — a restored row can be un-normalised while the marker
declares the work done, and a recorded entry can name a row the restore replaced
or removed. Revalidating entry by entry would be the cheaper repair but not a
correct one, because it cannot discover never-scanned rows. The cost is one
additional scan on an operation that is rare and already rewrites the library.

Skipping is not free, and the cost is worth stating. A skipped row stays in its
stored form, so it keeps whatever behaviour it has today, including exclusion
from §6.10's dedupe. If one device holds a colliding pair and a peer holds only
one of its members, the peer normalises its copy while this device does not.
Because the pass never touches `updated_at`, the shared record id then presents
to the skipping device as `same`/`changed` with **equal** `updatedAt` — its own
copy is unchanged against its baseline; the peer's has changed. Per §6.3 that
row's `>` is strict, so the difference is left un-downloaded rather than guessed
at, and MUST be reported on that pass and on every subsequent pass until a human
edits one side. The peer meanwhile sees an ordinary `changed`/`same` and
uploads, so the report is raised by the skipping device; it is a standing,
visible, non-convergent state over a pair the user already has reason to look
at, which this specification prefers to a silent merge, but which is a real cost
and not a formality.

**The pass MUST be idempotent and safe to interrupt.** Because skipping is the
only failure response, the pass is total: no row raises, so an interrupted pass
cannot repeat a failure on every launch. Re-running it over already-normalised
rows is a no-op.

**Every pass that rewrites a row MUST commit in three steps, and MUST NOT write
its completion marker until the derived rebuild has succeeded.** The steps are:
(1) the row rewrites, the `normalisation_skips` upserts and a durable *rebuild
owed* flag, all in one transaction; (2) the derived rebuild, **outside** that
transaction, and then the clearing of the flag, once the rebuild returns; (3)
for the one-time pass only, its completion marker, written last. A pass that
wrote nothing sets no flag and performs no rebuild; the one-time pass still
writes its marker, carrying the column set that run covered.

**The flag's set and its clear MUST share one condition.** Step 1 writes the
flag exactly when step 2 will rebuild, never on a broader trigger, because the
flag asserts *a rebuild is owed*: a path that sets it with no rebuild to follow
leaves nothing to clear it, and the next open's generic pre-check acts on it.
The default condition is "the pass rewrote something". The permission below
narrows that condition, and narrows **both** halves of it together — narrowing
one alone inverts the optimisation rather than partly achieving it.

**Clearing the flag belongs to step 2, not to the marker**, because retry has no
step 3 and would otherwise leave the flag standing after a rebuild it already
performed. The next open's generic pre-check would then see an owed rebuild that
is not owed and perform a second full one before clearing it — self-healing, but
paying a whole-library recomputation per repaired row, on app open. The
reference implementation clears in exactly this position, between the rebuild
and the marker (`:1011`–`:1016`), and gives this reason: otherwise *"the next
call's unconditional top-of-`_runMigration` check would redo a rebuild that is
no longer owed"* (`:1007`–`:1010`).

Bundling the marker into the mutation transaction instead — the shape of a sweep
that has no rebuild — is unsafe here, and unsafe permanently rather than until
the next open. A crash between the commit and the rebuild would leave the marker
asserting the scan is done while the full-text and substring indexes still hold
pre-normalisation text; the pass never runs again, and every later retry pass
writes nothing, so the rule below forbids the rebuild that would repair them.
Search would silently stop matching exactly the rows the pass had just fixed.
Running the rebuild *inside* the transaction is the other way to close the gap
and is rejected: it puts a full recomputation of derived data over the whole
library inside a write-locked transaction.

**The durable flag MUST be `derivedRebuildRequiredKey`** — the key already
declared at `database.dart:105` — and MUST NOT be a flag private to this pass.
This is the load-bearing half of the rule, because the repair does not come from
the sweep that sets the flag. It comes from an unconditional, pass-independent
check at the top of the migration path (`repositories.dart:467`–`:491`) that
runs *before any sweep*, rebuilds whenever the key is set (`:475`), and clears
it. A private flag reproduces the shape while leaving the mechanism behind, and
it reopens the exact gap this rule exists to close: a pass that checks and
clears its own flag resumes after a crash, rescans, finds nothing left to
rewrite, never fires its own rebuild, and leaves the flag and the stale index
standing forever. `_backfillChainHandIfNeeded` states this in its own comment
(`:939`–`:941`) — the owed rebuild is performed *"regardless of what this
sweep's own rescan finds"*, and it is performed by the next open's generic
check, not by the sweep. An implementation that introduces a different key
instead MUST first generalise that pre-check to cover it, since a key nothing
reads is not a safety net.

**The obligation attaches to any pass that writes, including retry — not to the
one-time pass's lifecycle.** Retry rewrites rows; that is its entire purpose,
and the rebuild rule below already contemplates it, excusing only a retry pass
in which every recorded row is still blocked. But retry never writes the
completion marker, because the marker already exists, so an obligation phrased
around step 3 would leave retry uncovered — with the same permanent
consequence: retry repairs a row, the process dies before the rebuild, and on
the next open retry rescans, finds nothing left to write, and is then forbidden
from rebuilding. Retry is also the path that runs forever rather than once, so
it is the likelier of the two to be interrupted in the field. The reference
implementation makes exactly this choice, keying the flag off `rewroteAny`
(`:985`) rather than off a pass lifecycle, and its comment names this case: the
flag *"forces the owed rebuild on the next open, even though a retry's own
rescan would find nothing left to rewrite"* (`:986`–`:990`).

That shape is `_backfillChainHandIfNeeded`'s: rewrites committed with the flag
(`:991`) in one transaction, `runDerivedRebuild` outside it (`:1006`), the flag
deleted once that returns, the done-marker last (`:1021`). It is deliberately
not the two-step shape used by sweeps with no derived
data to rebuild (`_repairPurgeCorruptionIfNeeded`, `:557`, `:569`), which is
where the simpler "marker in the same transaction" reading comes from. There is
no single sweep convention in that file to appeal to — markers are written
inside the mutation transaction in some sweeps and only after success in others
— so this specification states the shape it requires rather than citing "the
convention". What every shape does share, and what this pass also requires, is
that an interrupted sweep re-runs from the start rather than resuming.

**The pass MUST rebuild derived indexes if it wrote anything.** Full-text and
substring indexes over `shareable` text are maintained by the repository layer
on each write; a bulk normalisation that bypasses that layer leaves them holding
the pre-normalisation text, so search silently stops matching rows the pass just
changed. Rebuilding derived data is a local recomputation that touches none of
the three stamps, so it composes with the rule above. A pass that wrote nothing
— including a retry pass in which every recorded row is still blocked — leaves
the indexes correct and MUST NOT rebuild them.

**The available rebuild is whole-library and dance-scoped, while two of the
three in-scope columns do not feed it.** `runDerivedRebuild` forwards to
`DanceRepository.rebuildAllDerived`, which clears and repopulates `dance_fts`,
`dance_substring_fts` and `dance_figures` for every dance; it is the only
rebuild routine that exists. Its indexed columns are `title, authors, hook,
notes, figures_text, custom_values, sources`, and the row is assembled from
resolved author names, custom-field *values* and source texts
(`dance_repository.dart:509`–`:531`). Of the three tables this pass exists for,
only `choreographers.name` reaches an index, through `authors`; `tags.name` and
`custom_field_defs.key` reach none. So a pass that repairs only tags or
custom-field keys — plausible, since small controlled vocabularies are where
these collisions are likeliest — pays a full recomputation over the whole dance
collection for indexes whose content did not change.

An implementation **MAY** narrow the step-1 condition — setting no flag and
running no rebuild — when it can demonstrate by test that no column it rewrote
feeds any derived index; it MUST do both otherwise. That is one decision with
two consequences, taken once in step 1, and not two independent choices.
Skipping only the rebuild is strictly worse than declining the permission: the
flag is committed, the clear is bound to a rebuild that no longer happens, so
the flag survives and the next open's generic pre-check performs the
whole-library rebuild anyway — the same work, deferred to app open, with the
targeting lost. Narrowing only the set is wrong in the other direction, leaving
a rebuild running with nothing durable recording that it was owed.

It is a permission and not an obligation deliberately: rebuilding unnecessarily
is slow, whereas *not* rebuilding when it was needed is the permanent, silent
staleness this section has been closing, so the two errors are not symmetric and
the default must fall on the safe side. An implementation that never builds the
mapping below is fully conforming and simply pays the rebuild — the conservative
reading, that every rewrite feeds an index, is always available and always
correct. The permission is worth stating at all because the common tag-only
repair otherwise carries the largest cost in the design.

**That mapping is not reflectable, and MUST NOT be reached by reflection.**
Nothing in the schema records that `authors` comes from `choreographers.name`.
The FTS tables are raw `fts5(...)` strings carrying column names and no
provenance, and the indexed row is a positional Dart list assembled by hand
(`:514`–`:523`) across joins and many-to-one relations: `authors` resolves
through `dance.authorIds`, and `sources` concatenates *two* columns of
`published_sources` (`:581`–`:582`). Reflection recovers the FTS column names,
which is the half a skip does not depend on.

An implementation that takes the permission MUST instead **declare the mapping
once and check it behaviourally**: seed a distinct marker in every column of the
live in-scope set, run the rebuild, read the indexed rows back, and assert that
the markers reaching indexed columns are exactly those the declaration predicts.
**Every seeded row MUST be reachable from a dance the rebuild covers** — the
tag applied to a dance, the choreographer credited on one. The rebuild is
dance-scoped, so an unreferenced row contributes nothing to any index whatever
the mapping says, and the negative half of the assertion would hold vacuously
for exactly the columns the skip depends on.
`dance_fts` is an ordinary `fts5` table whose columns are selectable, and tests
already read from it directly (`migration_test.dart:234`). The assertion MUST be
total over the in-scope set, so that a column entering that set fails the test
until it is declared as feeding an index or not.

Observing the assembly is the point, because the drift that would silently
invalidate a skip need not touch the schema at all: `sources` reaches two
columns only because a loop in `_resolveSourceTexts` appends both, and a third
would be the same edit — invisible to any rule watching `CREATE VIRTUAL TABLE`.
This is the same bargain as the rest of this section, and the opposite trade
from the identity exclusion above: where a fact *is* schema-shaped it MUST be
reflected, and where it is not, it MUST be declared and tested rather than
asserted in prose or inferred from a schema that does not carry it.

Two number values that JSON cannot represent MUST be handled rather than
emitted: a `shareable` float column can hold NaN or ±Infinity — `SQLite` REAL
admits both — and RFC 8785 has no encoding for either. A record whose canonical
form would require one MUST be treated as malformed and rejected on the terms of
§6.7, never coerced to `null` or `0`, which would silently alter user data and
still not converge.

**A string can be un-encodable for the same reason a number can.** Dart strings
are UTF-16 and may contain an unpaired surrogate, which has no UTF-8 encoding
and therefore no RFC 8785 encoding. Implementations disagree about it — some
substitute `U+FFFD`, some emit WTF-8, some throw — and any two that disagree
produce different bytes for one record, which is the same non-convergence the
NaN rule closes. A `shareable` string containing an unpaired surrogate MUST be
treated as malformed and rejected on the terms of §6.7, on both the sending and
the receiving side. It MUST NOT be repaired by substitution: replacing it with
`U+FFFD` converges only if every implementation chooses the same repair, and
silently alters user data if it is ever wrong.

**The platform performs that repair for you, and does not tell you.** In Dart
the substitution is not opt-in: `utf8.encode` on a string holding a lone
`U+D800` returns the three bytes of `U+FFFD` and throws nothing, and
`jsonEncode` emits a `"\ud800"` escape without complaint — both measured
against this repository's toolchain, not inferred. A canonicaliser that
serialises and then encodes therefore hashes the **repaired** bytes. Two
devices then agree on that hash while holding different strings: the sender
keeps its surrogate, the receiver stores `U+FFFD`, both re-serialise to the
same bytes forever, and the record never presents as `changed` again. The
rejection this rule requires would never fire, and the divergence it exists to
prevent would be frozen in rather than caught.

The check MUST therefore run against the string, **before** any encoding step,
because the encoding step cannot signal the error. `utf8.decode(bytes,
allowMalformed: true)` performs the same substitution on the receiving side and
is forbidden here for the same reason.

`sanitizeImportedText` now closes the **import** path.
[#1063](https://github.com/ibanner56/CallersCompendium/issues/1063), filed
separately because it was an import defect that sync makes expensive rather
than a sync defect, was fixed by #1065: a lone surrogate of either half is
stripped and flagged, and a valid surrogate pair is preserved — measured.

That does not discharge the rule above, for two reasons. The platform
substitution is unchanged, so a canonicaliser that checks after encoding still
sees repaired bytes and no error; the check must run on the string regardless of
what any upstream sanitiser did. And rows imported **before** that fix may still
hold a lone surrogate, which is the same shape as the never-normalised library
in §4.1 — a write-path repair does not reach a row that is never written again.
Those rows need no new rule: the send-side rejection above catches them when
they are first serialised, which is the earliest moment sync can observe
them.

**Timestamp canonicalisation is mandatory on ingest.** A receiver MUST truncate
every inbound timestamp to a tick boundary *before* storing it and before
computing any hash over it, and MUST NOT assume a sender did so.

This is load-bearing, not tidiness. §4.2 hashes each device's **own**
re-serialisation, so if a peer emits a sub-tick value that the local
representation cannot store, the receiver persists the truncated value,
re-serialises a different byte string, and publishes a hash that disagrees with
the sender's on every subsequent pass. The record then reads `changed`/`changed`
forever and never converges. Any peer can trigger that, deliberately or by
carrying a finer representation, so truncating on ingest is what closes the
round-trip.

Two devices holding an identical record MUST produce identical bytes. A change
to canonicalisation is a wire-format break and MUST bump `v`.

### 4.2 Content hash

```
hash = lowercase-hex(SHA-256(canonical-json(blob)))
```

The baseline additionally stores a **`body`-scoped** hash over the same
canonicalisation, used only by §6.9.

### 4.3 Record blob

Eight kinds produce blobs: `dance`, `program`, `choreographer`, `tag`,
`publishedSource`, `customFieldDef`, `venue`, `setting`.

```json
{
  "v": 1,
  "kind": "dance",
  "id": "8f14e45f-ceea-467a-9f8c-1f3f9a2b7c11",
  "updatedAt": "2026-08-03T04:11:22.000Z",
  "deletedAt": null,
  "existenceAt": "2026-08-03T04:11:22.000Z",
  "body": { }
}
```

| Field | Requirement |
| --- | --- |
| `v` | Envelope version. A client MUST refuse an unknown value rather than guess. |
| `kind` | One of the eight above. |
| `id` | The record's UUID. |
| `updatedAt` | Content discriminator. UTC, one-tick precision (§2). Plain local clock. |
| `deletedAt` | Non-null means tombstone. Plain local clock; also the retention timestamp. |
| `existenceAt` | Orders live↔deleted transitions. Causally stamped; see §6.4. |
| `body` | Archive-codec output, `shareable` fields only. |

Join rows are not separate records; they ride inline with their parent.

### 4.4 Settings records

One blob per settings key, `kind: "setting"`, with `id` the settings key.
Per-key rather than per-table, because egress is classified per key.

`settings` MUST gain `deleted_at`: `SettingsRepository.remove` is a hard delete
today, and without a tombstone a removed setting cannot be expressed on the
wire.

### 4.5 Manifest

```json
{
  "v": 1,
  "deviceId": "b31f...",
  "epoch": "9c4a...",
  "writtenAt": "2026-08-03T04:11:22.000Z",
  "records": {
    "8f14e45f-ceea-467a-9f8c-1f3f9a2b7c11": "e3b0c442..."
  }
}
```

`records` includes tombstones. A record absent from a manifest was never known
to that device and MUST NOT be treated as a deletion.

## 5. HTTP contract

Base path `/v1`. TLS required; a client MUST refuse a non-`https` endpoint
except `http://localhost` and `http://127.0.0.1`. The exemption is an **exact,
case-insensitive match on the host** against those two literals, and nothing
else: not a prefix, not a suffix, not a substring. `localhost.example.com` is a
public host that a `startsWith` or `contains` test admits, and it is registrable
by anyone. Nor is the exemption "the loopback range" — `[::1]`, `127.0.0.2`,
and the encodings `2130706433` and `0x7f000001` that many URL parsers accept
are all outside it. This specification does not widen the hole to save a
self-hoster the trouble.

**The consequence, stated rather than left to be discovered: a self-hosted sync
needs a certificate the client will accept, which in practice means a
publicly-trusted one on a routable name whenever a phone is in the sync set.**
Sync involves at least two devices, so the server is by definition not
`localhost` as seen from the second one; the exemption covers same-machine
testing and never a functioning deployment. **A private CA is a real path on
desktop and not one on Android**, and the rule above does not change that
either way: it forbids an in-app `SecurityContext` or `badCertificateCallback`,
which is trust the *app* extends, and says nothing about trust the *operating
system* extends. `dart:io`'s `HttpClient` honours the OS trust store on
Windows, macOS and Linux — on Windows it enumerates the `CURRENT_USER` and
`LOCAL_MACHINE` stores, so nothing about the platform gates this behind
administrator rights — and on Linux it reads the standard bundle locations,
falling back to a compiled-in list only when none exist. A self-hoster who
installs a private root into the OS store on those platforms will find the
shipping client accepts their server, with no in-app affordance and nothing for
this specification to prohibit.

That path is **available rather than recommended**, and the reason belongs next
to it rather than in a support thread later. A private root in a machine's trust
store lets whoever holds its key forge *any* TLS connection that machine makes —
banking, email, updates — not merely this app's. That is a strictly larger
exposure than the in-app trust-anchor affordance the rule above refuses, which
would have compromised this app alone; refusing the smaller risk on principle
and presenting the larger one neutrally would be incoherent. It is also more
work than it looks: on macOS the import must be followed by an explicit *Always
Trust* step, and the private key has to be generated and then kept somewhere it
cannot leak, by the same person who wanted to avoid registering a domain name.

What that path does not do is cross platforms. On Android, `dart:io` loads
`/system/etc/security/cacerts` and only that, so a user-installed CA is not
trusted for app traffic — the same conclusion the API-24 change reaches, by a
stricter route. On iOS it requires a configuration profile with trust enabled
by hand. Editing the two literals in a build you control is likewise not
practical on iOS, where a free-provisioned build needs re-signing weekly. So a
sync set of two desktops has a working private-CA path today, and any set
containing a phone does not.

The **recommended cross-platform path** is therefore a name under a domain the
self-hoster controls, with a certificate issued over the DNS-01 challenge,
which proves control through a TXT record, requires no inbound reachability,
and may be issued for a name that resolves to a private address. One caveat is
worth stating because it bites exactly this audience: issuance and *resolution*
are separate steps, and DNS-rebinding protection, which some resolvers and
consumer routers enable, refuses to return an RFC 1918 address for a public
name. The self-hoster gets a valid certificate and the second device then
cannot resolve the name at all, a failure with no visible connection to the
instructions they followed. The resolver must be configured to permit it, by a
rebinding allow-list entry or split-horizon DNS.

That is the accepted cost of refusing to ship a trust-anchor escape hatch, and
§10 records the alternative that was left open.

**A note for whoever reads this next.** Dart's published API documentation for
`SecurityContext.defaultContext` states the opposite of the paragraph above —
that Windows and Linux use a Mozilla list — and it is **stale**: the behaviour
changed in Dart 2.14 (`dart-lang/sdk#46370`) and the page was never updated. An
earlier draft of this section asserted the documented behaviour, which is the
reasonable thing to do and was wrong. The claims here were verified against
`runtime/bin/security_context_{win,linux,macos}.cc`. Do not "correct" them back
against the documentation.

**A client MUST verify the server's certificate chain and hostname, and MUST NOT
provide any way to disable that.** This is stated because the rest of this
document's transport rules test the *scheme string*, and a scheme string is not
a secure channel. In Dart, `HttpClient.badCertificateCallback` returning `true`
— or a `SecurityContext` that trusts an injected root — leaves every URL
beginning `https://`, satisfies every check in §8's per-hop table, and reduces
the transport to plaintext against anyone positioned to present a certificate.
The failure has no symptom on either side. A conforming client therefore has no
"trust this certificate anyway" affordance, no debug flag that becomes a
shipped one, and no allowance for a user-supplied trust anchor: with the sync ID
riding every request as a bearer credential, an accepted bad certificate is the
same total, unrecoverable disclosure that a plaintext request would be.

### 5.1 Authentication

The sync ID travels in the `Authorization` request header using the `Bearer`
scheme, with the sync ID as the credential. It MUST NOT appear in a URL.

The server MUST derive a storage key as `HMAC-SHA256(pepper, syncID)` and MUST
NOT persist the plaintext sync ID. The sync ID is normalised first, exactly as
§8 specifies; a client and server that disagree there resolve one typed ID to
two stores and report no error at all. The pepper MUST live in server
configuration and MUST NOT be stored in the database. This is server-side only;
the client computes no MAC and MUST NOT hold the pepper.

**Content types.** Every request and response body in §5.2 is JSON except a blob
body, which is opaque octets. A client MUST send `application/json` on a JSON
request body and `application/octet-stream` on a blob `PUT`. A server MUST
accept a `Content-Type` carrying parameters — `application/json; charset=utf-8`
is the same media type — and MUST NOT reject on the parameter. A server MAY
reject a body whose media type is wrong with `415`, and MUST NOT treat a
*missing* `Content-Type` as an error, since neither choice affects what is
stored and an exact-string comparison here rejects conforming clients for a
header that carries no information the request does not already imply.

### 5.2 Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/store` | Store metadata: epoch, device list, quota usage. Creates the store if absent. |
| `DELETE` | `/v1/store` | Wipe store (destructive). |
| `GET` | `/v1/manifests/{deviceId}` | Fetch one manifest. `ETag` / `If-None-Match`. |
| `PUT` | `/v1/manifests/{deviceId}` | Publish this device's manifest. |
| `DELETE` | `/v1/manifests/{deviceId}` | Remove a device's manifest. |
| `GET` | `/v1/blobs/{hash}` | Fetch one blob. Immutable; long `Cache-Control`. |
| `PUT` | `/v1/blobs/{hash}` | Upload one blob. Idempotent. |
| `POST` | `/v1/blobs/missing` | Given hashes, return the subset the store lacks. |

Blob and manifest bodies are specified byte-exactly in §4.3 and §4.5, because
they are hashed. The two endpoints below are not content-addressed, so nothing
forced their shape and it is stated here instead.

**`ETag` on a manifest `GET`.** The value MUST be the manifest's own content
hash (§4.2), serialised as an RFC 7232 strong validator: the lowercase hex
digest wrapped in double quotes, `"a3f5…"`, quotes included. A client MUST send
it back verbatim in `If-None-Match` and MUST treat `304` as "my cached manifest
is current". Both halves are stated because neither is inferable and both fail
quietly: the manifest hash is already computed on both sides, so any other
derivation is gratuitous divergence, and an unquoted value is not a valid
entity-tag — some HTTP clients reject it, others pass it through, so a server
emitting one interoperates with a client library by luck. The failure is a
permanent fallback to refetching every manifest every pass, which is invisible
except as traffic.

**`GET /v1/store`.** Creates the store if absent (§7.1) and returns:

```json
{
  "epoch": "9c4a1f2e8b7d4a6c9e0f1a2b3c4d5e6f",
  "devices": ["b31f...", "7c02..."],
  "quota": { "blobs": 1234, "bytes": 5242880,
             "maxBlobs": 100000, "maxBytes": 262144000 }
}
```

| Field | Requirement |
| --- | --- |
| `epoch` | The store's current epoch, lowercase hex. Compared at §6.3 step 1. |
| `devices` | Device ids with a manifest in this store, including the caller if it has published. Order is unspecified; a client MUST NOT depend on it. |
| `quota.blobs`, `quota.bytes` | Current usage. |
| `quota.maxBlobs`, `quota.maxBytes` | The §5.4 caps, echoed so a client can warn before hitting them rather than discovering a `507`. |

`devices` is the peer set that drives step 3's per-peer manifest fetches. A
client MUST exclude its own id from that iteration.

**`POST /v1/blobs/missing`.** Request and response are both objects, not bare
arrays, so either can gain a field without a `v` bump:

```json
{ "hashes": ["e3b0c442...", "a3f5b1c9..."] }
```

```json
{ "missing": ["a3f5b1c9..."] }
```

`missing` is the subset of `hashes` the store lacks; a hash the store already
holds is omitted. Every hash in the request MUST match `^[0-9a-f]{64}$`
(§7.1) — the whole request is rejected `400` if any does not, rather than the
offending hash being skipped, so a client cannot read a short response as
"present".

**Blob `PUT` verification.** The server MUST verify that the body hashes to
`{hash}` under §4.2 and MUST reject `400` if it does not. Without that check
any holder of the sync ID can store arbitrary bytes under a chosen hash, which
would break the content-addressing that "Immutable; long `Cache-Control`"
depends on and let a peer serve one record's bytes under another's name. A
`PUT` to a hash the store already holds MUST be treated as a no-op returning
`200` and MUST NOT overwrite the stored bytes; once verified the bytes are
identical by definition, so a rewrite can only be a downgrade. The no-op MUST
NOT update `uploaded_at` either. That column is the sole input to §7.3's grace
window, so refreshing it on each repeat `PUT` would let a client that re-uploads
the same never-manifested blob every pass keep it collection-immune
indefinitely, and the window would bound nothing.

### 5.3 Status codes

| Code | Meaning |
| --- | --- |
| `200` | OK. |
| `201` | Blob or manifest created. |
| `204` | Deleted. |
| `304` | Manifest unchanged. |
| `400` | Malformed request. |
| `401` | Missing or malformed `Authorization`. |
| `403` | Sync ID fails the structural rule (four hyphen-separated words). |
| `404` | No such blob, manifest, device — or store. |
| `409` | Epoch mismatch. |
| `413` | Payload exceeds a cap. |
| `415` | Body media type is not the one the endpoint expects (optional; see §5.1). |
| `422` | Payload rejected by the allow-list. |
| `429` | Rate limited. `Retry-After` set. |
| `507` | Store quota exhausted. |

There is no distinct "expired" status. Reset detection is the epoch's job. A
client receiving `404` from a store-scoped endpoint recovers by calling
`GET /v1/store`.

`413` and `507` divide on **per-request versus per-store**, and the split is
normative because it is otherwise a coin toss. A single request exceeding a
size cap — blob size, manifest size, parse depth, decompressed size, or the
number of elements in a request body such as §5.4's hashes-per-request cap — is
`413`. Any *aggregate* cap on the store is `507`: blobs per store, bytes per
store, and **devices per store**, so the 33rd device attaching receives `507`
rather than `413` or `429`. A client MUST surface `507` to the user and MUST NOT
retry it without user action, since nothing the client does alone clears it.

That last rule has one qualification the client MUST honour. §7.3 keeps
unreferenced blobs for a 24-hour grace window, so space freed by deleting
records or detaching a device may not be reclaimable immediately: a `507` can
persist after the user has already done the thing that should clear it. The
client MUST NOT present such a `507` as permanent, and MUST NOT treat the
user's corrective action as having failed. `DELETE /v1/store` is the only
in-band remedy that acts at once, and it is destructive, so it MUST NOT be
offered as the first response to a quota error.

`422` MUST be surfaced to the user, logged, and MUST NOT be silently retried.

### 5.4 Limits

Every limit MUST be enforced before allocation, streaming-abort style.

| Limit | Value |
| --- | --- |
| Blob size | 1 MB |
| Manifest size | 16 MB |
| Blobs per store | 100,000 |
| Bytes per store | 250 MB |
| Devices per store | 32 |
| Hashes per `POST /v1/blobs/missing` request | 10,000 |
| JSON parse depth | 32 |
| Decompressed size of a `Content-Encoding: gzip` body (§4) | 10× compressed, cap 32 MB |
| Request rate | per-IP and per-store |

## 6. Client conformance

### 6.1 Enablement

Device Sync MUST be disabled on every installation until the user turns it on.
An unconfigured app MUST make no sync-related network call. It gets its own
top-level Settings blade.

Every settings key Device Sync introduces is `deviceScoped` and MUST NOT sync.

### 6.2 Attach

1. User enters or accepts a sync ID and confirms the endpoint.
2. `GET /v1/store`.
3. **Fresh attach** always: on first attach, on re-attach after detach, and on
   `409`. Detach MUST forget the sync ID entirely.
4. Upload every local record; download every remote record. Inbound rejection
   (§6.9) applies here as in steady state.
5. **Union**, then dedupe (§6.10). No deletion occurs during a fresh attach.
   Where two peers advertise the same id with different content, the higher
   `updatedAt` wins; existence disagreements resolve per §6.4. Where the two
   `updatedAt` values are **equal** and the bodies differ, §6.3's tie treatment
   applies here too: neither body wins, the local one is left in place, and the
   divergence MUST be reported. Step 6 then persists that local body's hash as
   the baseline, so the record presents as `same`/`changed` on every later pass
   and carries §6.3's reporting duty from then on. What a fresh attach MUST NOT
   do is apply one body over the other silently. The two devices do not converge
   either way — that is why this sits in §10 — so the report is the whole of the
   requirement, and suppressing it is the whole of the harm.
6. Persist the epoch and the resulting manifest as the new baseline. Quarantine
   and repair run **after** this, never during the union.

### 6.3 Steady-state sync

1. `GET /v1/store`. Epoch differs → fresh attach; stop.
2. Compute the local manifest.
3. `GET /v1/manifests/{peer}` for each peer, with `If-None-Match`.
4. Per record, resolve existence first (§6.4), then compare hashes and
   `updatedAt`:

   | Local vs baseline | Remote vs baseline | Action |
   | --- | --- | --- |
   | same | same | nothing |
   | changed | same | upload |
   | same | changed | download only if `remote.updatedAt > local.updatedAt` |
   | changed | changed | conflict → higher `updatedAt` wins |
   | absent from baseline, present locally | absent remotely | upload |
   | absent locally | absent from baseline, present remotely | download |
   | absent from baseline, present locally | absent from baseline, present remotely | resolve as `changed`/`changed` |

   A quarantined record MUST be excluded from this table entirely.

   The last row exists because the two preceding ones are otherwise both
   satisfied by a record absent from the baseline and present on **both** sides,
   which would make the table say "upload" and "download" for one case and let
   two conforming implementations diverge permanently. It is not an edge case.
   §4.4 makes the settings key the record `id`, so it is a natural key rather
   than a UUID: two attached devices that each set the same shareable preference
   before the next pass reach exactly this state, and 49 settings keys are
   `shareable`. Records with UUID ids reach it too, because archive
   import preserves ids, so two devices importing one bundle and then editing it
   locally collide on the same id.

   Resolving it as `changed`/`changed` rather than inventing a rule keeps one
   tie-break in the document: the higher `updatedAt` wins, an equal `updatedAt`
   with differing bodies does not resolve and MUST be reported, and §6.2 step
   5 — which already specifies this situation for fresh attach — stays
   consistent with steady state instead of being the only place it is written
   down.

   Both `updatedAt` comparisons are strict, and that is deliberate. Where
   `updatedAt` is **equal** and the bodies differ, the `changed`/`changed` row
   does **not** resolve: neither side wins, neither body is applied, and the
   divergence MUST be reported. The `same`/`changed` row's strict `>` likewise
   leaves an equal-`updatedAt` difference un-downloaded rather than guessing,
   and MUST report it on the same terms. That row carries a reporting duty
   because it is where a tie left unresolved anywhere else — including at a
   fresh attach (§6.2 step 5) — resurfaces on every subsequent pass; without it
   the divergence would be permanent *and* silent, and §10's claim that ties are
   reported bilaterally would be false. An implementation MUST NOT invent a
   tie-break — silently keeping local and silently taking remote are both
   non-convergent, and a device choosing either disagrees permanently with a
   peer that chose the other.

   One tick is one second (§2), so this is reachable in ordinary use: bulk
   imports, fresh attaches, and concurrent repairs (§6.9) all produce edits that
   land within the same second. Recorded as a limitation in §10.

   With N peers, evaluate against all and take the newest `updatedAt`.
5. `POST /v1/blobs/missing`; `PUT` only what is missing.
6. `GET /v1/blobs/{hash}` for each needed hash. The client MUST verify the hash
   before applying. A `404` here MUST be treated as an **unresolved reference**
   — skip the record and report it (§6.7) — and MUST NOT be treated as a
   deletion, since absence never deletes (§6.8) and the peer's manifest still
   asserts the record exists. The record MUST NOT advance in the baseline, so
   the next pass retries it; if this device is the record's origin, step 5 will
   find the blob missing and re-upload it. This is reachable without a faulty
   peer: a manifest can outlive its blob by §7.3.
7. Apply in one transaction (§6.7). Rebuild derived indexes.
8. `PUT /v1/manifests/{self}`. A client relying on §3.1's forfeiture rule MUST
   record every record the manifest names in `published_records` **before**
   issuing the request. A crash between the two then over-marks rather than
   under-marks, and those costs are not equivalent: an under-mark forfeits the
   guarantee, while an over-mark makes a later hard delete of that record fall
   back to a tombstone. The over-mark is not free — a tombstone left behind by
   an undone import is exactly what §3.1's `hardDelete` exemption exists to
   avoid — but it is recoverable and visible, where the under-mark is neither.
   This step is the only point at which a record becomes exposed: §6.2 performs
   no manifest `PUT`, and by §7.3 a blob is unreachable until some manifest
   references it, so the blobs uploaded at attach step 4 create no window ahead
   of the first mark.
9. Store the new baseline. A record's entry advances **only** where a peer's
   manifest was observed to carry this device's current content hash.

### 6.4 Existence

When two copies disagree about whether a record exists, **the greater
`existenceAt` wins**, and its `deletedAt` says which state that is. Equal values
resolve to the tombstone. `updatedAt` MUST NOT participate in this decision, on
any path.

An implementation MUST NOT assume `existenceAt == deletedAt` on a tombstone.
The two are related only in that a tombstone carries both: a deletion stamps
`existenceAt` causally, so it lands ahead of `deletedAt` whenever the record
transitioned within the preceding tick, while migration-backfilled tombstones
copy `deletedAt` verbatim and are exactly equal. Both shapes are valid and a
receiver MUST treat `deletedAt` only as the state indicator this paragraph
describes, never as a second comparand.

**With three or more peers, existence and content are decided separately.** The
greater `existenceAt` decides *whether* the record lives; §6.3 then decides
*which body* it carries, by the greatest `updatedAt` among the copies that agree
with the winning state. The two maxima need not come from the same peer, and an
implementation MUST NOT persist the existence winner's body on the strength of
its having won existence. Doing so silently discards a newer edit whenever the
peer that most recently revived a record is not the peer that most recently
edited it, which with N peers is the ordinary case rather than the exotic one.

**Equal `existenceAt` is resolved silently, and that is the one place this
design chooses a winner without reporting it.** A conflicting `updatedAt` is
reported as bilateral divergence; existence is not, because a tie here has to
resolve somewhere and deletions are sticky. The exposure is narrowed by the
causal stamp — a device reviving a record it received as a tombstone stamps
above that tombstone by construction, so it cannot tie with it — leaving only
genuinely concurrent transitions on two devices that have not yet seen each
other's, within one tick of each other.

This rule MUST be applied on every path that can decide existence:

| Path | Requirement |
| --- | --- |
| Steady-state merge | Decided before the merge table |
| Fresh attach | Same, with no baseline |
| Collision reconciliation | A row in its decision table (§6.6) |
| Fresh-attach dance dedupe | Tombstones excluded from candidacy |
| Record creation | Seeds the field |
| Migration backfill | Per §3.1 |
| Inbound validation | Per §6.9 |
| Quarantine repair | Per §6.9 |

**Stamping.** Every live↔deleted transition driven by a **local decision** MUST
stamp

```
existenceAt = max(localNow, currentExistenceAt + 1 tick)
```

**Writers.** Creation (plain clock), every user-initiated deletion including a
deferred one, and every revival. Every other sync-apply path MUST leave it
alone; applying a peer's blob copies that peer's value.

Quarantine repair also writes `existenceAt`, but MUST NOT use the formula above:
it reads no clock at all and derives the value from a peer (§6.9). A repairing
device's clock is by definition untrusted, so `localNow` is not an input it may
use.

Because dances have no `UNIQUE` natural key, existence does not propagate across
UUIDs for them, unlike the `UNIQUE`-key kinds.

### 6.5 Invariants

Two invariants are normative and any new write path MUST be checked against
both:

> **I1.** Any operation that changes a record's serialised content MUST also
> advance its `updatedAt`.

> **I2.** No write may advance `updatedAt` while leaving both `body` and the
> record's existence state unchanged.

I1 protects the merge discriminator; a record's serialised form includes fields
hydrated from other tables, so a write that never touches the record's own row
can still change what it publishes. I2 protects the repair classifier in §6.9,
which compares body hashes: a metadata-only re-stamp would be invisible to it.

**I1 has exactly one exception, and it is stated as a property rather than as a
name.** An operation MAY change serialised content without advancing
`updatedAt` if and only if it satisfies **both** of the following.

1. **Content-derived.** Its output is a pure, idempotent function of the
   database's existing content. It MUST NOT consult the clock, the device
   identity, a random source, peer state, or any input outside the database.
2. **Divergence-surfacing.** It MUST be row-local, *or* every way in which its
   output can depend on rows other than the one being written MUST be
   enumerated in this specification, and each such dependency MUST produce
   divergence that is **reported** under §6.3 and never silently resolved.

Condition 1 alone was the original formulation and it was **wrong**, because it
was written as "consults no state outside the row" — which §4.1's own collision
rule then violated by design, since whether a row is normalised depends on
whether a sibling row normalises to the same `UNIQUE` value. The rule was not
the mistake; the property was too strong to describe it, and a specification
whose justifying sentence is false for the one path it authorises is worse than
one that never stated a justification.

The two conditions together are what actually make the exception safe. I1 exists
so that peers can **order** content that diverged. Condition 1 ensures the
operation invents no ordering of its own. Condition 2 concedes that a
content-derived operation may still produce different results on two devices
holding different libraries, and requires that when it does, the difference
**surfaces** rather than resolving silently — which is the same protection a
stamp would have provided, obtained without inventing an order over rows nobody
edited.

§4.1's one-time normalisation pass is the only operation in this specification
that qualifies. Its single cross-row dependency — the `UNIQUE` collision skip —
is enumerated there, and its divergence surfaces as an equal-`updatedAt`
`changed`/`changed` report under §6.3.

A conforming implementation MUST NOT satisfy this by maintaining a list of
exempt operations; a list would relocate the omission it exists to catch, which
is the same argument §3.1's join ratchet rests on. The exemption MUST be proved
per operation, and the proof MUST cover both conditions:

- For condition 1, two independent runs over the **same** database produce
  identical output and leave `updated_at`, `existence_at` and `deleted_at`
  unchanged.
- For condition 2, the operation is run over **two different databases that
  contain the same row** — one where the enumerated cross-row dependency is
  triggered and one where it is not — and either the row's output is identical
  in both, or the resulting difference is shown to surface as a §6.3 report.

The second half is not optional padding. A same-input-twice test is satisfied by
any deterministic operation, including one that reads every other row in the
table, so on its own it detects nondeterminism and nothing else. The failure
this exception must actually guard against is a *deterministic* cross-row read
whose result differs between two devices — which is precisely what the
single-database test cannot see.

### 6.6 Collision reconciliation

`choreographers.name`, `tags.name` and `custom_field_defs.key` are `UNIQUE`.
Applying a record of those kinds:

1. **UUID known locally** → update, last-writer-wins on `updatedAt`. If the
   update would move the natural key onto a name another local row holds, it
   MUST NOT merge silently — route to the review queue.
2. **UUID unknown, natural key matches** → reconcile silently.
3. **Neither** → insert.

Settings are **not** in this list, and their absence is a decision rather than
an omission. A settings record's id *is* its natural key (§4.4), so two devices
setting the same key never hold two ids to reconcile — they hold one id with two
bodies, which is a content conflict and resolves in §6.3's table, not here. An
implementer scanning this section for "which kinds need collision handling"
would otherwise conclude settings need none and find no rule anywhere.

Step 2's decisions:

| Decision | Rule |
| --- | --- |
| Which UUID survives | Lexicographically smaller — never `updatedAt` |
| Whether the survivor exists | Greater `existenceAt` — never `updatedAt` |
| Which field values survive | Last-writer-wins on `updatedAt` |
| Which `deviceLocal` values survive | Coalesce onto the survivor |

Every "which record survives" decision in this specification — including the
fresh-attach dance merge — MUST use the lexicographically-smaller-UUID rule. A
rule that decides on "local" versus "incoming" does not converge.

`deviceLocal` coalescing applies to step 2 only. Step 1 involves two
pre-existing local rows and MUST NOT coalesce.

**A record this device created and no peer has seen MUST NOT be reconciled out
of existence silently.** Where step 2 resolves the survivor to non-existence
and the losing local row is **absent from this device's baseline** — created
here, never observed on any peer manifest — the resolution MUST be reported
rather than applied, on the same terms as §6.3's equal-`updatedAt` divergence.
Report and leave the local row in place; do not invent a tie-break.

This is the one existence decision that needs it, because creation is the one
existence write exempt from the causal floor: §6.4's stamping table seeds
`existenceAt` from the plain clock, there being no prior value to supersede. A
device whose clock is behind therefore stamps a record it creates *now* below a
tombstone a correctly-clocked peer stamped **earlier** in real time, for a
different UUID on the same natural key. Nothing else catches it. Both values
sit inside the acceptable window, so §6.9 quarantines neither; a moderate
behind-skew never trips clock-suspect, which requires every observed peer value
to fall outside the window; and repair revisits only records already flagged,
so no repair path reaches it. Without this rule the record the user created
moments ago disappears from their own device, with nothing reported.

This does not disturb the equal-`existenceAt` rule below, which resolves
silently by design. That case is a genuine tie between two transitions each
stamped against a real prior value; this one is an *unequal* comparison against
a value that was never floored, so the ordering carries no causal meaning to
respect.

**Custom-field defs** reconcile only when `type` matches. On mismatch both
survive: the smaller UUID keeps the bare key, the other is renamed.

The renamed key MUST be `<key>_<suffix>`, where `<suffix>` is the first
**eight** lowercase hexadecimal digits of the **losing** UUID with hyphens
removed — losing UUID `7f3a9c2b-…` against key `skill_level` yields
`skill_level_7f3a9c2b`. The suffix MUST derive from the losing UUID and MUST NOT
be a counter. Because the suffix is a pure function of the losing UUID, every
device derives this key without coordinating, and a third device carrying a
third type yields a third distinct key rather than contending for the same one.

This derivation is normative because `custom_field_defs.key` is `shareable` wire
content that participates in the record's content hash: two implementations that
chose different digit counts or separators would produce different keys for the
identical collision on each device, forking the data permanently while each
device remained individually correct.

If the derived key is already taken, the suffix MUST become the losing UUID's
**full 32 hexadecimal digits**, hyphens removed — in a single step, never by
progressive lengthening, so that every device reaches the same second candidate.
Distinct losing UUIDs cannot collide at full length. If the full-length key is
*also* taken — reachable only if a user authored that exact key — the record
MUST route to the review queue rather than renaming again, so the rule always
terminates.

The coordination-free property above covers the primary derivation only. Whether
a key is "already taken" is decided against **local** state, and reconciliation
is re-evaluated per device, per pass, against whatever peer manifests that
device has observed, so two devices with different observed peer sets MAY mint
different keys — one the eight-digit form, the other the full-length one — for
the same losing UUID. That is not a fork. Both rows carry the same UUID, so the
first pass in which those two devices see each other resolves them under step 1
above (UUID known locally, last-writer-wins on `updatedAt`), with that step's
review queue catching a residual name collision.

**The remap.** Reconciliation produces `losing → surviving`, applied to local
references **and** to every inbound record in the same batch, and persisted in
`id_aliases`. Lookups MUST chase the chain to a fixed point; superseded entries
are rewritten in place. An alias is retired once no current peer manifest lists
the losing id.

`published_records` is a local reference to a record id, so it is remapped like
any other — and because it is a set, the remap is a **union**: a marker on
either id marks the survivor, and a marker is never dropped. Dropping the losing
id's marker would reopen §3.1's forfeiture hole by a different route. A
pre-existing published record can lose reconciliation to a just-imported one,
after which the import's undo hard-deletes the survivor; peers still holding the
losing id re-advertise it, the alias maps it onto the survivor, and the record
returns against a device that kept no tombstone.

Rewriting a reference changes a dance's serialised content without touching its
row, so it MUST bump that record's `updated_at` and re-upload it (I1).

Reconciliation runs inside the apply transaction, before any record that
references the reconciled row, and is re-evaluated against every current peer
manifest each pass.

`venues` and `published_sources` have no `UNIQUE` key and insert without
reconciliation.

### 6.7 Apply

Apply MUST be read-modify-write inside the apply transaction — never the
repository `upsert` path, which writes every column:

1. read the local record;
2. overlay only the fields the blob carries;
3. write the merged result.

**Sender/receiver contract.** The sender emits explicit `null` for an empty
`shareable` field and omits only non-`shareable` fields. The receiver MUST
independently consult the registry to decide which absences mean *preserve*, and
MUST drop any inbound key not classified `shareable` for that kind and nesting
context. For `kind: "setting"` the receiver MUST additionally look the record id
up in `settingsClassifications` and refuse anything not `shareable`.

**Ordering**, within the transaction:

1. Reconcile `UNIQUE`-key collisions, building the remap.
2. Apply the remap to every inbound record in the batch.
3. Apply parent records by UUID.
4. Apply join rows last.

A record whose reference cannot be resolved MUST be skipped and reported.
**Exception:** a dangling `Programs.venueId` MUST be nulled before the program
reaches the repository and reported — `ProgramRepository` throws otherwise.

**Hostile input.** Per-record decode MUST catch `Error` as well as `Exception`;
`PartialDate.parse` throws `ArgumentError` for a well-shaped invalid date. Text
from a peer MUST pass through `sanitizeImportedText`.

### 6.8 Deletion and pending tombstones

Absence never deletes. A deletion travels only as a tombstone.

The referential guards are kept, so a tombstone for a still-cited entity cannot
be applied. Such a device MUST:

- record the deletion as **pending** in `pending_deletions`;
- keep the row live locally;
- **advertise the entity as a tombstone**, never as live;
- **not** advance its baseline entry for that record;
- apply the deletion when its last citation goes.

A pending tombstone is cancelled **only** by a deliberate user edit, gated on
`existenceAt` per §6.4 — never on a newer `updatedAt`, since several sync
mechanisms advance that without user involvement.

Fresh attach MUST run the revive-on-citation rule; without it an attaching
device can land holding a record that cites a tombstone.

### 6.9 Quarantine and repair

**Inbound rejection.** A blob whose `existenceAt` **or** `updatedAt` exceeds
`localNow + 24h` MUST be refused as malformed and reported: one record skipped,
batch intact, local state unchanged. Values MUST NOT be clamped. A rejected hash
is reported once per session (in memory).

Rejecting both fields is what makes a poisoned value always **local**.

**Quarantine.** A record whose own `existenceAt` or `updatedAt` exceeds
`localNow + 24h` is quarantined. This is a derived predicate; it needs no
schema.

A quarantined record MUST NOT be uploaded, MUST be excluded from the merge table
and from a fresh attach's union with its local row retained, and its manifest
entry MUST fall back to the last agreed **wire** hash. A quarantined record with
no agreed hash is omitted, and every record citing it MUST be withheld with it —
computed as a **fixpoint over the publish set**, scoped to references that are
database-enforced foreign keys. `Programs.venueId` is exempt (§6.7).

**Repair** runs during a sync pass, not on a user gesture, and reads no clock.
For each out-of-window field, gather peer copies, discard any whose value **for
that field** is outside the local window, and take the greatest of what remains:

| Field | Verbatim when | Otherwise |
| --- | --- | --- |
| `existenceAt` | peers agree with local live-or-deleted state | `peer + 1 tick` |
| `updatedAt` | local body matches this device's own **baseline body hash** | `peer + 1 tick` |

The adopted timestamp MUST come from the peer whose body matched, not the global
maximum. Repair MUST NOT leave a record at equal `updatedAt` with content
differing from the peer that supplied that timestamp. A field inside the window
MUST be left untouched. A rebuilt value is re-checked against the local window
before the record is considered repaired; one that still fails leaves the record
quarantined.

**Missing baseline entry**, by cause:

| Cause | Rule |
| --- | --- |
| No entry at all | Never agreed; compare local body to peers' |
| Wire hash, no body hash | Agreed pre-upgrade; verbatim if body matches a peer, else stays quarantined |
| Wholesale wipe | Cannot occur — fresh attach repersists the baseline first |

The body hash starts null on upgrade and populates on the first pass that
observes agreement. There is no safe backfill.

**Clock-suspect** is a derived per-pass diagnostic: it holds when at least one
peer value was observed and every value observed in that pass fell outside the
local window. Zero observed peers is NOT clock-suspect. It gates nothing and
MUST NOT restrict user writes. A device MUST also report when its own published
records go unreflected by every observed peer across three consecutive passes
(session-scoped counter), **with at least one peer observed in each of those
passes**. Zero observed peers is not evidence, for the same reason it is not
evidence of a slow clock: with no peer observed, "unreflected by every observed
peer" is vacuously true, and a solo install would otherwise report its uploads
as unreachable forever.

A solo install has no repair path. A never-corrected clock does not self-heal.

### 6.10 Fresh-attach dedupe

Union matches on record id. Silent merge only where both hold an exact
normalized-title match **and** `_choreographyEquals`. Tombstones MUST NOT be
dedupe candidates.

**Normalized title** means the transformation implemented by `normalizeTitle`
in `packages/compendium_core/lib/src/imports/dedupe.dart`, applied in this
order: lowercase using the Unicode default, locale-independent mapping; fold
diacritics via the precomposed-character table; replace every character outside
`[a-z0-9]` and whitespace with a space; collapse each internal run of whitespace
to one space and trim; remove a single leading article (`the`, `a`, or `an`)
with its following space. Inputs are already NFC, because §4.1 requires
normalisation on **every write path**, including the local edit and import
paths that produce the library this section compares.

That NFC precondition is load-bearing here and not merely inherited. The
diacritic fold is a lookup keyed on **precomposed** characters, so a combining
mark never matches it; an NFD combining mark instead falls through to the
punctuation rule and becomes a *space*. `résumé` in NFC normalizes to `resume`
and in NFD to `re sume`. A trailing mark happens to survive this — the injected
space is then trimmed — so the divergence appears on internal accents only,
which makes it intermittent and hard to attribute. Normalising on write is what
makes the two forms agree; the fold table is not going to. **The scope matters
at exactly this section**: an ingest-only rule would leave both sides of a
fresh-attach comparison un-normalised, because at fresh attach neither library
has been through a sync path. This divergence was live in shipped import dedupe
independently of sync — filed as #1021, fixed by #1024, which normalises inside
the fold. That repair is on the **comparison** only; stored values are still
un-normalised, which is what §4.1's one-time pass exists to fix.

The definition is normative, and given by reference to real code rather than as
a restatement, because an earlier draft of this paragraph *did* restate it — as
NFC, trim, collapse, lowercase — and silently dropped the diacritic fold, the
punctuation rule and the article rule. A conforming implementation built from
that restatement would disagree with the shipped client on `The Nice
Combination` versus `Nice Combination`, which is exactly the pair dedupe exists
to catch. A spec that paraphrases an algorithm it also names is offering two
definitions and guaranteeing only that one of them is checked.

The comparison decides whether two dances **merge silently**, with no review
queue entry and no user prompt: two clients disagreeing about it disagree about
whether a record exists. The locale-independent clause is what stops a
Turkish-locale device lowercasing `I` to `ı` and declining a merge every peer
performs.

On silent merge the survivor is the lexicographically smaller UUID; id
collections the equality test ignores are unioned; `program_slots.dance_id` MUST
be rewired to the survivor; scalars `_choreographyEquals` does not compare
(`walkthrough`, `rating`, `status`, `composedOn`, `revisedOn`) resolve by
last-writer-wins. Dance merges write `id_aliases` entries.

Everything else `DedupeIndex` flags is deferred to `review_queue`. Queuing MUST
be idempotent under the canonical tie-break ordering, MUST carry an immutable
candidate blob and hash, and a queued pair MUST NOT be re-resolved while
pending. The queue MUST NOT denormalise contact fields.

### 6.11 Restore

A restore MUST drop the sync baseline, forcing a fresh attach. `id_aliases` and
`review_queue` clear with it; `pending_deletions` does not, and is revalidated
afterwards.

A restore MUST also clear the §4.1 normalisation completion marker and
`normalisation_skips`. Neither is reached by dropping the baseline, and the
distinction is easy to miss in both directions: the marker is a local
one-time-sweep flag rather than sync state at all, and `normalisation_skips`
deliberately *survives* baseline drops (§3.2), so an implementer who clears
"everything that goes with the baseline" clears neither. Clearing both re-runs
the pass over the restored library, which is the only way rows the pass never
judged are repaired; §4.1 states why revalidating entry by entry is not an
adequate substitute.

**"Restore" here means every path that writes a library the running pass has not
judged, in either mode.** The codebase has three such entry points —
`BackupService.restoreFromJson`, `ArchiveRestorer.restore` and
`CompendiumArchiveImporter` — and `RestoreMode` offers `merge` alongside
`replace`. Today the shipped UI path uses `replace`, so the merge case is
latent; but a merge writes rows the pass never saw exactly as a replace does, so
the rule is stated over the event and not over the mode, and holds unchanged
when merge-mode sharing ships.

Restore converges on a deletion only while some peer still advertises the
tombstone.

### 6.12 Failure, offline and triggers

Sync is best-effort and MUST NOT block the UI. Any failure MUST leave local data
untouched and MUST retry on the next trigger.

Triggers: app start, a debounced interval after a change, and a manual "Sync
now" (a delta pass). *Sync only on WiFi* defaults to on; on a metered connection
automatic sync does not run and a manual attempt routes to the setting.

## 7. Server conformance

### 7.1 Storage

```
data/
  athenaeum.sqlite      stores, devices, blob refcounts, quota, activity
  blobs/<aa>/<bb>/<hash>
```

Every path that turns a **caller-supplied** hash into a filesystem path MUST
validate it against `^[0-9a-f]{64}$` before touching the filesystem: `GET`,
`PUT`, and every hash in a `POST /v1/blobs/missing` body. Blobs have no `DELETE`
endpoint — removal is GC (§7.3) — but the sweep MUST apply the same check to
values read back from the database, so a row written before this rule cannot
escape it.

```sql
CREATE TABLE stores (
  id_key      TEXT PRIMARY KEY,
  epoch       TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  last_seen   INTEGER NOT NULL,
  bytes_used  INTEGER NOT NULL
);
CREATE TABLE manifests (
  id_key TEXT NOT NULL, device_id TEXT NOT NULL,
  etag TEXT NOT NULL, written_at INTEGER NOT NULL, body BLOB NOT NULL,
  PRIMARY KEY (id_key, device_id)
);
CREATE TABLE blob_refs (
  id_key TEXT NOT NULL, hash TEXT NOT NULL, size INTEGER NOT NULL,
  uploaded_at INTEGER NOT NULL,
  PRIMARY KEY (id_key, hash)
);
```

Blobs MUST be namespaced per store. Cross-store deduplication is a privacy leak
and MUST NOT be implemented.

The server MUST NOT merge, lock, or interpret record content beyond §7.2.

**Epoch.** The epoch is **minted by the server** and by nothing else; a client
MUST NOT supply one on store creation. Only the server can mint it, because two
devices creating the same store concurrently would otherwise choose different
values and each treat the other as a reset.

The server MUST mint a **fresh** 128-bit random epoch on every store creation:
the first `GET /v1/store` for an unknown `id_key`, the next `GET` after
`DELETE /v1/store`, and the next `GET` after the store was reaped by the sweep
(§7.3). A fresh one MUST NOT be derived from the sync ID, the `id_key` or a
counter, and an epoch MUST NOT be reused across incarnations of a store. This
is the whole of the reset-detection mechanism: a device compares the epoch at
§6.3 step 1 and fresh-attaches when it differs, so an implementation that
reproduces an old epoch after a wipe leaves every peer believing its baseline
still describes the store, and no device ever detects the reset.

Store creation MUST be an atomic upsert on the `stores` primary key, and
concurrent creators MUST both observe the **same** epoch — the loser of the
race returns the winner's row rather than minting a second one.

`409` has exactly one source: `PUT /v1/manifests/{deviceId}` where the
manifest body's `epoch` (§4.5) does not equal the store's current epoch. The
server MUST reject that request and MUST NOT store the manifest. No other
endpoint emits `409`; blob uploads are content-addressed and store-scoped, so a
blob written under a stale epoch is left unreferenced and is collected by §7.3
once its grace period lapses, rather than being rejected.

### 7.2 Allow-list validation

The server MUST reject (`422`) any blob carrying a key not classified
`shareable` for its kind. The mapping MUST be **generated** from the registry
and proven by test — a hand-maintained list drifts and is worse than useless.

This is a second line of defence. The client serialiser is the control, and
neither is sufficient alone.

**Deployment ordering.** Because that mapping is generated from the client's
registry and lives on the server, **the server MUST be deployed before any
client emits a new `shareable` field or a new record kind.** Adding either does
not bump `v` (§4.1 bumps only for a canonicalisation change), so nothing in the
wire format signals the difference: a client shipping ahead of the server gets
`422` on every affected blob, and `422` MUST be surfaced to the user and MUST
NOT be retried (§5.3). This ordering constraint is load-bearing for every
future vocabulary change and is the one part of the design a client-side
revision cannot absorb on its own.

**Unknown envelope `v`.** The server MUST apply the key check regardless of the
value of `v`, and MUST NOT reject a blob solely because `v` is unknown to it —
`v` is for the client, which refuses an unknown value rather than guessing
(§4.3). Rejecting it server-side would force a server-first rollout for every
wire bump, including bumps that do not touch the key vocabulary. A future `v`
that changes body *structure* enough that the key check no longer applies is
the exception, and MUST be deployed server-first for the same reason a new
field is.

### 7.3 TTL and garbage collection

A sweeper runs hourly:

```sql
DELETE FROM stores WHERE last_seen < (now - 30 days);
```

then cascades manifests, blob refs and blob files. `last_seen` is refreshed by
any authenticated request, making this a rolling TTL on activity.

A blob is reachable while any manifest for its store references it. After each
manifest `PUT`, and during the sweep, unreferenced blobs for that store are
deleted — **except** that a blob whose `uploaded_at` is within the last **24
hours** MUST NOT be collected, whether or not any manifest references it. A
recent upload is a temporary GC root.

Without that exemption the specified GC deletes live data, because every upload
passes through a window in which no manifest names it: the client uploads blobs
at §6.3 step 5 and publishes its manifest at step 8, with a full
download-and-apply in between. Device A `PUT`s a blob; before A's manifest
lands, device B `PUT`s its own manifest, which triggers store-scoped GC; A's
blob is unreferenced and is deleted, and A then publishes a manifest naming a
blob the store no longer holds. The hourly sweep firing in the same window
reproduces it with a single device.

24 hours is chosen against the window it protects, not tuned: steps 5 through 8
are one pass, bounded by request timeouts, so the exposure is seconds to
minutes and the margin is three orders of magnitude. The cost of being generous
is bounded twice over — by the 250 MB store cap, and by the fact that an
abandoned upload is *reused* rather than duplicated, since step 5's
`POST /v1/blobs/missing` reports it present. An age bound is preferred to an
upload session or a client-declared intent because it keeps the server free of
per-client state and needs no new endpoint, which is the property §7's
architecture is built on.

A pass that stalls for longer than the grace period and then publishes will
name a collected blob. That is not silently wrong: peers skip and report the
record (§6.7), and the next pass re-uploads it, because `blobs/missing` reports
it missing again. The server is deliberately **not** required to reject a
manifest naming a blob it lacks — that would make manifest `PUT` referentially
interpret its own body, which §7.1 forbids, to catch a case the client already
self-heals.

**`DELETE /v1/store` is the one exception, and MUST delete unconditionally.** It
removes the store's blobs, manifests and rows immediately, grace window or not.
The window exists to protect a blob whose manifest has not landed *yet*; a wiped
store has no manifest coming, so retaining bytes there protects nothing and
breaks a promise the user was given explicitly. §5.3 tells the client that
`DELETE` is the one remedy that acts at once, which is only true if this says
so — the grace rule above is scoped to the manifest `PUT` and the sweep, and a
server reading it as universal would leave a wiped store's contents on disk for
a day while reporting success.

### 7.4 Break-glass access log

Break-glass access MUST write to a **separate database** holding exactly:

| Column | Retention |
| --- | --- |
| `id_key` | `HMAC-SHA256(pepper, syncID)`, never plaintext. Nulled after 30 days. |
| `accessed_at` | Retained. |

Separate so that reaping a store cannot destroy evidence of access to it. Its
retention is therefore not the 30-day disuse TTL and MUST be stated in the
privacy policy.

### 7.5 Deployment

The server MAY terminate TLS itself, but the reference deployment does not: TLS
terminates at a reverse proxy and the server binds a loopback address only. See
ADR-004, *TLS and deployment*, for why — the reason is certificate renewal, not
issuance.

Where a proxy is used, it is part of the conforming implementation and MUST
satisfy all five of the following. Each has been chosen because the default
behaviour of at least one common proxy violates it.

| # | Requirement | Why it is not automatic |
| --- | --- | --- |
| 1 | The `Authorization` request header MUST reach the server unmodified. | It carries the sync ID (§5.1). A proxy that consumes it makes every request `401`. Apache needs `CGIPassAuth On` if the server is ever fronted by CGI/FPM. |
| 2 | Request bodies MUST be permitted to at least the manifest limit in §5.4 (16 MB). | Defaults are wrong in opposite directions: nginx's `client_max_body_size` is 1 MB and rejects valid manifests; Apache's `LimitRequestBody` is unlimited and enforces nothing. Set it explicitly. |
| 3 | The proxy MUST NOT decompress request bodies. | §4 puts the decompression limit on the receiver, enforced streaming-abort style. Inflating at the proxy moves a security control to a component that does not implement it. |
| 4 | The sync ID MUST NOT be written to any log. | Common log formats omit headers, so this holds by default and is lost the moment someone adds `%{Authorization}i` or `$http_authorization` to a debug format. §5.1 keeps the ID out of URLs for the same reason. |
| 5 | The public listener MUST NOT serve `/v1` over plaintext HTTP. A plaintext request to `/v1` MUST be **refused**, never proxied and never redirected; other paths MAY redirect. The `https` origin SHOULD send `Strict-Transport-Security` with a `max-age` of at least six months, as browser-only defence in depth. | A vhost that owns `:80` for ACME HTTP-01 (which the reference deployment does — see ADR-004) will serve whatever its configuration reaches, and a `ProxyPass` written outside a vhost, or copied into both, silently exposes the API on both ports. Nothing in the response distinguishes the two. |

A server behind a proxy that violates (1) or (2) is **not conforming**: it will
reject valid requests. Violations of (3), (4) or (5) are not visible in
behaviour at all, which is why they are stated rather than left to deployment
taste.

**(5) is the one this specification cannot rely on the client to cover.** Every
other transport rule here is enforced twice — §8 already requires a conforming
client to refuse a plaintext endpoint and to refuse a plaintext redirect hop —
but a server that answers on `:80` is reachable by things that are not
conforming clients: an older build, a `curl` in a support thread, a user who
typed the endpoint without a scheme into something that defaulted to `http`, or
a redirect from an unrelated site. The cost of one such request is not
proportionate to its likelihood. The sync ID is a bearer credential sent on
every request, and §8 records that it is simultaneously the store address and
the entire read, write and `DELETE` capability, with no accounts, no rotation
and no revocation — so a single plaintext request discloses it in full to
anything on the path, permanently and unrecoverably.

**What refusal buys is not the first disclosure, which is already unrecoverable
by the time the listener can respond at all.** The credential is on the wire in
the request; no status code recalls it. What refusal prevents is a *working*
plaintext sync — every subsequent request, on every subsequent run — and that
is the whole of the justification. This is also why `/v1` MUST be refused
rather than redirected, and the two are not interchangeable here — but not
because the redirect itself carries the credential onward. Scheme is part of an
origin, so an `http`→`https` redirect is a *cross-origin* hop, and both clients
named below strip `Authorization` across it: `dart:io`'s `HttpClient` copies no
sensitive header unless scheme, host and port all match (`_isSameOrigin`,
consulted from `shouldCopyHeaderOnRedirect` in `sdk/lib/_http/http_impl.dart`),
and `curl` extended its same-host check to cover port and protocol in 7.83.0,
the fix for CVE-2022-27776. Both facts are stated from those primary sources;
earlier drafts of this paragraph asserted the opposite of each, on secondary
ones.

The reason a redirect is unacceptable is that **whether it is harmless depends
on a client policy the operator cannot see.** A client that strips gets a `401`
on the retry and fails visibly. A client that retains — bespoke tooling and
non-app callers, since those fixes shipped in Dart 2.16 on 2022-02-03 and curl
7.83.0 on 2022-04-27, and no build of this app carrying sync predates either —
gets a sync that *works*, over a redirect, which is the outcome this
requirement exists to deny: nothing then surfaces the misconfiguration, so it
is never corrected, and every subsequent run repeats the plaintext request that
discloses the bearer in full. Refusal produces the same visible failure for
every client whatever its header policy, and that uniformity is the point. A
deployment MUST NOT have to reason about which clients will reach it in order
to be safe. A redirect remains the right answer for other paths, which carry no
credential.

`Strict-Transport-Security` is listed as a SHOULD, and separately from the
refusal, because it protects a different population than the one above: HSTS is
a browser mechanism, and this app has no web target. `package:http` resolves to
`dart:io`'s `HttpClient` on all five supported platforms, which maintains no
HSTS store and performs no `http`→`https` upgrade, and `curl` honours HSTS only
when given an explicit `--hsts` file. So of the non-conforming callers
enumerated above, the header reaches none of them; it is worth sending for the
human who pastes the origin into a browser, and it MUST NOT be counted as part
of the guarantee that the other four requirements provide.

This binds the deployment this project operates. It cannot bind a self-hoster
who reconfigures their own proxy, and no client-side rule can detect that they
did: a plaintext endpoint is refused by §8's entry validation, but an `https`
endpoint terminating at a proxy that *also* answers on `:80` looks identical
from the client. What protects a user of a third-party server is therefore §8's
client-side refusal, not this requirement, which is why both exist.

Beyond these, deployment is unconstrained. `localhost`/`127.0.0.1` waives TLS
(§8), which a self-hoster needs for **testing on one machine** and which does
not extend to a working self-hosted sync, and a non-default port is permitted
on a user-configured endpoint — though redirects are followed only to the
default port, so a server behind a non-default port MUST NOT rely on
redirects.

## 8. Security

**Sync ID.** Format is four hyphen-separated words, enforced. A generated ID
uses the EFF long wordlist. A user-chosen ID MUST clear a strength floor of
~2⁴⁰ scored on the actual string, and four weak words MUST be rejected.

**The floor is enforced at the point of choice, on the client.** The server
enforces only the *structural* rule and returns `403` for a violation of it:

| Rule | Value |
| --- | --- |
| Separator | exactly three `U+002D HYPHEN-MINUS`, yielding four words |
| Word length | 1–32 Unicode code points, after the normalisation below |
| Total length | ≤ 131 code points (implied by the two rules above) |
| Forbidden in a word | whitespace, control characters, and `U+002D` itself |

Those bounds are deliberately far looser than any ID the client will produce:
the EFF long wordlist is 7,776 words of 3 to 9 characters, so a generated ID
runs 15 to 39 characters and sits well inside them. That slack is the point. A
minimum of **1** rejects an empty word — `a--b-c` — and nothing else, because a
one-character word is a *strength* judgement and strength is not the server's to
make; a server that raised the minimum to something more sensible-looking would
be re-implementing the estimator this section forbids. The maximum bounds memory
per request, not quality.

**The sync ID MUST be normalised identically by client and server** before the
HMAC of §5.1 and before this structural check: strip leading and trailing
whitespace, apply Unicode NFC, then lowercase using the Unicode default,
locale-independent mapping. This is stated because the failure it prevents is
silent rather than loud. `id_key` is `HMAC-SHA256(pepper, syncID)`, so two
implementations that disagree about whether to trim or normalise route the same
ID the user typed to two different storage keys: the second device does not get
an error, it gets a *different, empty store*, and it looks exactly like a sync
that is working and has nothing to say. Every other disagreement in this section
surfaces as a `403`.

The server MUST NOT run its own strength estimator, because client and server
would then both gate the same string on two implementations of a heuristic that
has no canonical definition. The failure is asymmetric and the strict direction
is the bad one: a server marginally stricter than the client rejects an ID the
user has already adopted, and since the ID *is* the store address, the user is
locked out of their own data with no recovery path and no way to tell the
difference from an outage. A server marginally more permissive accepts a weak
self-chosen ID whose residual risk is bounded by the per-IP and per-ID-hash
rate limits below, and is borne by the person who chose it. Pinning a specific
estimator and version would close the gap only until either side upgraded it.

**Transport.** TLS required except `localhost`/`127.0.0.1`, matched exactly as
§5 specifies, with certificate chain and hostname verification mandatory and not
disableable — the per-hop table below constrains what a URL may *say*, and only
that verification constrains who is on the other end of it. Redirects MUST be
followed manually with per-hop validation and `package:http`'s
`followRedirects = true` MUST NOT be used. Every hop MUST be checked, before the
request is issued, against all of:

| Per-hop rule | |
| --- | --- |
| Scheme | https (or `localhost`/`127.0.0.1` under the same exemption as above) |
| Origin | **identical to the configured endpoint's** scheme, host and port |
| Userinfo | absent |
| Port | the scheme default, or the endpoint's own explicit port |
| Hop count | capped |

A hop failing any of these MUST be refused rather than followed, and the
`Authorization` header of §5.1 MUST NOT be sent to any origin other than the
configured endpoint's. A client MAY instead refuse cross-origin redirects
outright; it MUST NOT follow one while still carrying the credential.

**The origin rule is the load-bearing one.** The other four bound what a hop may
look like; only this one bounds *where the sync ID can go*. A redirect chain
that satisfies every cosmetic check and terminates at an attacker-controlled
https host on port 443 with no userinfo is exactly the case that matters, and it
is not exotic: §7.5 treats a reverse proxy as the reference deployment, so a
misconfigured proxy, an open redirect, or a stale `Location` target reaches this
path without anyone doing anything unusual. The sync ID is not a session token —
it is simultaneously the store address and the entire read, write and `DELETE`
credential, with no accounts, no rotation and no revocation — so a single
credentialed request to a foreign origin is unrecoverable and total. Bounding
the shape of a hop while leaving its destination unbounded protects nothing.

Scheme and Port are formally **subsumed** by Origin, which already fixes scheme,
host and port together. They are listed separately anyway, and the redundancy is
deliberate: an implementer working down the table must not be able to satisfy
four rows, feel finished, and have implemented none of the protection. Read the
table as one rule with four corollaries rather than five independent checks —
the version of §8 that stood until round 31 listed the corollaries and omitted
the rule.

The user-configured endpoint is validated on entry: https or an exactly-matched
`localhost`/`127.0.0.1`, no userinfo, no fragment, no query. A custom endpoint
MUST be shown prominently and a change MUST warn.

**Threat model.** Anyone holding the sync ID has full read and write access,
including `DELETE /v1/store`. This is inherent to the bearer model and MUST be
disclosed. A peer can write any `shareable` record; it cannot write
`deviceLocal` or `deviceScoped` fields, because the receiver filters
independently of the server.

**Enumeration.** Rate limits are per-IP and per-ID-hash, with a global cap on
store creation.

**Operator visibility.** The operator can see all store content: choreography,
programs, tags, shareable settings. Not venue addresses or contacts. The privacy
policy MUST say this plainly rather than implying the store is opaque.

## 9. Conformance tests

A conforming implementation MUST cover at least the following. Each is stated
with the mutation it must catch; a test that cannot fail against that mutation
does not satisfy the requirement.

This list is scoped to the rules **this document** states normatively, and it is
the completion bar for an implementation built from this document alone.
[sync.md §Testing](sync.md) is a superset: it carries the same tests annotated
with the reasoning behind each, plus cases that follow from the rationale rather
than from a MUST here. An implementer who satisfies §9 is conforming; one who
also reads sync.md will write more tests, not different ones. Where the two ever
disagree, this section is what conformance is measured against.

**Wire format.** Canonical-JSON goldens (two devices, byte-identical);
integer/float form; absent-versus-null; recursive key order. RFC 8785
conformance vectors. A fractional `shareable` value round-trips to identical
bytes on two independent encoders (mutation: emit `double.toString()` instead
of the shortest round-tripping form). The same title in NFC and NFD hashes
identically after ingest (mutation: skip normalisation, and watch two devices
hold one record as a permanent `changed`/`changed`). **A title created locally
in NFD and never synced serialises as NFC on its first upload** (mutation:
scope normalisation to inbound values only — the device then uploads NFD
forever from its own unchanged storage, and no test exercising both forms
*through* the sync path can catch it). A record requiring NaN or ±Infinity is
rejected rather than coerced, and so is a `shareable` string carrying an
unpaired UTF-16 surrogate (mutation: substitute `U+FFFD`, which converges only
while every implementation picks the same repair). **The surrogate rejection is
asserted on the string, before encoding** (mutation: check after `utf8.encode`
— the platform has already substituted by then, no error is raised, and two
devices agree on the hash of the repaired bytes while holding different
strings). **A row written before the normalising build is NFC after upgrade**
(mutation: normalise only on write — a library that is never edited again is
never repaired, and §6.2 step 4 uploads it verbatim), **and the pass leaves
`updated_at` unchanged** (mutation: bump it — every normalised row is then
handed to whichever device upgraded last). **A pass over a local pair whose
names normalise to the same `UNIQUE` value leaves both rows untouched, reports
the pair, and completes** (mutations: merge them — two devices resolving the
pair differently then diverge, and the pass no longer qualifies for I1's
exception; abort the pass — the row throws on every launch and the device never
normalises anything; **detect the collision by catching the `UNIQUE` violation
instead of grouping before writing** — the first row of the pair writes
successfully because nothing holds the target yet, so exactly one member is
normalised and which one depends on row order). **A retry applies both halves
of the grouping test — recorded-row grouping and live occupancy — and a
mutually-colliding recorded pair survives re-open unchanged** (mutations: test
live occupancy alone — neither member occupies the target, so whichever the
client reaches first is written and the pair the initial pass left whole is
split along an unspecified iteration order, so two devices can normalise
opposite members; test recorded-row grouping alone — record a skipped pair,
create a third row already holding the target in NFC, rename one member, then
re-open: the survivor is a singleton by grouping and the retry raises against
the third row, breaking totality at retry time). **An entry whose row is
hard-deleted is retired, and one whose row is soft-deleted is not** (mutations:
read existence through an accessor that filters `deleted_at`, as all three
in-scope repositories' `getById` do — a tombstone is then indistinguishable
from a deleted row, so an owed and still-blocked repair is dropped; retire on
neither — retry has no stored value to re-derive from, and the entry
accumulates forever behind an ordinary import undo). **Recording the same row
twice leaves it repairable** (mutation: insert rather than upsert, then
interrupt and re-run the pass — the duplicate satisfies condition (a) against
its own twin and the row blocks itself forever). **Widening the in-scope column
set re-runs the pass** (mutations: reclassify a column to `shareable` and leave
the completion marker standing — its rows are never judged, never recorded, and
are repaired only if a user happens to rewrite each one; gate the re-run on a
migration rather than on comparing the recorded column set against the live one
— a reclassification runs no migration, so the guard never fires for the
trigger it was written for). **A crash between the pass's commit and its
derived rebuild still leaves search matching the repaired rows** — interrupt
after the transaction commits and re-open (mutations: write the completion
marker inside the mutation transaction — the marker asserts the scan is done,
later passes write nothing so the rebuild is forbidden, and the indexes hold
pre-normalisation text permanently; omit the durable rebuild-owed flag — the
re-run's own rescan finds nothing left to rewrite and concludes no rebuild is
owed; use a flag private to the pass rather than `derivedRebuildRequiredKey` —
nothing else reads it, so the generic pre-check never performs the owed
rebuild). **A crash between a *retry* write and its rebuild leaves search
matching that row** (mutation: set the rebuild-owed flag only on the one-time
pass — retry writes the repaired row, dies before the rebuild, and its next
rescan finds nothing to write and is forbidden from rebuilding).
**Reclassifying a column out of `shareable` and back in re-runs the pass**
(mutation: test the live set for containment in the recorded set rather than
inequality — the removal contracts nothing, so the re-entry is contained and
silent, and rows that accrued NFD while out of scope are never scanned and
never recorded). **A newly `shareable` column enters the live in-scope set
without anyone editing a list** (mutation: hand-enumerate the string columns —
a column added to the registry but not the list never enters the live set, the
comparison never differs, and the widening trigger is disabled at its input).
**No primary key enters the live in-scope set** (mutation: derive the set as
string ∩ `shareable` without excluding identity by reflection — `_key` is
`shareable`, so every id column joins the scan and `settings.key` is renamed
rather than repaired; a ratchet checking only classification coverage passes
this mutation unchanged, so the vector must assert the derived set itself). **A
retry that rebuilds does not leave a rebuild owed** (mutation: clear the flag
only alongside the completion marker — retry never writes one, so the next open
performs a second whole-library rebuild it did not owe). **A pass that skips the
rebuild sets no flag** (mutation: take the permission on its rebuild only, still
committing the flag in step 1 — nothing clears it, and the next open performs
the whole-library rebuild the skip was taken to avoid). **The column-to-index
mapping is checked against the rebuild's behaviour, not the FTS schema**
(mutation: join one more column into an existing indexed value without altering
`CREATE VIRTUAL TABLE` — a schema-derived mapping is unchanged, and a skip
covering that column becomes silently wrong). **Both writers of
`normalisation_skips` spell `(table, column)` identically** (mutation: have the
write-path carve-out use the Dart accessor name while the pass uses the
registry's snake_case form — entries for the same column never group, condition
(a) stops correlating them, and no error is raised anywhere). **A tag and a
choreographer with the same name are both normalised** (mutation: group by
target value alone rather than by `(table, column, target)` — both are skipped
forever, and retry cannot repair it because a cross-table collision never stops
colliding). **A restore re-runs the pass** — restore a library containing an
un-normalised row after the pass has completed, and assert it is NFC (mutation:
keep the completion marker across restore — the row is never scanned and stays
un-normalised for the life of the install; mutation: revalidate the recorded
entries instead of clearing the marker — the restored row is in no entry, so
nothing discovers it). **`normalisation_skips` survives an epoch reset and a
detach** (mutation: clear it with the baseline, as `id_aliases` and
`review_queue` do — every owed repair is dropped on the next `409` while the
marker still asserts the scan completed). **A live row whose only colliding
partner is a tombstone is also skipped, and is normalised on a later run once
that tombstone is purged** (mutations: ignore soft-deleted rows when grouping —
the write then fails against an index that does not filter `deleted_at`; treat
a skip as final — the live row is blocked forever by a record the user cannot
see or list). **An ordinary edit to a blocked row succeeds** (mutation: apply
the write-path normalisation rule unconditionally — the user's edit is rejected
to satisfy an internal invariant). **`settings.key` is not rewritten by the
pass** (mutation: include every `shareable` string column without excluding
record identity — the settings record is renamed rather than repaired).
**Re-running the pass changes nothing** (mutation: make any step non-idempotent
— a pass interrupted after its last write then repeats it). **A row whose text
changed is still found by search afterwards** (mutation: skip the derived
rebuild — the index keeps the pre-normalisation text and matches nothing).

**Merge.** Every row of the table, both directions. A stale peer does not roll
back newer data (mutation: remove the `updatedAt` comparison). Equal `updatedAt`
with differing bodies ties and is reported, rather than producing a silent
winner (mutations: break the tie by keeping local; break it by taking remote).
≥3-device convergence with interleaved edits. A record absent from the baseline
and present on **both** sides converges — two devices independently setting the
same shareable settings key, whose id is the key itself, is the cheapest fixture
(mutations: resolve it as unconditional upload; resolve it as unconditional
download — each is one of the two one-sided rows read in isolation, and each
leaves the two devices permanently disagreeing while both look correct in a
single-device test).

**Existence.** A bystander does not resurrect a tombstone (mutation: drop the
existence rule from the `same`/`changed` row). A live record never out-ranks an
applied tombstone. Only a deliberate edit resurrects. A sync-initiated write
never cancels a tombstone. `existenceAt` crosses a device boundary. A later sync
write does not erase a revival (mutation: carry the signal as a boolean).

**Soft-delete join coverage.** §3.1's rule that every read joining through to a
soft-deletable parent filters `parent.deleted_at IS NULL` MUST be enforced by a
test that enumerates such reads, not left as prose. Stated as a property it has
no failure signal: a new read path that omits the filter compiles, passes, and
is caught only when a screen misbehaves. It has already decayed once — issue
#1016, where `VenueRepository.externalIdToVenueId` resolved an archive re-import
onto a tombstoned venue while the sibling `listAllIds` on the same class
filtered correctly, so a program was written referencing a tombstone with no
error. #1018 fixed that read; nothing yet stops the next one. Under sync that
program publishes while its venue publishes as deleted. The mutation the test
must catch is dropping the `deleted_at` predicate from any one such read.

**Write-path invariants.** §6.5's **I1** and **I2** MUST be enforced by a test
over write paths, not left as prose, for the same reason and with the same
decay mode as the join rule above: a new write path that violates either
compiles and passes. I1's test must catch a write that changes a record's
serialised content through a **join-hydrated** field without touching the
record's own row and without advancing `updatedAt` — the direct single-row case
is the one every implementer already gets right. I2's test must catch a
metadata-only re-stamp that advances `updatedAt` while `body` and the existence
state are unchanged, which is invisible to §6.9's repair classifier. The
enforcement MUST be structural over write paths rather than a maintained list
of known ones; a list relocates the omission it is meant to catch.

I1's test MUST also pin the **exception** in §6.5, not just the rule, and it
MUST cover both of the exception's conditions. For the content-derived
condition, an operation claiming the exemption is shown to produce identical
output on two independent runs over the same database while leaving all three
stamps unchanged
(mutation: let the exemption be claimed by declaration — an operation that
consults the clock, the device id or a random source then passes, and its output
diverges between devices with no stamp to order it). For the
divergence-surfacing condition, the operation is run over **two databases that
contain the same row** and differ only in whether its enumerated cross-row
dependency fires, and the row's output is either identical in both or shown to
surface as a §6.3 report (mutation: assert only the same-database property — it
is satisfied by any deterministic operation, including one that reads every
other row in the table, so a deterministic sibling read whose result differs
between devices passes it unchanged; this is the exact hole through which
§4.1's collision skip entered the specification while its justifying sentence
claimed the pass consulted nothing outside the row). The structural scan MUST
cover repository write paths; a migration-path operation is in scope only
through this proof, never through an exemption list.

Separately, and gating the normalisation pass rather than I1: **every write path
that populates a `shareable` string column routes through the normalising choke
point**, asserted structurally over the write paths themselves rather than over
a list of importers (mutation: add a writer that bypasses the choke point — the
row is stored NFD, and because nothing recorded it in `normalisation_skips` it
is never retried and is uploaded verbatim for the life of the install).

The ratchet is stated over **routing**, not over stored bytes, and that
distinction is now load-bearing rather than stylistic. §4.1's carve-out means a
legitimately routed write can also leave a row stored NFD, so a test asserting
"every `shareable` string in the database is NFC" would fail against sanctioned
behaviour, and a test written to the outcome could not tell a bypassing writer
from a recorded skip. What separates them is that the sanctioned path passed
through the choke point and left a `normalisation_skips` entry behind; the bug
did neither.

**Classification.** `deviceLocal` never serialised — property test over the
registry, and it MUST NOT be allowed to become vacuous. Inbound apply preserves
device-local columns. Inbound apply rejects present non-shareable keys, using
the **wire** spelling. A peer cannot push a `deviceScoped` setting.

**Reconciliation.** Converges from both sides (mutation: keep the local row).
Inbound references to the losing UUID are remapped. `deviceLocal` fields
preserved. Recency respected. Existence respected. Rename into an existing
name. Two devices derive the **same** renamed custom-field key from the same
collision (mutation: derive the suffix from a counter). Three devices carrying
three types yield three **distinct** keys (mutation: derive the suffix from the
surviving UUID rather than the losing one — two devices agree on the survivor,
so a two-device fixture cannot distinguish the two derivations). A collided
derived key lengthens to the full UUID in one step (mutation: lengthen
progressively). A record created on a device whose clock is behind, colliding
on the natural key with a tombstone a correctly-clocked peer stamped later in
real time, is **reported and left in place**, never silently erased (mutation:
apply the greater `existenceAt` without the baseline-absence check — the
tombstone wins and the just-created record vanishes with no report). Both
stamps MUST sit inside the acceptable window, so that the fixture proves the
rule rather than §6.9's quarantine. Custom-field type mismatch does not crash
on read. Alias chains resolve transitively. Alias retention is content-bounded.
Rewriting a reference bumps the referring record's `updated_at` and re-uploads
it (mutation: rewrite in place — the content changed but no row did, so peers
never learn of it and the reference stays broken on every device but this one).

**Dedupe.** A tombstone is never a dedupe candidate (mutation: include
tombstones, which silently resurrects a deleted dance by merging a live one onto
it). `program_slots.dance_id` is rewired to the survivor (mutation: leave it
pointing at the merged-away id). The uncompared scalars — `walkthrough`,
`rating`, `status`, `composedOn`, `revisedOn` — resolve by last-writer-wins
rather than following the tie-break survivor (mutation: take the survivor's
values, which loses whichever copy was edited more recently). Two clients agree
on a normalized-title match across NFC/NFD, case, internal whitespace,
punctuation, folded diacritics and a leading article (mutation: compare raw
titles; and separately, implement the four-step paraphrase this spec used to
carry, which passes every ASCII-lowercase fixture and fails on `The …`).
Review-queue insertion is idempotent under the canonical ordering, and
re-running a pass does not enqueue a pair twice
(mutation: key the queue on the unordered pair).

**Quarantine and repair.** Repairs against circulation without a user gesture
(mutations: keep the `max`; reset from the local clock; require a gesture). A
slow clock does not rewrite the collection downward. Repair adopts the matching
peer's timestamp, not the greatest. Repair does not push stale content. A local
edit made while poisoned survives. An in-window field is never touched. An
out-of-window `updatedAt` is rebuilt. A poisoned `updatedAt` never enters
circulation. A quarantined record advertises its last agreed hash. Withholding
reaches the second hop. A program citing a quarantined venue still publishes.

**Deletion.** Absence never deletes (mutation: make absence delete). A pending
tombstone is never republished. A pending-held row is never advertised as live.
A referenced entity cannot be tombstoned away. Purge refuses to cascade off live
records. An epoch reset does not discard a pending deletion. A published record
tombstones instead of hard-deleting (mutation: evaluate forfeiture against the
baseline, which answers "never published" for a record `PUT` in the pass that no
peer has confirmed yet). A detach-and-re-attach does not reverse a completed
deletion (mutation: clear `published_records` on detach — the hard delete then
proceeds without a tombstone and the peer's live copy is downloaded back).
Reconciliation carries the publication marker onto the survivor (mutation:
remap without it, then hard-delete the survivor while a peer still advertises
the losing id).

**Attach and restore.** Epoch mismatch → fresh attach, never deletion. Union and
silent merge. An equal-`updatedAt` fresh-attach tie is reported rather than
swallowed, and is reported again on the next steady pass (mutation: apply the
remote body and skip the report — a mutation that merely keeps local is
indistinguishable from the rule). Fresh attach stays referentially closed across
a pending hold. Three-peer fresh attach (deleter, pending holder, stale peer). A
restore converges rather than diverging.

**Server.** Each cap rejected at the boundary, not after allocation. A sync ID
one code point over the word bound is rejected `403`, and one at the bound is
accepted. Client and server derive the same `id_key` from the same typed ID
under differing whitespace and Unicode form (mutation: normalise on one side
only — the second device silently gets an empty store rather than an error,
which no status-code test can catch). A manifest `GET` returns a quoted strong
`ETag` equal to the manifest content hash, and honours `If-None-Match` with
`304`. A `Content-Type` carrying `; charset=utf-8` is accepted. `DELETE
/v1/store` removes grace-window blobs immediately (mutation: apply the 24-hour
exemption to `DELETE` as well, and the wipe silently leaves the data on disk).
**A plaintext request to `/v1` on the public listener is refused, never proxied
and never redirected** (mutation: place the `ProxyPass` outside a vhost, or in
both the `:80` and `:443` vhosts — the API answers identically on each, and the
bearer credential is disclosed on every plaintext call. Second mutation: answer
`301` to the `https` origin instead of refusing — the credential is already
disclosed by the plaintext request itself, and what the redirect adds is that a
client which follows it *and retains* `Authorization` across the hop gets a sync
that **works**, so nothing ever surfaces the misconfiguration and every run
repeats the disclosure. A client that strips instead follows the redirect and
gets a `401`, which fails visibly — but which of the two reaches a given
deployment is not the operator's to know (§7.5), and refusal is the only answer
that fails visibly for both. This is a deployment test
against the running configuration, since no unit test of the server process can
observe which port a proxy accepted the request on).

**Client isolate and robustness.** Allow-list bijection over real
`encodeArchive`-shaped output, never a hand-written key string. Hostile peer
blob: a malformed date rejects one record without aborting the batch or
escaping the isolate. Interrupted sync is a no-op. **A server presenting an
untrusted, expired or wrong-host certificate is refused, and no request
carrying `Authorization` is issued to it** (mutation: install a
`badCertificateCallback` returning `true` — the endpoint is still `https`, the
per-hop table still passes in full, and the sync ID is readable by anyone able
to present a certificate; a test asserting only on the URL scheme cannot fail
here). **No certificate-validation escape hatch exists in the client source at
all** (mutation: add a `badCertificateCallback` behind a debug flag defaulting
to off — the behavioural vector above still passes, because the test build
takes the default; only a source scan sees it. This is why the property is
owned by a standing ratchet and not by the unit that builds the client). **A
`localhost`-prefixed public host is refused** (mutation: test the loopback
exemption with `startsWith` or `contains` rather than an exact host match —
`http://localhost.example.com/v1` is then accepted as exempt and the sync ID
goes out in plaintext to a registrable domain). **`http://[::1]` and
`http://127.0.0.2` are refused** (mutation: implement the exemption as a
loopback-*range* test, such as `InternetAddress.tryParse(host)?.isLoopback` —
this is a distinct implementation from the one above and neither test catches
the other, since a range test rejects `localhost.example.com` correctly while
admitting every address §5 excludes). **A `302` to a foreign https host is
refused, and no request carrying `Authorization` is issued to it** (mutation:
validate only scheme, userinfo and port — every cosmetic check still passes and
the sync ID, which is the whole credential, leaves for an attacker-controlled
origin on the first hop). These are client-side and are grouped here rather
than under **Server** because the server never parses record content beyond
§7.2's key check — a server suite written from a list that included them would
be testing rules its implementation is forbidden to have.

A blob uploaded but not yet manifested survives a concurrent peer's manifest
`PUT` and survives the sweep (mutation: collect every unreferenced blob
regardless of age — the two-device interleave of §7.3 then deletes it, which is
the whole defect). Every store (re)creation mints an epoch no peer has seen
before (mutation: derive the epoch from the `id_key`, so a `DELETE /v1/store`
and recreate reproduces it and no peer ever fresh-attaches). Concurrent
creators of the same store observe the same epoch. A manifest `PUT` carrying a
stale epoch is rejected `409` and does not land. A blob `PUT` whose body does
not hash to its path segment is rejected, and a `PUT` to an existing hash does
not replace the stored bytes or refresh `uploaded_at` (mutation: touch
`uploaded_at` on the no-op — a client that re-uploads the same never-manifested
blob each pass then holds it past every grace window, indefinitely). A
structurally valid but weak user-chosen ID is
**accepted** by the server (mutation: re-run the client's strength estimator
server-side — the test fails as soon as the two implementations disagree, which
is the lockout). A blob `GET` returning `404` skips and reports the record and
leaves the baseline unadvanced, rather than deleting it.

## 10. Deferred

The following are recorded as known and are not specified here:

- Dance dedupe runs only at fresh attach, so a dance can fork permanently.
- Equal `updatedAt` with differing bodies does not converge (§6.2 step 5, §6.3).
  The divergence is reported bilaterally rather than resolved, because every
  available tie-break is non-convergent.
- Pepper rotation is impossible for inactive stores as specified.
- The `T₀` backfill is per-device and can resurrect some pre-migration
  deletions; accepted for beta.
- Alerting, retention proof, break-glass authorisation and lost-ID support are
  operational prerequisites of shipping, not of implementation.
- A privacy-policy amendment is a blocking prerequisite of shipping.
- **Pinning a self-hosted server's certificate on first use.** Self-hosting
  requires a publicly-trusted certificate on a routable name whenever the sync
  set contains a phone (§5), which is most of them, and that is a real cost
  against the ADR's hard constraint 4. Two desktops can use a private CA in the
  OS trust store instead, at the blast radius §5 sets out. A sanctioned
  pin-on-first-use — the user records one specific server certificate
  fingerprint, which is not a general trust anchor and does not reopen the hole
  §5 closes — would remove that cost. It is not specified here because it needs
  a rotation story and a change-of-fingerprint UX that this design has not
  worked through, and because the DNS-01 path exists today. The maintainer
  reviewed this trade and accepted it on those terms, keeping pinning available
  as the way to remove the cost later; it is deferred rather than rejected.
