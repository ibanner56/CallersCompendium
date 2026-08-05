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
| Whether the survivor exists | Greater `existenceAt` — never `updatedAt` |
| Which field values survive | Last-writer-wins on `updatedAt` |
| Which `deviceLocal` values survive | Coalesce — see below |

**Existence has to be restated here for the same reason recency does.** This path
never reaches the merge table, so a rule that lives only there does not apply to
it — the argument this section already makes for recency, and the reason
*Reconciliation respects recency* is a test. Without the second row, a natural-key
collision resurrects deletions: device A creates choreographer "Bob Smith" and
deletes it; device B, offline, independently creates its own "Bob Smith", still
live and with a newer `updatedAt`. The names match and neither UUID is known to
the other, so this is step 2 — and "merge field values by recency" alone would
carry B's live state onto the survivor and silently undo A's deletion. Comparing
`existenceAt` gives the tombstone precedence, exactly as it does everywhere else.

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
`dance_links.target_dance_id` is a real FK to `Dances` (`DanceLinks.targetDanceId` in `tables.dart`), and a
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

**The table is bounded by pruning, and the bound is content-based.** An alias is
needed only while some peer might still publish a record referencing the losing
id, so it is retired once **no current peer manifest lists that id**. Every pass
already fetches every peer manifest and re-evaluates reconciliation against all
of them, so the check costs nothing extra and self-heals: a peer that has not yet
reconciled still lists the losing id and keeps the alias alive; once the last one
drops it, the alias goes.

This is deliberately *not* time-based. An earlier draft bounded retention by "the
oldest attached device's last-sync watermark, which `GET /v1/store` already
returns" — and every clause of that was wrong. The endpoint returns epoch, device
list and quota usage, and nothing per-device. The server holds
`stores.last_seen`, refreshed by *any* device, and `manifests.written_at`, which
is when a device last *published* rather than when it last caught up — a device
can `PUT` hourly while never downloading the merge. And the quantity actually
wanted, "has this device reconciled past this merge", is a function of that
device's baseline, which is `deviceScoped` and never leaves it. The server cannot
know it, so no endpoint could return it.

The same draft claimed a stale peer "eventually ages out of the store itself".
There is no per-device aging: the only reaping is `DELETE FROM stores` on the
whole store, and any device's request refreshes the clock that drives it. Two
active devices keep a store alive indefinitely, so one peer that syncs once and
vanishes would have pinned every alias forever — reintroducing the unbounded
growth pruning was added to prevent.

The content-based rule has none of those problems because it reads only what the
client already holds: the peer manifests it just downloaded, whose `records` map
lists every id each device knows, tombstones included.

The residual case is a peer that has dropped the losing *record* while some blob
of its own still references it — impossible under correct behaviour, since
reconciliation remaps its own references in the same transaction, but not
impossible from a buggy or much older client. That degrades gracefully rather
than dangerously: an unresolvable reference is skipped and reported, never
applied with a dangling id, so the cost is one skipped record rather than a
discarded batch.

**Boundedness still has one operational dependency, and it is disclosed rather
than solved.** A device that stops syncing without being removed keeps listing
the losing id in its last-published manifest, and so keeps that alias alive
indefinitely — there is no per-device aging, and `stores.last_seen` is refreshed
by any device, so the store never expires while others use it. A client-side
detach does not help either: it forgets the sync ID locally and leaves the
manifest in place. Pruning is therefore bounded in practice by someone calling
`DELETE /v1/manifests/{deviceId}` for devices that are genuinely gone.

The failure mode is bounded and slow — one row per merge per abandoned device, in
a `deviceScoped` table of ids — so it is a housekeeping cost rather than a
correctness problem. The converse is the sharper case: removing a manifest for a
device that is merely *dormant* retires an alias it still needs. That self-heals,
because the device re-reconciles from the natural key on its next pass and any
reference it cannot resolve is skipped and reported rather than aborting the
batch; but it is the one path that can retire an alias while a live device still
holds the losing id, so it gets a test.

`id_aliases` is **`deviceScoped`** — a local remap of local row identity,
meaningless on another device and never serialised. Like the baseline manifest it
is a schema change **beyond v23**, belonging to the sync implementation rather
than the migration, and it must be classified in the PR that creates it or the
coverage ratchet fails.

#### Rewriting a reference must advance `updatedAt`

A dance's `authorIds`, `tagIds` and `customFields` are **not columns on
`dances`**; they are hydrated from the join tables on read
(`DanceRepository.listAll`, via `_authorsForMany` / `_tagsForMany`). Rewriting `dance_authors` therefore changes
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
`choreographers.name` is `UNIQUE` (`Choreographers.name` in `tables.dart`), so one device cannot hold
two same-named choreographers today. Sync is not introducing the approximation,
only applying it across devices, and a review queue here would contradict what
the app already enforces locally. The failure mode is named rather than fixed.

**Custom-field definitions are the exception**, because merging them corrupts
data rather than merely conflating it. `decodeCustomFieldValue` does
`value = valueNum!` for a `number` field (`decodeCustomFieldValue`), so
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
(`CustomFieldDefs.key` in `tables.dart`), so minting a `skill_level_2` that already exists — created
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
| Pending deletions — markers (`kind`, `record_id`, `tombstoned_at`, `tombstone_hash`) | `pending_deletions` | `deviceScoped` |
| Pending deletions — retained tombstone bytes (`tombstone_blob`) | `pending_deletions` | `shareable` |
| Deferred review items (`kind`, `record_id`, `counterpart_id`, `reason`, `candidate_blob`, `candidate_hash`, `queued_at`) | `review_queue` | `deviceScoped` |

**All three are scoped to the store identity**, and `id_aliases` and
`review_queue` are additionally scoped to the epoch and cleared with the
baseline. Each records a conclusion drawn *about a particular store* — that two
ids were merged, that a pair needs adjudicating — and neither conclusion survives
a different store or a re-seeded one.

**`pending_deletions` survives an epoch reset, deliberately.** Scoping it to the
epoch as well would be wrong in a way that silently discards user intent. Fresh
attach fires on a `409` epoch mismatch, not only on detach, and a pending-held
entity still has a **live** local row — it was never soft-deleted, because the
device still cites it. So clearing the table on that path and then running "upload
every local record" republishes the entity as live, and the deletion the user
performed on another device is gone. The `tombstone_hash` mitigation cannot save
it, because it operates in steady state and the table is by then empty.

Retaining it across the reset closes that, and the round-six advertisement rule
makes it safe: a pending-held record is uploaded **as a tombstone** on fresh
attach exactly as it is advertised as one in steady state, so the deletion is
re-published rather than reversed and the entity remains addressable for anything
still citing it. On **detach** the table clears with the rest, because the user
has left the store entirely.

Leaving these unscoped is wrong in the other direction, which is why the scoping
is stated rather than left to the implementation: retained across a *detach*, a
stale `pending_deletions` row would suppress an entity from the manifest of an
unrelated store indefinitely, and a stale alias would silently redirect ids that
mean nothing there.

Every row is per-installation protocol state, meaningless on another device, and
adding them means a schema change **beyond v23** — which the implementation issue
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

#### A rule may only read what its own path can reach

> **Every rule must name the data it reads, and that data must be reachable on
> the path where the rule runs** — in the HTTP contract if a client needs it, in
> the server schema if the server needs it, and on the code path in question
> rather than a neighbouring one.

The fourth invariant, and the one that would have caught the two worst defects of
the round it was written in. Alias pruning was bounded on a per-device watermark
that `GET /v1/store` was asserted to return and does not; the pending-hold
mechanism relied on a revive-on-citation rule that runs on the steady-state apply
path, on behalf of a fresh-attaching device that explicitly skips it.

Both read as correct when written, and that is the point: the quantity each rule
needed obviously *existed somewhere* — on some device, in some table, on some
code path — just not anywhere the rule could see it. "Which `GET /v1/store`
already returns" is checkable against the endpoint's own definition four hundred
lines further down the same document. "The revive-on-citation rule handles it" is
checkable against the fresh-attach section that says no deletion logic runs.

So when a rule cites a quantity, name where it comes from, and check that the
path in question can actually reach it — rather than that it exists.

#### A changed ruling must be propagated to every restatement

> **When a ruling changes, grep for every restatement of the old one — in the
> algorithm steps, the test list, and the ADR — before the revision is done.**

