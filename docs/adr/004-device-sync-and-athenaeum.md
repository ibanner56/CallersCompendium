# ADR-004: Sync, and the Athenaeum sync store

- **Status**: Proposed
- **Roadmap item**: Amends the v1 non-goals list in `docs/ROADMAP.md` (removing
  "cloud sync") and supersedes the Later-milestones item "Optional
  device-to-device sync, beyond Apple-native AirDrop support". Referenced by
  text rather than line number: both moved when this PR edited that file.
- **Deciders**: @ibanner56
- **Specification**: [docs/design/sync.md](../design/sync.md) — wire format,
  HTTP contract, client algorithm, server implementation and threat model.

## Context

Caller's Compendium is built on a promise: **the app collects nothing about
you, has no accounts, and stores your data only on your own device.** That
promise is published, linked from both app stores, and mirrored in
`site/privacy/index.html`.

Users keep asking for their collection to appear on more than one device. The
app already exports a complete backup to a single JSON file that can be restored
elsewhere, and that satisfies technically-confident users. For everyone else it
is a chore they get wrong: it is a manual, whole-collection, point-in-time
operation, and a caller who edits a dance on a laptop the night before a gig has
no way to get it onto the phone in their pocket without thinking about files.

So the problem is not "can data move between devices" — it can. It is that the
only mechanism we offer demands the user understand and drive it.

### What we may and may not carry

The maintainer's position is that **dance choreography and programs are not user
data**. A dance is a sequence of figures; a program is a list of dances. Neither
describes the person using the app, and both may travel unscrubbed.

But the app stores more than figures and dance lists. It stores venue postal
addresses, venue contact names, phone numbers and email addresses, and
choreographer contact details — data about **people who have never used this
app and cannot consent to a transfer they do not know about**.

Until recently that boundary was prose. A doc comment on `Choreographer` said
its `email` and `location` "MUST NOT be emitted in any shareable export";
nothing enforced it, and the same question had no answer at all for the 22
columns of `venues`. That was fixed first, deliberately, before any of this was
designed. The classification registry in `packages/compendium_core/lib/src/privacy/` now
records, for every persisted field, what kind of data it is, whose data it is,
and whether it may leave the device — enforced by CI ratchets and rendered to
[data-classification.md](../dev/data-classification.md).

**That registry is the precondition for this design.** Sync does not get its own
allow-list; it reads `EgressClass` and carries exactly what is marked
`shareable`. A field added without classification fails CI, so it can never
reach the network by omission.

### Constraints

These bound every option below.

1. **No encryption that carries operational overhead.** An earlier beta shipped
   a passphrase-encrypted backup (Argon2id + XChaCha20-Poly1305) and it was
   removed in #536 to return the app to export-compliance-exempt status — no
   encryption declaration, no annual BIS self-classification report. Any design
   that reintroduces confidentiality crypto reopens that, and is out.
2. **Asynchronous.** Devices are rarely awake at the same time. "Put both
   devices on the same wifi and press sync" does not solve the problem.
3. **All platforms.** iOS, Android, macOS, Windows, Linux. No mechanism that
   serves Apple users and strands the rest.
4. **Self-hostable, and optional.** Whatever we run, a user must be able to run
   their own, and the app must work fully when it is unreachable or gone.
5. **Nothing we host survives 30 days of disuse.** Retention is a rolling
   TTL on activity, not an absolute age cap: an actively-synced store persists
   as long as it is used. See Retention.
6. **No user accounts and no sign-in**, per the published policy.

## Decision

Ship **Sync**, backed by a store called **Athenaeum**.

**Sync is off by default on every installation.** Nothing is configured, no
endpoint is contacted and no device ID is minted until a user opts in. The app
that has not opted in makes no sync-related network call at all — so "works fully
offline, phones home to nobody" stays true by construction for everyone who never
turns it on, rather than being a promise about our conduct. Sync gets its **own
top-level Settings blade**, because it is the one feature that sends a
collection off the device and should be surfaced at the level of that decision.

*Sync* is the feature; *Athenaeum* is the service it talks to. The default
endpoint is `https://athenaeum.callerscompendium.com/`, shown **un-abstracted as
a URL in Settings** and editable, so pointing at your own server is a visible
first-class option rather than a hidden one.

