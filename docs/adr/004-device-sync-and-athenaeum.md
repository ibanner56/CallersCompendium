# ADR-004: Device Sync, and the Athenaeum sync store

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

**That registry is the precondition for this design.** Device Sync does not get its own
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

Ship **Device Sync**, backed by a store called **Athenaeum**.

**Device Sync is off by default on every installation.** Nothing is configured, no
endpoint is contacted and no device ID is minted until a user opts in. The app
that has not opted in makes no sync-related network call at all — so "works fully
offline, phones home to nobody" stays true by construction for everyone who never
turns it on, rather than being a promise about our conduct. Device Sync gets its **own
top-level Settings blade**, because it is the one feature that sends a
collection off the device and should be surfaced at the level of that decision.

*Device Sync* is the feature; *Athenaeum* is the service it talks to. The default
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
`Dances` and `Programs` carry `deletedAt` today; schema v23 adds it to the other
six kinds and converts their repositories from hard to soft delete, because a
kind that cannot express deletion cannot propagate it — the record would simply
reappear from any peer that still held it. A device that has not synced for a
month must never conclude that records missing from a sibling's manifest were
deleted.

### Record model: eight first-class kinds

Every persisted entity is a **first-class synced record** with its own blob:
`dance`, `program`, `choreographer`, `tag`, `publishedSource`,
`customFieldDef`, `venue`, `setting`. Join rows ride inline with their parent —
a dance carries its `authorIds`, `tagIds`, citations and custom-field values; a
program carries its slots — exactly as the archive codec already models them.

This mirrors the codec's existing shape rather than fighting it: `archiveToJson`
already emits choreographers, tags, published sources and venues as **top-level
arrays**, siblings of `dances`. Per-record blobs are that shape, one entity at a
time.

An earlier revision of this ADR narrowed sync to three kinds and had the other
five ride inline as content. That was withdrawn, and the reasoning is recorded
because the failure is instructive:

- The analogy it rested on was **backwards**. `authorIds` and `tagIds` are flat
  arrays of **UUID references**, not inline content — precisely the
  surrogate-identity mechanism that cannot survive a cross-device transfer. Only
  `figures` is genuinely inline. Inline would therefore have required
  sub-archive assembly and a reference-rewriting layer, neither of which existed.
- It **cancelled this ADR's own conflict rule**. Editing a choreographer calls
  `ChoreographerRepository.upsert` and touches nothing else — by design, since
  contact data sits outside the dance's draft/undo stack. Inlined, that rename
  changes the blob's hash while leaving the referencing dance's `updatedAt`
  untouched, so the `remote.updatedAt > local.updatedAt` gate would discard it
  permanently.
- It **silently dropped standalone entities**. Venues are created and edited
  through their own manager screen with no program involved; inline, such a venue
  never syncs at all — not even its creation.

First-class costs a larger migration and buys all of that back.

### Identity: sync the UUID, reconcile the collision once

Records sync under their existing UUID. Identity is therefore stable across
renames — the name is a field, not the key.

Three kinds carry `UNIQUE` natural keys (`choreographers.name`, `tags.name`,
`custom_field_defs.key`), so two devices that independently created "Bob Smith"
hold one person under two UUIDs. Inserting the second violates the constraint and
fails the whole apply transaction, so applying a record of those kinds
reconciles:

1. **UUID known locally** → update, last-writer-wins on `updatedAt` — unless the
   update would move the natural key onto a name another local row already holds.
   That collides exactly as an insert does, and a plain LWW update would violate
   `UNIQUE`, fail the transaction, and fail every retry identically, deadlocking
   that device pair until a human renamed one side. It is **not** merged
   silently: two pre-existing local rows are involved, they may be two different
   people, and it goes to the review queue.
2. **UUID unknown, natural key matches an existing local row** → the same entity,
   created independently on both devices. Reconcile silently to one UUID, remap
   every reference, drop the loser. One-time; the two devices agree from then on.
3. **Neither** → insert.

