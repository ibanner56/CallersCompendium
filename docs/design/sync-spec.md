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

`tombstone_blob` is `shareable` because it is record content that is
re-transmitted, not device bookkeeping.

**Lifecycle.** All are scoped to the store identity except `published_records`,
which is treated separately below. `id_aliases` and `review_queue` clear with
the baseline. `pending_deletions` MUST survive an epoch reset and MUST clear on
detach; after a restore its rows MUST be revalidated against the restored data.

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
- **all strings in Unicode NFC**, normalised on ingest as timestamps are.

RFC 8785 leaves the last of these out of scope, so it MUST be stated separately
and it MUST be applied before hashing. Titles and
`custom_field_values.value_text` are arbitrary user text, and a title pasted
from a macOS filename arrives in NFD while the same title typed on Android
arrives in NFC. Both display identically and hash differently, which under §6.3
is a permanent `changed`/`changed` for two records that are the same record.
Normalising on ingest closes it for the same reason tick truncation does, and
MUST NOT be skipped on the assumption that a sender normalised.

Two number values that JSON cannot represent MUST be handled rather than
emitted: a `shareable` float column can hold NaN or ±Infinity — `SQLite` REAL
admits both — and RFC 8785 has no encoding for either. A record whose canonical
form would require one MUST be treated as malformed and rejected on the terms of
§6.7, never coerced to `null` or `0`, which would silently alter user data and
still not converge.

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
| `DELETE` | `/v1/store` | Detach-and-wipe. |
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
   before the next pass reach exactly this state, and 47 settings keys are
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
normalisation on ingest.

That NFC precondition is load-bearing here and not merely inherited. The
diacritic fold is a lookup keyed on **precomposed** characters, so a combining
mark never matches it; an NFD combining mark instead falls through to the
punctuation rule and becomes a *space*. `résumé` in NFC normalizes to `resume`
and in NFD to `re sume`. A trailing mark happens to survive this — the injected
space is then trimmed — so the divergence appears on internal accents only,
which makes it intermittent and hard to attribute. Normalising on ingest is what
makes the two forms agree; the fold table is not going to.

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

A backup restore MUST drop the sync baseline, forcing a fresh attach.
`id_aliases` and `review_queue` clear with it; `pending_deletions` does not, and
is revalidated afterwards.

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
satisfy all four of the following. Each has been chosen because the default
behaviour of at least one common proxy violates it.

| # | Requirement | Why it is not automatic |
| --- | --- | --- |
| 1 | The `Authorization` request header MUST reach the server unmodified. | It carries the sync ID (§5.1). A proxy that consumes it makes every request `401`. Apache needs `CGIPassAuth On` if the server is ever fronted by CGI/FPM. |
| 2 | Request bodies MUST be permitted to at least the manifest limit in §5.4 (16 MB). | Defaults are wrong in opposite directions: nginx's `client_max_body_size` is 1 MB and rejects valid manifests; Apache's `LimitRequestBody` is unlimited and enforces nothing. Set it explicitly. |
| 3 | The proxy MUST NOT decompress request bodies. | §4 puts the decompression limit on the receiver, enforced streaming-abort style. Inflating at the proxy moves a security control to a component that does not implement it. |
| 4 | The sync ID MUST NOT be written to any log. | Common log formats omit headers, so this holds by default and is lost the moment someone adds `%{Authorization}i` or `$http_authorization` to a debug format. §5.1 keeps the ID out of URLs for the same reason. |

A server behind a proxy that violates (1) or (2) is **not conforming**: it will
reject valid requests. Violations of (3) or (4) are not visible in behaviour at
all, which is why they are stated rather than left to deployment taste.

Beyond these, deployment is unconstrained. `localhost`/`127.0.0.1` waives TLS
(§8) so a self-hoster needs no certificate, and a non-default port is permitted
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
bytes on two independent encoders (mutation: emit `double.toString()` instead of
the shortest round-tripping form). The same title in NFC and NFD hashes
identically after ingest (mutation: skip normalisation, and watch two devices
hold one record as a permanent `changed`/`changed`). A record requiring NaN or
±Infinity is rejected rather than coerced.

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
#1016, where `VenueRepository.externalIdToVenueId` resolves an archive
re-import onto a tombstoned venue while the sibling `listAllIds` on the same
class filters correctly, so a program is written referencing a tombstone with no
error. Under sync that program publishes while its venue publishes as deleted.
The mutation the test must catch is dropping the `deleted_at` predicate from any
one such read.

**Classification.** `deviceLocal` never serialised — property test over the
registry, and it MUST NOT be allowed to become vacuous. Inbound apply preserves
device-local columns. Inbound apply rejects present non-shareable keys, using
the **wire** spelling. A peer cannot push a `deviceScoped` setting.

**Reconciliation.** Converges from both sides (mutation: keep the local row).
Inbound references to the losing UUID are remapped. `deviceLocal` fields
preserved. Recency respected. Existence respected. Rename into an existing name.
Two devices derive the **same** renamed custom-field key from the same collision
(mutation: derive the suffix from a counter). Three devices carrying three types
yield three **distinct** keys (mutation: derive the suffix from the surviving
UUID rather than the losing one — two devices agree on the survivor, so a
two-device fixture cannot distinguish the two derivations). A collided derived
key lengthens to the full UUID in one step (mutation: lengthen progressively).
Custom-field type mismatch does not crash on read. Alias chains resolve
transitively. Alias retention is content-bounded. Rewriting a reference bumps
the referring record's `updated_at` and re-uploads it (mutation: rewrite in
place — the content changed but no row did, so peers never learn of it and the
reference stays broken on every device but this one).

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

**Client isolate and robustness.** Allow-list bijection over real
`encodeArchive`-shaped output, never a hand-written key string. Hostile peer
blob: a malformed date rejects one record without aborting the batch or escaping
the isolate. Interrupted sync is a no-op. These are client-side and are grouped
here rather than under **Server** because the server never parses record content
beyond §7.2's key check — a server suite written from a list that included them
would be testing rules its implementation is forbidden to have.

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