### Identity

A sync ID is a **diceware passphrase** (`correct-horse-battery-staple`),
pre-filled with a randomly generated one. The user may replace it with their own,
behind a clear warning that it must not contain personal information.

**The format is fixed: four words, hyphen-separated.** Generated or chosen, the
shape is the same, which makes it recognisable, speakable and typeable.

A generated four-word ID from the EFF long wordlist carries ~2⁵² of entropy and
is not guessable at any realistic online rate. A user-chosen one is a different
matter, so two checks apply rather than one: the **format** (four words) rejects
`isaac-banner-dances` structurally, and a **strength floor of ~2⁴⁰**, scored on
the actual string, rejects four weak words that satisfy the pattern. A warning
alone would not have stopped either.

**The sync ID is a bearer credential.** Anyone holding it has full read and
write access to the collection. This is deliberate: it is what makes the design
work with no accounts and no sign-in, and it is what allows two people to share
a collection if they choose (below). It also means there is no recovery if it is
lost and no revocation if it leaks.

### What the server holds

```
<syncId>/epoch                     opaque 128-bit random value
<syncId>/blobs/<content-hash>      one copy per distinct record, shared
<syncId>/devices/<deviceId>.json   one manifest per device
```

A **manifest** maps record ids to content hashes. A device writes only its own
manifest and reads every sibling. Records are stored as **content-addressed
blobs**, so two devices holding the same dance store it once: N devices cost N
small manifests plus one copy of each distinct record, not N copies of the
collection.

The server performs no merging, no locking and no compare-and-swap. It is a
key-value store with a TTL and a generated allow-list.

### Merging

**The manifest is the merge base.** For each record a device has three hashes —
its own, the sibling's, and the baseline it last synced — which is a complete
three-way merge without vector clocks or wall-clock ordering:

| Local | Remote | Result |
| --- | --- | --- |
| changed | unchanged | upload |
| unchanged | changed | download |
| changed | changed | **direct conflict** → last-writer-wins on `updatedAt` |
| absent, not in baseline | present | download (new elsewhere) |
| present | absent, not in baseline | upload (new here) |

A remote version is accepted only when its `updatedAt` is **newer than the
local record's**, not merely different from the baseline. Comparing hashes alone
cannot distinguish "the peer edited this" from "the peer has not caught up yet",
and the latter would roll a newer local record backwards. With N peers, the
newest `updatedAt` wins.

**Absence never means deletion.** Deletions travel as `deletedAt` tombstones.
`Dances` and `Programs` carry `deletedAt` today and the Recently Deleted screen
already surfaces it; the other record kinds do not, which is one reason they are
**not independently synced** (see Record model). A device that has not synced for
a month must never conclude that records missing from a sibling's manifest were
deleted.

### Record model: three syncable kinds, the rest inline

Only **Dance**, **Program** and **Setting** are syncable records with their own
blobs. Choreographers, tags, published sources, custom-field definitions and
venues **ride inline** with the dance or program that references them, exactly as
`authorIds` and figures already do in the archive codec.

This is a deliberate narrowing, made because the alternative was much larger than
it first appeared. A first-class record needs a stable cross-device identity, a
modification timestamp and a durable tombstone. The schema provides all three on
**two of eight** kinds: `Dances` and `Programs`. The other six have neither
`updatedAt` nor `deletedAt`, and their repositories **hard-delete** — so
last-writer-wins would have no discriminator and deletions could never propagate
at all.

Worse, three of them carry `UNIQUE` natural keys — `choreographers.name`,
`tags.name`, `custom_field_defs.key`. Two devices independently creating "Bob
Smith" mint different UUIDs; syncing by UUID then violates the constraint and
fails the entire apply transaction. The import pipeline already solves this with
`_resolveAuthors`, by resolving on the **natural key** rather than the surrogate
one, and the inline model reuses that path rather than building a second.

**What this costs**, stated plainly:

- A venue edited on one device does not propagate unless a program referencing
  it also changes.
- Renaming a tag creates a second tag on the receiving device rather than
  renaming the first, because resolution is by name.