**The survivor is the lexicographically smaller UUID** — one canonical rule, used
by every "which record survives" decision in the design, including the
fresh-attach dance merge. This generalises to a rule the design now states
normatively: **any rule deciding which of two records survives must be a pure
symmetric function of the two, never a function of "local" versus "incoming".**
A device-relative rule does not converge — each device keeps its own, advertises
it to a peer that has already discarded it, and reconciles the same pair forever
without either side able to detect the standoff. That mistake has been made three
times in this design's history, most recently in the same revision that fixed the
previous two, so it is written down rather than left to judgement. It also fixes
a test shape: every convergence test runs from both sides, because a one-sided
test passes against a non-convergent rule.

Identity and content are decided **separately**: identity by the tie-break,
content by last-writer-wins on `updatedAt`. Deciding identity by `updatedAt`
would be unstable, since the survivor could change on a later pass; deciding
content by the tie-break would let a stale duplicate clobber a just-edited
record, which is the exact defect the merge rule exists to prevent.

Because a dance's authorship and tags are **derived from join rows** rather than
stored on the dance, remapping a reference changes what the dance publishes
without moving its `updated_at` — so reconciliation must bump the referencing
record's timestamp and re-upload it. This is a specific case of an invariant the
design now states normatively: *any operation that changes a record's serialised
content must advance its `updatedAt`.* Two separate mechanisms have broken it, so
it is written down rather than left to be rediscovered.

Reconciliation is **silent**. No prompt, no review queue: at beta scale the
collision is common (any two devices that both typed "Cary Ravitz") and a prompt
per entity would be noise. Silence is defensible here because **the schema
already makes the same assumption**: `choreographers.name` is `UNIQUE`, so a
single device cannot hold two same-named choreographers today. Sync applies that
existing approximation across devices rather than introducing a new one. Two
genuinely different people sharing a name do merge, and that is named as a known
failure mode rather than fixed.

**Custom-field definitions are the exception.** Merging two defs that share a key
but differ in `type` repoints values at a decoder that will throw when the dance
is next loaded — a crash on read, far from the sync that caused it. Those
reconcile only when the type matches; otherwise both survive, and the tie-break —
not "incoming" — decides which keeps the bare key, with the other renamed using a
suffix derived from the losing UUID so that both devices compute the same result
and a mint can never collide with an existing key.

`venues` and `published_sources` have **no** `UNIQUE` natural key —
`venues.name` and `published_sources.title` are plain `text()`, unlike the three
above — so their UUIDs cannot collide destructively; two records simply coexist.
They are therefore inserted without reconciliation, and a user who created the
same hall, or cited the same book, on two devices will see it twice. Choosing a
resolution key for them (`title`? `title` + `author` + `year`?) is deferred with
the fuzzy dedupe that would use it.

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

1. **Exact normalized-title match** (the `normalizeTitle` gate in `autoResolveAmbiguous`). A
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

**That queue needs storage it does not have.** The design said these items go "to
the review queue" from its first draft, which read as reuse of the import
pipeline's plan → review → commit flow. The review *screen* does exist — the
adapter-agnostic import review-queue UI shipped — but the batch behind it is an
explicitly non-persisted, session-scoped `ImportSession`, and there is no
`review_queue` table. It is a surface for a user who has just started an import,
and Device Sync runs unattended, with no import in progress to attach a decision
to.

Device Sync therefore adds a `review_queue` table — `deviceScoped`, beyond v23,
alongside `id_aliases` — carrying an immutable candidate blob as well as the pair
of ids, because a rejected rename cannot be written locally under the `UNIQUE`
constraint and so exists nowhere else to show the user. Queuing is idempotent
under the canonical tie-break ordering, so an unattended device does not
accumulate a duplicate item per pass.

It also needs a **new review surface**. An earlier draft said the existing screen
would serve, so the work was storage and a way in; that was wrong.
`import_review_screen.dart` reviews dances — it is built on `ImportRecordPlan`
and `DanceEditorScreen` — and cannot review a choreographer, tag or
custom-field collision. What those need is far smaller than the dance screen,
since their collisions are name-level rather than content-level: a generic
keep-both-or-merge list with no per-kind editors. Small, but new.