The fifth check, and the only one that is about the document rather than the
design. This document deliberately restates its key rules at the point of use,
which is right for an implementer reading one section and wrong for a reviser
changing one: the normative statement gets updated and a restatement three
hundred lines away does not, leaving two contradictory specifications of the same
mechanism with nothing to indicate which is current.

It has happened three times. The rename-collision ruling landed in the identity
section while "Renames collide too" still prescribed the opposite; the
tombstone-advertisement ruling landed in the normative section and the tests but
not in the fresh-attach algorithm; and a superseded test survived seventeen lines
above its own replacement, each asserting what the other forbids.

The repository already requires this discipline for claims about *code* — grep
for the property, not the citation. The same applies to claims about the design:
the place a stale rule survives is never where the change was made.

#### Scope: check every rule the change makes load-bearing

The five checks above apply to more than the lines a revision edits.

> **Apply them to every rule the revision's changes make load-bearing, not only
> to the rules the revision rewrites.**

The provenance gate is the worked example. Its text was written when it only had
to hold for the device performing a deletion, which knows the provenance of its
own writes — no wire representation needed, and check #4 had nothing to catch.
Extending it to *applied* tombstones a round later never touched that sentence,
but it turned a local rule into a cross-device one, and from that moment the gate
read a quantity that existed only on the writing device. The defect was
introduced by a change somewhere else, and both checks were run — against the
rules that had been edited.

So the trigger for re-checking a rule is not "did I change these words" but "did
I change who has to evaluate this, or where". A rule can rot without being
touched.

#### A rule belongs in the step it governs

> **A rule that governs a step of an algorithm belongs *in* that step.** Prose
> may explain it; the algorithm, the table and the test must state it. If a
> rule's only home is a section elsewhere, an implementer following the steps
> will not apply it.

The sixth check, and the one that has cost the most rounds. Three separate
findings have had this exact shape: a ruling that reached a normative paragraph
but not the section describing the same case; one that reached the normative text
and the tests but not the algorithm; and the provenance gate, which reached the
normative text but neither the merge table nor a test of the case that matters.

The checks above are all framed around rules that *changed*, which is why they
kept missing this: a rule can be brand new, correct, prominently stated — and
still absent from the one place an implementer reads. The failure is not staleness
but **placement**.

It also predicts where the damage lands. A rule stated only in prose gets applied
to the case the prose discusses and missed everywhere else, so the surviving hole
is usually the *commoner* path rather than the exotic one — the gate's prose
argued the `changed`/`changed` collision while the resurrection actually arrives
through `same`/`changed`, the bystander case, which is the mainline for any
tombstone that travels more than one hop.

#### Check what a condition is composed with

> **When hardening a condition, check what it is ANDed or ORed with.** A
> guarantee that holds for one term does not hold for the compound. If another
> term can independently block or admit the outcome, it needs the same treatment
> — or the guarantee is void.

The seventh check, and the natural sequel to the sixth. That one put a rule in
the step it governs; this one asks whether the rule *decides* anything once it is
there.

The worked example is one round of this design's own history. The existence rule
was written in prose, so it was placed into the merge table — correctly — as a
**second condition ANDed with recency**. Both terms were then visible on the same
line, and the conjunction still had a hole: recency could block a download before
the hardened term was ever evaluated, so a deliberate un-delete from a
slow-clocked device was silently reverted. Hardening one term of a conjunction
hardens nothing.

The fix was not a third condition but the removal of the conjunction: existence
disagreements are decided by `existenceAt` alone, before the table. When a
guarantee needs to hold, the question to ask is not "is my term strong enough"
but **"can anything else decide this first?"** — and where the answer is yes, the
usual remedy is to separate the decisions rather than to strengthen both terms.

#### Trace a new rule to every path that decides the same question

> **The checks above apply to rules a revision *introduces*, not only to rules it
> edits.** A new rule must be traced to every path that can decide the same
> question, and the trace written down.

The eighth check exists because the seven above are all phrased around a rule
that *changes* — "when a ruling changes", "when hardening a condition". A brand
new rule has no prior version to grep for and no existing condition to inspect,
so all seven pass over it in silence. The round that introduced `existenceAt`
shipped it correctly in two places and missed four others, and the round that
introduced the seventh check was the same round.

New rules are also where the *old* text is most dangerous, because prose written
for a predecessor field reads as current: a "which writes set it" enumeration
survived a field's generalisation from one direction to two, and contradicted the
rule stated thirty lines above it.

So a rule that decides something gets a table naming every path that decides it.
For existence:

| Path | Rule |
| --- | --- |
| Steady-state merge | Decided by `existenceAt` before the merge table |
| Fresh attach | Same, with no baseline to consult |
| Collision reconciliation | Second row of its decision table |
| Fresh-attach dance dedupe | Tombstones excluded from candidacy; no cross-UUID effect |
| Record creation | Seeds the field |
| Migration backfill | `T₀` for live rows, `deleted_at` for deleted ones — see the accepted consequence |
| Inbound validation | Out-of-range values rejected, never clamped |
| Quarantine repair | Adopts the greatest acceptable peer value; mints nothing from the local clock |

Written as a table because the alternative is discovering the paths one review
round at a time, which is what happened.

##### A safety rationale must name the readers it claims do not exist

A related habit, from two consecutive failures of the same shape. "This value is
safe to write freely because nothing else reads it" was asserted twice here, and
both times something did: `deletedAt` was said to be "never displayed or used for
retention" while the purge sweep and the Recently Deleted countdown both read it,
and `existenceAt` was said not to be "the merge discriminator" ninety lines after
this document made it exactly the discriminator for existence.

Both were load-bearing for accepting a decision, and both were checkable in under
a minute. So **when a rationale rests on nothing reading a value, enumerate the
readers and say you checked** — the claim is a factual one about the codebase,
not a design intention, and it is the kind that stays wrong quietly.

##### A global claim needs a global enforcer

The sibling habit, and the one that has now produced the more expensive error.

> **When a safety argument says "every peer", "nowhere", or "always", identify
> what actually enforces it.** If the enforcing check runs locally — against
> local state or a local clock — then the guarantee is local, and the argument
> needs its real precondition stated or a mechanism that makes it global.

The repair path is the worked example: "safe precisely because the poisoned value
was rejected **everywhere**" rested on a threshold defined as `localNow + 24h`,
which is one receiver's opinion evaluated against one receiver's clock. Both
halves sat thirty lines apart in the same section. The retired `T₀` constraint
had the same structure — "older than every `deleted_at` **in the table**" was a
per-device check standing in for a fleet-wide property — which suggests this is a
recurring shape rather than one slip.

The tell is a quantifier in the justification that does not appear in the
mechanism. When the argument says *every* and the code says *mine*, the gap is
where the defect lives.

##### A rejected assumption survives in the fallback

> **When a mechanism is hardened because some input is untrustworthy, check every
> branch that still consumes that input — the fallback first.**

The tenth habit, and the one with the worst record here: two consecutive rounds
of repair mechanisms failed on it. A fallback is written as "the case where the
new mechanism has nothing to work with", which is precisely the phrasing under
which the old, rejected assumption slips back in — the primary path stopped
trusting the local clock and the fallback ended "`localNow` alone is used".

It is easy to miss because the fallback looks like a degenerate case rather than
a decision. It is not: it is the branch that runs exactly when the situation is
worst, and it inherits none of the reasoning that made the primary path safe. A
hardened primary with an unhardened fallback is an unhardened mechanism with
extra steps.

The companion question is what a mechanism should do when it genuinely has
nothing to work with. Minting a value from the distrusted source is one answer;
declining, staying in a stable and loud failure, and reporting is usually the
better one — a device that cannot tell what time it is should not be ordering
events, and saying so is more useful than guessing.

##### Bounds are directional