- **Venues have no unique natural key** (`venues.name` is not `UNIQUE`), so two
  halls may share a name and an inline venue has no exact key to resolve
  against. Resolution is therefore best-effort, and may duplicate venues that
  differ only in the address fields we deliberately do not sync.

Promoting these to first-class records later is a schema migration plus an
identity-resolution layer; it is deferred rather than ruled out, and the costs
above are the evidence that would justify it.

### Fresh attach

When a device has no baseline for a sync ID, the merge is **additive**: a device
holding `{B, C}` joining a store holding `{A, B}` produces `{A, B, C}`. Only
genuine record-id collisions fall through to last-writer-wins.

Fresh attach also **runs the existing dedupe machinery** — `DedupeIndex`, fuzzy
title-and-author matching, and the confident-match rule from #685. Without it, a
caller who imported "Rory O'More" separately on a laptop and a phone before
pairing gets two of everything, which is precisely the user we are building for.

**Obvious duplicates merge silently. Only genuine ambiguity is surfaced.**
Asking a user to review 11,500 dances is not a review, it is a wall, and the
common case — the same source imported on both devices — produces records that
are identical in everything that matters.

The silent-merge test reuses the rule already in the import pipeline:

1. **Exact normalized-title match** (`import_pipeline.dart:613`). A
   fuzzy-but-inexact title is never confident; that is the "two different dances
   share a title" trap.
2. **`_choreographyEquals`** — form, formation, progression, phrase structure,
   **figures including their params**, hook, calling notes, level, mixed level
   and tunes. It deliberately ignores identity, provenance, timestamps and
   device-local id collections, so, in the words of its own doc comment, "a
   bundle received on another device still matches by its intrinsic content".

One deliberate divergence from the import rule. Import treats exact title plus
**author overlap** as confident *even when the choreography differs*, which is
right when re-importing a source record. **Fresh attach must not**: same title,
same author, different figures is exactly a dance the user edited differently on
each device, and merging it silently would discard one side's work. So sync
requires content equality as well, and sends title-and-author matches whose
content diverges to review.

That leaves the review queue holding only real divergence, which is the small
set a human can actually adjudicate.

On a silent merge the surviving record keeps one identity, and the id-collection
fields the equality test ignores — tags, custom fields, links, citations — are
**unioned** rather than taken from a winner, since they are additive by nature
and neither side is more correct.

`_choreographyEquals` is currently private to `ImportPipeline`; exposing it (or
lifting it somewhere shared) is an implementation detail for the sync issue, but
sync must call *that* function rather than reimplement the comparison, or the
two definitions of "the same dance" will drift.

**Three distinct events produce a fresh attach, and all three behave
identically:**

1. A device attaches to a sync ID for the first time.
2. A device that had detached re-attaches. **Detaching forgets the sync ID
   entirely** — there is no memory of previously-attached IDs.
3. The sync ID expired server-side and someone reconnects.

### The epoch

Case (3) is a data-loss hazard, and the epoch exists to close it.

A device offline for 31 days reconnects holding a baseline that says "records X,
Y, Z at these hashes". The server has since expired that sync ID, and another
device has re-seeded it. A three-way merge would read "in my baseline, absent
from the server" as *deletions* and remove them locally.

So the server stamps an **opaque 128-bit random epoch** on a sync ID when it is
created, regenerated whenever the ID is created afresh after expiry. Devices
store it alongside their baseline. **Epoch mismatch means the store was reset:
the device discards its baseline and performs a fresh attach.**

The invariant, stated so it can be tested: *a device honours a deletion only
when it can trace it to a tombstone within the same epoch. Absence never
deletes, and a changed epoch is never mistaken for mass deletion.*

The epoch is **random, not monotonic, and compared only for equality** — see
Rationale.

### Retention

**A sync ID that no device has used for 30 days is dropped in its entirety** —
epoch, manifests and blobs. The next device to connect performs a fresh attach,
and the first to do so seeds the store.

Two paths, together covering every case without us processing a request by hand:

- **Abandoned stores reap themselves** after 30 days of disuse. No action by
  anyone.
- **Active stores are wiped by their owner**, at any time, via detach — which
  issues `DELETE /v1/store` and removes everything under the sync ID.

