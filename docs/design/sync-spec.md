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

`tombstone_blob` is `shareable` because it is record content that is
re-transmitted, not device bookkeeping.

**Lifecycle.** All are scoped to the store identity. `id_aliases` and
`review_queue` clear with the baseline. `pending_deletions` MUST survive an
epoch reset and MUST clear on detach; after a restore its rows MUST be
revalidated against the restored data.

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

- keys sorted lexicographically, applied recursively;
- no insignificant whitespace;
- one pinned number form — integers MUST NOT be emitted as `8.0`;
- envelope fields always present, `null` where empty;
- body fields: explicit `null` for an empty `shareable` field, omission **only**
  for a field that is not `shareable`;
- **timestamps emitted at exactly one-tick precision** (§2), UTC, with the
  sub-tick component always zero.

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
except `http://localhost` and `http://127.0.0.1`.

### 5.1 Authentication

The sync ID travels in the `Authorization` request header using the `Bearer`
scheme, with the sync ID as the credential. It MUST NOT appear in a URL.

The server MUST derive a storage key as `HMAC-SHA256(pepper, syncID)` and MUST
NOT persist the plaintext sync ID. The pepper lives in server configuration,
never in the database. This is server-side only; the client computes no MAC and
MUST NOT hold the pepper.

### 5.2 Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/store` | Store metadata: epoch, device list, quota usage. Creates the store if absent. |
| `DELETE` | `/v1/store` | Detach-and-wipe. |
| `GET` | `/v1/manifests/{deviceId}` | Fetch one manifest. `ETag` / `If-None-Match`. |
| `PUT` | `/v1/manifests/{deviceId}` | Publish this device's manifest. |
| `DELETE` | `/v1/manifests/{deviceId}` | Remove a device's manifest. |
| `GET` | `/v1/blobs/{hash}` | Fetch one blob. Immutable; long `Cache-Control`. |
| `PUT` | `/v1/blobs/{hash}` | Upload one blob. Idempotent. |
| `POST` | `/v1/blobs/missing` | Given hashes, return the subset the store lacks. |

### 5.3 Status codes

| Code | Meaning |
| --- | --- |
| `200` | OK. |
| `201` | Blob or manifest created. |
| `204` | Deleted. |
| `304` | Manifest unchanged. |
| `400` | Malformed request. |
| `401` | Missing or malformed `Authorization`. |
| `403` | Sync ID below the entropy floor. |
| `404` | No such blob, manifest, device — or store. |
| `409` | Epoch mismatch. |
| `413` | Payload exceeds a cap. |
| `422` | Payload rejected by the allow-list. |
| `429` | Rate limited. `Retry-After` set. |
| `507` | Store quota exhausted. |

There is no distinct "expired" status. Reset detection is the epoch's job. A
client receiving `404` from a store-scoped endpoint recovers by calling
`GET /v1/store`.

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
   `updatedAt` wins; existence disagreements resolve per §6.4.
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
   | absent from baseline, present locally | — | upload |
   | — | absent from baseline, present remotely | download |

   A quarantined record MUST be excluded from this table entirely.

   With N peers, evaluate against all and take the newest `updatedAt`.
5. `POST /v1/blobs/missing`; `PUT` only what is missing.
6. `GET /v1/blobs/{hash}` for each needed hash. The client MUST verify the hash
   before applying.
7. Apply in one transaction (§6.7). Rebuild derived indexes.
8. `PUT /v1/manifests/{self}`.
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

### 6.6 Collision reconciliation

`choreographers.name`, `tags.name` and `custom_field_defs.key` are `UNIQUE`.
Applying a record of those kinds:

1. **UUID known locally** → update, last-writer-wins on `updatedAt`. If the
   update would move the natural key onto a name another local row holds, it
   MUST NOT merge silently — route to the review queue.
2. **UUID unknown, natural key matches** → reconcile silently.
3. **Neither** → insert.

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

**Custom-field defs** reconcile only when `type` matches. On mismatch both
survive: the smaller UUID keeps the bare key, the other is renamed with a suffix
derived from the losing UUID (not a counter). If a derived key collides,
lengthen the prefix.

**The remap.** Reconciliation produces `losing → surviving`, applied to local
references **and** to every inbound record in the same batch, and persisted in
`id_aliases`. Lookups MUST chase the chain to a fixed point; superseded entries
are rewritten in place. An alias is retired once no current peer manifest lists
the losing id.

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
(session-scoped counter).

A solo install has no repair path. A never-corrected clock does not self-heal.

### 6.10 Fresh-attach dedupe

Union matches on record id. Silent merge only where both hold an exact
normalized-title match **and** `_choreographyEquals`. Tombstones MUST NOT be
dedupe candidates.

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

A backup restore MUST drop the sync baseline, forcing a fresh attach.
`id_aliases` and `review_queue` clear with it; `pending_deletions` does not, and
is revalidated afterwards.

