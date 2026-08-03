# Design: Sync and the Athanaeum protocol

> **Decision record:** [ADR-004](../adr/004-device-sync-and-athanaeum.md).
> That ADR decides *what* we build and why; this document specifies *how*. If
> the two disagree, the ADR wins and this document is wrong.

**Status: specification. Nothing here is built.**

## Vocabulary

| Term | Meaning |
| --- | --- |
| **Sync** | The user-facing feature. |
| **Athanaeum** | The store Sync talks to. Default `https://athanaeum.callerscompendium.com/`; user-editable. |
| **sync ID** | Diceware passphrase identifying one store. A bearer credential. |
| **device ID** | Random v4 UUID minted once per installation. A **protocol identifier that is transmitted** — it appears in manifests and request paths. See the note below; it is deliberately *not* `deviceScoped`. |
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

### The device ID is not `deviceScoped`

An earlier draft of this spec called the device ID `deviceScoped`. That was
wrong, and the term matters because it is enforced: `deviceScoped` means *never
travels by any route*, and the device ID travels in every manifest and every
request path.

The device ID is an opaque protocol key: minted per installation, random,
meaningless outside its store, and never reused across stores. When Sync is
built it becomes a new persisted settings key, at which point the settings
ratchet **will require it to be classified** — and the honest classification is
`dpv:NonPersonalData` / `DataSubject.none` / `EgressClass.shareable`, with a note
that it must travel for the protocol to function.

Worth stating plainly rather than burying: it is a persistent per-installation
identifier that our server sees. A store operator can observe that N devices sync
to one store and when each was last active. That is metadata we hold, it is
bounded by the 30-day TTL, and the privacy policy should say so rather than imply
the store is opaque to us.

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
| `410` | Store expired and was reaped. Treat as fresh attach. |
| `413` | Payload exceeds a cap. |
| `422` | **Payload rejected by the deny-list** — a device-local field was present. |
| `429` | Rate limited. `Retry-After` set. |
| `507` | Store quota exhausted. |

`409` and `410` both mean "discard your baseline and re-attach". They are
distinguished for diagnosis, not for behaviour.

`422` should never occur in normal operation. It fires only when a client bug
would otherwise put a venue address on our infrastructure, so it is a **loud**
failure: surfaced to the user, logged, never silently retried.

## Client algorithm

### Attach

1. User enters or accepts a sync ID and confirms the endpoint.
2. `GET /v1/store`. Server creates the store if it does not exist, returning its
   epoch.
3. **Fresh attach**, always, on first attach for this ID, on re-attach after
   detach, and on `409`/`410`. Detaching **forgets the sync ID entirely**: no
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
- `507` → surface with a link to what is taking the space.
- Partial upload → harmless. Blobs are content-addressed and immutable; the
  manifest is written last, so a half-finished sync publishes nothing.

**The manifest is written last, always.** That single ordering rule is what
makes an interrupted sync a no-op instead of a corruption.

### Triggers

- On app start, once, after any pending migration completes.
- Debounced 30s after a local change.
- Manually via "Sync now".
- Never on a metered connection unless the user opts in.

## Server implementation

**Dart + `shelf`**, one container, SQLite plus a blob directory, in a new
top-level `server/` package with a path dependency on `compendium_core`.

The path dependency is the point: the server reads the **same** classification
registry as the client, so the deny-list has one definition.

### Storage layout

```
data/
  athanaeum.sqlite      stores, devices, blob refcounts, quota, activity
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
  last_seen   INTEGER NOT NULL,   -- drives the 30-day TTL
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

`last_seen` is updated by **any** authenticated request for the store. Deletion
is unconditional and needs no per-user action, which is what makes retention
obligations self-satisfying rather than procedural.

### Garbage collection

A blob is reachable while any manifest for its store references it. After each
manifest `PUT`, and during the sweep, unreferenced blobs for that store are
deleted. Mark-and-sweep scoped to one store is cheap; no global scan.

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
- **User-chosen IDs are subject to a minimum-entropy floor**, server-enforced
  with `403`. A warning alone would not stop `isaac-banner-dances`, which is
  guessable in seconds. The floor is computed on the *chosen* string, not on its
  length: a word-count check would pass four common words.
- The ID never appears in a URL, so it does not reach logs or `Referer`.
- The server stores only SHA-256 of the ID, so a stolen store yields no IDs.

### Enumeration

`GET /v1/store` creates a store if absent, so a probe cannot distinguish "exists"
from "does not exist" by status code. Creation is cheap and the sweeper reaps
unused stores in 30 days.

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

## Open questions

Carried for the maintainer; none blocks specification.

1. **Settings merge granularity.** Settings sync as `shareable`, but the table
   is key/value: is each key a record (fine-grained, more blobs) or is the whole
   settings map one record (simple, but any change re-uploads all of it, and two
   devices changing different keys conflict)? Leaning per-key.
2. **Programs referencing device-local venues.** A program syncs and references
   a venue whose address did not travel. The venue record arrives partially.
   Confirmed acceptable — but should a program's *own* `venue` free-text label
   travel? It is `shareable` today.
3. **Metered-connection default.** Proposed: never auto-sync on metered, opt-in
   per device. Confirm.
4. **Quota exhaustion UX.** `507` at 250 MB — what does the app say, and does it
   offer to exclude imported dances (the setting from ADR-004)?
5. **Does "Sync now" force a full re-verify** or only a delta pass? A user
   pressing it usually suspects something is wrong, which argues for a full
   pass.
6. **Server operator visibility** — is there any admin surface at all, or is the
   store deliberately opaque even to the operator? Affects abuse handling.
7. **Entropy floor value.** Proposed: reject anything below ~2⁴⁰ estimated. Needs
   a number and a wordlist decision (EFF long list, 7776 words, is the default).