Stated precisely because the looser phrasing is tempting and wrong: this is a
rolling TTL on *activity*, not an absolute age cap. A store synced weekly
persists indefinitely. What holds is that nothing survives disuse and nothing
requires us to act on a deletion request — not that no byte outlives 30 days.

### Scope of what syncs

Everything classified `shareable`, **settings included** — a paired device
should feel like the same app, and custom dialects, themes, shorthand mappings
and walkthrough snippets represent real work a user would hate to redo.

- `shareable` → travels
- `deviceLocal` → **never reaches Athenaeum**
- `deviceScoped` → never travels at all (window position, per-device text scale)
- `derived` → never transmitted; rebuilt on arrival

**There is no device-to-device channel.** `deviceLocal` data moves only by the
existing manual JSON backup export and import, or by AirDrop of that file
between Apple devices. We are not building local network discovery.

The visible consequence is that **venues sync partially**: name, website, event
name, schedule, time, price, sponsor and notes arrive; the address block and both
contact blocks stay blank. This is correct and required, and it looks exactly
like data loss, so affected venue records carry a **persistent hint**.

The hint must **name the fields that stay local** rather than promise that
contact details do not travel. `venues.notes` is `shareable` — ruled so
deliberately, as the user's own words — and the registry's own note for that
field predicts the interaction verbatim: *"a user who wrote 'ask for Bob,
555-1234' into a venue note will have that text travel."* A hint saying "contact
details stay on this device" would therefore be a false assurance about the one
field most likely to break it.

### Imported dances

**Imported dances sync in full**, like any other dance. The manifest does not
care where a record came from, and there is no pristine-tracking, no re-fetch
path and no special case.

A user setting to **exclude imported dances from sync** ships in v1, for people
who want a lean sync — and it is the lever offered when a store hits its quota.

The reference-and-refetch alternative is recorded under Rationale and as a
revisit trigger, not as an open choice.

### The server

**Dart + `shelf`, a single container, SQLite or the filesystem for storage**, in
a new top-level `server/` package in this repository with a path dependency on
`compendium_core`.

Sharing the package is the point. The server reads the **same
`fieldClassifications` registry** as the client and **rejects any upload
containing a device-local field**, from one source of truth with no second list
to drift. "We never store venue addresses" stops being an intention the client
is trusted to honour and becomes something both ends enforce.

The check is an **allow-list generated from the registry**, rejecting any key not
classified `shareable` for that kind. An earlier draft used a deny-list of
forbidden keys, for forward-compatibility — and it failed **open**, because the
registry is keyed in SQL names (`venues.contact1_email`) while the codec emits
camelCase (`contact1Email`), so the two key spaces did not intersect at all and a
full address book would have been accepted. An allow-list makes a mapping error a
loud rejection instead of a silent pass. It remains a backstop; the client's
classification-filtered serialiser is the primary control.

## Rationale

### Why not end-to-end encryption

It would let us hold venue addresses and contacts as ciphertext we cannot read,
which would solve the hardest constraint outright. It is out because of
constraint 1: reintroducing confidentiality crypto reverses #536, makes the
honest answer to "does your app use encryption?" *yes*, and may owe an annual
BIS self-classification report. The cost is that private fields do not sync at
all. We accept the cost.

### Why not a change log, or a version control system underneath

A change log is the textbook answer and it is more machinery than it looks. It
requires ordering across devices with no trustworthy shared clock (Lamport or
vector clocks), compaction — the log grows without bound, so you build snapshots
*as well* — replay determinism across app versions, and versioning of the
operations themselves alongside the schema. Conflicts stop being rare because
you have built the apparatus to reason about them.

Using git as the substrate was considered seriously. It solves distributed
asynchronous merge, deduplicates by content address, deltas efficiently, and is
trivially self-hostable. It loses on two points:

- **Git is designed never to forget, and this feature's entire purpose is a hard
  privacy boundary.** If a device-local field ever reaches the store — a
  classification bug, a bad merge — snapshots self-heal, because the next upload
  simply does not contain it. In git it is permanent in the object store of
  every clone, and removing it means rewriting history everywhere. Building our
  strictest privacy guarantee on a substrate engineered to make deletion hard is
  the wrong foundation.