A related and simpler slip. Every bound in the quarantine mechanism —
`localNow + 24h` for both rejection and quarantine — is **one-sided and upper**.
That is correct against a clock running fast and inverts entirely against one
running slow, which the same paragraph's own motivating hardware ("a dead RTC, a
mis-set year") does about as often. When a bound guards against a value being
wrong, ask which *direction* of wrong it catches, and whether the other direction
turns the guard into its opposite.

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
  "existenceAt": "2026-08-03T04:11:22.000Z",
  "body": { }
}
```

- `v` — blob envelope version. Unknown values are refused by the client, not
  guessed at.
- `kind` — which repository owns the record.
- `updatedAt` — the conflict discriminator. UTC, millisecond precision.
- `deletedAt` — non-null means a **tombstone**: the record is deleted, and this
  blob is how that fact travels.
- `existenceAt` — orders the record's live↔deleted transitions causally.
  Always present, advanced on every such transition and — apart from quarantine
  repair — by nothing else, and it alone decides an existence disagreement; see
  below.
- `body` — archive-codec output for the record, `shareable` fields only.

#### `existenceAt`, and why existence needs its own clock

The provenance gate — *a live record never out-ranks a tombstone unless the write
carrying it was user-initiated* — was written when it only had to hold for the
device performing the deletion, which knows the provenance of its own writes.
Extending it to applied tombstones made it a **cross-device** rule: a receiver
must now decide, from a downloaded blob, whether some peer's write was a
deliberate human act. Nothing in the envelope carried that, so the rule read data
that was not reachable on the path where it runs. `existenceAt` is that data.

**It must be a timestamp, not a flag.** A boolean "this write was user-initiated"
describes only the *most recent* write, and the content invariant guarantees
there will be later ones: a user revives X at T1, publishing `userInitiated:
true`; the device later reconciles an unrelated collision that rewrites one of
X's references, which *must* bump `updatedAt` and re-upload — now publishing
`userInitiated: false`. The revival becomes invisible and the tombstone wins, so
the flag destroys the very signal it exists to carry. A timestamp is monotone: a
later sync write advances `updatedAt` and leaves `existenceAt` untouched.

**The rule is a comparison, evaluable by any receiver with both blobs:**

> When two copies of a record disagree about whether it exists, **the greater
> `existenceAt` wins**, and its `deletedAt` says which state that is. Equal
> values go to the tombstone.

That works with no local history *beyond the two blobs*, which is what the
fresh-attach case demands — an attaching device has no baseline and no prior
relationship with any peer, and still gets the right answer from what is in front
of it. Ties resolve to the tombstone because deletions are sticky here, and
because both devices must reach the same answer without coordinating.

**`existenceAt` is a third timestamp, deliberately separate from the other two.**
Each of the three answers a different question, and an earlier version of this
design collapsed the first two, which broke both:

| Field | Question | Clock |
| --- | --- | --- |
| `updatedAt` | when did this record's content last change? | plain local clock |
| `deletedAt` | when did the user delete this, in real time? | plain local clock |
| `existenceAt` | which existence transition is later, causally? | causally stamped |

`deletedAt` cannot serve as the ordering value because it is a **retention**
timestamp with two real consumers: `purgeDeleted` hard-deletes on
`deletedAt <= now - retention`, and the Recently Deleted screen renders a
countdown from `deletedAt.add(retention)`. An earlier draft claimed these fields
were "never displayed or used for retention" — that was simply false, and the
consequence was severe: causally stamping `deletedAt` forward could pin it in the
future, after which the purge never fires and the record sits in Recently Deleted
for ever, showing a nonsense countdown. Since a tombstoned choreographer still
carries a name, that also quietly defeats the retention the privacy posture
leans on.

`updatedAt` cannot serve either, because it answers a content question and is
compared for every record whether or not deletion is involved.

**`existenceAt` is stamped causally, not read from a bare clock.** The comparison
is between values written by two different devices, so on independent clocks it
is only as good as the skew between them. Thirty seconds between two phones is
unremarkable, and a revival is *causally* after the deletion it supersedes — the
device had to receive the tombstone to revive from it — so a slow clock would
rank a deliberate un-delete as earlier and silently revert it. This design
elsewhere treats clocks as untrustworthy: it rejected timestamp epochs partly
because they depend on a server clock never stepping backwards.

So **every** live↔deleted transition stamps

```
existenceAt = max(localNow, currentExistenceAt + 1ms)
```

reading the value already on the record, which the device has necessarily
observed in order to act on it. A revival therefore outranks the deletion it
supersedes by construction, and a deletion outranks the revival it supersedes by
construction, whatever the clocks say. Both directions need it: an earlier
version stamped only the revival, which left a device with a *slow* clock unable
to delete a previously revived record at all — its value would land below the
existing one, peers would keep the live copy, and the deleting device would
download its own deletion back.

One field rather than a pair also removes a failure this mechanism had while it
was two: with `revivedAt` and `deletedAt` as separate comparands, a device could
advance one while the other stood still. A single monotone value per record
cannot disagree with itself.

**A future-dated `existenceAt` is contained, and hostile values are rejected
rather than clamped.** Nothing outside the existence decision reads it — not
retention, not display, not `updatedAt` recency — so a `max` landing slightly
ahead of local time has no side effect, which is the property the old wording
wrongly claimed for fields that *did* have other readers. It is emphatically not
true that "nothing reads it": it is the existence discriminator, and being read
for that decision is its entire purpose.

That is exactly why an out-of-range inbound value must be **rejected, not
clamped**. Clamping a causal comparand corrupts the comparison it feeds: capping
a value downward can drop a legitimate later revival below the true value another
device still holds, silently reverting the un-delete this field exists to
protect — and if `localNow` were sampled once per pass rather than per record,
two correctly-ordered values could clamp to the *same* ceiling, turning a strict
inequality into a tie that the tie rule then resolves to the tombstone. Capping
also does not even stop the attack it was meant to: a peer pinned at the ceiling
still wins every comparison, and can refresh it.

(That tie hazard is an argument against clamping specifically. Under rejection
nothing derived from `localNow` is stored, so whether it is sampled per record or
once per pass makes no difference to final state — an earlier draft mandated
per-record sampling on the strength of the clamping argument, which does not
carry over to the mechanism actually chosen.)

So a blob whose `existenceAt` exceeds `localNow + 24h` is **refused as malformed
and reported**, exactly like a record that fails to decode — one record skipped,
the batch intact, local state unchanged. This is stated as a check to implement
rather than assumed: `_dtOrNull` validates only ISO-8601 parseability and calls
`.toUtc()`, and the codec's clamping is all string and list length, so no date
range check exists today.

**An honestly skewed value needs a repair path, because monotonicity makes it
permanent.** The reasoning above is about a hostile peer; the likelier case is a
device with a badly wrong clock — a dead RTC defaulting to a future build date, a
mis-set year — which stamps a transition at, say, 2036. Every honest peer rejects
that blob on every pass, so the originating device believes the record deleted
while every peer holds the opposite. And correcting the clock does not fix it:
`max(2026, 2036 + 1ms)` is still 2036, so every later legitimate transition on
that record stays above the rejection threshold. Without a repair path the record
drops out of sync until wall-clock time catches up, which is not a bounded
divergence in the way the restore case is.

Three rules close it, and the repair happens **during a sync pass rather than on
a user gesture** — because that is the only moment the device can see what the
other copies actually hold:

- **A record whose own `existenceAt` exceeds `localNow + 24h` is quarantined.**
  This is a derived predicate over an existing column, not new state, so it needs
  no schema.
- **Repair adopts observed values; it never mints one from the local clock.** The
  device gathers the peers' copies of that record, discards any whose
  `existenceAt` falls outside its own acceptance window, and takes the greatest
  of what remains. Then:
  - if the peers agree with the local live-or-deleted state, it **adopts that
    value verbatim** — no new value, and the two copies become bit-identical;
  - if the local state differs, the user made a transition while poisoned, so the
    device stamps `thatValue + 1ms` to preserve their intent and outrank the
    peers.

  It also restamps `updatedAt` to `greatest acceptable peer updatedAt + 1ms`,
  which both satisfies the content invariant below and cleans the `updatedAt`
  that the same broken clock poisoned. The local live-or-deleted state and the
  record's content are untouched; only the two ordering values are rebuilt.
- **A rejected hash is reported once per session**, held in memory. The blob
  stays in the peer's manifest and would otherwise be re-fetched and re-rejected
  for ever, turning one bad record into an endless stream of identical warnings.
  Per-session is deliberate: repair now happens automatically on the next pass,
  so the window in which a rejection recurs is short, and suppressing it across
  restarts would mean persisting a set of a peer's content hashes — new state,
  needing a classification, to solve a problem that no longer lasts long enough
  to warrant it.

**Repair reads no clock, and that is the point.** A draft of this rule ended "if
no acceptable peer copy exists, `localNow` alone is used" — reinstating, in the
fallback, exactly the trust the primary path had just withdrawn. Quarantine and
acceptance are both **one-sided upper bounds**, which is right for a fast clock
and inverts completely for a slow one, and the motivating hardware fails in both
directions.

A device whose RTC dies to 2000 finds every healthy record at 2026 above
`localNow + 24h`, so it quarantines **all** of them; every peer value is likewise
outside its window, so "no acceptable peer copy exists" fires everywhere and it
rewrites its whole collection *downward* to 2000. A subsequent deletion stamps
`max(2000, 2026 + 1ms)`, quarantines again, repairs down again — and the peers'
live copies at 2026 outrank it, so the deletion is silently reverted. That is the
cardinal failure, reached through the one branch that still trusted the clock.

**When every observed peer value is outside the local window, the local clock is
the outlier, not the peers.** One device disagreeing with the fleet is the device
that is wrong. In that state it declares itself **clock-suspect**: it does not
repair, does not mint existence values, and reports — because a device that
cannot tell what time it is cannot safely order anything. Records stay
quarantined and diverged, which is stable and loud, rather than silently wrong.

With no clock in the repair path there is also no fallback branch to contradict,
and the earlier draft had one: it promised `localNow` when no acceptable peer
copy existed while the residual below promised the opposite, and a single
out-of-window peer satisfied both triggers at once. An unacceptable peer value is
**excluded from the maximum, not a veto** — ten honest peers still repair the
record when an eleventh is broken.

**Why the repair reads peer values rather than trusting the local clock.** An
earlier version reset from the local clock alone, arguing it was safe "precisely
because the poisoned value was rejected everywhere, so every peer still holds a
value older than the local clock". That inference is invalid, and the sentence
contained both halves of its own refutation: rejection fires only above
`localNow + 24h`, **evaluated by each receiver against its own clock**, so
"rejected" is one receiver's local opinion and never a global fact.

Three routes defeat it. A device whose clock is *mildly* fast — eighteen hours,
under the bar — has its values **accepted** by every peer; if that device later
poisons the record, corrects its clock, and deletes, a reset from the corrected
clock lands *below* the accepted live value and the deletion loses. A peer whose
own clock is equally wrong — a shared firmware defect is the motivating case —
accepts the poisoned blob as ordinary and holds it permanently, rejecting
nothing. And a gradually drifting clock emits a chain of values each inside every
peer's window at the moment it is sent, so nothing is ever rejected while the
absolute value climbs. In all three the repaired record loses to something still
in circulation, silently reverting a deliberate deletion — the exact failure this
field exists to prevent, reintroduced by its repair path.

Reading the peers' values makes the guarantee match the check: the repaired value
outranks what is observably there, rather than what an argument assumed was there.

**Repairing on a pass rather than on a gesture also closes two gaps the earlier
version had.** It never triggered in its own motivating case: a device that
poisoned a record while reviving it already displays that record exactly as its
user intended, so the user has no reason to perform another transition, and the
divergence is invisible from the device causing it. And a record poisoned while
*live* was worse than stranded — content edits do not touch `existenceAt`, while
rejection is whole-blob, so every later edit to that record went unsyncable with
nothing to signal it and no gesture that would fix it. Automatic repair needs
neither the user to notice nor the user to guess the remedy.

**The residual is stated rather than argued away.** Where a peer's value falls
outside this device's window but the device is not clock-suspect — the peers
disagree with each other, not with it — that peer is excluded from the maximum
and the record repairs against the rest. The divergence from *that* peer remains,
and is reported.

An earlier draft said it "resolves when that device's own quarantine fires",
which is an unenforced *always* of exactly the shape the habit below was written
to catch. It resolves only if that peer's value is out of range **by its own
window** too. When two individually-honest devices simply sit a long way apart —
neither broken enough to quarantine itself, neither able to raise its value
without exceeding its own ceiling — nothing fires and the divergence is
open-ended. It is bilateral and reported rather than silent, and the honest
statement is that the design bounds it no further than that.

The guarantee is also over **observable** peers: the consulted set is whatever
the current manifests advertise, so a peer that is offline holding an unpublished
later transition can outrank a repair when it returns. That is the design's
standing behaviour for any deletion rather than something repair introduces, but
it belongs in the statement of what repair guarantees.

A repaired value that ties a peer's loses to a tombstone under the standing tie
rule, so the `+ 1ms` is load-bearing rather than decorative. Two devices
repairing the same record concurrently converge through the **content** table
rather than the existence rule — when both agree the record exists, existence
never runs — which works because each stamps `updatedAt` above the greatest it
observed, so one of the two is strictly newer and wins outright. An earlier draft
derived that convergence through the existence comparison, which cannot decide it,
and left the pair tied at equal `updatedAt` in a row the table does not resolve.

One skew does compound mildly: a peer honestly near its own ceiling plus a
repairer whose clock is moderately fast can produce a value a third,
correctly-clocked device rejects. It is bounded by one hop's worth of window and
self-corrects through that device's own repair, so it is recorded rather than
engineered against.

Keeping the plain `max` instead was considered and rejected: it leaves the record
diverged but *stable*, which is genuinely safer than a silent wrong winner, and
that is exactly why the naive reset could not ship. Repairing against observed
values recovers the record without making that trade.

**Which writes set it.** Every write that changes whether the record exists, in
both directions:

- **Creation** seeds it, from a plain clock. A new record is `∅→live` rather than
  a live↔deleted transition, so it needs its own rule or the field would have no
  value for the first deletion's `max` to read.
- **Deletion** — every user-initiated soft delete, including the deferred one
  applied when a pending hold's last citation goes.
- **Revival** — cancelling a pending tombstone by editing the record, and an
  explicit restore from Recently Deleted.
- **Quarantine repair** — the one writer that is not a transition. It rebuilds a
  poisoned ordering value from observed peer values without changing whether the
  record exists, and it is listed here because this is the section an implementer
  reads to find out which writes set the field. A draft of this enumeration
  omitted it while two absolutes elsewhere said the field moved on transitions
  and nothing else, which is the same stale-enumeration failure this document
  records one field earlier.

**Every other sync-apply path leaves it alone**, including reference rewriting,
merge-by-recency, reconciliation and the dance merge's scalar recency. Applying a
peer's blob copies that peer's value rather than stamping a new one — the field
records where a record sits in its own existence history, not when this device
last heard about it.

An earlier draft enumerated only the revival cases here, carried over verbatim
from a predecessor field that covered one direction. It contradicted the causal
rule two paragraphs above, and it was the more dangerous of the two to follow:
"which writes set it" is the section an implementer reads to find out which
writes set it, so a deletion would have gone unstamped and the slow-clock
deletion failure would have returned intact.

A device that never learned of a deletion still cannot revive one, because
reviving means acting on a tombstone it can see. An ordinary edit on a stale
device is not a decision about a deletion it never saw, and does not outrank one.

The cost of that choice is stated plainly: such an edit is swept up when the
deletion arrives. It is not destroyed — the record soft-deletes into Recently
Deleted with the edit intact — but the user is not told it happened. Deletions
staying sticky is the deliberate trade, since a deletion silently reversed on
every device is the failure this whole mechanism exists to prevent, and it is
also the harder of the two to notice.

`existenceAt` is `shareable`: it is a bare timestamp with no subject, it must
travel for the rule to work, and it is stored per record on all eight syncable
kinds (see the v23 scope).

Because nothing has shipped, this lands in envelope `v: 1` rather than bumping
the version — there is no deployed client that could receive a blob without it.

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
it. **Schema v23** adds `updated_at` *and* `deleted_at`, stamping existing rows
at migration time. Both need classifying like any other column, and the coverage
ratchet will require it.

`deleted_at` is not optional. `SettingsRepository.remove` is a hard delete today,
so without a tombstone a removed setting cannot be expressed on the wire: the
peer still holds it, "absence never deletes" preserves it, and the next sync
**downloads it back**. The deletion would reverse every time, permanently.

#### The real scope of v23

**The version number was checked against `main`, not assumed.** An earlier draft
called this migration v22. While the design was being written, #748 landed
`dance_figures.group_idx` as v22 (PR #802), taking `kCompendiumSchemaVersion` to
22 on `main`. The sync migration is therefore **v23**, and whoever implements it
should re-check the number again at that point rather than trusting this line —
the collision happened once precisely because a sibling merged between drafting
and review. Nothing else about the two migrations interacts: v22 touches
`dance_figures`, which this design does not migrate.

An earlier draft also called it "one column on `settings`". Under first-class
records, and with the provenance gate needing `existence_at` on every kind that can
be tombstoned, it is **eight tables and twenty columns**:

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

`dances` and `programs` already carry `updated_at` and `deleted_at`, so they join
the migration only for `existence_at` — but join it they must, since both can be
deleted and both can be deliberately restored, and the rule has to be able to
tell those apart on every kind rather than most of them.

Every write that deletes or restores a record must stamp it as
`max(localNow, currentExistenceAt + 1ms)` — **not** from a bare clock, which is
the whole point of the column and the easiest part of it to get wrong when
working from a migration checklist. `updated_at` and `deleted_at` are stamped
from a plain clock as they are today: the existing `softDelete` writes one shared
value into `deletedAt` and `updatedAt`, and that stays correct precisely because
nothing causal flows into either of them.

**The backfill rule matters, and the obvious choice is wrong.** Reusing the
adjacent `updated_at` would be the natural thing to reach for and would
reintroduce, through the migration, the exact coupling this column exists to
break: a device that edited a live record after another device deleted it would
carry `existence_at = updated_at` greater than the tombstone's, so its live copy
would win and the record would resurrect on first sync. The corpus at launch is
entirely pre-migration rows, so this would not be an edge case.

Backfill instead from the row's **existence history, not its content history**:

| Row state at migration | `existence_at` |
| --- | --- |
| live | a single constant `T₀`, identical for every live row |
| already soft-deleted | `deleted_at` |

`T₀` is one timestamp chosen at migration time and written to every live row, so
no live row outranks another and the first real transition on any device
establishes the ordering. An already-deleted row takes `deleted_at`, which is
when its existence actually last changed — the one case where a pre-existing
column carries the right meaning.

**`T₀` is per-device, and that resurrects some pre-migration deletions.** A
draft of this section also required `T₀` to be older than every `deleted_at` in
the table, which cannot be satisfied: a value sampled when the migration runs is
necessarily later than deletions already in the past. The two sentences could not
both be implemented, so one had to go.

The constraint is the one dropped, on the maintainer's decision, because at beta
scale every install reaches the sync-capable contract before the first stable
release and the migration's edge cases were judged acceptable. The consequence is
recorded here rather than left implicit:

> Device A deleted record R before migrating, so R carries `existence_at =
> deleted_at`. Device B never deleted R and migrates later, so R carries
> `existence_at = T₀`, which is greater. On first sync the live copy outranks the
> tombstone and **R comes back**.

Two honest qualifications. This is an ordinary situation rather than an exotic
one — two phones set up from the same backup, one of which has deleted something
— and it is **not bounded by the migration window**: `T₀` remains a record's
operative existence value until that record has another live↔deleted transition,
so neither the passage of time nor universal migration retires it. The
alternative, had it been wanted, is one line: make `T₀` a hardcoded pre-release
constant rather than a sampled clock, which satisfies both original sentences and
removes the vector.

`existence_at` is classified `dpv:NonPersonalData` / `shareable`: a bare timestamp
with no data subject, which has to travel for the gate to be evaluable by a
receiver.

Plus **six `_db.delete(` call sites** converted from hard to soft delete across
five repositories, and the **`restore()` paths on every kind** — the two that
exist (`DanceRepository`, `ProgramRepository`) plus the six added by this
migration — updated to stamp `existence_at`. Restore is the write that *sets* the
provenance signal, so it is as much a part of this migration's surface as the
deletes are; listing one without the other would leave the gate with no writer.

`Dances` and `Programs` already have `updated_at` and `deleted_at`; they need
only `existence_at`.

##### `DanceRepository` is not the pattern to copy

An earlier draft said to copy `DanceRepository`. That is wrong, and the
difference is not cosmetic: dances are the **parent** in every one of these
cascades, and the five kinds converting here are on the other side of them. Each
needs a per-kind decision, and two of them carry an app-behaviour regression if
converted naively.

**`TagRepository.delete` relies on the FK cascade** to clear `dance_tags` — its
own comment says so (`TagRepository.delete`). A soft delete is an `UPDATE`, so
**the cascade never fires**: the join rows survive, and because `dance_tags`
gains no `deleted_at` in v23, nothing filters them. The tag would vanish from the
tag manager while staying silently attached to every dance. The same applies to
`custom_field_values` and `dance_sources`.

> **Every read that joins through to a soft-deletable parent must filter
> `parent.deleted_at IS NULL`.** This is a change to existing query paths, not
> only to the sync code, and it is the part of v23 most likely to be missed —
> the migration passes, the tests pass, and the defect only shows on a screen.

**Deletes that are referential guards must keep guarding.**
`ChoreographerRepository.delete` throws while the entity is still credited
(`ChoreographerRepository.delete`); `VenueRepository` and
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
record on any device. Cancellation therefore keys off **`existenceAt`** — the
timestamp a deliberate un-delete sets and no sync-apply path ever writes —
however new the resulting `updatedAt`.

**The same gate governs an *applied* tombstone, not only a pending one.** On the
device that actually performed the deletion the tombstone is applied, and there
the ordinary merge rule — `changed`/`changed` → higher `updatedAt` wins — would
otherwise let any live copy with a newer timestamp win. Since reconciliation,
reference rewriting and the dance merge all advance `updatedAt` without a user
edit, a third device could manufacture a live record newer than an applied
tombstone and the deleting device would download it. So the rule is stated once,
generally: **when two copies disagree about existence, the greater
`existenceAt` wins.** Pending and applied tombstones are the same rule seen
at two moments, not two rules — and because the test is a comparison of two
fields both blobs carry — each stamped strictly after the transition it
supersedes, so the comparison does not rest on the two devices' clocks
agreeing — a receiver can apply it with no local history at all.

**A pending-held row is advertised as a tombstone, not withheld.** The holding
device publishes the deletion it has not yet applied: its manifest carries the
entity as a **tombstone**, while the row stays live locally until its last
citation goes. It never publishes the entity as *live*, which is the property
that stops the deleting device downloading its own deletion back.

An earlier draft omitted the entity from the manifest entirely. That stopped the
resurrection but broke **referential closure**, because the device goes on
advertising the dances that cite the entity. `dance_authors.choreographer_id` is
a hard FK with `onDelete: cascade`, so a fresh-attaching device that downloads
one of those dances and can find no record for its author fails at COMMIT and
**discards the entire batch** — and if the deleting device has since purged the
tombstone, the blob is unreachable from any manifest and garbage-collected, so
there is nothing to fetch at all. Publishing the tombstone keeps the FK target
addressable while carrying exactly the same "this is deleted" claim.

**Fresh attach runs the revive-on-citation rule too.** A device attaching for the
first time can download a tombstoned entity and a dance citing it in the same
batch, and it has no baseline, so none of the steady-state deletion logic applies
to it. Without this it would land holding a dance that credits a tombstone — the
state the whole mechanism exists to prevent, reached on a clean device. Fresh
attach therefore revives a tombstoned record that an incoming record cites, and
marks the tombstone pending, exactly as the steady-state path does.

**The baseline is not advanced for a pending-held record, and the merge table
does not see it.** A pending-held record has **two hashes on one device**: the
published manifest carries the tombstone's, while the baseline keeps the live
row's. The steady-state algorithm computes "the local manifest" once and then
compares local against baseline, so read literally those two differ, the record
reads as `changed`, and the merge table routes it to upload or conflict — the
opposite of a stable hold.

So the two are decoupled explicitly: **the merge comparison uses the live row's
hash, and the tombstone hash substitutes only when the published manifest is
serialised.** A pending-held record is owned by `pending_deletions` alone and is
excluded from the local-versus-baseline comparison entirely; the deferred state
is not something the merge table can express. Advancing the baseline instead
would leave the local row permanently differing from it, so `changed`/`same`
would fire every pass and the device would republish its stale live blob forever
— the same resurrection reached through upload rather than download.

**`tombstone_blob` is `shareable`, not `deviceScoped`, and that split is
deliberate.** The other columns in `pending_deletions` are per-device
bookkeeping — which record, when, which tombstone — and are meaningless
elsewhere. The blob is not: it is the record's own serialised content,
`deviceLocal` fields already omitted, and the **entire reason** for keeping it is
so the holder can re-`PUT` it to project infrastructure. `deviceScoped` asserts a
value is never transmitted as record content, with a carve-out only for routing
metadata that carries no user data by construction; these bytes are exactly
record content and are transmitted verbatim, so that label would have been false.

The distinction matters against `review_queue.candidate_blob`, which *is*
`deviceScoped` and correctly so: that candidate is a local adjudication artifact
that is never uploaded. Retention is what separates them from transmission.

Classifying it honestly also keeps the registry's accounting intact. A tombstoned
choreographer still carries its name, so these bytes hold third-party personal
data at rest in a second location. Folding them into an opaque `deviceScoped`
row would have told a future audit both that they never leave the device — they
do — and nothing about whose data they hold.

**Why the bytes are retained at all.** The holder may need to re-`PUT` the blob:
garbage collection is reference-counting over current manifests, and the holder's
own manifest only begins referencing the tombstone hash once it publishes. In the
window before that, if the original deleter has already purged its local
tombstone and a sweep fires, the blob can be collected — leaving the holder
advertising a hash with nothing behind it, which is precisely the "target still
addressable" property the advertisement rule exists to provide. Keeping the bytes
lets the holder restore it.

The cost is bounded by the per-kind blob cap rather than being small in absolute
terms. An earlier draft called a tombstone "a few hundred bytes"; that
understates it, because soft delete only stamps `deletedAt` and `updatedAt` and
leaves every other column intact — which this design depends on elsewhere, since
it is the same soft delete that backs the Recently Deleted screen. A tombstoned
choreographer or venue therefore still carries its full notes, URL and address
content. The retention decision is unchanged, since the count is bounded by
currently-pending items and each entry by the existing cap, but the justification
should not lean on a size claim that is not true.

**A purge must not cascade off live records.** `DanceRepository.purgeDeleted`
guards its hard delete with `_cleanupDanglingReferences` and a GC that never
weakens the delete-guards. A choreographer or tag purged by its own repository
has no such guard, and the hard delete would cascade `dance_authors` /
`dance_tags` / `dance_sources` / `custom_field_values` off **live** dances
(the `DanceAuthors`, `DanceTags`, `DanceSources` and `CustomFieldValues` FKs in `tables.dart`) — silent loss of authorship, tags, citations
and custom values. Every purge added here must refuse to hard-delete an entity
still referenced by a live record.

#### Land the migration first, before any other sync work

**Schema v23 should ship ahead of every other piece of this programme**, on its
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
   while the stamps still reflect *migration order*. Ship v23 early and users
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

   Pending tombstones make that conflict routine rather than rare, and they
   resolve through it rather than around it. A device holding a deletion pending
   **advertises the entity as a tombstone**, so an attaching device sees the same
   id carrying a tombstone from the holder and the deleter, and possibly a live
   copy from a third device that has not caught up. Recency decides, and a
   tombstone written after the last live edit therefore wins: the attaching
   device applies the deletion. That is the correct outcome — it is what every
   caught-up device already believes — and it is reached by the ordinary conflict
   rule rather than a special case.

   The stale live copy is not a reason to keep the entity. It is exactly the
   "peer that has not caught up" the recency rule exists to distinguish from a
   peer that edited, and the provenance gate applies here too: a live record
   loses to a tombstone with a greater `existenceAt`. A device whose user
   genuinely un-deleted the entity stamped a later value and wins; one that
   merely never learned of the deletion never advanced it, and does not.

   An earlier draft said the holder "advertises nothing for that record", making
   this the ordinary union case and yielding the live entity. That premise is
   superseded — withholding broke referential closure — and so is the outcome it
   produced.
6. Persist the epoch and the resulting manifest as the new baseline. A record
   revived by the citation rule during this attach is **pending-held**, so the
   same carve-out applies as in steady state: its baseline entry records the live
   hash it holds locally, not the tombstone it advertises. The same holds for
   rows carried over in `pending_deletions` from before the reset — the baseline
   is rebuilt from scratch here, so both sources of pending holds need the
   carve-out stated, not just the ones this attach created.

### Fresh-attach dedupe

Union matches on record id. Two devices that imported the same dance separately
hold different ids for it, so union alone yields duplicates.

**Silent merge** where both hold:

1. exact normalized-title match (`normalizeTitle`), and
2. `_choreographyEquals` — form, formation, progression, phrase structure,
   figures *including params*, hook, calling notes, level, mixed level, tunes.

**Tombstones do not participate.** A deleted dance is not a duplicate candidate.
Merging a live copy with a tombstoned one would decide existence by title and
choreography — content questions — and the deletion would vanish whenever the
surviving record happened to be the live one. So a tombstoned dance leaves
dedupe candidacy entirely: it is not matched, not merged, and persists as a
tombstone until its own purge.

A draft of this paragraph also said such a pair is "settled by `existenceAt` and
only then considered for dedupe". That step cannot run. Dedupe pairs records
holding **different UUIDs**, and the only thing that pairs them is the title and
`_choreographyEquals` match — so excluding tombstones from the match means no
pair ever exists for `existenceAt` to settle. The claim was harmless in effect,
since the safe reading is the implemented one, but it described a mechanism that
does not exist.

It also implied something false about a neighbouring case. Because dances have
**no `UNIQUE` natural key**, one device deleting its content-duplicate does *not*
suppress another device's independently created live copy: the two are different
records under different UUIDs, and existence is a per-record property. That is
the opposite of the `UNIQUE`-key kinds, where collision reconciliation makes two
UUIDs into one record and existence therefore has to be settled between them.

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
`candidate_blob`, `candidate_hash`, `queued_at`), classified `deviceScoped`, a
schema change beyond v23 alongside `id_aliases`. Deferring an item is a write,
not a prompt; the user is shown a count and works through it whenever they
choose.

**It needs a new review surface, and an earlier draft understated that.** Having
correctly established that the review *UI* exists, that draft went on to say the
work was "storage plus a way in, not a new UI". It is not.
`import_review_screen.dart` is built on `ImportRecordPlan`, figure diffs and
`DanceEditorScreen`; its only choreographer references are repository arguments
to `ImportPipeline`. It reviews **dances**, and cannot review a choreographer,
tag or custom-field collision.

What these kinds need is much smaller than the dance screen, because their
collisions are name-level rather than content-level: a generic list — *these two
records look like the same choreographer; keep both, or merge* — with no per-kind
editors. That is genuinely new UI, and it is named as such rather than folded
into "storage".

**A queued item carries an immutable candidate, not just a pair of ids.** The
rename case cannot otherwise be represented: incoming X renamed to "Bob" collides
with local Y "Bob", and X *cannot* be written locally because of the `UNIQUE`
constraint — so the version the user is being asked to judge exists nowhere. The
queue would show local "Alice" against local "Bob" and never show the incoming
change at all. Storing the candidate blob and its hash also stops queued rows
rotting when the underlying record is later deleted, reconciled away, aliased or
its blob garbage-collected; an item whose counterpart has since vanished is
invalidated and dropped rather than shown against a missing row.

Two further properties, both of which follow from sync being repeated rather than
one-shot:

- **Queuing is idempotent, under a canonical key.** An item is keyed by the pair
  it concerns, **ordered by the same tie-break the rest of the design uses** —
  lexicographically smaller UUID first. Without a canonical order the same
  collision discovered with the roles swapped inserts a second row, which is
  precisely the duplication the idempotency exists to prevent. With it, an
  unresolved collision updates its existing row on every later pass.
- **A queued pair is not re-resolved behind the user's back.** While an item is
  pending, neither record is silently merged or dropped by a later pass; the
  deferral holds until it is answered.

**The queue must not denormalise contact fields.** Its `deviceScoped`
classification holds because every column is an id, kind, reason, hash or
timestamp — and the candidate blob carries only what the wire format carries,
which excludes `deviceLocal` fields by construction. A review surface hydrates
display values from the live rows by id. Copying an email or location into the
queue for convenience would break the classification the table was granted.

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
`onDelete: KeyAction.setNull` (`ProgramSlots.danceId` in `tables.dart`), so removing the losing
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

   **Existence disagreements are decided before this table is consulted, and by
   `existenceAt` alone.** If one side is a tombstone and the other is live, the
   greater `existenceAt` wins outright; `updatedAt` does not participate, on any
   row. The table above then governs only the ordinary case where both sides
   agree the record exists.

   It has to cover `same`/`changed` and not just the `changed`/`changed`
   collision, because the *bystander* is the mainline for any tombstone that
   travels more than one hop. A deletes X while it is unreferenced, so the
   deletion applies at once; C downloads the tombstone and it becomes C's
   baseline. D never learned of the deletion, still holds X live, and later
   reconciles an unrelated duplicate that rewrites a reference into X — which,
   per *Content changes must move the discriminator*, **must** bump X's
   `updatedAt` past the tombstone. C then sees local `same`, remote `changed`,
   and on plain recency downloads a live X: a resurrection with nobody having
   revived anything, which neither A nor D is in a position to prevent.

   The ordering matters, and getting it wrong is subtle. An earlier draft added
   the existence check to the `same`/`changed` row as a **second condition ANDed
   with recency** — which leaves the hole open, because the recency term can
   block the download before the existence term is ever reached:

   1. D, with a correct clock, deletes X at real time `T`. Its `updatedAt` and
      `deletedAt` are both `T`. Bystander C applies the tombstone; it becomes C's
      baseline.
   2. R's clock is thirty seconds slow. Its user watches the deletion arrive and
      taps Restore ten seconds later. `restore()` stamps `updatedAt = T − 20s`
      from that bare clock. Causal stamping sets `existenceAt` above the
      deletion's, so the existence test passes.
   3. C hits `same`/`changed` and asks first whether
      `remote.updatedAt (T − 20s) > local.updatedAt (T)`. It is not. **The
      download is blocked before the existence test is consulted**, and a
      deliberate un-delete is silently reverted.

   Hardening one term of a conjunction hardens nothing. Deciding existence first,
   on its own field, removes the conjunction rather than strengthening half of
   it — and it is why `existenceAt` is separate from `updatedAt` in the first
   place: a record's content recency and its existence are different questions,
   and answering the second with the first is what created the hole.

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
   `settings`, gain it in schema v23. A kind without a modification timestamp
   cannot participate in this rule at all, which is why v23 is a prerequisite
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

It has since been broken a third time, by **quarantine repair**, and the check
above is what should have caught it: `existenceAt` is a top-level field of the
blob, the hash covers the whole blob, so rebuilding it changes the record's
serialised content. The draft that introduced repair did not advance `updatedAt`,
so a repaired record would have differed from its peers by hash while the
discriminator said nothing had changed — peers discarding the repair, and the
divergence outliving the fix.

The compounding case is worse and is the reason repair now rebuilds `updatedAt`
too. A broken clock poisons **both** values, because `softDelete` writes one
timestamp into `deletedAt` and `updatedAt` together. Whole-blob rejection had
kept that poison contained to one device; a repair that cleaned only
`existenceAt` would have let the blob win an existence disagreement and then be
applied wholesale — poisoned `updatedAt` included, since `updatedAt` takes no
part in that decision — spreading it fleet-wide and making every honestly-stamped
later edit lose every content conflict until wall-clock time caught up. The loud,
contained failure would have become a silent, general one.

5. `POST /v1/blobs/missing` with the hashes to upload; `PUT` only what is
   missing.
6. `GET /v1/blobs/{hash}` for each needed hash. **Verify the hash before
   applying.**
7. Apply in one transaction, **read-modify-write** (below). Rebuild derived
   indexes.
8. `PUT /v1/manifests/{self}`.
9. Store the new baseline.

### Backup restore invalidates the baseline

Restore is a **local, direct-to-repository path that bypasses the merge engine
entirely.** `ArchiveRestorer` writes every entity through unconditional
`upsert`/`create` — `ChoreographerRepository.upsert` is a bare
`insertOnConflictUpdate` — with no awareness of `updatedAt`, `deletedAt`,
`existenceAt`, the sync baseline or `pending_deletions`. That predates this design
and is right for what restore is: putting a device back to a known state.

Left alone, the two features contradict each other. A user restores a backup
taken before X was deleted and synced away. X returns as a live row carrying its
old `updatedAt` and no `existenceAt`, while the sync baseline — a separate table
restore never touches — still records X as a tombstone. The next pass reads local
as `changed`, remote as `same`, and the table says **upload**, unconditionally.
Peers correctly refuse it, since the backup's `updatedAt` predates the deletion
and its `existenceAt` predates the deletion, so it does not reverse
network-wide. But
the restoring device now shows X alive **permanently, diverged from every peer,
with no error and no path back**.

**So a restore drops the sync baseline**, which forces a fresh attach on the next
pass. The baseline is a claim about what this device last agreed with its peers,
and a wholesale replacement of local state makes that claim false — dropping it
is not a workaround but the accurate response to state it no longer describes.
Fresh attach is already the specified path for "no valid baseline", and it
resolves this case correctly **while any peer still advertises the tombstone**:
X uploads, that tombstone carries the greater `existenceAt`, and the device
converges on the deletion instead of diverging from it for ever.

**That bound is real and is not a formality.** Once the deletion has been applied
everywhere and each device's sweep has purged the soft-deleted row past the
retention window, no tombstone survives to out-rank anything. A user restoring a
pre-deletion backup then uploads X as live against nothing, and **X returns on
every device.** This is the tombstone-retention tradeoff already disclosed for a
long-absent peer reattaching — but restore is an ordinary action a user takes
deliberately, which moves the case from exotic to reachable, so the convergence
claim is stated with its precondition rather than flatly.

`id_aliases` and `review_queue` clear with the baseline. **`pending_deletions`
does not** — for the same reason it survives an epoch reset: those rows record
deletions the user performed that are owed but not yet applied, and a restore is
no more evidence against them than a re-seeded store is.

The analogy is not exact, though, and the difference has to be handled rather
than waved at: an epoch reset never touches local rows, whereas
`RestoreMode.replace` wipes and reloads them. A pending row can therefore end up
pointing at a record the backup predates, or at one whose citations were replaced
wholesale, so the "last citation goes away" event that would discharge it may
never fire. **After a restore, pending rows are revalidated against the restored
data**: one whose record no longer exists is dropped, and one whose record is now
uncited applies immediately rather than waiting for an event that has already
happened.

A user who genuinely wants the restored version to win can delete and re-enter
the record, or restore it from Recently Deleted once the deletion applies — both
of which stamp `existenceAt` and carry the intent explicitly. That is the same
sticky-deletion trade made everywhere else here, applied consistently rather than
re-litigated at the restore boundary.

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
  `_sendFollowingHttpsRedirects` in `artifact_downloader.dart` — https only, no userinfo, default port, hop
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
  Mutation-proved by gating cancellation on `updatedAt` rather than on
  `existenceAt`, which resurrects the record with nobody having edited it.
- **A bystander does not resurrect a tombstone** — A deletes X and it applies
  immediately; C downloads and applies the tombstone, so it is C's baseline. D,
  which never learned of the deletion, reconciles an unrelated duplicate that
  rewrites a reference into X, bumping its `updatedAt` past the tombstone. Assert
  C keeps X deleted. Mutation-proved by dropping the gate from the `same`/`changed`
  row, which resurrects it. This is the mainline path for a tombstone travelling
  more than one hop, and it is not the case the pending-holder test covers.
- **Reconciliation respects existence** — device A creates a choreographer and
  deletes it; device B independently creates the same name, still live and with a
  newer `updatedAt`. Assert the reconciled survivor stays deleted. Mutation-proved
  by dropping the existence row from the reconciliation decision table, which lets
  merge-by-recency carry B's live state across and undo the deletion. Mirrors
  *Reconciliation respects recency*, and exists for the same reason: this path
  never reaches the merge table.
- **A tombstoned dance is not a dedupe candidate** — same title and identical
  choreography, one copy deleted; assert they are not silently merged and the
  deletion stands. Mutation-proved by letting tombstones into dedupe candidacy,
  which decides existence by choreography.
- **Creation seeds `existenceAt`, and the migration backfills it safely** — assert
  a newly created record carries a value, and that after backfill every live row
  shares `T₀` while each already-deleted row carries its `deleted_at`.
  Mutation-proved by backfilling from `updated_at`, which is the natural
  implementer choice: a pre-migration bystander that edited a live record after
  another device deleted it then outranks the tombstone and resurrects the record
  on first sync.
- **An out-of-range `existenceAt` is rejected, not clamped** — a blob dated far in
  the future is refused and reported, the batch commits, and local state is
  unchanged. Mutation-proved by clamping to the ceiling instead, which lets the
  hostile value win every existence comparison and, when two out-of-range values
  clamp to one ceiling, converts a strict ordering into a tie.
- **A clock-poisoned record repairs itself against what is in circulation** —
  poison a record from a badly wrong clock, correct the clock, and run a sync
  pass **without any user gesture**; assert the record syncs again and the local
  live-or-deleted state is preserved. Mutation-proved three ways, each of which
  the others leave passing: keep the `max` (the record stays unsyncable long
  after the clock is right — the failure is not that a bad value was written but
  that nothing can supersede it); reset from the local clock alone (a peer that
  accepted an eighteen-hour-fast value still outranks the repair, and a
  deliberate deletion bounces back); and require a user transition to trigger it
  (the repair never fires, because the poisoned device already displays the state
  its user intended).
- **A slow clock does not rewrite the collection downward** — set a device's
  clock to 2000 with peers holding healthy 2026 values; assert it declares itself
  clock-suspect, mints nothing, and reverts no deletions. Mutation-proved by
  restoring the `localNow` fallback, which quarantines every record, repairs them
  all downward, and lets the peers' live copies outrank a subsequent deletion.
  This is the direction the one-sided bounds invert on, and no other test covers
  it.
- **Repair advances `updatedAt` and cleans the poisoned one** — assert the
  repaired blob is accepted by peers on the content path, and that the
  `updatedAt` the broken clock stamped does not survive the repair.
  Mutation-proved by rebuilding only `existenceAt`: the repair is discarded at
  equal `updatedAt`, and where it does land it carries the poisoned `updatedAt`
  fleet-wide, so every honestly-stamped later edit loses.
- **One unacceptable peer does not veto a repair** — ten peers with acceptable
  values and one without; assert the record repairs against the ten.
- **A quarantined record cannot outrank an unacceptable peer value** — a peer
  whose own clock is wrong holds a value this device would reject; assert the
  repair excludes it rather than exceeding its own ceiling, and that the
  remaining divergence is reported. This is the stated residual, asserted rather
  than assumed away.
- **A repeated rejection is reported once per session** — run three passes
  against a peer still advertising the bad blob; assert one report, not three.
- **A tombstoned dance neither merges nor suppresses** — same title and identical
  choreography, one copy deleted: assert no silent merge, the deletion stands,
  and a *different* device's independently created live duplicate is untouched.
  The second half guards the property that dances have no `UNIQUE` key, so
  existence does not travel across UUIDs the way it does for choreographers.
- **The rule survives clock skew in both directions, end to end** — run the
  revival with the reviving device's clock set behind the deleting device's, and
  the deletion with the deleting device's clock behind a prior revival's. Assert
  the revival wins in the first and the deletion wins in the second, **through a
  full sync pass on a bystander device**, not by calling the comparison directly.
  Mutation-proved three ways, because each leaves the others passing: stamp
  `existenceAt` from a bare clock (fails one direction); stamp it causally on
  only one of the two transitions (fails the other); and re-add the existence
  test as a condition ANDed with `updatedAt` recency on the `same`/`changed` row
  rather than deciding before it — which passes a direct comparison test and
  still reverts the revival end to end. That last mutation is the one an
  implementer is most likely to write, and a test scoped to the comparison alone
  certifies it as correct.
- **A restore converges rather than diverging** — restore a backup taken before a
  record was deleted and synced away; assert the device fresh-attaches and ends
  agreeing with its peers that the record is deleted, rather than republishing it
  forever. Mutation-proved by leaving the baseline in place, which produces a
  permanent one-device divergence with no error.
- **`existenceAt` crosses a device boundary** — A un-deletes a record B tombstoned;
  assert the blob A publishes carries `existenceAt`, and that B, reading only that
  blob, revives its own copy. The gate is a cross-device rule, so it needs a test
  that actually crosses devices rather than asserting the outcome locally.
- **A later sync write does not erase a revival** — after A revives a record,
  reconcile an unrelated collision that rewrites one of its references, forcing
  `updatedAt` to advance and the blob to be re-uploaded. Assert `existenceAt` is
  unchanged and the record still out-ranks the tombstone. Mutation-proved by
  carrying the signal as a boolean `userInitiated` on the write, which the
  re-upload flips to false and the revival is lost — this is why the field is a
  timestamp.
- **A stale device's ordinary edit does not revive** — D edits a record it never
  learned was deleted; assert `existenceAt` is not advanced and the deletion applies
  on D. This is the sticky-deletion trade asserted rather than assumed, and its
  counterpart is the deliberate-revival test above.
- **Queuing a review item is idempotent** — run three passes over the same
  unresolved collision; assert one row, not three. Guards the unattended device
  that syncs for a week before anyone looks.
- **A queued pair is not resolved behind the user** — assert neither record is
  merged or dropped by a later pass while the item is pending.
- **Alias retention is content-bounded** — merge on A, let the store stay alive
  through A and B for longer than the TTL, then return C from a long absence
  still holding the losing id. Assert C's records resolve and no duplicate is
  re-inserted, because C's own manifest still listed the losing id and so kept
  the alias alive. Mutation-proved by pruning on the store's clock instead, which
  drops the alias while C still needs it. An earlier draft asserted a per-device
  watermark rule that no endpoint could satisfy; this asserts the rule that can
  actually be computed from the manifests each pass already fetches.
- **A pending-held row is advertised as a tombstone, never as live** — assert the
  holder's manifest carries the tombstone and its baseline entry is not advanced.
  Mutation-proved twice: publishing it live lets the deleting device download its
  own deletion back, and omitting it entirely breaks the fresh-attach case below.
- **Fresh attach stays referentially closed across a pending hold** — A holds a
  deletion pending and still advertises a dance citing the entity; a clean device
  F attaches. Assert F's batch commits and F does not land with a dance crediting
  a tombstone. This is the case that fails if the entity is withheld from the
  manifest, and the one fresh attach's own "no deletion processing" rule would
  otherwise skip.
- **Fresh attach resolves one id carrying conflicting content** — two peers
  advertise the same id with different hashes; assert the higher `updatedAt`
  wins. There is no baseline at fresh attach, so this rule has nothing else to
  fall back on.
- **Fresh attach against a deleter, a pending holder and a stale peer** — F
  attaches while B advertises a tombstone, A advertises the same tombstone from
  its pending hold, and D still advertises the entity live. Assert F applies the
  deletion, and that D's stale live copy does not revive it because its
  `existenceAt` still predates the tombstone's. The three-peer combination is the
  one the two other fresh-attach tests miss, and it is where the superseded
  "advertise nothing" model produced the opposite outcome. F has no baseline and
  no prior relationship with any peer, so this is also the test that proves the
  rule is evaluable from the blobs alone.
- **An epoch reset does not discard a pending deletion** — hold a deletion
  pending, force a `409`, and assert that after the fresh attach the entity is
  still deleted rather than republished live. Mutation-proved by clearing
  `pending_deletions` with the baseline, which resurrects it via "upload every
  local record".
- **A pending-held record is excluded from the merge table** — assert it is
  neither uploaded nor treated as a conflict while held, despite its published
  manifest hash differing from its baseline hash. Mutation-proved by feeding the
  published manifest hash into the merge comparison, which routes a stable hold
  to upload every pass.
- **A removed-then-returning device does not resurrect a merged row** — call
  `DELETE /v1/manifests/{deviceId}` for a dormant device, let the alias prune,
  then bring it back. Assert its unresolvable references are skipped and reported
  rather than re-inserting the merged-away duplicate or discarding the batch.
- **A live record never out-ranks an applied tombstone** — the same provenance
  gate as the pending case, asserted on the device that performed the deletion.
  Mutation-proved by letting the merge table's plain `updatedAt` comparison
  decide, which lets a third device's reconciliation undo the deletion.
- **Review items are keyed canonically** — queue the same collision from both
  sides, with the roles swapped; assert one row. Mutation-proved by keying on
  (local, incoming) order, which yields two.
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
| Settings merge granularity | Per-key blobs, plus an `updated_at` column on `settings` at **schema v23**, stamping existing rows at migration time. |
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