The queue is a real addition to the programme's scope, and it is not work Device
Sync creates: the dance dedupe path has needed it since the first draft and would
have hit the gap on the first fresh attach.

On a silent merge the survivor is chosen by the same canonical tie-break — the
lexicographically smaller UUID — so both devices agree without coordinating, and
the id-collection fields the equality test ignores — tags, custom fields, links,
citations — are **unioned** rather than taken from a winner, since they are
additive by nature and neither side is more correct. Local `program_slots`
pointing at the losing duplicate are rewired to the survivor; the column is
`onDelete: setNull`, so leaving them would silently strip a caller's program of a
dance that still exists.

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
- **Device Sync is not backup.** With a 30-day-of-disuse TTL the store is a relay with
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
  conflict rule cannot reach it. Schema v23 adds `updated_at`, stamping existing
  rows at migration time.

  **Sequencing is deliberate: v23 lands before any other sync work**, on its own.
  Its real scope, stated honestly after an earlier draft understated it: `settings`
  gains `updated_at` **and `deleted_at`**, and the five kinds that lack them —
  choreographers, tags, published sources, custom-field defs, venues — gain both,
  with their repositories converted from hard delete to soft. All eight syncable
  kinds additionally gain `existence_at` for the provenance gate, which brings
  `dances` and `programs` into the migration for that one column. That is eight
  tables and twenty columns, plus six `_db.delete(` call sites, not one column. It
  remains the programme's only schema change, and isolating it still leaves the
  rest as feature work with no migration risk; it is defensible on its own terms, so
  nothing is wasted if the programme stalls; and — the real reason — it defuses
  the one-time ordering wart. Because each device stamps at *its own* migration
  time, the device that upgrades last would otherwise win every settings conflict
  on first sync. That only holds while the stamps still encode migration order.
  Shipping v23 early means users spend the intervening releases changing settings
  for real, and every real change overwrites a migration stamp with a meaningful
  one. The gap between releases is what fixes it, so earlier is strictly
  better.

  **It is also not a mechanical conversion**, which an earlier draft implied by
  naming `DanceRepository` as the pattern to copy. Dances are the *parent* in
  these cascades and the five converting kinds are on the other side of them, so
  each needs its own decision. Two consequences are load-bearing: soft-deleting a
  tag no longer fires the FK cascade that cleared `dance_tags`, so every read
  joining through to a soft-deletable parent must filter on `deleted_at` or a
  deleted tag stays silently attached to every dance; and the existing referential
  guards, which refuse to delete a still-credited choreographer, are **kept**
  rather than relaxed — a tombstone applies at once where the entity is
  unreferenced, and where it is still cited the receiving device holds the
  deletion **pending**, keeping the row live locally without republishing it,
  and applies it when the last citation goes.

  The obvious alternative — let the still-citing device republish the entity as
  live — reverses the user's deletion permanently: republishing advances
  `updatedAt`, so it out-ranks the tombstone, the deleting device downloads its
  own deletion back, and nothing ever re-tombstones because the user already
  deleted it once. Holding the deletion pending keeps the guarantee that no dance
  credits a tombstone without buying it by resurrecting deleted data.

  A held deletion is cancelled **only by a deliberate user edit**, ordered by an
  `existenceAt` timestamp that travels in the blob envelope: when two copies
  disagree about whether a record exists, the greater `existenceAt` decides, and
  its `deletedAt` says which state that is. Several sync mechanisms advance
  `updatedAt` without a user touching anything — reference rewriting,
  merge-by-recency, the dance merge's scalar recency — so a plain recency rule
  would let a third device silently reverse another's deletion.

  Three properties of that field are load-bearing. It **travels**, because
  extending the rule to *applied* tombstones made it cross-device: a receiver
  must judge a peer's write, and a fresh-attaching device has no local history to
  judge it from. It is a **timestamp rather than a flag**, because the content
  invariant guarantees later sync writes to the same record, each of which would
  overwrite a boolean and erase the revival it recorded. And it **decides alone**
  rather than qualifying the recency comparison: a first attempt added it as a
  second condition ANDed with `updatedAt` recency, where the recency term could
  block the outcome before the hardened term was ever reached, so a deliberate
  un-delete from a slow-clocked device was still silently reverted. Hardening one
  term of a conjunction hardens nothing.

  It is set only by a live↔deleted transition and by no sync-apply path, which
  makes deletions sticky: an edit made on a device that never learned of the
  deletion is swept up when it arrives — recoverable from Recently Deleted, but
  not announced. Chosen because a deletion silently reversed on every device is
  both worse and harder to notice than an edit that follows its record into the
  bin. It costs an `existence_at` column on all eight syncable kinds, which is
  why v23 is eight tables rather than six.

  It is stamped **causally rather than from a bare clock** — every transition
  lands strictly after the value already on the record,
  `max(now, currentExistenceAt + 1ms)`, in **both** directions. A revival is
  necessarily *after* the deletion it supersedes, since the device had to receive
  the tombstone to revive from it, but on independent clocks a slow device would
  stamp it earlier and silently revert a deliberate un-delete; the reverse skew
  would stop a device deleting a previously revived record at all.

  Because it decides a question several code paths reach independently, it is
  restated on each of them rather than in one place: the steady-state merge,
  fresh attach, collision reconciliation, dance dedupe, record creation, the
  migration backfill, and inbound validation. The design carries that list as a
  table, since the alternative — found by experience — is discovering the paths
  one at a time. The backfill in particular must not inherit `updated_at`, which
  would reintroduce the content-versus-existence coupling this column exists to
  break, through the migration itself.

  **One migration consequence is accepted rather than fixed.** Live rows are
  backfilled with a per-device constant sampled when the migration runs, so a
  device that deleted a record before migrating carries a tombstone dated earlier
  than a peer's untouched live row — and on first sync the live copy wins and the
  record returns. The maintainer accepted this on the grounds that beta installs
  all reach the sync-capable contract before the first stable release. Recorded
  here because it is not confined to the migration window: the constant remains a
  record's operative existence value until that record next changes state. A
  hardcoded pre-release constant instead of a sampled clock would remove it.

  **A badly wrong clock is repaired rather than tolerated.** Because the field is
  monotone, a device that stamps a record from a broken clock poisons it
  permanently — correcting the clock does not help, since the `max` preserves the
  bad value. Such a record is quarantined and **restamped on the next sync pass
  above the greatest value its peers actually hold**, preserving the local
  live-or-deleted state and needing no user gesture.

  Repairing against observed peer values rather than the local clock is the
  load-bearing part. An earlier version reset from the clock and justified it by
  the poisoned value having been "rejected everywhere" — which does not follow,
  because rejection is a per-receiver test against a per-receiver clock. A value
  merely *ahead* of local time, but under the threshold, is accepted by every
  peer, so a clock-based reset could land below one still in circulation and
  silently revert a deliberate deletion: the failure this field exists to
  prevent, reintroduced by its own repair path.

  **Repair therefore reads no clock at all**, and rebuilds **only the fields the
  local clock says are impossible** — a record is quarantined, and an inbound
  blob refused, when `existenceAt` *or* `updatedAt` exceeds `localNow + 24h`.
  Refusing both fields at the door is load-bearing rather than tidy: repair
  sources values only from peers, so a poison allowed into circulation becomes
  the only value there is for that record and turns into stable consensus with
  nothing honest left to adopt. With both refused, a poisoned value can only ever
  be **local**, which is the property that makes the rebuild decidable at all.

  Each field is then rebuilt from peers that are sound **in that same field** —
  an ordinary edit poisons `updatedAt` while leaving `existenceAt` untouched, so
  a single filter would select a peer that is sound in one and poisoned in the
  other — and each is keyed on the signal that answers its own question:
  `existenceAt` on live-or-deleted agreement, because only a local transition can
  poison it; `updatedAt` on whether local content still matches **this device's
  own baseline**, because only a local write can poison it, and the baseline is
  what tells a device whether it wrote.

  Two details of that comparison are load-bearing rather than incidental. It is
  scoped to the record's **`body`**, not the whole blob: the wire hash covers the
  timestamps, and poisoning *is* a timestamp-only change, so a whole-blob
  comparison reports "differs" for every quarantined record and the classifier
  collapses to "I edited" — the same comparator that, pointed at a peer a round
  earlier, could never report "equal". And a baseline entry advances only once a
  peer is observed to carry that hash, because "what I last uploaded" and "what
  we last agreed" came apart the moment inbound rejection widened: with no
  failure signal back to a sender, a device could baseline a blob every peer
  refused, then later compare a poisoned record against a baseline written by the
  very write being repaired — matching, adopting an older timestamp, and
  stranding newer content where the strict-`>` gate moves nothing either way.

  A record with **no** baseline entry is resolved by comparing local content to
  the peers' — sound only where this device has *never agreed*, since staleness
  needs an agreement for the peers to have moved past. That precondition is
  stated as itself rather than as "there is no entry", because five paths clear
  an entry and only one carries it: a record agreed under the previous scheme has
  a wire hash and no body hash, and takes the wire-hash path or stays
  quarantined; a wholesale-wiped baseline routes through fresh attach, which
  repersists it before quarantine and repair run at all. Existing baselines
  cannot be migrated — the body was never retained, and every backfill that
  invents a value re-opens a defect this design has closed — so the column starts
  null and fills on the first pass that observes agreement.

  A quarantined record is also never uploaded: a device does not publish a value
  it has judged impossible. Its **manifest entry falls back to the last agreed
  hash**, though — withholding a blob and withholding a manifest entry are
  separate acts, and advertising a hash no peer can fetch or omitting the record
  outright would each break something the pending-tombstone rule already settled.
  Its value is excluded from arbitration and the local row retained, never
  replaced, since a poisoned timestamp can accompany genuinely newer content —
  in a fresh attach's union and in the steady-state merge table alike, since
  otherwise a poisoned `local.updatedAt` no honest peer can exceed would freeze
  the record while appearing to participate. A record citing a quarantined
  entity is withheld with it, or a peer's batch fails at COMMIT on the cascading
  foreign key — computed as a fixpoint over the publish set, since the citation
  graph is multi-hop, and excluding `Programs.venueId`, which is not a database
  foreign key and is instead resolved-or-nulled on apply, as the archive
  restorer already does. That withholding does not resolve itself: an entity created while
  a clock was broken has no peer copy to repair against, so it and everything
  citing it stay unsynced until the user writes to it again. The report says how
  many records each one holds back, because otherwise the only symptom is a
  collection that quietly stops syncing. And an advertised fallback never counts
  as agreement: it is this
  device's own hash coming back to it, and treating it otherwise would populate
  a baseline from the poisoned content it exists to repair.

  **Choosing those classifiers was the substance of the decision.** Neither field
  carries a signal separating a value poisoned by a broken clock from a genuine
  one, so no comparison of magnitude can tell them apart; plausibility against
  the local window can, and that is what selects the fields to rebuild. Two
  earlier drafts then reached for the nearest observable to decide *how* to
  rebuild: live-or-deleted agreement, which is orthogonal to poisoned-versus-
  genuine, and content differing from the peer's, which is orthogonal to
  edited-versus-stale — and worse, anti-correlated with it, since a poisoned
  discriminator wins every content merge and so manufactures the staleness that
  inverts the signal. The baseline was already in the design, already
  distinguishing "I changed this" from "I haven't caught up", and is the signal
  the question actually turns on.

  A successor draft kept a `localNow` fallback for the case with no acceptable
  peer copy, and that single branch reinstated the whole failure for a clock
  wrong in the *past* direction: quarantine and acceptance are one-sided upper
  bounds, so a device stuck in 2000 finds every healthy record and every peer
  value out of range, rewrites its collection downward, and loses every
  subsequent deletion to a peer's live copy.

  When every value observed in a pass lies outside the local window, the device
  is the outlier rather than the fleet, and it says so: **clock-suspect** is a
  derived, per-pass **diagnostic**, needing no schema and clearing itself as soon
  as an acceptable value is seen. It gates nothing — once the `localNow` fallback
  was removed, repair already could not proceed without an in-window peer value —
  and it restricts nothing: the device goes on creating and editing normally,
  because refusing user writes over a fault the user cannot see would trade a
  contained, loud problem for an unusable app. Its purpose is to name the one
  pattern the user can actually fix. And **zero** observed peers is not
  clock-suspect: with no fleet there is nothing to be an outlier against, so a
  solo install simply has no repair path and its records stay quarantined until a
  peer attaches.

  A clock that is never corrected is the worse case and does not self-heal: such
  a device stays clock-suspect indefinitely, quarantines more records as its
  peers legitimately transition things, and — if it is wrong in the *behind*
  direction — rejects the fleet's honest values on first attach before it has any
  local state to quarantine at all. A persistently *fast* clock is the third
  direction and needed its own detector: it never quarantines its own records and
  never sees a peer above its inflated ceiling, so widening inbound rejection
  made its blobs refused everywhere while the device itself was told nothing. A
  device therefore also reports when its own values sit far above every peer's.

  All three stay contained to the affected device, none can silently reverse
  another device's work, and each is now surfaced on the device whose clock is
  wrong rather than on the peers that cannot fix it. The only real remedy is the
  user's clock; the design surfaces it rather than guessing around it.

  It is a **separate column** rather than a reuse of `deletedAt` because that
  field is a retention timestamp with real consumers — the purge sweep and the
  Recently Deleted countdown both read it — so stamping it forward could pin a
  record in the future, never purge it, and defeat the retention this design's
  privacy posture depends on. `updatedAt` and `deletedAt` keep ordinary clock
  semantics; only existence ordering is causal, because a wrong winner there
  reverses a deletion everywhere rather than costing one recoverable edit.

  **Restoring a backup drops the sync baseline**, forcing a fresh attach. Restore
  writes straight to the repositories, outside the merge engine and with no
  knowledge of tombstones or the baseline, so after one the baseline's claim
  about what this device agreed with its peers is simply false. Left in place it
  produced a device that republished a restored-but-deleted record forever,
  diverged from every peer with no error and no way back.

  The pending marker, the id aliases and the review queue are each persisted,
  classified `deviceScoped`, scoped to the store, and land beyond v23 — except
  the retained tombstone bytes, which are `shareable`, since they are record
  content that is re-uploaded rather than device bookkeeping.
  `pending_deletions` deliberately survives an epoch
  reset — a pending-held row is still *live* locally, so clearing it and then
  re-uploading every local record would republish the entity and discard the
  user's deletion — and is uploaded as a tombstone on fresh attach, exactly as it
  is advertised as one in steady state.

  A device holding a deletion pending advertises the entity as a **tombstone**
  rather than omitting it. Omitting it stops the resurrection but leaves the
  manifest referentially incomplete — the device still advertises the dances that
  cite the entity, and a fresh-attaching device that cannot resolve the author
  fails its whole batch on the cascading foreign key. Publishing the tombstone
  makes the same claim while keeping the target addressable.
