# Design: Sync and the Athenaeum protocol

> **Decision record:** [ADR-004](../adr/004-device-sync-and-athenaeum.md).
> That ADR decides *what* we build and why; this document specifies *how*. If
> the two disagree, the ADR wins and this document is wrong.

**Status: specification. Nothing here is built.**

## Vocabulary

| Term | Meaning |
| --- | --- |
| **Sync** | The user-facing feature. |
| **Athenaeum** | The store Sync talks to. Default `https://athenaeum.callerscompendium.com/`; user-editable. |
| **sync ID** | Diceware passphrase identifying one store. A bearer credential. |
| **device ID** | Random v4 UUID minted per installation, on opt-in. Classified `deviceScoped` — it is never synced as a record — while the same string travels in manifest envelopes and request paths as an opaque routing key. See "what `EgressClass` actually governs". |
| **epoch** | Opaque 128-bit random value the server stamps on a sync ID at creation. |
| **record** | One syncable row — a dance, program, tag, choreographer, published source, custom field def, venue, or a settings key. |
| **blob** | One record, serialised and content-addressed. |
| **manifest** | One device's map of record id → content hash. |
| **baseline** | The manifest a device last successfully synced, held locally. The merge base. |

## What travels

Sync holds no allow-list. It reads `EgressClass` from
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

### Record kinds, and what rides inline

Top-level records, each producing its own blob:

`dance` · `program` · `choreographer` · `tag` · `publishedSource` ·
`customFieldDef` · `venue` · `setting`

Join rows are **not** separate records. They ride inline with their parent
exactly as the archive codec already models them — a dance carries its
`authorIds`, tag ids, links, source citations and custom-field values; a program
carries its slots. This keeps the merge unit equal to the thing a user edits,
so "I changed this dance" is one blob and one conflict, not seven.

### The serialiser must filter — the codec does not

**This is the highest-risk detail in the design.**

The archive codec emits `deviceLocal` fields today, and it is right to:
`_choreographerToJson` writes `email` and `location`, and the venue serialiser
writes the address block and both contact blocks. A local backup *should*
contain them.

So a sync implementation that reaches for `encodeArchive` and uploads the result
would ship precisely the data this feature exists to keep off our
infrastructure — and it would look completely reasonable in review.

Sync therefore serialises through a **classification-filtered** path that
consults `EgressClass` per field, and the property test named under Testing
exists specifically to catch a regression here. The server's deny-list is the
second line; neither is sufficient alone, because the server check is a
forward-compatible deny-list and the client check is the one that knows about
new fields first.

### The device ID, and what `EgressClass` actually governs

An earlier draft called the device ID `deviceScoped`; a review pointed out that
this contradicts the term, since the ID plainly travels. Over-correcting to
`shareable` would have been worse, and would have caused a real bug: settings
sync would then carry `device_id` into a settings blob, and the receiving device
would adopt the sender's ID — two devices writing the same manifest.

The resolution is a distinction the registry has always implied and this
document now states outright:

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

### Sync's own configuration never syncs

Every settings key Sync introduces is `deviceScoped`:

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
parse-never-fails) and already round-trip tested. Sync must not grow a second
serialiser.

### Settings records

Each settings key is its own blob, `kind: "setting"`, with the key as the record
id. Per-key rather than one settings document, so two devices changing different
preferences never collide.

This requires a schema change: `settings` is `(key, value_json)` with no
timestamp, so the `updatedAt` conflict rule cannot reach it. **Schema v22** adds
`updated_at`, stamping existing rows at migration time. The new column needs
classifying like any other, and the coverage ratchet will require it.

### Content hash

`hash = lowercase-hex(SHA-256(canonical-json(blob)))`

Canonical JSON means keys sorted lexicographically, no insignificant whitespace,
and no floating-point re-formatting. Two devices that hold an identical record
**must** produce an identical hash, or delta sync degrades to full sync.

Golden tests pin the canonicalisation. A change to it is a wire-format break
and needs a `v` bump.

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
hashed (SHA-256) to produce the storage key prefix, so the plaintext ID is never
written to disk and a stolen backup of the store does not yield working
credentials for the IDs inside it.

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
| `422` | **Payload rejected by the deny-list** — a device-local field was present. |
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

**Sync is disabled on every installation until the user turns it on.** No sync
setting is populated, no endpoint is contacted, no device ID is minted. An app
that has never been configured for Sync makes no sync-related network call of any
kind, which keeps "the app works fully offline and phones home to nobody" true by
construction for every user who does not opt in — not merely true by policy.

Sync gets its **own top-level blade in Settings**, not a row buried under
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
   there is no baseline to justify one.
6. Persist the epoch and the resulting manifest as the new baseline.

### Fresh-attach dedupe

Union matches on record id. Two devices that imported the same dance separately
hold different ids for it, so union alone yields duplicates.

**Silent merge** where both hold:

1. exact normalized-title match (`normalizeTitle`), and
2. `_choreographyEquals` — form, formation, progression, phrase structure,
   figures *including params*, hook, calling notes, level, mixed level, tunes.

Everything else that the existing `DedupeIndex` flags goes to the review queue,
through the import pipeline's plan → review → commit flow.

Sync **calls** `_choreographyEquals` rather than reimplementing it. Two
definitions of "the same dance" would drift, and the drift would be silent.

Deliberately stricter than import: import treats title + author-overlap as
confident even when choreography differs, which is right for re-importing a
source record and wrong here — that case is a dance edited differently on each
device, and merging it silently would discard one side.

On silent merge the surviving record keeps one id; the id-collections
`_choreographyEquals` ignores — tags, custom fields, links, citations — are
**unioned**, since they are additive and neither side is more correct.