- **Git merges text line-by-line.** Our records are structured. A three-way merge
  of two edited JSON documents produces conflict markers, which is a corrupt
  document; avoiding that means a custom merge driver that implements per-record
  last-writer-wins — at which point git supplies transport and history, not
  conflict resolution.

Dependency weight is a secondary concern: the only pure-Dart implementation is
`git_on_dart` (v0.1.4, single maintainer, MIT); the alternative is libgit2 via
FFI, which means native builds on five platforms.

**Content-addressed blobs keep the good part** — deduplication and cheap deltas
— without the merge machinery or the permanent history.

### Why per-device manifests rather than one shared snapshot

A single shared snapshot halves storage but needs optimistic concurrency:
uploads rejected when the store changed underneath, clients re-merging and
retrying. Per-device manifests remove the possibility of clobbering entirely and
keep the server a dumb key-value store. Because blobs are content-addressed, the
storage saving of a shared snapshot largely disappears anyway.

### Why a diceware ID rather than a system-minted opaque one

A purely system-minted ID (`k7m2-9xqp-4wnf`) removes the "is this user data?"
question by construction. A purely user-supplied one is memorable but guessable
and can contain personal data.

Diceware is not a compromise between them — it is both properties at once:
generated, it is high-entropy *and* memorable *and* speakable over the phone,
which matters for a user pairing a device with no camera. Allowing an override
respects users who want a memorable ID, and the entropy floor prevents the
override from being a foot-gun.

### Why the epoch is random rather than monotonic

Two arguments, either sufficient.

**Self-hosting makes counters meaningless.** Two independent servers can both
hold a sync ID named `correct-horse-battery-staple`. A device holding "epoch 3
from server A" that meets "epoch 3 from server B" concludes nothing changed and
three-way merges against an unrelated store — the data-loss bug in a different
guise. Counters are comparable only within one authority; this design has no
single authority. 128-bit random values collide negligibly across any number of
servers, and re-pointing the endpoint correctly becomes a fresh attach.

**A counter contradicts the retention rule.** To increment, the server must
remember the previous value for a sync ID *after* that ID has expired —
retaining `syncId → lastEpoch` indefinitely. That is persistent data about a
user beyond 30 days, specifically about IDs we promised to forget.

Timestamp-based monotonicity avoids the persistence problem but leaks creation
time, depends on the server clock never stepping backwards, and at second
granularity two re-creations within one second produce identical epochs —
collision on exactly the axis where collision causes data loss.

What ordering would buy is rollback detection. With union semantics and
locally-held tombstones a rollback is largely self-healing, so it buys little. If
it is ever wanted, add an advisory creation timestamp as a separate field rather
than overloading the epoch.

### Why full sync of imported dances

The case for carrying public-source dances as references was bandwidth. Measured
rather than assumed: an archive-format dance is ~1.5 KB, so 11,500 dances is
~17 MB uncompressed and 3–4 MB gzipped — and under delta sync that is a
**one-time** cost, with subsequent syncs moving only what changed. At 500 users
that is ~8.5 GB, which is pennies a month.

Against that, reference-passing costs per-dance "is this still pristine?"
tracking, a failure mode where a dance silently does not arrive because the
source is slow or gone, and — decisively — **it breaks the app's offline
promise**. A caller in a hall with no signal opening a dance that is not there
is a worse outcome than 17 MB.

Licensing was considered and is not a driver: choreography is not copyrightable,
and The Caller's Box's permission tiers are a social convention rather than a
legal constraint. Separately, the app already imports non-`full`-tier dances as
metadata-only stubs because the source serves no figures for them.

The reference-passing variant is recorded here and as a revisit trigger, not as
an open choice: it returns only if hosting cost stops being trivial.

### Why Dart for the server

Go produces the nicest artefact to self-host — a single static binary — and Rust
is a defensible choice. Both lose the property that decided it: the allow-list of
shareable fields would have to be maintained by hand in a second language,
which is exactly the drift the classification registry exists to eliminate. A
Dart server imports the registry.

Managed object storage plus a small function would mean nothing to patch, but
makes self-hosting materially harder, which constraint 4 forbids.

## Consequences

### Easier

- A caller edits on a laptop and finds it on their phone, with no files.
- Adding a device is nearly free: one small manifest, and blobs are shared.
- The privacy boundary is enforced at both ends from one registry.
- Self-hosting is a first-class, visible option rather than a hidden flag.
- The server is small enough to reason about: no merge logic, no locking.