- **Id aliases are pruned on content, not on a clock — a reversal.** An earlier
  version of this design bounded alias retention by the oldest attached device's
  last-sync watermark, said to be returned by `GET /v1/store`. It is not: that
  endpoint returns epoch, device list and quota usage, the server's only
  timestamps are an aggregate `last_seen` refreshed by any device and a
  per-manifest `written_at` recording when a device last *published* rather than
  last caught up, and the quantity actually wanted is a function of the peer's
  baseline, which is `deviceScoped` and never leaves it. No endpoint could return
  it.

  An alias is now retired once **no current peer manifest lists the losing id**,
  which reads only the manifests every pass already fetches. Recorded here as a
  reversal rather than silently corrected, because the superseded rule was stated
  with equal confidence and a reader deserves to see which way the decision went.
  Its one residue is operational and disclosed: a device that stops syncing
  without being removed pins its aliases indefinitely, so pruning depends in
  practice on dead devices being removed via `DELETE /v1/manifests/{deviceId}`.
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
- **A deletion can sit unapplied on another device indefinitely.** Because the
  referential guards are kept, a device that still cites a deleted choreographer,
  tag or source holds the tombstone pending rather than applying it — and the
  user is not told why. Two devices then legitimately disagree about whether the
  entity exists, until the last citation is removed.

  This is the deliberate trade against the alternative, which is worse and less
  visible: letting the still-citing device republish the entity would reverse the
  deletion everywhere and permanently, because a republish out-ranks the tombstone
  and nothing re-tombstones afterwards. A deletion that is *late* is recoverable;
  a deletion that is silently *undone* is not. Revisit if beta users report
  deletions that appear not to take.