The user is told the count afterwards ("merged 412 duplicates"), not asked.

### Steady-state sync

1. `GET /v1/store`. **Epoch differs → fresh attach.** Stop.
2. Compute the local manifest.
3. `GET /v1/manifests/{peer}` for each peer, with `If-None-Match`.
4. Per record, compare local / remote / baseline hashes:

   | Local vs baseline | Remote vs baseline | Action |
   | --- | --- | --- |
   | same | same | nothing |
   | changed | same | upload |
   | same | changed | download and apply |
   | changed | changed | **conflict** → higher `updatedAt` wins |
   | absent from baseline, present locally | — | upload (new here) |
   | — | absent from baseline, present remotely | download (new elsewhere) |

5. `POST /v1/blobs/missing` with the hashes to upload; `PUT` only what is
   missing.
6. `GET /v1/blobs/{hash}` for each needed hash. **Verify the hash before
   applying.**
7. Apply in one transaction. Rebuild derived indexes.
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

### Failure and offline

Sync is best-effort and never blocks the UI. Any failure leaves local data
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
registry as the client, so the deny-list has one definition.

### Storage layout

```
data/
  athenaeum.sqlite      stores, devices, blob refcounts, quota, activity
  blobs/<aa>/<bb>/<hash>
```

Blobs are fanned out two levels to keep directory sizes sane. The path is
derived from the hash, which the server has **verified** — so it cannot contain
traversal sequences.

```sql
CREATE TABLE stores (
  id_hash     TEXT PRIMARY KEY,   -- SHA-256 of the sync ID; never the plaintext
  epoch       TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  last_seen   INTEGER NOT NULL,   -- any request refreshes it; drives the TTL
  bytes_used  INTEGER NOT NULL
);
CREATE TABLE manifests (
  id_hash TEXT NOT NULL, device_id TEXT NOT NULL,
  etag TEXT NOT NULL, written_at INTEGER NOT NULL, body BLOB NOT NULL,
  PRIMARY KEY (id_hash, device_id)
);
CREATE TABLE blob_refs (
  id_hash TEXT NOT NULL, hash TEXT NOT NULL, size INTEGER NOT NULL,
  PRIMARY KEY (id_hash, hash)
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
| `id_hash` | SHA-256 of the sync ID — **the same hash the store uses**, never the plaintext |
| `accessed_at` | Timestamp |

Hashed rather than plaintext for a specific reason: the sync ID is a bearer
credential, and the store already avoids holding it in the clear so that a stolen
copy yields nothing usable. A plaintext access log would undo exactly that, and
would be worse than the store, because the log is meant to outlive the stores it
describes. Hashing costs nothing operationally — to find entries for a store
under investigation, hash the ID and match.

The log is deliberately minimal: it records **that** access happened and to
which store, not why. Justification lives in whatever incident process wraps it,
not in a field nobody validates.

It is a **separate database** so that reaping a store cannot destroy the evidence
of access to it. Its retention is therefore not the 30-day disuse TTL — an audit
log that expires with its subject is not an audit log — and needs its own stated
period in the privacy policy.

### Deny-list validation

On `PUT /v1/blobs/{hash}` the server:

1. checks the size cap **before** reading the body;
2. streams and hashes, aborting if the running total exceeds the cap;
3. rejects with `400` if the computed hash differs from the path;
4. parses as JSON with a depth cap (a new server-side bound — the codec's
   `kMaxMeanwhileDepth` guards figure nesting, not parse depth);
5. **walks every key and rejects with `422` if any key is device-local**,
   per the shared registry.

Step 5 is a backstop, not the control. The client's serialiser is the control.
It exists so a client bug fails loudly on our side rather than silently
persisting a venue address.

It is a **deny-list on known-forbidden keys**, so it is forward-compatible: keys
the server does not recognise pass. A device-local field added in a client newer
than the server would not be caught — but that client would not send it either.
Stated so the limit of the guarantee is legible.

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
- The server stores only SHA-256 of the ID, so a stolen store yields no IDs.

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
- **Deny-list backstop** — a hand-built blob containing `contact1_email` is
  rejected `422`.
- **Interrupted sync is a no-op** — kill after blob upload, before manifest
  `PUT`; assert peers see nothing.
- **Fresh-attach union and silent merge** — `{B,C}` joining `{A,B}` yields
  `{A,B,C}`; identical-choreography duplicates merge without a prompt;
  same-title-same-author-different-figures reaches the review queue.
- **Server caps** — each limit rejected at the boundary, not after allocation.

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
| Default state | **Off on every installation.** Opt-in only; an unconfigured app makes no sync network call at all. Sync gets its own top-level Settings blade. |
| Access log | **Separate database**, holding only a **hashed** sync ID and a timestamp. Hashed so the log is not itself a credential store; separate so reaping a store cannot destroy evidence of access to it. |

### The settings migration has a one-time ordering effect

Each device stamps `updated_at` at *its own* migration time, so the device that
upgrades last carries the newest settings and wins every settings conflict on the
first sync afterwards. Deterministic, one-time, and recoverable by re-setting a
preference — but it is a real effect and should not be discovered in the field.

An alternative was considered and rejected: stamping a fixed sentinel so all
devices agree. That makes every settings row tie, leaving the conflict rule with
no discriminator at all, which is worse.

## Open questions

1. **Break-glass access-log retention period.** The log holds a hashed sync ID
   and a timestamp, in a separate database so that reaping a store cannot
   destroy the record of access to it. It therefore cannot inherit the 30-day
   disuse TTL — an audit log that expires with its subject is not an audit log —
   so it needs a stated period, and the privacy policy has to name it.