### Harder, and knowingly accepted

- **Sharing is not collaboration.** Two people on one sync ID works — it falls
  out of the layout, and blocking it would be more complex than allowing it —
  but merging is last-writer-wins with no attribution and no prompt. If two
  people edit the same dance, one edit disappears silently. This must be said at
  pairing time, not discovered.
- **A bearer credential has no recovery and no revocation.** Lose the ID and the
  store is unreachable; leak it and the only remedy is to move to a new ID on
  every device.
- **Sync is not backup.** With a 30-day-of-disuse TTL the store is a relay with
  a grace period, not an archive. The file backup remains the recovery path and the UI
  must say so.
- **30 days of disuse is a liveness requirement on the user.** A caller who does not open
  the app for five weeks returns to a fresh attach and a dedupe review —
  correct and safe, but surprising. The UI should warn as expiry approaches.
- **Venues sync partially**, and correct behaviour looks like data loss.
  Mitigated by a persistent hint, not eliminated.
- **We now operate infrastructure**, with the uptime, abuse and cost that
  implies — mitigated by the app working fully without it.
- **Settings sync requires a schema migration, and it should ship first.**
  `settings` is `(key, value_json)` with no timestamp, so the `updatedAt`
  conflict rule cannot reach it. Schema v22 adds `updated_at`, stamping existing
  rows at migration time.

  **Sequencing is deliberate: v22 lands before any other sync work**, on its own.
  Under the inline record model it is the programme's only schema change — a
  claim that only holds *because* of that model: promoting the other five kinds
  to first-class records would require roughly ten further columns across five
  tables plus hard-to-soft delete conversion. Isolating v22 leaves the rest as
  feature work with no migration risk; it is defensible on its own terms, so
  nothing is wasted if the programme stalls; and — the real reason — it defuses
  the one-time ordering wart. Because each device stamps at *its own* migration
  time, the device that upgrades last would otherwise win every settings conflict
  on first sync. That only holds while the stamps still encode migration order.
  Shipping v22 early means users spend the intervening releases changing settings
  for real, and every real change overwrites a migration stamp with a meaningful
  one. The gap between releases is what fixes it, so earlier is strictly
  better.
- **Applying an inbound record must not erase what it omits.** A blob correctly
  omits `deviceLocal` fields — and the repositories' `upsert` methods write
  *every* column, which is right for a local restore and destructive here. A
  remote edit to a venue's website would otherwise null its address and both
  contact blocks on the device that owns them. Apply is therefore
  read-modify-write inside the apply transaction, overlaying only the fields the
  blob carries. The serialiser hazard and this deserialiser hazard are
  symmetric, and the second is the more dangerous: it destroys the user's own
  data rather than exposing it.
- **Settings whose value is a whole collection collide destructively.**
  `custom_dialects`, `custom_themes`, `shorthand_mappings` and
  `walkthrough_snippets` each hold an entire set behind one key, so a
  changed/changed conflict discards one device's complete set with no review
  queue. Accepted, and it belongs beside "sharing is not collaboration": the
  first pairing of two long-established devices is the case that loses work.
- **Any holder of the sync ID can impersonate a device or wipe the store.**
  Manifest `PUT` accepts a caller-chosen device id, and the same bearer
  authorises `DELETE /v1/store`. This is inherent to the bearer model rather than
  an oversight, and it is stated here as explicitly as the read-access case
  because the write-access case is the one that destroys data.
- **A deletion can still resurrect across a long absence.** Tombstone retention
  is floored at the sync window while Sync is enabled, which covers the ordinary
  case. A device offline for longer than that returns to a fresh attach, where
  union is additive and no tombstone survives anywhere to contradict it. There is
  no fix inside this design that does not amount to unbounded tombstone
  retention.
- **The operator can read a store if they choose to.** The design exposes only
  sizes, device counts and activity timestamps, but content is plaintext, so
  access is a matter of policy rather than capability. A break-glass path for
  abuse investigation exists, is logged, and is disclosed in the privacy policy.
  The log lives in a **separate database** — so reaping a store cannot destroy
  the record of access to it — and holds two fields: the derived sync-ID key and
  a timestamp. Never the plaintext ID: the store deliberately avoids holding the
  credential in the clear, and a plaintext log would undo that while outliving
  the stores it describes.