- **Collision reconciliation merges silently, and one class of field is
  destroyed.** When two devices independently created the same choreographer, tag
  or custom-field definition, applying the peer's copy keeps one UUID and drops
  the other row. Chosen deliberately for beta: the collision is common and a
  prompt per entity would be noise.

  The `shareable` fields on the losing row — `name`, `website`, `notes` — are
  clobbered but not lost, because they travel: a copy survives on the peer that
  published them. The **irrecoverable** fields are the `deviceLocal` ones —
  `choreographers.email`, `choreographers.location` and `deceased`. Those are
  never serialised, so no copy exists on any peer or on the server, and dropping
  the row holding them destroys them outright. That is third-party contact data,
  the precise category this whole feature exists to protect, so reconciliation
  **coalesces the loser's `deviceLocal` fields onto the survivor** before
  dropping it rather than accepting the loss.

  This was stated backwards in an earlier draft, which named `website` and
  `notes` as the vanishing data — the two fields that are in fact recoverable —
  and omitted the three that are not. The correction matters beyond accuracy: a
  symmetric tie-break means the incoming UUID wins about half the time, and those
  are exactly the passes in which the row holding the local contact data is the
  one dropped.

  Coalescing is confined to **independently created duplicates**, and the reason
  is structural rather than a judgement about likelihood. In that case only one
  row can hold `deviceLocal` values at all — the incoming blob never carries
  them — so coalescing preserves data and cannot blend it. A *rename* that
  collides is the opposite: two pre-existing local rows, each possibly holding
  contact details for a different real person, so merging them would attach one
  non-consenting third party's email and location to a row representing someone
  else. That path is therefore not silent and not coalesced; it goes to the
  review queue. A rename that happens to collide is rare enough that this asks
  the user close to never.