Restore converges on a deletion only while some peer still advertises the
tombstone.

### 6.12 Failure, offline and triggers

Sync is best-effort and MUST NOT block the UI. Any failure leaves local data
untouched and retries on the next trigger.

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
  PRIMARY KEY (id_key, hash)
);
```

Blobs MUST be namespaced per store. Cross-store deduplication is a privacy leak
and MUST NOT be implemented.

The server MUST NOT merge, lock, or interpret record content beyond §7.2.

### 7.2 Allow-list validation

The server MUST reject (`422`) any blob carrying a key not classified
`shareable` for its kind. The mapping MUST be **generated** from the registry
and proven by test — a hand-maintained list drifts and is worse than useless.

This is a second line of defence. The client serialiser is the control, and
neither is sufficient alone.

### 7.3 TTL and garbage collection

A sweeper runs hourly:

```sql
DELETE FROM stores WHERE last_seen < (now - 30 days);
```

then cascades manifests, blob refs and blob files. `last_seen` is refreshed by
any authenticated request, making this a rolling TTL on activity.

A blob is reachable while any manifest for its store references it. After each
manifest `PUT`, and during the sweep, unreferenced blobs for that store are
deleted.

### 7.4 Break-glass access log

Break-glass access MUST write to a **separate database** holding exactly:

| Column | Retention |
| --- | --- |
| `id_key` | `HMAC-SHA256(pepper, syncID)`, never plaintext. Nulled after 30 days. |
| `accessed_at` | Retained. |

Separate so that reaping a store cannot destroy evidence of access to it. Its
retention is therefore not the 30-day disuse TTL and MUST be stated in the
privacy policy.

## 8. Security

**Sync ID.** Format is four hyphen-separated words, enforced. A generated ID
uses the EFF long wordlist. A user-chosen ID MUST clear a strength floor of
~2⁴⁰ scored on the actual string, and four weak words MUST be rejected. The
server returns `403` below the floor.

**Transport.** TLS required except `localhost`/`127.0.0.1`. Redirects MUST be
followed manually with per-hop validation — https only, no userinfo, default
port, hop cap. `package:http`'s `followRedirects = true` MUST NOT be used. The
user-configured endpoint is validated on entry: https or localhost, no userinfo,
no fragment, no query. A custom endpoint MUST be shown prominently and a change
MUST warn.

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
does not satisfy the requirement. The full annotated list, with the reasoning
behind each, is in [sync.md §Testing](sync.md).

**Wire format.** Canonical-JSON goldens (two devices, byte-identical);
integer/float form; absent-versus-null; recursive key order.

**Merge.** Every row of the table, both directions. A stale peer does not roll
back newer data (mutation: remove the `updatedAt` comparison). ≥3-device
convergence with interleaved edits.

**Existence.** A bystander does not resurrect a tombstone (mutation: drop the
existence rule from the `same`/`changed` row). A live record never out-ranks an
applied tombstone. Only a deliberate edit resurrects. A sync-initiated write
never cancels a tombstone. `existenceAt` crosses a device boundary. A later sync
write does not erase a revival (mutation: carry the signal as a boolean).

**Classification.** `deviceLocal` never serialised — property test over the
registry, and it MUST NOT be allowed to become vacuous. Inbound apply preserves
device-local columns. Inbound apply rejects present non-shareable keys, using
the **wire** spelling. A peer cannot push a `deviceScoped` setting.

**Reconciliation.** Converges from both sides (mutation: keep the local row).
Inbound references to the losing UUID are remapped. `deviceLocal` fields
preserved. Recency respected. Existence respected. Rename into an existing name.
Custom-field type mismatch does not crash on read. Alias chains resolve
transitively. Alias retention is content-bounded.

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
records. An epoch reset does not discard a pending deletion.

**Attach and restore.** Epoch mismatch → fresh attach, never deletion. Union and
silent merge. Fresh attach stays referentially closed across a pending hold.
Three-peer fresh attach (deleter, pending holder, stale peer). A restore
converges rather than diverging.

**Server.** Each cap rejected at the boundary, not after allocation. Allow-list
bijection over real `encodeArchive`-shaped output, never a hand-written key
string. Hostile peer blob: a malformed date rejects one record without aborting
the batch or escaping the isolate. Interrupted sync is a no-op.

## 10. Deferred

The following are recorded as known and are not specified here:

- Dance dedupe runs only at fresh attach, so a dance can fork permanently.
- Pepper rotation is impossible for inactive stores as specified.
- The `T₀` backfill is per-device and can resurrect some pre-migration
  deletions; accepted for beta.
- Alerting, retention proof, break-glass authorisation and lost-ID support are
  operational prerequisites of shipping, not of implementation.
- A privacy-policy amendment is a blocking prerequisite of shipping.