- **Identifiers are derived with HMAC, not a bare hash.** A bare SHA-256 of a
  sync ID is weak *because the ID is deliberately low-entropy*: at the ~2⁴⁰ floor
  for user-chosen IDs, exhausting the space is minutes of commodity GPU time, so
  a stolen database would yield working credentials. Keys are therefore
  `HMAC-SHA256(pepper, syncID)` with the pepper held in server configuration and
  never in the database. This is server-side only — the client computes no MAC
  and never holds the pepper. **Rotation is a store migration, not a config
  change, and is impossible for inactive stores as specified** (only the derived
  key is retained, so there is nothing to re-derive from until a client returns)
  — tracked in **#793**, with versioned peppers and lazy re-keying proposed.
- **Even a derived identifier is linkable, so the log expires too.** The access
  log keeps its identifier for 30 days and then **degrades to a timestamp-only
  row**, preserving "an access occurred on this date" as a non-linkable aggregate
  while the linkable part expires on the same schedule as everything else.
- **Export compliance is unchanged, and was checked rather than assumed.** Sync
  adds no new cryptographic *category*: TLS is OS-provided, SHA-256 content
  addressing is hashing, and the binary already ships both plus Ed25519 for
  update-signature verification. `ITSAppUsesNonExemptEncryption = false` remains
  accurate on the analysis already recorded in
  [store-submission/README.md](../dev/store-submission/README.md) §2, which names
  the trigger that would change it — reintroducing *confidentiality* crypto. The
  server-side pepper does not enter into it: it is not in the distributed binary,
  and export declarations attach to that artifact. The tripwire is close to us,
  which is why it is written down: encrypting payloads before upload — the E2EE
  option rejected under constraint 1 — would flip the answer to yes.
- **Silent merge is irreversible from the user's point of view.** Two records
  that pass the title-plus-choreography test become one without being shown. The
  test is strict — identical figures *and* params — so a false positive means two
  genuinely identical dances, but the user is not told it happened. Reporting a
  count afterwards ("merged 412 duplicates") is the mitigation, not a prompt.

### Blocking prerequisite

**The published privacy policy contradicts this design.**
`docs/dev/store-submission/privacy-policy.md` §2 and its mirror
`site/privacy/index.html` both state that "there is no cloud sync" and that "we
have no servers that receive or hold your content", and both app store listings
link to it. Both files must be amended together, with the effective date bumped,
**before Sync ships**. This is a prerequisite of shipping, not of this ADR.

## Revisit triggers

- **Users ask for venue addresses on their second device often enough that the
  answer "re-enter them" stops being acceptable.** The options are a device-to-
  device channel (rejected here) or encryption (rejected by constraint 1);
  either would reopen this ADR.
- **Two-person sharing becomes common in practice.** Last-writer-wins without
  attribution is defensible for one person's devices and indefensible for a
  couple sharing a library; observing real use would justify per-field merge or
  conflict surfacing.
- **Storage or bandwidth on the hosted instance stops being trivial**, at which
  point the reference-passing variant for imported dances becomes worth its
  complexity. This is the decided-against alternative most likely to return.
- **The 30-day disuse window proves too short** — evidenced by users repeatedly hitting
  fresh attach after ordinary gaps in use.
- **Export-compliance rules change**, or a platform provides encryption we can
  use without a declaration, making E2EE cheap enough to reconsider.
- **A pure-Dart or well-maintained cross-platform sync primitive appears** that
  would let us delete our own merge implementation.
- **The inline record model proves limiting** — evidenced by users renaming tags
  and finding duplicates, editing venues that never propagate, or duplicate
  venues accumulating because the name is not a unique key. Promoting those kinds
  to first-class records is a schema migration plus an identity-resolution layer,
  and these symptoms are the evidence that would justify paying for it.
- **Silent merge is observed collapsing dances users considered distinct** — for
  instance two arrangements that differ only in fields `_choreographyEquals`
  ignores. That would mean the equality test is too loose for sync even though it
  is right for import, and the two should stop sharing one definition.