- **Venues and published sources can duplicate.** Neither has a `UNIQUE` natural
  key, so there is nothing to reconcile against: the same hall created on two
  devices arrives twice. Deduplicating them would need the fuzzy matching the
  import pipeline uses, which is deferred.
- **A deletion can still resurrect across a long absence.** Tombstone retention
  is floored at the sync window while Device Sync is enabled, which covers the ordinary
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
  key is retained, so there is nothing to re-derive from until a client returns).
  Versioned peppers with lazy re-keying are the proposed resolution; see
  [sync.md](../design/sync.md) → Recorded limitations.
- **Even a derived identifier is linkable, so the log expires too.** The access
  log keeps its identifier for 30 days and then **degrades to a timestamp-only
  row**, preserving "an access occurred on this date" as a non-linkable aggregate
  while the linkable part expires on the same schedule as everything else.
- **Export compliance is unchanged, and was checked rather than assumed.** Device Sync
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
**before Device Sync ships**. This is a prerequisite of shipping, not of this ADR.

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
- **Silent collision reconciliation loses work people notice.** If beta users
  report a choreographer's `shareable` fields — website, notes — being replaced
  by a peer's version after pairing, the clobber is too aggressive and
  reconciliation needs to merge fields, or ask. A report of a *`deviceLocal`*
  field vanishing (email, location) is a stronger signal: those are coalesced
  rather than clobbered, so losing one means the coalesce is broken, not merely
  aggressive.
- **Venue and published-source duplication becomes a nuisance** rather than a
  curiosity, justifying fuzzy dedupe for the two kinds with no natural key.
- **Silent merge is observed collapsing dances users considered distinct** — for
  instance two arrangements that differ only in fields `_choreographyEquals`
  ignores. That would mean the equality test is too loose for sync even though it
  is right for import, and the two should stop sharing one definition.
