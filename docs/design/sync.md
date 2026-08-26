# Design: Device Sync and the Athenaeum protocol

> **Decision record:** [ADR-004](../adr/004-device-sync-and-athenaeum.md).
> **Normative specification:** [sync-spec.md](sync-spec.md).
> **Execution plan:** [sync-implementation.md](sync-implementation.md).
>
> Four documents, four jobs. The ADR decides *what* we build and why. The
> specification states *what a conforming implementation must do*, without
> argument. The implementation plan sequences the work — units, dependencies,
> checkpoints — and carries no behaviour of its own. This document holds the
> *reasoning* — the alternatives considered, the defect each rule prevents, and
> the drafts that were wrong. Build from the specification; come here to find
> out why a rule is the way it is.
>
> If the ADR and this document disagree, the ADR wins. If the specification and
> this document disagree, that is a defect in one of them.

**Status: design rationale. Only the schema migration is built** — v25, shipped
early so its soft-delete columns hydrate across devices before sync code depends
on them (see ADR-004, *Implementation status*). Everything else here is unbuilt:
no client, no server, no network code.

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

A *column* with no classification cannot exist: that half of the coverage
ratchet reflects over the drift schema, so it sees every column and CI fails on
a gap.

**Settings keys are different, and the serialiser must handle it.** Their half
of the ratchet walks the source for `const String k…Key = '…';` declarations, so
it covers only keys that exist as declared constants. The editor drafts do not:
they are built at runtime from a prefix (`editor_draft:<id>`,
`program_editor_draft:<id>`) whose constants are named `…KeyPrefix` and are not
matched by that pattern.

This design found that gap while checking an earlier review round and filed it
as #923; the maintainer ruled both prefixes `deviceScoped`, and #973 closed it.
`settings_registry.dart` now carries `settingsPrefixClassifications` alongside
the exact map, and `classifySettingsKey` resolves a runtime key against both —
exact first, longest matching prefix second. Both keys that motivated this
paragraph are classified today, and being `deviceScoped` they are excluded from
sync by the ordinary allow-list, not by the fallback.

Two obligations survive that fix. The serialiser MUST resolve through
`classifySettingsKey` rather than reading the exact map directly, because a
future prefix classified `shareable` would otherwise resolve to nothing and be
dropped from sync. That failure is safe but invisible — fail-closed produces
exactly the outcome a correct lookup produces for a `deviceScoped` prefix, so
the bug is indistinguishable from the rule working, and the coverage ratchet
cannot see it because the registry entry exists and it is the *lookup* that is
wrong. And `classifySettingsKey` still returns null for a key in neither map,
so a genuinely unclassified key remains possible; fail-closed is what makes
that safe. `sync-spec.md` §3.3 states both rules, and filtering is expressed as
an allow-list of `shareable` keys precisely so that an unclassified key is
excluded by default rather than admitted by default.

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
is a schema change **beyond the sync migration**, belonging to the sync
implementation rather
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
`skill_level_7f3a9c2b`, taking the loser's first eight hex digits. The suffix is
a pure function of the losing UUID, so every device derives the same key without
coordinating, and a third device carrying a third type yields a third distinct
key instead of contending for the same one. A
counter would not be collision-safe: `custom_field_defs.key` is `UNIQUE`
(`CustomFieldDefs.key` in `tables.dart`), so minting a `skill_level_2` that already exists — created
by the user, or by an earlier reconciliation — violates the constraint, fails the
apply transaction, and fails every retry identically. That is precisely the
deadlock *Renames collide too* exists to prevent, and it would be reintroduced by
the mechanism meant to avoid a crash. Should a derived key collide even so — two
distinct losing UUIDs sharing a 32-bit prefix — the suffix becomes the losing
UUID in full, in a single step, rather than routing back through reconciliation,
which is what produced the collision and would simply produce it again.
Progressive lengthening was rejected for the same reason a counter was: each
intermediate length is a state two devices could disagree about, whereas one
jump to the full UUID gives every device the same second candidate and cannot
collide again, since distinct losers differ somewhere in their 32 digits.

That second candidate is coordination-free in the same sense the first is: every
device that escalates reaches the same key. But *whether* to escalate is not.
"Already taken" can only be asked of local state, and reconciliation runs against
whatever peer manifests a device has actually observed, so a device that has seen
the conflicting def escalates while one that has not keeps the short form. The
two are not forked — both rows carry the same losing UUID, so the first pass in
which those devices meet resolves them by the ordinary UUID-known-locally path,
and a residual name clash routes to the review queue. Worth separating out
because the coordination-free property is the thing an implementer will lean on,
and it is weaker in the escalation branch than in the derivation above it.

`sync-spec.md` §6.6 states the derivation normatively.

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
| Per-record last-seen hashes — wire and `body`-scoped | Baseline table | `deviceScoped` |
| Id aliases (`losing_id`, `surviving_id`, `kind`) | `id_aliases` | `deviceScoped` |
| Pending deletions — markers (`kind`, `record_id`, `tombstoned_at`, `tombstone_hash`) | `pending_deletions` | `deviceScoped` |
| Pending deletions — retained tombstone bytes (`tombstone_blob`) | `pending_deletions` | `shareable` |
| Deferred review items (`kind`, `record_id`, `counterpart_id`, `reason`, `candidate_blob`, `candidate_hash`, `queued_at`) | `review_queue` | `deviceScoped` |
| Records this device has published (`kind`, `record_id`) | `published_records` | `deviceScoped` |
| Rows the normalisation pass could not repair (`table`, `column`, `record_id`) | `normalisation_skips` | `deviceScoped` |

**Three of these are scoped to the store identity**, and `id_aliases` and
`review_queue` are additionally scoped to the epoch and cleared with the
baseline. Each records a conclusion drawn *about a particular store* — that two
ids were merged, that a pair needs adjudicating — and neither conclusion survives
a different store or a re-seeded one. `published_records` is one exception, for
reasons given below: it records an event rather than a conclusion, and events do
not stop having happened when the store changes.

`normalisation_skips` is the other, and it is the odder of the two because it is
not store state in any sense. It records that two rows in **this library** hold
values that collapse onto the same `UNIQUE` string — a fact that is true before
the device ever attaches, stays true while it is attached, and is still true
after it detaches. Nothing about a store makes it true or false, so neither an
epoch reset nor a detach may clear it. The trap is that its nearest visible
neighbours do clear, and an implementer reaching for the obvious precedent
drops owed repairs on every `409` while the completion marker goes on asserting
the scan is finished. Restore is the one event that clears it wholesale,
because a restore brings in rows the scan never saw — and that holds for a
merge-mode restore as much as a full replace, since both write rows the pass has
not judged.

Individual entries retire on one further event: the row they name being
**hard-deleted**, which an ordinary import undo already does. An entry that
outlives its row can never be written, so it would never clear, and retry would
have no stored value to re-derive from. That retirement belongs in the retry
loop rather than in the delete paths — a polymorphic `record_id` spanning three
tables cannot carry `ON DELETE CASCADE`, and a self-healing consumer beats an
obligation on every delete path anyone adds later. A *soft*-deleted row is not
retired: its tombstone still occupies the key, so the repair is still owed.
Telling those two apart needs a read that ignores `deleted_at`, which does not
exist in any of the three repositories today — every `getById` there filters,
so both states return `null` and the natural implementation retires both. That
lookup is new work, and it is called out in the plan because the rule reads as
though it were free.

The table carries a primary key on `(table, column, record_id)` and recording is
an upsert, because a duplicate entry would make a row block itself: the retry
test asks whether any *other* recorded row derives the same target, and a twin
answers yes forever.

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
still citing it. On **detach** `pending_deletions` clears along with the baseline
and the aliases, because the user has left the store entirely.

Leaving *those three* unscoped is wrong in the other direction, which is why the
scoping is stated rather than left to the implementation: retained across a
*detach*, a stale `pending_deletions` row would suppress an entity from the
manifest of an unrelated store indefinitely, and a stale alias would silently
redirect ids that mean nothing there. `published_records` is the deliberate
exception and is argued for separately below — the distinction is whether the
row means anything once the store is gone.

**`published_records` does not take that lifecycle, and the reason is worth
spelling out, because the intuitive reading is wrong.** The hard-delete
forfeiture rule asks a question the baseline cannot answer. A baseline entry
advances only where a peer was observed carrying this device's hash, so it
records *agreement*; forfeiture turns on *exposure*, which begins one step
earlier, when the manifest is `PUT`. Using the baseline would leave a one-pass
window in which a record is fetchable by every peer while the check still says
"never published" — and a hard delete inside that window is the resurrection
loop the rule exists to prevent, since the peer that downloaded it keeps
republishing a row this device can no longer tombstone.

So it is its own marker, written before the `PUT` rather than after it: a crash
between the two over-marks instead of under-marking. Those are not equivalent
mistakes, and the asymmetry is the whole design of this table. An under-mark
loses the guarantee silently; an over-mark leaves a tombstone where an undone
import should have left nothing, which is a real cost — it is precisely what
`VenueRepository.hardDelete`'s exemption exists to avoid — but a visible and
recoverable one.

**The first draft cleared it on detach, and that was wrong.** The reasoning was
that re-attach is a union which deletes nothing, so a hard delete made while
detached "loses to the union rather than looping". That is true about the *loop*
and silent about the *outcome*. Walk it: A publishes R and marks it; A detaches,
clearing the marker; A's import undo hard-deletes R, which the check now permits
because R reads as never published, so **no tombstone is written**; A re-attaches
and unions against peer B, which still holds R live. R is downloaded back. The
user's deletion is reversed, with nothing to report it — the shape of #903,
reached through the detach path rather than the undo path.

What makes it wrong is not that the rule was insufficiently cautious. It is that
**detach does not un-publish anything.** Detach forgets the sync ID locally and
leaves this device's manifest on the server; there is no `DELETE
/v1/manifests/{self}`, and a blob stays reachable while any manifest for its
store references it. So the marker's claim — these bytes left this device and
peers can still fetch them — remains literally true after a detach. Clearing it
records a falsehood, and every consequence follows from that one error.

The correction is that `published_records` is **not store-scoped state at all**,
which is why the analogy to `pending_deletions` misled. The other three tables
hold conclusions *about a store*: which ids were merged there, which pairs need
adjudicating there, which deletions are owed there. All of those stop meaning
anything when the store does. This one holds a physical event — bytes left the
device — and an event does not stop having happened. It is monotonic: written
once, never cleared by an epoch reset, a detach or a restore.

That also settles retirement, which `id_aliases` gets and this deliberately does
not. An alias retires once no current peer manifest lists the losing id; that
bound is unavailable here, because *this device's own manifest* is one of the
manifests keeping the record reachable and it outlives the detach. The failure
modes decide the rest: a wrongly-retired alias skips one record and reports it,
whereas a wrongly-retired marker silently resurrects a deletion. Permanence is
therefore required rather than merely tolerated, and the cost is small — though
not by the comparison that first suggested itself. Each row is smaller than the
baseline entry for the same record: a `(kind, record_id)` pair against a pair
plus a hash. But that compares row size, not trajectory. The baseline is rebuilt
on an epoch reset and drops records that are purged; this table is rebuilt by
nothing, which is the whole point of it. So on a device with churn the marker
table will hold *more* rows than the baseline, and "smaller than the baseline"
is a bound that quietly stops holding at exactly the moment anyone would want to
lean on it. The figure that actually bounds it is absolute: tens of bytes per
pair, one per record ever published, so a device that has published 100,000
records over its lifetime carries a few megabytes. An entry is kept even after
its record is tombstoned and purged.

Stale entries after a restore are inert and need no revalidation for the same
reason they need no clearing: the marker is consulted only when deleting the
record it names, so one naming a record the restore removed is never read, and
one naming a record the restore brought back is still correct.

Every row is per-installation protocol state, meaningless on another device, and
adding them means a schema change **beyond the sync migration** — which the
implementation issue
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
| Inbound validation | Out-of-range `existenceAt` *or* `updatedAt` rejected, never clamped |
| Quarantine repair | Rebuilds only out-of-window fields, from peers sound in that same field; keyed on the baseline for `updatedAt` |
| Repair's missing-baseline branch | Never-agreed only; upgraded and wiped entries take other paths |
| Quarantined records | Excluded from merge table and union; manifest advertises last agreed hash; records citing them withheld to a fixpoint over database-FK references, `venueId` exempt |

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

##### A rule's scope is its wording, not its motivating case

> **When a rule is written for a case, enumerate the other cases its own wording
> will also govern** — the empty set, the symmetric actor, the sibling branch —
> and derive the behaviour there before shipping it.

The eleventh habit, and the one that describes three findings from a single
revision:

- *"It also restamps `updatedAt`"* was written for the branch where local and
  peer state differ. The wording governs the agree-branch too, where it
  contradicted that branch's own guarantee and turned a local cleanup into a
  content push that could lose a peer's genuine edit.
- *"When every observed peer value lies outside the local window"* was written
  for a device surrounded by disagreeing peers. The wording is vacuously true of
  **zero** peers, which would condemn every solo install on no evidence.
- *"Each stamps above the greatest it observed"* was written for one repairer
  against its peers. The wording governs two repairers running at once, who
  observe the same set, compute the same value, and tie.

The failure is not sloppiness about the motivating case — each rule is correct
there. It is that a rule's scope is fixed by how it is written, and the cases it
silently acquires are the ones nobody derives. The three worth checking every
time are the **empty input**, the **symmetric actor** doing the same thing
concurrently, and the **sibling branch** the wording also reaches.

##### Reconciling two texts is not resolving the question they disagree about

> **When two statements of the same mechanism disagree, find the question neither
> answers before making them consistent.** Consistency reached by giving each
> answer its own branch hides the open question instead of closing it.

The twelfth habit, and the one that cost this design a full round. Two documents
specified different `updatedAt` restamps; the fix made them agree. But they had
drifted apart *because* an underlying question had never been answered — what
should repair do with a large local value it cannot classify? — and each text had
absorbed a different half of it. Making them consistent produced one rule
containing both halves, keyed on a condition orthogonal to the question, with a
guarantee attached to each branch that the other branch falsified.

The tell was available and unusually concrete: **two entries in the test list
demanded opposite outcomes from the same input.** Prose can disagree with itself
quietly for a long time, but a test list cannot — two tests that cannot both pass
are a decision that has not been made, written down in the one place where that
is unambiguous.

So when a fix consists of making two statements match, check whether it also
determines an answer. If the answer differs by branch, ask what distinguishes the
branches, and whether that distinction is actually the one the question turns on.
Here it was not: the branch condition was live-or-deleted agreement, and the
question was poisoned-versus-genuine, which are unrelated.

##### Check a classifier against the case where it diverges from the question

> **State the question a classifier must answer, then find a case where the
> chosen signal and the question give different answers.** If that case is
> reachable, the signal is a proxy and not a classifier.

The thirteenth habit, and the one this design has now paid for twice in
consecutive rounds. Each time the need for a classifier was correctly identified,
and each time the nearest available observable was reached for instead of the one
that answers the question:

- live-or-deleted agreement, for *poisoned versus genuine* — orthogonal;
- content-differs-from-peer, for *edited versus stale* — agrees in the common
  case and diverges exactly when the local copy is behind.

The second is the more instructive, because the signal is not merely orthogonal
but **anti-correlated on the cases that matter**: a forward-poisoned discriminator
wins every content merge, so it *manufactures* the staleness that makes
"differs" mean the opposite of what the rule assumed. A proxy that is right in
the common case and wrong in the mechanism's own motivating case is worse than an
obviously bad one, because nothing about it looks wrong when read.

The tell in both rounds came from the test list, and the failure mode is worth
separating from the twelfth habit's: there, two tests could not both pass; here,
a single test could not pass *at all* under the rule it accompanied. A test that
contradicts its own rule is a decision made twice, differently, in two places.

And the remedy both times was already present in the design: the acceptance
window for one question, the baseline for the other. **Before inventing a
classifier, look for the one the design already uses to make the same
distinction** — a mechanism that already separates "I changed this" from "I
haven't caught up" is worth more than a fresh signal that seems to.

##### A comparator's granularity is part of the classifier

> **When a classifier compares two things, check that the comparison's
> granularity matches the question.** The tell is an answer that goes *constant*
> — always-differs or always-matches — in exactly the situation the classifier
> exists for.

The fourteenth habit, and the companion to the thirteenth: that one checks
whether the *signal* answers the question, this one whether the *measurement*
can. Both are needed, and picking the right signal with the wrong granularity
fails just as completely.

The whole-blob content hash defeated two consecutive attempts at the same
comparison. Against a peer it could never report *equal*, because repair only
runs when the ordering fields differ. Against this device's own baseline it could
never report *matches*, because poisoning is a timestamp-only change and the hash
covers timestamps. One comparator, two opposite degeneracies, both invisible in
the common case and both total in the case that mattered.

A hash is especially prone to this, because its convenience hides its scope: it
is one value, cheap to compare, already computed for another purpose — and that
last part is the trap. **A value computed for one question is not automatically
the right measurement for another**, however closely the two are related.

##### A convenience must consult the principles the document already settled

> **Before smoothing an edge case, search for the principle the smoothing might
> contradict.** The tell is a new rule whose motivation is ergonomic — "don't
> fail on arithmetic", "avoid a spurious warning" — rather than derived from the
> mechanism's own invariants.

The fifteenth habit, and a failure mode this document only became large enough to
suffer from recently. A clamp was added so a repair would not fail "on arithmetic
at the last tick". It was unsound, and both halves of the argument against
it were already written down in other sections: that clamping a comparand into a
comparison manufactures ties, and that a tie in this particular comparison loses
to the tombstone. Neither had to be discovered. The new rule simply did not
consult them, because it did not feel like a decision — it felt like tidying.

That is the distinguishing quality worth watching for. A rule introduced to
*answer* something gets checked against the design; a rule introduced to *smooth*
something often does not, and a long document will not re-derive a point it has
already made when the same shape reappears three hundred lines away under a
different name.

A useful sanity check on any such rule: work out the exact conditions under which
it fires. The clamp turned out to activate only when the selected peer sat
precisely at the ceiling — which is exactly the case where clamping produces a
tie — so its entire domain was the case it broke.

##### A narrowing must be keyed on its precondition, not on an observable

> **When a rejected signal is re-admitted under a narrowing, name the
> precondition the narrowing actually requires, then enumerate every path that
> produces the narrowing's *observable* without that precondition.**

The sixteenth habit, and the deepest version of the eleventh: there a rule's
scope was fixed by its wording; here a *precondition's* scope is fixed by
whatever the implementation actually tests for.

The worked example is the local-versus-peer content comparison, rejected as a
general classifier for conflating "I edited" with "I am stale", then correctly
re-admitted in one branch where staleness cannot arise. The precondition is
**"this device has never agreed on this record"** — sound, and enough. What the
rule tested was **"there is no baseline entry"**, which is a different statement:
five paths produce a missing entry, and only one of them means never-agreed. The
upgrade path that violates it was described seventy lines below the argument
asserting it could not happen, in the same revision.

The instinct to narrow is right and worth keeping. The discipline is to write the
precondition down as a sentence about the world — not about a field — and then
ask what else can make the field look that way. A precondition tested by proxy is
a precondition that holds until someone adds a fifth way to clear a table.

##### The scaffolding gets less scrutiny than the fix

> **Apply the checks to the rules added to *support* a fix, not only to the fix
> itself.** The supporting rule is where the next defect lives, because the fix
> is what is being reasoned about and the scaffolding is what is being assumed.

The seventeenth habit, and the fifteenth at a different scale: that one separated
conveniences from answers, this one separates a load-bearing correction from the
rules introduced to make it work.

One revision produced three defects of this shape at once, none in the correction
itself. "A quarantined record is never uploaded" was added to protect the fix and
shipped without the advertise-versus-withhold analysis its sibling rule — pending
tombstones — had received in full, leaving a manifest entry pointing at a blob
nobody could fetch. A replacement diagnostic shipped claiming to need no state,
having inherited that phrase from mechanisms that genuinely need none. And a
safety branch shipped with a cost of "a pass of delay" that nobody traced — three
existing rules formed a closed cycle around it and the wait was indefinite.

Each was checkable by a habit already written down. What they had in common was
attention: the fix was the thing under examination, and these were the things
holding it up. **A rule you add without hesitation is a rule you have not
examined** — hesitation is what triggers the checks, and scaffolding rarely
produces any.

##### Follow a changed value to its readers, not to its neighbours

> **When a rule changes what a value *means*, trace that value to everything that
> reads it.** Neighbouring rules are the ones you will check anyway; the readers
> are a section away, and that is where the defect lands.

The eighteenth habit, and the fourth inverted: that one asks what data a rule
reads and whether the path can reach it, this one asks who reads what a rule
writes.

The manifest gained a second meaning in one revision — for quarantined records it
began advertising a last-agreed hash rather than the current one — and that
change was reasoned carefully against the pending-tombstone rule sitting beside
it. Its *readers* were elsewhere: the baseline-advance trigger, which would have
taken this device's own fallback echoing back as agreement; the steady-state
merge table, which had no idea quarantined records existed at all; and
referential closure, where omitting a record left the device free to publish
another that cited it. Three sections, three defects, one changed meaning.

The tell is a value that now means different things in different places. That is
sometimes correct — the pending-tombstone rule deliberately holds two hashes for
one record — but it is only correct when every reader has been told which one it
gets, and a document large enough to have distant readers will not tell them by
itself.

##### Read the tests before changing a rule

> **When a rule changes, read the tests that assert it first.** They are the
> compressed form of every prior round's conclusions, and they are where the
> previous answer is written most precisely.

The nineteenth habit, and the cheapest one here. A revision inserted a new
disposition — "adopt the peer's record wholesale" — immediately ahead of an
existing sentence giving the *same condition* the opposite outcome, leaving two
contradictory instructions in one paragraph with the old sentence's tail carried
forward unedited. Not a reasoning failure but an editing one, which is a distinct
hazard in a document this size.

Two tests already said "stays quarantined", and one of them explicitly asserted
that passes do **not** clear the record and only a local write does. Reading them
first would have surfaced the contradiction before the sentence was written,
because the test list states outcomes without the prose's room for
interpretation. It is also the fastest available check: the tests are a few
hundred lines, and they encode what every earlier round concluded.

This is the twelfth habit with a search order attached. Where that one says two
disagreeing statements mean an unanswered question, this one says where to look
for the answer that was already given.

##### An elaboration can be wrong where the decision is right

> **A clause added to scope or justify a correct rule is as capable of being
> false as the rule itself, and gets a fraction of the scrutiny.** Check a
> narrowing against the thing it claims to narrow, and a justification against
> the code it claims to describe.

The twentieth habit, and the last one produced before this document was split.
Two defects survived
into a closure audit, in one paragraph, both of this shape. The fixpoint rule was
right; the clause scoping it to FKs "with cascade or restrict semantics" named a
semantic this schema does not contain and excluded both edges the fixpoint
existed for. The venue exemption was right; the sentence explaining it asserted
that a program with a dangling `venueId` "commits fine", where the repository
throws.

In both cases the decision survived review and its supporting clause did not, and
in both cases the clause was checkable in one grep. That they appeared together,
in one paragraph, in the round that produced no other defect, is the tell: the
attention went to the rule, and the sentences around it were written as though
explaining a settled thing carried no risk.

The ADR states both points correctly, and states them in one line each. It was
right precisely where it declined to elaborate — which is not an argument for
saying less, since this document exists to be implementable, but is an argument
for treating every added clause as a claim rather than as commentary.

##### Bounds are directional

A related and simpler slip. Every bound in the quarantine mechanism —
`localNow + 24h` for both rejection and quarantine — is **one-sided and upper**.
That is correct against a clock running fast and inverts entirely against one
running slow, which the same paragraph's own motivating hardware ("a dead RTC, a
mis-set year") does about as often. When a bound guards against a value being
wrong, ask which *direction* of wrong it catches, and whether the other direction
turns the guard into its opposite.

##### Moving a rule is a revision

> **When rules are extracted, split, or restated into another document, run the
> propagation checks over every rule that moved — not only the ones reworded.**
> A rule that arrives without its convergent formulation, its limitation entry
> or its test has been dropped, even though the text it came from is unchanged.

The twenty-first habit, and the first produced after this document was split.
Extracting `sync-spec.md` relocated the whole rule set, and four rules did not
survive the move intact. The custom-field rename kept the *argument* for its
suffix — "derived from the losing UUID, not a counter" — and lost the derivation
itself, leaving a convergence rule that two conforming implementations could
implement incompatibly. The equal-`updatedAt` tie lost the merge-table row, the
limitations entry and the conformance test, all three, while the existence
section went on citing it. The unreflected-uploads report lost its "at least one
peer observed" guard while the sibling diagnostic one sentence earlier kept the
identical clause.

None of those was a changed ruling, which is why the propagation habit above did
not fire: that one is worded for a ruling that changes, and here nothing
changed. The text moved. That is precisely when a rule can arrive stripped of
the parts that made it work, because attention goes to whether the sentence
survived rather than to whether the *rule* did.

The check that catches it is to read each relocated rule against the new
document's purpose rather than against its source. Not "does this match what
`sync.md` said" — the rename suffix matched its source sentence exactly and was
still unimplementable — but "could someone build this from here, with the source
unavailable". A document meant to stand alone has to be checked alone.

## Wire format

All payloads are UTF-8 JSON. All requests and responses may use
`Content-Encoding: gzip`.

**Timestamps are emitted at one-tick precision, and truncated to a tick on
ingest.** The receiver truncates rather than trusting the sender, and does so
before storing *and* before hashing.

That asymmetry is deliberate, because the failure it prevents is remotely
triggerable and permanent. The content hash is computed over each device's
**own** re-serialisation of a record, not over the bytes it received. So a peer
emitting a sub-tick value the local column cannot represent gets it stored
truncated, re-serialised differently, and advertised under a hash that disagrees
with the sender's — on every subsequent pass. The merge table reads that as
`changed`/`changed` in perpetuity and the record never converges. One value with
a stray fractional second is enough, from a buggy peer or a hostile store, and
nothing downstream would ever repair it because both sides are behaving
correctly by their own lights.

Truncating on ingest closes the round-trip: every value that reaches storage is
already at the precision storage keeps, so re-serialisation is a fixed point.
This is the same class of defect as the `+ 1ms` no-op — an assumption about
timestamp precision that was never checked against what the database actually
stores — and it is why the canonicalisation rules now state precision explicitly
instead of leaving it to whatever `toIso8601String` happens to emit.

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
- `updatedAt` — the conflict discriminator. UTC, one-tick precision.
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
existenceAt = max(localNow, currentExistenceAt + 1 tick)
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

#### The increment is one *tick*, and that is not a detail

This rule said `+ 1ms` for most of its life, and at this storage precision that
was a **silent no-op**. Drift persists a `DateTimeColumn` as a unix *second*
count — there is no `build.yaml` in this repository, so the default applies, and
the v23 fixture confirms it empirically: `dances.updated_at` for
2026-01-01T00:00:00Z is the integer `1767225600`, not `1767225600000`. A
millisecond added to a value that is about to be truncated to a second does not
survive the write, so `max(localNow, current + 1ms)` returned a value equal to
the one it was supposed to exceed.

The consequence was not theoretical. Deleting a record and undoing that deletion
within the same second stamped the revival *equal* to the tombstone, and the
standing rule resolves a tie to deleted — so the undo silently lost. An Undo
snackbar is exactly that interaction.

So the increment is defined as **one tick: the smallest interval the storage
representation can distinguish**, currently one second. Every argument in this
document that turns on the increment is quantised rather than metric and holds
unchanged under that definition — the clamp analysis above, for instance,
concludes that `peer + 1 tick` exceeds the ceiling only at `peer == ceiling`,
which follows from values being multiples of a tick and is true whatever the
tick's magnitude. Writing the rule in terms of a fixed millisecond is what tied
it to a precision the database does not have.

The lesson generalises past this rule: **an arithmetic constant in a stamping
rule is a claim about the storage representation**, and this one was never
checked against it. The migration should pin the two together with a comment, so
that a later reader looking at `+ 1s` beside a millisecond-precision `DateTime`
API does not "tighten" it back into a no-op.

`updatedAt` and `deletedAt` are at that same one-second precision, and always
have been — the specification claimed millisecond precision for `updatedAt`,
which was simply false about the schema it describes. Nothing is being *changed*
there; it is being *documented*.

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

So a blob whose `existenceAt` **or `updatedAt`** exceeds `localNow + 24h` is
**refused as malformed and reported**, exactly like a record that fails to decode
— one record skipped, the batch intact, local state unchanged. This is stated as
a check to implement rather than assumed: `_dtOrNull` validates only ISO-8601
parseability and calls `.toUtc()`, and the codec's clamping is all string and
list length, so no date range check exists today.

**An honestly skewed value needs a repair path, because monotonicity makes it
permanent.** The reasoning above is about a hostile peer; the likelier case is
a device with a badly wrong clock — a dead RTC defaulting to a future build
date, a mis-set year — which stamps a transition at, say, 2036. Every honest
peer rejects that blob on every pass, so the originating device believes the
record deleted while every peer holds the opposite. And correcting the clock
does not fix it: `max(2026, 2036 + 1 tick)` is still 2036, so every later
legitimate transition on that record stays above the rejection threshold.
Without a repair path the record drops out of sync until wall-clock time
catches up, which is not a bounded divergence in the way the restore case is.

Three rules close it, and the repair happens **during a sync pass rather than on
a user gesture** — because that is the only moment the device can see what the
other copies actually hold:

- **A record is quarantined when `existenceAt` *or* `updatedAt` exceeds
  `localNow + 24h`, and an inbound blob is refused on the same test.** Both are
  stamped by the same clock — `softDelete` writes one timestamp into `deletedAt`
  and `updatedAt` together — so a broken clock poisons both, and a predicate
  watching only one of them leaves the other uncatchable. This is a derived
  predicate over existing columns, not new state, so it needs no schema.

  **Rejecting inbound on both fields is what makes the rest of this work.** An
  earlier draft rejected on `existenceAt` alone, reasoning that a bad existence
  value silently reverses a deletion while a bad `updatedAt` costs one
  recoverable edit. That is true about the *severity* of each, and it is not an
  argument for letting one in. Accepting a poisoned `updatedAt` puts it into
  circulation, and repair sources values only from peers — so once two devices
  hold it, 2036 is the only `updatedAt` in circulation for that record, there is
  nothing honest left to adopt, and the poison becomes stable consensus instead
  of a transient. Clock-suspect never fires either, because the device *does*
  observe an in-window value: the record's untouched `existenceAt`.

  With both fields refused at the door, **a poisoned value can only ever be
  local** — a device's own write is the only way one arrives. That is the
  property that already made the `existenceAt` rebuild sound, and extending the
  rejection extends the property.
- **Repair rebuilds only the out-of-window fields, and adopts observed values for
  them.** For each field being rebuilt, the device gathers the peers' copies of
  that record and **discards any whose value *for that field* falls outside its
  own acceptance window**, then takes the greatest of what remains. The filter is
  per-field because the poisoning paths are: an ordinary edit stamps `updatedAt`
  and leaves `existenceAt` untouched, so a peer can be perfectly sound on one
  field and poisoned on the other. Filtering both rebuilds on `existenceAt`
  alone would let such a peer be selected, and the device would adopt a value
  still outside its own window — re-quarantining the record immediately, for as
  long as that peer's clock stayed broken. **A rebuilt value is re-checked
  against the local window before the record is considered repaired**, and one
  that still falls outside it leaves the record quarantined — loud, contained,
  and honest about having failed.

  A draft softened that, clamping a value back to the ceiling when it failed
  "only because `+ 1 tick` crossed the boundary", so as not to fail on
  arithmetic at the last tick. Work out when that can fire: peers are
  pre-filtered to the window, so `peer ≤ ceiling`, and `peer + 1 tick` exceeds
  the ceiling only when `peer ≥ ceiling`. Both hold only at `peer == ceiling` —
  so the clamp activates **exclusively** in the case where it sets the rebuilt
  value equal to the peer's, and can never produce a strictly winning value. On
  the `existenceAt` branch that ties the peer's tombstone and the standing rule
  resolves a tie to deleted, so a user's un-delete is silently reverted,
  unreported, in the one situation the `+ 1 tick` exists to prevent.

  This document had already reached both halves of that conclusion, in two
  separate sections: that clamping a comparand into a comparison manufactures
  ties, and that a tie here loses to the tombstone. The convenience simply did
  not consult them.

  Then, per field:
  - `existenceAt`: adopt the peer value **verbatim** when the peers agree with
    the local live-or-deleted state; stamp `peer + 1 tick` when the local state
    differs, since only a local transition can have poisoned it, so a difference
    means the user made one and their intent must outrank the peers.
  - `updatedAt`: adopt the peer value **verbatim** when the local content matches
    **this device's own baseline** for the record; stamp `peer + 1 tick` when it
    does not, since only a local write can have poisoned it, so a difference from
    the baseline means this device edited and that edit must survive.

  A field that is **inside** the window is left exactly as it is, and a record
  with neither a baseline entry nor any peer copy — a new record on a
  clock-broken device — simply stays quarantined, since there is nothing to
  reconcile it against.

  **A missing baseline entry is resolved by what the entry's absence actually
  proves**, which depends on *why* it is absent. The three cases are
  distinguishable from state the design already keeps:

  - **No entry at all.** This device has never observed agreement on this record,
    so a peer's copy cannot have moved past an agreement that never happened.
    Compare local content to the peers': matching means nothing was edited since,
    and the verbatim branch is right — adopting **that peer's** `updatedAt`, per
    the pairing rule below; differing from every peer means this device holds
    content no one else has, which it can only have written itself, and the
    differs-branch is right.
  - **An entry with a wire hash but no body hash** — a record agreed under the
    previous scheme, whose body hash could not be migrated. Agreement *did*
    happen here, so the never-agreed comparison is unsound, and the wire hash
    cannot substitute for the missing body hash either: under the previous scheme
    it was written **on upload**, not on observed agreement, so its meaning
    changed at the upgrade boundary and "matches the stored wire hash" now proves
    only "nothing changed since I published", which is not the question.

    Where the local **body equals a peer's**, repair proceeds on the verbatim
    branch, adopting **that peer's** `updatedAt` — not the greatest across the
    peer set. Content demonstrably never diverged from *that* peer, so there is
    no local edit to protect and nothing to decide; this is the
    `softDelete`-poisoned case, where the clock moved the timestamps and left the
    body untouched, and it is the common one.

    **The timestamp must come from the peer whose body matched.** Taking the
    global maximum instead pairs one peer's body with another's clock and
    produces a `(body, updatedAt)` combination that exists on no device: if peer
    B holds the pre-poison body and peer C genuinely edited it at a later
    in-window time, the local record would keep B's content while claiming C's
    recency. Against C that is `changed`/`changed` at **equal `updatedAt`**,
    which the strict-`>` gate moves in neither direction, so C's real edit could
    never displace stale content that now falsely claims C's timestamp — a
    breach of *content changes must move the discriminator* manufactured by the
    repair itself. **Repair must never leave a record at equal `updatedAt` with
    content differing from the peer that supplied that timestamp.**

    Where the body matches no peer at all, the record stays **quarantined and
    reported** until a fresh in-window local write replaces the poisoned stamp.
    A draft inserted a "wholesale adopt the greatest peer's record" rule here,
    reasoning that a body matching nobody means this device is stale rather than
    poisoned. That conclusion cannot be drawn on this branch, and drawing it
    loses data: a device whose clock broke and whose user then made a genuine,
    never-synced edit also matches no peer, and wholesale adoption silently
    overwrites that edit with older content. Quarantine's premise is that the
    device cannot trust its own clock, so it equally cannot conclude "I must be
    behind" over "I edited before anyone saw it" — the same reasoning stated two
    paragraphs above for the never-agreed case and three below for the union.
    Pulling a genuinely stale record forward is the download path's job once
    repair has cleared the timestamp, not repair's.

    **That second case does not resolve on its own, and an earlier draft said it
    would.** It claimed the record waits "a pass of delay" for agreement to
    populate a body hash; agreement is defined as a peer advertising this
    device's *current* hash, the wire hash covers the timestamps, and a
    quarantined record is never uploaded — so no peer can ever come to carry it,
    the body hash never populates, and the wait is indefinite rather than one
    pass. Three rules of this design formed a closed cycle, and the exit was
    asserted rather than traced. It is a narrow population — a record poisoned in
    the window between the schema upgrade and the first post-upgrade pass — but
    the honest statement is that a user write is what clears it.
  - **A wholesale-wiped baseline** — restore, fresh attach, epoch reset. These
    would be indistinguishable from "never agreed" and are not, because every one
    of them routes through fresh attach, which repersists the baseline before
    steady-state sync resumes. **Quarantine and repair run after that**, so a
    wipe never presents a record to this rule in the no-entry state.

  **Why the local-versus-peer comparison is sound in the first case only.**
  Rejected earlier as a general classifier, it conflated "I edited" with "I am
  stale", because a peer's newer content also reads as a difference. Staleness
  needs an agreement for the peers to have moved past; where no agreement exists,
  there is nothing to be stale relative to. That is the precondition, and it is
  worth separating from its observable: an earlier draft argued from "there is no
  baseline entry to have moved after", which reads as the same statement and is
  not — *five* paths produce a missing entry and only the first carries the
  precondition. The upgrade path that violates it was described seventy lines
  below the argument assuming it could not happen.

  Narrow the input enough and a rejected signal becomes sound; what is not sound
  is keying that narrowing on something merely correlated with it.

  **A quarantined record is never uploaded, and its manifest entry falls back to
  the last agreed hash.** A device does not publish a value it has itself judged
  impossible. But withholding a blob is not the same act as withholding a
  manifest entry, and the two have to be decided separately — the same
  distinction the pending-tombstone rule turns on:

  - **The blob is withheld.** Nothing publishes a poisoned value.
  - **The manifest advertises the record's last agreed hash**, whose blob peers
    already hold — the **wire** hash, which is what a manifest carries and what
    peers fetch by, and which survives the body-hash migration since it was never
    dropped. Advertising the *current* hash would name a blob nobody can fetch,
    and omitting the record entirely would break referential closure — a
    fresh-attaching peer that downloads a dance citing the omitted entity fails
    at COMMIT on the cascading foreign key and discards its whole batch, which is
    the failure the pending-tombstone rule exists to prevent.

    Advertising a hash older than what this device holds means peers may offer it
    their newer content, which is correct and harmless: this device is genuinely
    behind on that record until repair completes, and downloading a peer's record
    is how it stops being behind. What it must not do is *publish* its own
    poisoned value, and it does not.
  - **A quarantined record with no agreed hash** — created locally while the
    clock was already broken, so no peer ever held it — is omitted, **and any
    record citing it is withheld with it.** Omission alone is not safe, and the
    proof an earlier draft offered ("nothing on any peer can cite a record no
    peer has ever seen") is true of peers and false of this device. Quarantine is
    per-record: correcting the clock does not clear it without a fresh write to
    *that* record. So a device can create choreographer `C` while broken —
    quarantined, omitted — then correct its clock and create dance `D` citing
    `C`, where `D` is freshly stamped, in-window, not quarantined, and uploads
    normally. `D` is then in every manifest citing a record in none, and a peer
    downloading it fails at COMMIT on the cascading foreign key and discards its
    whole batch: the failure the pending-tombstone rule exists to prevent,
    reached through the door omission left open.

    Withholding is a **fixpoint over the publish set**, not a single-hop test.
    "Is what I cite quarantined?" answers *no* for a dance that is merely
    withheld rather than quarantined, so a program citing that dance would
    publish and a peer would fail at COMMIT on the same class of foreign key.
    `ProgramSlots.danceId` and `DanceLinks.targetDanceId` are real record-to-record
    edges, so Program → Dance → Choreographer chains exist. The rule is therefore:
    withhold any record referencing something **not in the manifest actually
    being published**, iterated until nothing more is removed — the same chase to
    a fixpoint the alias rule performs, and for the same reason. The evolving
    publish set is per-pass working state and outlives nothing, so it adds no
    schema.

    **`Programs.venueId` is exempt**, because the justification does not reach it:
    it is deliberately not a database foreign key — integrity is enforced at the
    app layer, and import paths already resolve-or-null a dangling `venueId`
    before persisting. The test is simply **whether the reference is a
    database-enforced foreign key**: `ProgramSlots.danceId` and
    `DanceLinks.targetDanceId` are, `Programs.venueId` is not.

    A draft narrowed that to FKs "with cascade or restrict semantics", which is
    wrong twice. `KeyAction.restrict` appears nowhere in this schema, and both
    edges the fixpoint exists for are `setNull` — so the clause excluded exactly
    what it was written to cover, and the second-hop test could not have passed
    against its own prose. The premise was wrong too: `ON DELETE` governs what
    happens when a *parent* is deleted, and says nothing about inserting a child
    whose parent is absent. That insert fails at COMMIT on a `setNull` FK exactly
    as on a `cascade` one, and that failure is the whole hazard here.

    **It does not self-clear on the same pass, and a draft claimed it would.**
    Dependents clear when the cited entity becomes publishable — which for the
    population that triggers this rule means never, by any pass: an entity
    created locally while the clock was broken has no peer copy and no baseline,
    and this document states elsewhere that such a record "simply stays
    quarantined, since there is nothing to reconcile it against." Only a fresh
    in-window local write to that entity clears it. So one quarantined
    choreographer can silently withhold every dance crediting them, indefinitely.
    That is a real cost of choosing correctness over availability here, and it is
    why quarantined records are **reported**: the count of records held back by
    each one belongs in that report, since the user is the only party who can
    resolve it and the only visible symptom otherwise is a collection that
    quietly stops syncing.

  In the union, a locally quarantined value is **excluded from arbitration and
  the local row is retained**, pending repair afterwards. It is not replaced by
  the peer's: a device holding a poisoned timestamp may still hold genuinely
  newer content, and discarding it before the classifier runs would lose a real
  edit — the round-20 defect reached one step earlier.

  A draft read a missing entry as agreement outright, reasoning that a record
  never agreed cannot have been edited *since* agreement. That does not follow —
  "never agreed" and "never edited" are different facts — and the round-18 change
  is what made them come apart: because nothing is written on upload, a device
  that creates a record, has it accepted, and then edits it before the next pass
  observes agreement holds **no** baseline entry and content no peer has. Read as
  agreement, repair would adopt the peers' older `updatedAt` while keeping the
  newer local content, stranding it at an equal timestamp behind a strict-`>`
  gate that moves nothing in either direction — the exact failure the round-18 fix
  was written to close, reached through a door that fix opened.

  **Agreement keys on the hash a peer actually advertises matching this device's
  current local hash.** That is stated because it is the choice the rule turns on
  and it was previously left implicit: a device does not remember what it
  uploaded, so it can only recognise agreement it can still see. The consequence
  is that agreement reached on content this device has since edited away from is
  never recorded — correctly, since by then the device *has* edited, and the
  content comparison above reaches the same answer without needing the memory.

  **A quarantined record never advances its baseline, whatever its manifest
  says.** Those two facts pull apart for exactly these records: the manifest
  advertises the last agreed hash while the device holds a poisoned current one,
  so a peer echoing the advertised hash would look like agreement on every pass
  under a rule keyed to "the hash it published". It is not agreement — it is this
  device's own fallback coming back to it — and treating it as such would
  populate a null body hash from the poisoned body and land the edited sub-case
  on the verbatim branch next pass, reopening the stranding defect. It would also
  falsify the deadlock analysis above, which holds precisely because agreement is
  keyed to the current hash and a quarantined record never publishes one.

  This is the same two-hashes-on-one-device split the pending-tombstone rule
  settled, and it is settled the same way: the merge and the baseline read the
  live row's hash, and the fallback substitutes only when the manifest is
  serialised.

  **The classifier must answer "did *I* edit", and only the baseline does.** A
  draft keyed the `updatedAt` rebuild on local content differing from *the
  peer's*, justified as "a genuine local edit must outrank the peer's copy". That
  substitutes an available signal for the needed one. Content can differ because
  the local copy is **stale**, and a forward-poisoned `updatedAt` *manufactures*
  staleness: a 2036 discriminator wins every content merge, so the poisoned
  device stops accepting its peers' newer content. On exactly the records repair
  handles, "differs" more often means "I am behind" than "I edited" — and the
  rule would then stamp the stale copy above the peer and push it fleet-wide,
  silently reverting a rename or an edit made elsewhere. The design's own test
  *"repair does not push stale content"* was unsatisfiable under it, because both
  branches yielded `updatedAt ≥ peer`.

  The baseline is the signal that answers the question, and this document already
  uses it for exactly this distinction — it is what the merge table calls the
  thing that separates "changed" from "not caught up". Local-versus-baseline is
  "did I write since we last agreed"; local-versus-peer is "are we the same right
  now", and only the first is what the rebuild needs to know.

  The comparison is **hash equality over the record's `body` alone**, against a
  body-scoped hash stored alongside the wire hash in the baseline table, using
  the same canonicalisation the wire hash uses so that `8` and `8.0`, or absent
  and null, cannot read as a difference.

  **It has to exclude the ordering fields, or it answers a different question.**
  The wire hash covers the whole blob — `v`, `kind`, `id`, `updatedAt`,
  `deletedAt`, `existenceAt` and `body` — so comparing it asks "is my record
  byte-identical to my last synced snapshot", not "did I edit the content". Those
  diverge in exactly the situation repair exists for: poisoning changes a
  timestamp and nothing else, so a whole-blob comparison reports "differs"
  unconditionally, and the classifier degenerates to "I edited" for every
  quarantined record. A device that soft-deleted while its clock was broken —
  `softDelete` writes `deletedAt` and `updatedAt`, never touching `body` — would
  be classified as having edited, and would stamp its possibly-stale content
  above the peers. That is the round-17 defect returning by another route, and it
  is the same whole-blob comparator that caused it: there it could never report
  *equal*, here it can never report *differs* falsely — the tell in both cases
  being an answer that goes constant precisely where the classifier is needed.

  **The baseline entry must record agreement, not merely upload.** A record's
  baseline entry advances only once a peer's manifest is observed to carry that
  hash; an upload this device has not yet seen reflected stays out of it.

  **Existing baselines cannot be migrated, and are dropped.** The baseline has
  only ever stored the wire hash, so a device already attached under the previous
  scheme has no way to derive a body hash for its rows — the content those hashes
  covered was never retained. Both obvious backfills reintroduce bugs this design
  has already closed: taking the *current local content* records an unconfirmed
  edit as agreed, which is the advance-on-upload defect applied to every record
  with an edit in flight at upgrade; and inventing any other value is a guess
  about content.

  So the body hash is **left null on upgrade and populated on the first pass that
  observes agreement**. In the interval, such a record is *not* handed to the
  never-agreed comparison — it was agreed, and the surviving wire hash proves
  that much — and it stays quarantined if quarantined at all, since the wire hash
  cannot stand in for the body hash it lacks. There is no safe backfill to write, which
  is worth saying outright rather than leaving an implementer to discover it:
  unlike the `existence_at` migration, where the wrong choice is available and
  tempting, here every choice that invents a value is wrong, and the only correct
  one is to admit the value is not recoverable.

  This was harmless while every well-formed upload was accepted, and stopped
  being harmless in the same revision that widened inbound rejection — the two
  changes landed together, which is what made "I uploaded" and "we agreed" come
  apart. With per-receiver rejection there is no failure signal back to the
  sender, so a device whose clock was fast could publish a poisoned blob, store
  it as its own baseline, have every peer refuse it, and then — once its clock
  was corrected — compare the poisoned record against a baseline set by the very
  write being repaired, match, and take the verbatim branch. It would adopt the
  peers' older `updatedAt` while keeping its own newer content: identical
  timestamps, different content, on a merge gate that requires strict `>`, so
  nothing uploads and nothing downloads and a genuine edit is silently invisible
  for ever. It would also move `updatedAt` *backwards* past content it now
  describes, breaking *content changes must move the discriminator*.

  A baseline named for what two devices last agreed on has to be advanced by
  evidence of agreement.

  The record's content and its live-or-deleted state are never changed by repair;
  only impossible ordering values are. The two copies end bit-identical exactly
  when both fields were adopted verbatim.

  **The window is the classifier for *which* values to rebuild, and that is the
  whole point.** `updatedAt`
  carries no signal separating "poisoned by a broken clock" from "genuinely newer
  local edit" — both are simply a large local value — so no comparison of
  *magnitude against the peer* can tell them apart. What does tell them apart is
  plausibility: a value the local clock says cannot exist yet is impossible and
  must be rebuilt, and a value inside the window is ordinary and must be kept.

  A draft of this rule keyed both fields on live-or-deleted agreement instead,
  which is orthogonal to the question and so resolved it oppositely in each
  branch. The differs-branch took `max(local, peer + 1 tick)`, which
  *preserves* a
  forward-poisoned `updatedAt` — 2036 dominates the max — while claiming to clean
  it; and because existence is decided first, the record's clean tombstone would
  then win and carry that 2036 fleet-wide, where nothing would ever catch it,
  since `updatedAt` had no window. Meanwhile the agree-branch adopted the peer's
  `updatedAt` verbatim even when the local *content* was a genuine newer edit,
  leaving content newer than the stamp claiming to describe it — a direct breach
  of *content changes must move the discriminator*, with the edit then discarded
  by every peer. The design asserted both "cleans the poison" and "preserves
  genuine edits" while its two branches each did one and broke the other.

  The tell was in this document's own test list, where two entries demanded
  opposite outcomes from the same input.

  **Both classifiers earn their place, and they answer different questions.** The
  window says *which* values are impossible and must be rebuilt; the baseline
  says *how* to rebuild `updatedAt`, by telling this device whether it wrote the
  record since it last agreed with its peers. Neither substitutes for the other,
  and the two failures of earlier drafts were each a case of one signal being
  asked a question only the other could answer.
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
`max(2000, 2026 + 1 tick)`, quarantines again, repairs down again — and the
peers'
live copies at 2026 outrank it, so the deletion is silently reverted. That is the
cardinal failure, reached through the one branch that still trusted the clock.

**When every observed peer value is outside the local window, the local clock is
the outlier, not the peers.** One device disagreeing with the fleet is the device
that is wrong. In that state it declares itself **clock-suspect**: it does not
repair and does not rebuild existence values, and it reports — because a device
that cannot tell what time it is cannot safely *reorder* what other devices
already agreed on. Records stay quarantined and diverged, which is stable and
loud, rather than silently wrong.

**Clock-suspect is defined precisely, because a state with no exit and no scope
is not a mechanism.**

- **It is derived, not stored.** It holds when, **across the pass as a whole**,
  at least one peer value was observed for some quarantined record and *every*
  value observed in that pass fell outside the local window. Set and clear are
  deliberately stated over the same aggregate: phrasing the set condition
  per-record and the clear condition over any value lets both fire in one mixed
  pass, which is harmless — the worst case is a deferred repair — but is the kind
  of quantifier mismatch this document has been bitten by before. Like quarantine
  itself it is recomputed each pass from data already present, so it needs no
  schema and no classification.
- **It exits by being recomputed.** The next pass in which any observed value
  falls inside the window clears it, with no explicit transition to store. A
  corrected clock therefore recovers on the following pass.
- **It reports; it no longer gates anything.** Once the `localNow` fallback was
  removed, per-record repair already could not proceed without an in-window peer
  value, so there is no remaining branch for clock-suspect to block. It is
  honestly a **diagnostic**: the name for the pattern "every value I can see
  looks impossible to me", surfaced to the user because that pattern has one
  overwhelmingly likely cause and the user is the only party who can fix it. It
  is described here as a state rather than a gate to avoid implying it changes
  behaviour that would otherwise occur.
- **Zero observed peer values is not clock-suspect.** "Every observed value is
  out of range" is vacuously true of the empty set, and concluding from no
  evidence that this device is the outlier would condemn a solo install, or any
  device syncing while its peers happen to be offline, on the strength of a fleet
  that was never consulted. With nothing observed there is no fleet to be an
  outlier against: the record stays quarantined and reported, and repair waits
  for a pass that can see something.
- **It does not restrict the app.** A clock-suspect device continues to create,
  edit, delete and revive records normally, stamping from its own clock as ever.
  Those writes may be poisoned and will quarantine, which is the loud containable
  failure this section is built around; the alternative — refusing user writes on
  a device with a bad RTC — would make the app read-only over a fault the user
  cannot see and did not cause, and local-first means the local user keeps
  working. The one operation whose correctness depends on the clock being right
  — rebuilding ordering values — is already unavailable to such a device for want
  of an in-window peer value to rebuild from.

A single-device install therefore has no repair path at all, and that is stated
rather than hidden: with no peers there is nothing to adopt, so a poisoned record
stays quarantined until another device attaches. It is also the case with the
least at stake, since a record that syncs with nobody cannot lose a conflict to
anybody.

**A persistently fast clock is the silent mirror, and widening inbound rejection
created it.** Clock-suspect detects only the *slow* direction: a device seeing
every peer value as impossibly far off. A device running persistently fast beyond
the bar sees the opposite of trouble — its own records are never future relative
to itself, so nothing quarantines, and every peer value sits comfortably *below*
its inflated ceiling, so it is never clock-suspect. Meanwhile every ordinary edit
it makes now stamps an `updatedAt` that honest peers refuse outright, where under
the narrower rule those blobs were accepted and cleaned downstream.

It re-uploads and is re-rejected every pass, and learns nothing: peers' manifests
still advertise the old hash, which reads as "remote unchanged" rather than
"remote refused me". So the one user who can fix the clock is told nothing, while
the warning surfaces on peers whose users cannot.

**A device also reports when its own values sit far above every peer's** — the
symmetric counterpart, computed from the same per-pass observation and equally
free of new state. Detecting only the direction that inconveniences *other*
devices, and staying quiet on the one that inconveniences the device that can
act, would put the signal where it is least useful.

It needs the same guards clock-suspect was given, and cannot borrow either its
scoping or its shape. Clock-suspect looks only at quarantined records, which is
meaningless here: a fast device's own records are never future *relative to
itself*, so none of them quarantines and the set would always be empty.

**The signal is uploads that peers never reflect, not values that peers trail.**
A device already learns, per record, whether a peer's manifest came to carry the
hash it published — that is how baseline entries advance. A device whose blobs
are being refused sees its own uploads never reflected by **any** peer, pass
after pass, while peers' own records continue to move. That is close to direct
evidence of rejection, and it covers the records that matter most: a record this
device *created* is stored by no peer at all when its blob is refused, so there
is no peer value to compare against — the case a trailing-value test cannot see,
and exactly the case a user seeding a library on a fast device would hit.

The report fires when **every** record this device published in a pass goes
unreflected by every peer whose manifest it observed, across **three consecutive
passes**, with **at least one peer observed** in each. Zero observed peers is not
evidence, for the same reason it is not evidence of a slow clock.

**The streak counter is in-memory, per session, and that is a real limitation.**
The per-record part is derived — reflection is already computed to advance the
baseline — but "the last three passes were each fully unreflected" is a temporal
aggregate that outlives a pass, and an earlier draft claimed the whole signal
"needs no new state" by carrying over language that is true only of the derived
half. It is state, and this design requires state that survives a restart to be
named, placed and classified; rather than add a persisted counter for a
diagnostic, the counter is scoped to the session and the cost is stated instead:
**a device restarted between passes may never reach three, and may never surface
the report at all.** That weakens exactly the dead-RTC case the signal exists for,
since a phone rarely runs three uninterrupted passes in one session.

It is kept anyway because the alternative is worse. Persisting it would mean new
`deviceScoped` state, a migration and a classification for a warning message,
where the same fault already surfaces through the records it poisons; and a
single-pass trigger would fire on any transient network failure, which is the
false positive that made the previous formulation useless. Three consecutive
in-session passes is a compromise that is honest about being one.

A draft instead required peer values to *trail* this device's by more than the
acceptance window, across three records. That does not distinguish the fault from
the thing it was written to exclude: a healthy phone paired with a tablet used
monthly has every record it has touched since trailing that tablet's month-old
manifest by far more than a day, and importing one program touches three dances
easily. The justification offered — that a wrong clock offsets everything this
device writes while ordinary staleness does not — was simply false, since an
inactive peer is stale on everything the active device has touched since.

An earlier version of this section claimed both clock-failure directions "stay
loud and contained". Containment held; loudness did not, once inbound rejection
widened — the fast direction was contained *and silent on the originating
device*, which is the half that matters for getting it fixed.

**A clock that is never corrected is a worse case than a solo install, and looks
identical to the user.** The discussion above assumes a clock that glitches and
is then fixed. A dead RTC that simply stays wrong — the commonest form of the
fault — sees every honest peer value as impossibly far off for ever. Such a
device is permanently clock-suspect, repairs nothing, and quarantines *more*
records over time as its peers legitimately transition things, while continuing
to accept its user's writes and accumulating divergence it will never resolve.
"Wait for a peer" is no remedy here, because peers are not what is missing.

A device wrong in the *behind* direction meets this before it has any local state
at all: on first attach every honest value is above its ceiling, so it rejects
the fleet's records outright rather than quarantining its own, which is outside
the quarantine-and-repair machinery entirely and presents as a device that simply
cannot sync.

All three directions are bounded the same way — contained to the affected
device, never silently reversing another device's work, and each surfaced **on
the device whose clock is wrong**, which the fast case only became once its own
detector was added. None self-heals, and the only real fix is the user's clock.
That is what the reports are for. The
design does not attempt more than surfacing it, because a device that cannot tell
the time has no sound basis for ordering anything, and inventing one would be the
guess this whole section exists to refuse.

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
rule, so the `+ 1 tick` is load-bearing rather than decorative. Two devices
repairing the same record concurrently converge **when their content agrees** —
both adopt the same observed values verbatim, both land bit-identical, and there
is nothing left to reconcile. When their content differs they do **not**:
repairing concurrently means observing the same peer set, and no rebuild formula
reads a local *timestamp* — the baseline only selects a branch — so two devices
that take the same branch compute the same value and tie at equal `updatedAt`,
`changed`/`changed` on a row the merge table does not resolve. That divergence is
bilateral and reported, the same posture as the residual above.

Two repairers that take **different** branches do resolve, and correctly: the one
whose content diverges from its baseline edited the record and stamps
`peer + 1 tick`, while the one that merely fell behind adopts the peer value
verbatim and loses to it. That is the intended outcome rather than a tie, and it
is the classifier doing its job — the ties are confined to the case where both
devices genuinely edited, which is a real conflict and is reported as one.

The independence from local timestamps is what makes that analysis hold. An
intermediate draft took `max(local updatedAt, peer + 1 tick)` in one branch,
which
would have made the outcome depend on each device's own value: two concurrent
repairers would then *not* tie, and whichever held the larger local value would
win silently rather than surfacing the divergence. An earlier draft still claimed
convergence outright, reasoning that "each stamps above the greatest it
observed" — which orders each repairer against the *peers* it observed rather
than against the *other repairer*, an unenforced *always* of exactly the shape
the habits below were adopted to catch, written in the commit that adopted them.

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
kinds (see the sync-migration scope).

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
it. **The sync migration** adds `updated_at` *and* `deleted_at`, stamping existing rows
at migration time. Both need classifying like any other column, and the coverage
ratchet will require it.

`deleted_at` is not optional. `SettingsRepository.remove` is a hard delete today,
so without a tombstone a removed setting cannot be expressed on the wire: the
peer still holds it, "absence never deletes" preserves it, and the next sync
**downloads it back**. The deletion would reverse every time, permanently.

#### The real scope of the sync migration

**This design does not name a schema version, deliberately.** Two earlier drafts
did, and both were wrong before review finished. The first called it v22; #748
landed `dance_figures.group_idx` as v22 while the design was being written. The
second called it v23; `main` reached 24 before the ADR was accepted. The number
is whatever `kCompendiumSchemaVersion + 1` is on the day the migration lands, and
that is the only form of the statement that cannot go stale — a design under
review for weeks has no business pinning a counter that other work increments.

Whoever implements it reads the constant rather than this document. Nothing about
the intervening migrations interacts with this one: they touch `dance_figures`
and tables this design does not migrate.

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
`max(localNow, currentExistenceAt + 1 tick)` — **not** from a bare clock, which
is
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
**six** repositories, and the **`restore()` paths on every kind** — the two that
exist (`DanceRepository`, `ProgramRepository`) plus the six added by this
migration — updated to stamp `existence_at`. Restore is the write that *sets* the
provenance signal, so it is as much a part of this migration's surface as the
deletes are; listing one without the other would leave the gate with no writer.

**Six across six, and the count took two corrections to get right.** An earlier
draft said "across five", reaching that number through two errors that happened
to cancel: it counted `VenueRepository.hardDelete` as a conversion and omitted
`settings` entirely. Both are wrong. `settings` converts — the wire cannot
express a removed setting without a tombstone, which this document's own
settings-record section already said — and `hardDelete` must **not** convert.
It exists solely to revert a just-committed import batch, and turning it into a
soft delete would leave an undone import lingering as tombstones.
`DanceRepository` and `ProgramRepository` both keep exactly such a hard-delete
path on a kind that already soft-deletes, so the precedent is unambiguous.

Worth stating plainly because the arithmetic hid it: a total that matches by
coincidence is not evidence, and neither of the two counts that produced "six"
had the right set behind it.

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
gains no `deleted_at` in the sync migration, nothing filters them. The tag would
vanish from the
tag manager while staying silently attached to every dance. The same applies to
`custom_field_values` and `dance_sources`.

> **Every read that joins through to a soft-deletable parent must filter
> `parent.deleted_at IS NULL`.** This is a change to existing query paths, not
> only to the sync code, and it is the part of the migration most likely to be
> missed —
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

**The sync migration should ship ahead of every other piece of this programme**, on its
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
   while the stamps still reflect *migration order*. Ship it early and users
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

**The rules are RFC 8785 (JCS), adopted by reference, plus NFC.** That decision
was made late and it corrects a real gap rather than tidying one. For a long
time this section said "pick one form and pin it" about numbers and left the
rest — string escaping, `-0.0`, exponent form, trailing zeros, and what
"lexicographic" sorts by — to the encoder. Inside one Dart codebase that is
invisible: one shared encoder makes every unstated rule agree with itself. It
bites the *second* implementation, which is the entire premise of a document
that carries a `v` version and a conformance section.

The concrete case is not hypothetical. `custom_field_values.value_num` is a
`RealColumn` classified `shareable`, and those join rows ride inline in the
`dance` blob, so a fractional user value really is hashed. A shortest-round-trip
encoder and a `double.toString()` encoder disagree on it, and the record then
reads `changed`/`changed` on every pass forever.

Adopting a standard beats writing our own three paragraphs here, because float
formatting is exactly the kind of rule that looks simple and has been got wrong
for decades; RFC 8785 has test vectors and existing implementations, and §9 can
just cite them. Two things it does *not* settle we state ourselves: Unicode
normalisation, which JCS explicitly puts out of scope, and the JSON-inexpressible
floats. NFC matters because titles are arbitrary user text — the same title
pasted from a macOS filename (NFD) and typed on Android (NFC) displays
identically and hashes differently, which is the same permanent non-convergence
tick truncation was introduced to close, arriving by a different door. NaN and
±Infinity matter because SQLite `REAL` admits both and JSON encodes neither; the
tempting coercion to `null` or `0` would silently alter a user's data *and*
still not converge, so rejection is the only answer that is honest.

**Where NFC applies was wrong for thirty rounds, in a way the analogy caused.**
The rule was originally written as "normalised on ingest as timestamps are", and
the comparison is what hid the defect: for timestamps, ingest-scoping really is
sufficient, because a `DateTimeColumn` persists as unix seconds and sub-tick
precision cannot survive *any* write, local or remote. The representation
enforces the invariant. A TEXT column enforces nothing, so the same scoping
applied to strings leaves the largest population of strings in the app — the
user's pre-existing library, which never arrived through a sync path — never
normalised at all. §6.2 step 4 uploads it verbatim; the device re-serialises
from the same unchanged rows every pass afterwards, so it emits NFD forever
while every peer that ingests it stores NFC. One record id, two byte strings,
permanently. It also quietly broke §6.10, which assumes its inputs are already
NFC on the strength of this very rule, while at fresh attach one side of every
dedupe comparison is exactly that never-ingested local library. The rule now
covers every write path that can populate a `shareable` string.

**The claim that grounded this needed narrowing, not deleting.** When it was
written it said there is no Unicode normalisation anywhere in the app, and by
round 33 that was false as literally worded: #1024 added `nfc()` calls in
`dedupe.dart` and `import_pipeline.dart`, and `unorm_dart` is a dependency of
`compendium_core`. It remains true in the only sense the argument uses. Both
call sites normalise a value being **compared** — a fold table and a
choreographer matching key — and neither writes a normalised value back. Nothing
in the storage layer, the models or `app` normalises a value that gets stored,
and `app` does not depend on the package that could. So this is still new work
on the write paths, and §4.1's one-time pass is still required. Narrowing the
claim was the honest repair; deleting it would have removed the premise the
whole rule rests on, and leaving it would have let a reader check one `grep` and
discard the section.

**Correcting the rule was not the same as assigning the work, and I did only
the first.** Round 31 fixed §4.1 and left the implementation plan saying "NFC
normalisation applied on ingest" — the exact scoping the spec now spends four
paragraphs rejecting — while the local-edit and import work the corrected rule
creates appeared in no unit at all. The plan is the document an implementer
builds from, so an unpropagated fix builds the defect it was meant to remove.
This is the same shape as the paraphrase pattern one level up: the fix got the
scrutiny, the scaffolding around it did not. W18 exists to own that work.

**"Normalise on write" misses precisely the rows the rule was written for.** A
title imported two years ago and never edited is never written again, so no
write-path rule reaches it — and the pre-existing library is exactly the
population §4.1's own justification names, because §6.2 step 4 uploads it
verbatim at first attach. A rule that repairs everything except its motivating
case is not a rule that works. Hence the one-time backfill.

The backfill must **not** touch `updated_at`. Two devices upgrading at different
times then normalise the same NFD row into identical bytes with identical
stamps, so it presents as `same` and no conflict arises. Bumping the stamp
instead would hand every normalised row to whichever device upgraded last — a
mass, direction-arbitrary resolution over rows nobody edited. That is the same
hazard as the migration-stamp wart, and it would be self-inflicted.

**But "must not touch `updated_at`" collided head-on with invariant I1**, which
requires any change to serialised content to advance it — and the collision was
introduced by the same round that wrote both rules, in two documents, with a
conformance test codifying each side. The two clauses were written a page apart
and neither mentioned the other. §4.1 half-conceded the problem with a phrase —
"content did not meaningfully change" — that quietly appealed to an exception I1
does not contain. A hedge in prose is where a specification records that it
knows it is contradicting itself.

The resolution is worth stating in general form, because the tempting fix is
worse than the problem. **Name the property, not the operation.** The obvious
repair is to list §4.1's pass as I1's sanctioned exception, and that is a
whitelist — the exact "maintained enumeration relocates the forgetting" that
W17's own ratchet argument rejects three sections later. The next such pass gets
added by whoever remembers, which is how the first omission happened. So I1 now
carries a *condition* that a claimant proves by test rather than a name it
cites.

That reframing then did work I did not anticipate, which is the usual sign it is
the right one. It settles the collision rule too: the pass must skip a `UNIQUE`
collision rather than merge it, and the decisive argument is not "merging is
rude" but that a *user* resolving the same pair differently on two devices is
precisely the divergence I1 orders — so a pass that could merge would forfeit
the exemption it depends on. Two blocking findings turned out to be one
question.

**And then the property I named was false, which is the more useful half of the
story.** The condition I wrote was "pure, idempotent, **row-local**, computed
identically by every device" — and the collision rule I derived from it in the
same commit *reads sibling rows by construction*. Whether a row is normalised
depends on whether some other row normalises to the same `UNIQUE` value, so a
device holding a colliding pair skips while a device holding only one of them
does not. The pass is not row-local, and the sentence authorising it said it
was.

The lesson is not "check your work". It is that **a fix and the justification
written to support it are two artefacts, and only one of them gets reviewed.**
The collision rule was scrutinised hard — it is the part with the failure modes.
The clause it hangs from was treated as settled because it was the thing being
applied. Generalising: when a round produces both a rule and the principle the
rule is justified by, the principle is the newer of the two even when it reads
as the older, and it inherits none of the scrutiny the rule attracts.

**The mandated proof could not have caught it, and that is the part worth
keeping.** I had required a claimant to show that "two independent runs over the
same input produce identical output". That test is aimed at nondeterminism —
clocks, device ids, randomness — and a cross-row read is *perfectly
deterministic* given a fixed database, so the collision pass sails through it
while doing the exact thing the property forbids. A proof obligation that cannot
fail against the defect it was written for is worse than none, because it
converts an unexamined assumption into a discharged one. The condition is now
two-part — content-derived **and** divergence-surfacing — and the second half is
proved by running the operation over *two databases containing the same row*,
which is the only shape that can see a sibling read at all.

The repaired property is also the more honest one, and it was already in the
document: the pass does not guarantee that no divergence occurs, it guarantees
that **any divergence it can produce is reported and never silently resolved**.
That is what a stamp would have bought, obtained without inventing an order over
rows nobody edited. I had this argument in hand and wrote the exception on a
stronger claim instead, because the stronger claim sounded cleaner.

**Skipping is not free, and my description of the cost was itself too kind.** A
skipped pair stays un-normalised, so if a peer holds only one of the two rows,
that peer normalises its copy and this device does not. I wrote that the
resulting `changed`/`changed` tie "resolves and is reported". §6.3, ten
paragraphs away, says the opposite in as many words: neither side wins, neither
body is applied, and it is re-reported on **every** subsequent pass until a human
edits one side. It is a standing non-convergent state, not a resolution — and
"resolved and reported" is the exact hedge-shaped phrasing this design already
identified as how a specification records that it knows it is contradicting
itself. The design still prefers it to a silent merge. It is a residual, and it
had to be written as one.

**A skip recorded as final is a defect with two faces.** Nothing re-ran the pass
after the completion marker was written, so a skipped row stayed un-normalised
permanently — and separately, tombstones occupy their natural keys, because soft
delete is an `UPDATE` and none of the three `UNIQUE` indexes filters on
`deleted_at`. Compose those and a **live** row is blocked forever by a **dead**
one the user cannot see, cannot list and cannot act on. I had reached for a
special case for tombstones. The better fix was one rule that dissolves both:
record each skipped row and retry it on each open. Then every blocking
condition — a rename, a delete, a purge, a reconciliation — resolves itself at
the next launch with no rule naming any of them. Two findings, one root, and the
narrower fix would have left the other half live.

**The obvious implementation of "detect a collision" violates the rule it
implements.** Try the write, catch the `UNIQUE` violation. But when two rows sit
in different decompositions, the first write *succeeds* — nothing holds the
target value yet, because the second row is still in its own un-normalised form
— so exactly one member of a pair the rule says to leave alone gets normalised,
and which member depends on row order. The spec had a MUST ("leave **both**
un-normalised") and no mechanism that could deliver it. The fix is to group by
target value before writing anything, which removes the ordering question rather
than answering it. **Specifying an outcome is not specifying a procedure**, and
where the natural procedure quietly fails the outcome, the spec owes the
procedure.

**A pass defined over a classification will reach columns the classification
does not know about.** "Every `shareable` string column" includes `settings.key`
— which is `shareable`, and is also the settings record's *identity*, so
normalising it renames the record instead of repairing it. It is inert today
because settings keys are ASCII app constants and NFC is the identity function
over them, which is precisely why nobody would find it. A rule scoped by a tag
inherits everything the tag was drawn around, and the registry was drawn around
egress, not identity.

**A bulk write is not a loop, and the codebase already knew that.** Two further
constraints came from reading how the existing one-time sweeps behave rather
than from reasoning about sync. They write their completion marker only after
the whole pass succeeds, so a single throwing row is retried from scratch on
every launch and the sweep never completes — skip-on-collision is what makes
that idiom safe here, since nothing raises. And `dance_fts` /
`dance_substring_fts` hold literal text maintained by the *repository layer* on
each write, so a bulk `UPDATE` that bypasses that layer leaves search matching
the pre-normalisation text. `runDerivedRebuild()` fixes it and, conveniently,
touches none of the three stamps, so it composes with the rule above. Both are
the kind of defect that is invisible from inside the specification and obvious
from inside the repository.

**Reading the precedent is not the same as citing it.** The plan told an
implementer to call `runDerivedRebuild()` "unconditionally, as
`_normaliseInversePairMoveIdsIfNeeded` already does". It does not: it gates the
rebuild on `!alreadyRebuilt || rewroteAny`, and a second call site in the same
file gates on a rewrite count alone, with a comment written specifically to
contrast the two forms. So the plan cited a precedent that says the opposite of
the instruction it was supporting — and the instruction was *also* wrong once
skips became retryable, because a retry pass in which every group still collides
writes nothing and has no index to rebuild. The citation was doing the work of
an argument. This is the same class as the paraphrase failures of rounds 30–31,
one step removed: there the spec restated an algorithm it named, here the plan
characterised a function it named. **A named function in a normative sentence is
a claim about code, and it is checkable in one `grep`** — which is exactly why
leaving it unchecked is expensive.

**A fix that mandates new persisted state must classify it in the same breath.**
The retry that answered the tombstone problem quietly introduced a table — and
it appeared in neither the spec's storage inventory nor this document's, under
each inventory's own rule that everything persisted is classified in the PR that
adds it. This document had *already catalogued itself* doing this exact thing:
"introduced as behaviour with no storage; so was `id_aliases`; so was the
pending tombstone." The rule was written, the instances were listed, and the
next instance still walked past it one page later. **A rule about a class of
mistake does not fire on the mistake; only a mechanism does** — which is the
argument the coverage ratchet already rests on, applied to a design document
that has no ratchet of its own.

**The lifecycle question is the one that actually loses data, and the obvious
precedent is wrong.** `normalisation_skips` is the first thing this design
persists that is not store state in any sense. A `UNIQUE` collision between two
Unicode forms is a fact about *this library* — true before the device attaches,
while it is attached, and after it detaches. Its nearest visible neighbours,
`id_aliases` and `review_queue`, clear with the baseline, so an implementer
reaching for the obvious precedent drops every owed repair on the next `409`
while the completion marker goes on asserting the scan is finished. Silent, and
invisible in support. **New state inherits a lifecycle by proximity unless the
design states one**, so the statement is the whole of the work.

**Two findings dissolved into one design move, again.** The retry's "no longer
collides" test was under-specified, and the reading that comes naturally —
judge the recorded group — raises: a row created *after* the skip was recorded
can take the target value legitimately, and a later rename then leaves a
one-member group that "no longer collides" straight into it. Re-deriving from
the **live column** fixes that, and it also makes the recorded target value and
group membership unnecessary, which collapses the entry to `(table, column,
record_id)`. That in turn answers the classification question the same round
raised: the table stores no name, only the address of a row, so nothing in it is
`shareable` and nothing is ever re-transmitted. **Storing a snapshot of a
condition invites acting on the snapshot**; storing an address forces the
re-derivation that was correct anyway.

**Scoping a rule to "the target value" forgot which table the value lives in.**
Three `UNIQUE` indexes on three tables, and grouping by target alone treats a
tag and a choreographer sharing a name as a collision — skipping both
*permanently*, because a cross-table collision never stops colliding and the
retry can never clear it. The bug is worse than the one it emerges from: the
real collisions it was written for do resolve.

**A mutation description can be invalidated by a carve-out added elsewhere in
the same round.** §9's write-path ratchet was mutation-proved by "add a writer
that skips normalisation — the row is stored NFD and is uploaded verbatim". The
ordinary-edit carve-out made that outcome *legitimate*, so a test written to the
description could no longer distinguish the bug from sanctioned behaviour. The
ratchet was fine — it asserts **routing** through the choke point, not stored
bytes — but the mutation had to be restated in the same terms. **When a
conformance clause is expressed as an outcome and the spec later sanctions that
outcome, the clause rots silently**, because nothing links the carve-out to the
test that assumed it impossible.

**Round 36: a rule restricted to a subset must be shown equivalent over that
subset, not merely cheaper.** The round-35 fix replaced retry's stale-membership
test with a live-column test, which was right about the case it was written for
and wrong in the opposite direction. A mutually-colliding pair occupies nothing
— each member still holds its own un-normalised bytes — so a live-occupancy test
sees a free target for whichever member it reaches first, writes it, and blocks
the other. The pass's whole purpose is that such a pair is left whole, and retry
undid it along an iteration order nothing specified. The fix is both halves: the
grouping test *and* the occupancy test. **When a rule is re-expressed over a
narrower input set, the question is not whether the new test is sound but
whether it agrees with the original on every member of that set** — and here the
answer depended on an invariant (every un-normalised row is recorded) that was
true but unstated, which is why nothing flagged the gap.

**A guarantee stated in one section is not implemented by the section that owns
the event.** §4.1 said a restore clears the marker and `normalisation_skips`;
§6.11, the normative restore procedure, and W9, the unit that builds restore,
both said only that the baseline drops. An implementer builds restore from
§6.11 and W9. This is the same shape as round 35's inventory gap and round 32's
ownership gap, and it is the most repeated defect in this review series:
**the place a rule is written is rarely the place it will be read.** Every
cross-cutting rule needs a second home in the section that owns the trigger.

**"Cleared when it succeeds" is not a lifecycle — it omits the row going away.**
`normalisation_skips` entries cleared on being written, and on a wholesale
restore, and by nothing else; a hard delete left an entry naming a row that
could never be written and never cleared. The path was already shipped
(`ImportPipeline.undo`), and the obvious remedy was structurally unavailable,
because a polymorphic `record_id` spanning three tables cannot carry
`ON DELETE CASCADE`. **State what retires a record, not just what satisfies
it**, and prefer putting the retirement where it is self-healing — in the
consumer that already visits every entry — over spreading it across every
present and future delete path.

**A coverage matrix drifts when a section gains an obligation owned elsewhere.**
§3.2's row named W4 + W14, but the new table's lifecycle is built and tested by
W18, which serves §4.1. The matrix was not wrong when written; it was made wrong
by an addition somewhere else, and nothing links the two.

**Round 37: a rule is not implementable because it is stated precisely — it is
implementable when the operation it names exists.** §4.1 said to retire an
entry whose row no longer exists and, four lines later, never to retire one
whose row is soft-deleted. Both sentences are right; together they require a
read that ignores `deleted_at`, and no such read exists in any of the three
in-scope repositories — every `getById` there filters, and none takes an
`includeDeleted`. Both states come back `null`, so the *natural* implementation
retires exactly the entries the second rule forbids and drops owed repairs
silently. `DanceRepository` does take `includeDeleted`, which makes the pattern
look uniform when it is not. **When a rule turns on a distinction, name the
query that draws it and say whether it exists** — a correct rule resting on an
absent accessor fails in whichever direction the nearest available accessor
happens to point.

**Ask what a duplicate row does before deciding a key is bookkeeping.** Nothing
said recording a skip was an upsert, and every other table in the storage
inventory states columns without keys too — so the omission was consistent, and
consistently harmless everywhere else. Here a second entry for the same row
satisfies the retry test's "another recorded row deriving this target" against
its own twin, so the row blocks itself forever for a collision that does not
exist. **The question is never whether a table needs a key in general, but what
its own consumers do when a row appears twice.**

**An enumeration offered as a completeness proof needs the same scrutiny as the
rule it justifies.** The two-condition retry test rests on "every un-normalised
in-scope row is recorded", supported by three sources with restore called *"the
one event that introduces rows no pass has judged"*. It isn't: widening the set
of `shareable` columns brings unjudged rows into scope while the completion
marker asserts the scan is finished — and the server-readiness rule already
treats adding a `shareable` field as an anticipated, recurring event, so the
design planned for the trigger without connecting it to the claim. A
justification written to close a gap is the least-reviewed artefact in the
document, because it reads as the premise rather than as new work.

**Say which condition carries which guarantee.** The review's systematic pass
established something the document had not claimed for itself: raise-safety
rests on the live-occupancy condition *alone*, independent of the completeness
argument, while the grouping condition is what prevents divergence. That is a
stronger foundation, and it means a flaw in the completeness enumeration cannot
cause a crash — only a missed repair. **A two-part test whose parts protect
different properties should say so**, or every future reviewer re-derives it and
every future editor risks weakening the half that was load-bearing.

**Round 38: citing a codebase convention is not the same as reproducing the part
that makes it safe.** The pass was told to write its skips and its completion
marker in one transaction, "on the convention `repositories.dart` already uses
for one-time sweeps". That convention exists, but it has two shapes, and the one
that applies to a sweep needing a derived rebuild has **three** steps rather
than two: the rewrites commit alongside a durable *rebuild owed* flag, the
rebuild runs outside the transaction, and the done-marker is written only after
it succeeds. Taking the two-step shape leaves a crash window in which the marker
says the scan finished while the search indexes still hold pre-normalisation
text — permanently, because later passes write nothing and the design forbids
rebuilding when nothing was written. **When a rule leans on an existing pattern,
name the steps, not the pattern**, and check whether the pattern has variants
that differ in exactly the property being relied on.

**An obligation should be stated over the condition, not over the event you
expect to cause it.** The rule said a *migration* widening the in-scope column
set must clear the completion marker — but one of the two triggers the same
paragraph names, reclassifying a column to `shareable`, is an edit to a plain
map entry with no schema change, no version bump and no migration at all. The
emphatic half of the rule was therefore inert for half the cases it was written
for, and an implementer building exactly what it said would satisfy it
vacuously. Restating it as a comparison — re-run whenever the live in-scope set
is not a subset of the recorded one — catches both triggers with one mechanism.
**A rule keyed to a mechanism silently excludes every path that reaches the same
state by another route.**

**Two writers of one table need a pinned spelling, not just a pinned shape.**
The primary key's *columns* were specified exactly; the *strings* that go in
them were not, and the table has two independent writers whose entries retry
correlates by grouping on those strings. Two reasonable conventions exist in
this codebase and it reaches for both. A mismatch produces no error, no
exception and no failing test — collision detection simply stops correlating.
**Where two producers must agree on a value, generate it from one source**, the
standard the design already sets elsewhere for the identical
registry-versus-code mismatch.

**The conformance vector and the normative prose can drift apart, and the vector
is sometimes the stricter of the two.** The §9 mutation for the widening rule
tested the reclassification case, which the prose's migration-gated obligation
would not have caught — so a conforming implementation could fail a test it was
never told to pass. Worth checking in both directions: the usual drift is a test
that has gone slack, but a test that has stayed strict while the prose narrowed
is the same defect wearing different clothes.

**Round 39: a convention's safety is often not local to the code that
demonstrates it, and citing that code does not import it.** Round 38 fixed a
rule that had cited a sweep convention while omitting its durable rebuild-owed
flag. Round 39 found that the repair had reproduced the flag while omitting what
makes the flag work: the rebuild is not performed by the sweep that sets the
flag, but by an unconditional, pass-independent check at the top of the
migration path that runs *before any sweep*, reads that one specific key, and
clears it. A "durable rebuild owed flag" read as a private flag the pass owns
and clears is inert — after a crash the resumed pass rescans, finds nothing left
to rewrite, and never fires the rebuild. The lesson generalises past this
instance: **when a rule points at working code, trace where the guarantee is
actually enforced**, because the mechanism is frequently one layer out from the
example, and the example is what gets copied.

**Scope an obligation by the action that causes the hazard, not by the actor you
were thinking about.** The three-step commit rule was written for the one-time
pass and phrased around its completion marker — but retry also writes rows, and
retry never writes that marker, so the rule silently excluded the path that runs
forever rather than once. The hazard is created by *writing a row before the
rebuild*, and that is what the obligation should have named. The cited
implementation had already made this choice, keying its flag off "did this
rewrite anything" rather than off a pass lifecycle; the spec imported the shape
and re-narrowed the scope the source had deliberately made general. **Ask which
paths reach the hazardous state, then check the rule names all of them.**

**A containment test is directional, and the direction it ignores can come
back.** The widening comparison was stated as "re-run when the live column set
is not a subset of the recorded one", which is correct for every addition and
correct for a removal — but it means the recorded set never contracts, so it
becomes a high-water mark, and a column reclassified out and later back in is
still contained and never re-runs. Meanwhile the interval out of scope is
exactly when its rows can accrue un-normalised text unrecorded. Inequality costs
one no-op scan on a rare event and has no direction to ignore. **When a
predicate compares two evolving sets, walk all four directions rather than the
one that motivated it.**

**A derived input can disable the mechanism built on top of it.** The re-run
trigger depends on computing "the live in-scope set", and the obvious
implementation — hand-listing the `shareable` string columns — cannot be read
off the registry, because the classification carries no column type. A stale
hand-list means a newly `shareable` column never enters the live set, the
comparison never differs, and the safety net added to catch exactly that change
is silently disabled through its own input. **A rule that consumes a computed
set is only as strong as the derivation of that set**, so the derivation belongs
in the rule.

**Round 40: when a rule is re-scoped, re-scope every step of the operation, not
the one the finding named.** Round 39 correctly moved the rebuild-owed flag from
"the one-time pass" to "any pass that rewrites a row" — and left the *clearing*
of that flag bundled into step 3, the completion marker, which retry never
writes. So retry would set the flag, rebuild, and leave it set for the next open
to honour with a second whole-library recomputation. The set moved and the clear
did not. An operation described as a sequence of steps has a scope per step, and
a finding that names one step will get one step fixed unless the others are
re-read against the new scope.

**Mechanising two of three criteria can be worse than mechanising none.** The
scope of the normalisation pass is *`shareable` string columns that are not
record identity*, and the derivation rule automated `shareable` and `string`
while leaving *not identity* in prose. That is not a partial improvement, it is
an inversion: `_key` — the opaque surrogate identifier — is classified
`shareable`, so a literal string ∩ `shareable` set contains every primary key in
the schema, and `settings.key` is both `shareable` and its record's identity. An
implementer following the mechanised rule would normalise identity columns,
renaming records rather than repairing them. **When automating a predicate, list
its conjuncts and check each one made the trip**, because the automated part
reads as authoritative and the leftover prose reads as commentary.

**A ratchet that resembles an existing one is not thereby the right ratchet.**
The rule pointed at the classification coverage test as the family to imitate.
That test compares `table.column` names for presence and staleness; it inspects
neither column type nor primary-key membership, so it would pass unchanged if
the derivation leaked every id column into the scan. Naming a family is a
convenient shorthand that quietly transfers credibility. **Say what the test
must assert, not which test it should look like.**

**A repair's cost can be dominated by machinery it does not control.** The only
rebuild routine in the codebase is a whole-library clear-and-repopulate of the
dance indexes, and two of the three tables this pass exists to repair — tags and
custom-field keys — feed neither index. The likeliest repair therefore pays the
largest cost for indexes whose content did not change. The design now permits
skipping the rebuild under proof rather than requiring the skip, because the two
errors are not symmetric: a redundant rebuild is slow, while a missing one is
the permanent silent staleness three rounds have gone into closing.

**An optimisation must remove the bookkeeping along with the work.** Round 40's
skip permission removed the rebuild and left the durable *rebuild owed* flag
being set on any rewrite, with the clear bound to a rebuild that no longer
happened. Taking the permission was therefore strictly worse than declining it:
the flag survived, so the next app open performed the whole-library rebuild
anyway — the same work, deferred to startup, with the targeting lost. The
reference implementation does not have this problem because its flag is written
under the same condition that triggers the rebuild; the permission split the two
apart without re-joining them. Where a mechanism has a set and a clear, they are
one condition wearing two hats, and narrowing one alone does not partly achieve
the optimisation — it inverts it.

**"Derive it rather than assert it" is an instruction only if the thing is
derivable.** The same paragraph required an implementation to derive the mapping
from source columns to search-index columns rather than hard-code it, by analogy
with the rules just above it, which derive column types and record identity by
reflection over the schema. But nothing in the schema records that the index's
`authors` column comes from `choreographers.name`: the index is declared as a
raw `fts5(...)` string carrying names and no provenance, and its rows are a
positional list assembled by hand across joins. Reflection recovers the column
*names*, which is exactly the half a skip does not depend on. An implementer
facing that rule can only hard-code a map and call it derived, or leave the
permission unused.

The repair is to say which kind of fact each one is. Where a fact is
schema-shaped — a column's type, a table's primary key — reflect it. Where it
lives in imperative code, declare it once and check it by **observing the
behaviour**: seed a distinct marker in every in-scope column, run the rebuild,
and see which markers land in indexed columns. Observation also catches the
drift a schema-watching rule structurally cannot, which is the likeliest drift
here — the index's `sources` value reaches two columns only because a loop
appends both, and a third would be an ordinary code edit touching no schema.
Watching the wrong artifact is worse than watching none, because the check
reports success.

**A rule can be right while the sentence justifying it is false, and the false
sentence is what gets audited.** Two of round 42's findings were this. Refusing
plaintext at the listener was said to turn a disclosure into a failed
connection — but the credential is on the wire before the listener can respond
at all, so nothing recalls the first one; what refusal actually buys is that
there is no *second*. And `Strict-Transport-Security` was grouped with rules
"chosen because some common proxy violates the default", as though it protected
the callers the paragraph had just enumerated. HSTS is a browser mechanism,
this app has no web target, and `curl` ignores it without an explicit flag — so
it reaches none of them. Both rules survived the correction; both
justifications had to go. A false rationale is worse than a missing one,
because it is the thing a later reader checks the rule against, and it will
retire the rule when it fails.

**Naming two wrong implementations and testing one leaves the other
recommended.** The loopback exemption ruled out both a substring test and a
loopback-*range* test, and only the substring case got a conformance vector.
The two are not variants of one mistake: a range test rejects
`localhost.example.com` correctly, and admits `[::1]` and `127.0.0.2` — so it
passes the test that exists and fails the property. Enumerating hazards in
prose creates an obligation per hazard, not one for the set.

**An absence is not a behaviour, and cannot be owned by the unit that builds
the behaviour.** "The client verifies certificates" is testable and finishes.
"No affordance to skip verification exists anywhere in the client, ever" is
maintained against every future PR — the same distinction that created the
standing-invariant unit for the soft-delete join rule. A behavioural test is
satisfied by a debug flag that defaults to off, which is the exact shape the
rule was written to prevent, so the rule needed a source scan and a permanent
owner rather than a build-time assertion.

**Tightening one path can invalidate a promise resting on it that lives
elsewhere.** Forbidding a user-supplied trust anchor removed the last route by
which a self-hoster could use a certificate the client would accept — while two
documents went on saying the loopback waiver means a self-hoster "needs no
certificate". That was never true for sync, which is at least two devices and
therefore never `localhost` from the second, and the rationale document one
directory over had the accurate version all along ("which self-hosters need
*for testing*"). When a fix narrows what is possible, the claims to re-check
are not the ones near the edit; they are the ones that promised the thing just
removed.

**Where a justification rests on someone else's behaviour, the source is the
check — and official documentation is not the source.** Round 42 asserted that
`dart:io` trusts a compiled-in Mozilla root list on Windows and Linux rather
than the OS store, which would mean a private CA fails even when the operating
system trusts it. That is what Dart's published API documentation for
`SecurityContext.defaultContext` says, and it has been wrong since Dart 2.14.
The SDK source says the opposite: Windows enumerates the `CURRENT_USER` and
`LOCAL_MACHINE` stores and installs an *empty* store if that fails, with no
compiled-in fallback at all; Linux probes the standard bundle locations and
reaches the compiled-in list only if none exist. The claim was not careless —
it was the documented behaviour, arrived at by ordinary diligence — and it was
still false. Reading the documentation tells you what a maintainer once
intended; reading the source tells you what will happen.

**Getting the mechanism backwards inverted the conclusion that rested on it.**
The clause existed to show that even OS-level trust fails, which is what forced
the DNS-01 recommendation. Because the opposite is true, a self-hoster on two
desktops can install a private root into the OS store and the shipping client
accepts it — and the in-app trust-anchor ban cannot reach that, because it
governs trust the *app* extends and this is trust the *operating system*
extends. The recommendation survived, but for a different reason than the one
given: Android reads only the system cacerts directory, so any sync set
containing a phone still needs a publicly-trusted name. A conclusion that
survives its false premise is the dangerous kind, because nothing fails when
the premise is corrected — and the next reader audits the premise.

**Moving ownership in prose does not move it in the mechanism that decides when
work is done.** The certificate rule was reassigned from the unit that builds
the client to the standing-invariant unit, in that unit's *Serves* and
*Produces* lines. Its *Done when* still named two buckets, neither containing
the new clause, and the ownership matrix still routed that bucket to three
other units. So the unit could be marked complete with both named buckets green
and the scan never written. The matrix exists *precisely* to prevent unowned
clauses — its own preamble cites this same bucket as the historical instance —
which is the point: a mechanism that has caught a defect once does not maintain
itself, and a fix landed in normative text has to be walked into every gate
that decides whether the work happened.

**When a rule is tightened, the gates that accepted the old rule do not fail —
they silently keep passing.** The spec moved from "redirected or refused" to
"refused", and the deployment gate that is the *only* check of that requirement
still said "redirected or refused". Nothing broke, because a loosened gate is
indistinguishable from a satisfied one. Tightening a rule means grepping for
the old permission, not just editing the sentence that granted it.

**A fact asserted by a reviewer enters the document with less scrutiny than one
the author wrote, because the author has no reason to re-derive it.** Round 43
corrected a claim the author had taken from stale official documentation. Two
of round 44's five findings were claims the *reviewer* supplied in that same
report — that `curl -L` retains `Authorization` across an `http`→`https`
redirect, and that DNS-rebinding protection is on by default in a named list of
products — neither checked against a primary source, both written straight into
the normative text on the strength of having been reported as verified. The
first was not merely wrong but was the exact behaviour curl classified as a
vulnerability and fixed in 7.83.0 (CVE-2022-27776), with an advisory page that
had been available the entire time. The lesson is symmetrical to round 43's and
needs stating separately, because the mitigation is different: the author's own
claims get re-read on every pass, and a reviewer's arrive pre-endorsed.
Anything a review asserts as verified must carry its primary source or be
marked unverified, and an unsourced fact should be treated as a question rather
than a finding.

**Correcting one half of a false conjunction can leave the other half standing
and now load-bearing.** The retention claim named two clients. The review found
`curl` wrong and proposed resting the argument on `dart:io` alone — which would
have replaced a claim that was half false with one that was wholly false and no
longer had a second clause to draw attention to it. `dart:io` strips sensitive
headers unless scheme, host *and* port all match (`_isSameOrigin`, consulted
from `shouldCopyHeaderOnRedirect` in `sdk/lib/_http/http_impl.dart`), so a
scheme upgrade is cross-origin and the header is dropped there too. Checking
only the half that was challenged is how a correction becomes the next defect.
Check the survivor precisely because it was not challenged.

**The requirement was right for a reason better than the one given, and finding
that out made it stronger.** Both stated justifications for refusing rather
than redirecting were false, and the rule survived unchanged, because the real
argument never depended on them: whether a redirect is harmless depends on the
redirected client's header policy, which the operator cannot see, and a client
that retains gets a *working* plaintext-then-TLS sync in which nothing ever
surfaces the misconfiguration. Refusal produces the same visible failure for
every client. A justification that rests on how one named client behaves today
expires; one that rests on the operator not having to know expires never. When
a justification is found false, the question is not what to substitute for it
but why the rule felt right anyway.

**Refusing a smaller risk on principle while presenting a larger one neutrally
is not neutrality.** The specification forbids an in-app trust-anchor
affordance, which would compromise this app, and in the next breath described
installing a private root into the operating system's trust store — which lets
its keyholder forge every TLS connection that machine makes — as a real path,
noting approvingly that it needs no administrator rights. The asymmetry was
visible in the same section, where the smaller DNS-01 risk beside it carried an
explicit caveat. The section is also the source for user-facing self-hosting
documentation, so the omission would have propagated to the people least
equipped to supply it themselves.

**The general lesson, which is now fifteen rounds old: the newest machinery
carries the round's defects.** W18 was created in round 32 to fix an ownership
gap, and in round 33 it was where both blocking findings lived — including a
fresh ownership gap, since its own ratchet was gated by no conformance bucket.
Round 34 then found that the *property* written in round 33 to close that
round's blocking finding was itself false, and false in a way round 33's own
new proof obligation was structurally unable to detect. Round 35 then found
both of its defects in the retry machinery round 34 had added to close *its*
blocking finding — unclassified new state, and a retry test that raises. Round
36 found its headline defect in the *replacement test* round 35 installed to
fix that raise, which broke the grouping guarantee it was protecting. Round 37
found the retirement rule round 36 added to be unbuildable from any accessor
that exists, in a way whose natural implementation destroys the repairs it was
written to protect. Round 38 found two more in the same machinery: a rule that
cited a sweep convention while dropping the step that makes it crash-safe, and
a widening rule whose actionable half could not fire for one of the two
triggers it named. Round 39 then found round 38's own repair incomplete in the
same direction — it reproduced the durable flag but not the generic pre-check
that reads it, and scoped the rule to the one-time pass when retry writes rows
too. Round 40 then found round 39's re-scoping applied to the flag's set but
not its clear, and its derivation rule mechanising two of the three criteria in
the scope sentence directly above it. Round 41 then found round 40's own remedy
for that rebuild cost self-defeating in both halves: it removed the work but
not the bookkeeping, so taking the permission deferred the identical rebuild to
app open, and it demanded a derivation from an artifact that does not carry the
fact. Round 42 then found five defects in the transport section written
*beside* round 41's repair — the repair itself being the strongest work in the
document — of which two were true rules carrying false justifications and two
were rules stated in prose with no mechanism that could enforce them. Round 43
then found that round 42's own correction rested on a false mechanism taken
from stale official documentation — inverting it, though the conclusion
survived — and that the certificate rule it reassigned had been moved in prose
but in neither the owning unit's gate nor the ownership matrix built to prevent
exactly that. Round 44 then found that two of round 43's corrections had
themselves been written from secondary sources supplied by the review, one of
them describing as current behaviour the exact thing curl had classified as a
vulnerability and fixed four years earlier — and that the rule they justified
was correct for a reason neither of them had stated. Fourteen consecutive
rounds have found the round's defects in the previous round's repair, which is
no longer a coincidence and is better read as a property of how repairs get
written: under the belief that the hard thinking has just been done. Round 30's
instance was the spec paraphrasing an algorithm; round 31's was the same thing
twice more; round 32's was the plan getting less scrutiny than the spec.
Scaffolding built to close a gap is written last, reviewed least, and inherits
none of the scrutiny that produced it — and a *justification* written to close
a gap is the least reviewed artefact of all, because it reads as the premise
rather than as the new work.

**Normalise at the choke point, not in every writer.** The plan originally said
"every import adapter", which is an enumeration — and enumerations are exactly
what the same document argues against for the join ratchet and for I1. Every
dance write in this codebase, local or imported, already funnels through
`DanceRepository._upsert`. Requiring the property at that single point means a
new adapter inherits it instead of restating it. Missing the choke point while
arguing against enumerations elsewhere in the same file is the failure this
design keeps rediscovering: a principle held in one section and not applied in
the next.

**Unpaired surrogates are the string-shaped version of NaN.** Dart strings are
UTF-16, so one can hold a lone surrogate; UTF-8 cannot encode it and therefore
neither can JCS. Implementations diverge on what to do — `U+FFFD`, WTF-8, or
throw — and any two that choose differently give one record two hashes, which
is the identical failure the NaN rule closes. Rejection rather than repair, for
the same reason: substituting `U+FFFD` converges only for as long as every
implementation picks the same substitution, and it alters user data whenever it
is wrong. Rejecting is loud, and loud is recoverable.

**The platform commits the forbidden repair for you, with no flag and no
error.** This is what makes the rule hard to implement correctly rather than
merely hard to remember. Measured against this repository's toolchain:
`utf8.encode('ab\uD800cd')` returns the bytes of `ab\uFFFDcd` and throws
nothing, and `jsonEncode` emits a `"\ud800"` escape without complaint. So the
natural implementation — canonicalise to a string, encode, hash — hashes the
*repaired* bytes and never sees an error.

Trace what that does, because it is worse than a rejected record. The sender
keeps its surrogate and hashes `U+FFFD`; the receiver stores `U+FFFD` and
hashes `U+FFFD`; both re-serialise to the same bytes on every subsequent pass.
The two devices agree on the hash forever while holding different strings, so
the record never presents as `changed` and nothing ever repairs it. The rule
exists to prevent one record having two byte strings, and the naive
implementation produces one hash over two *different* records instead — which
is strictly harder to detect. The check therefore has to run on the string,
before encoding, because encoding is where the evidence is destroyed.

The reviewer who raised this pointed at `utf8.decode(bytes, allowMalformed:
true)` on the receiving side, which is real but opt-in. The encode side is the
dangerous one precisely because there is nothing to opt into.

`sanitizeImportedText` did not catch it either, so a malformed import could put
one in the database where it sat invisibly until sync gave it consequences —
filed as [#1063](https://github.com/ibanner56/CallersCompendium/issues/1063) and
fixed by #1065, which strips and flags a lone surrogate of either half while
leaving valid pairs alone.

**The fix narrows this section without retiring it, and the reason is the same
one §4.1 spends four paragraphs on.** #1065 is a write-path repair, so it does
not reach a row imported before it — the identical population the NFC pass
exists for. And it changes nothing about the platform: `utf8.encode` still
substitutes silently, so a canonicaliser that checks after encoding is still
wrong no matter how clean its inputs were. Deleting this section on the strength
of "the sanitiser handles it now" would have removed a rule about the encoder
because a different component was fixed.

**This is entirely new code.** The archive codec emits keys in *insertion* order,
not lexicographic, and there is no SHA-256 anywhere in `packages/`. "Reuse the
archive codec" applies to the record *body*; the canonicalisation and hashing
layer is built for sync.

Three concrete divergences the golden tests must pin, each of which silently
degrades delta sync to full sync by giving two devices different hashes for the
same record:

- **Numbers.** `encodeCustomFieldValue` forces `.toDouble()`, so an integer `8`
  reaches the wire as `8.0`. An RFC 8785 canonicaliser rewrites that back to `8`
  — which is now the rule rather than one candidate.
- **Absent versus null.** The codec *omits* `deletedAt` when null; the blob
  envelope above shows `"deletedAt": null` present. Same record, two hashes.
  Policy: the envelope's fields are always present, `null` where empty; the
  body follows the sender rule in "Applying a record" — explicit `null` for
  empty `shareable` fields, omission only for `deviceLocal`.
- **Key order.** Lexicographic, applied recursively, regardless of what the
  codec produced — and "lexicographic" now means JCS's UTF-16 code unit order,
  which for our ASCII camelCase keys is the same order it always was, and for a
  future non-ASCII key is a rule rather than an assumption.

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

**Both of the endpoints that are not content-addressed carry a schema, and they
did not always.** The blob and the manifest are specified to the byte because
they are *hashed* — canonicalisation is a correctness requirement there, so the
document had no choice. `GET /v1/store` and `POST /v1/blobs/missing` are
ordinary JSON, nothing forced their shape, and for several rounds they were
described only in prose: "epoch, device list, quota usage". Two servers
emitting `devices` and `deviceIds` would both have satisfied that sentence and
only one would work with any given client.

The pattern is worth naming because it is not laziness and will recur: rigour
had accumulated wherever some other mechanism *demanded* it, and the places
nothing demanded it were invisible precisely because the surrounding document
looked so precise. `GET /v1/store` is also the endpoint that has already caused
a shipped defect of exactly this kind — alias pruning was once bounded on a
per-device watermark "that `GET /v1/store` already returns", which it does not
and cannot — and it was still, rounds later, the endpoint with no schema. The
fourth invariant says to check that the data a rule names is reachable on the
path where the rule runs; a reader can only do that where the path's shape is
written down.

Both request and response are objects rather than bare arrays, so either can
gain a field later without a version bump. A top-level array is the classic
shape that cannot be extended.

**`Content-Type` and `ETag` are pinned rather than left to convention**, and
this is the same gap as the schema one, one layer down: the payloads were
specified exactly, and the headers carrying them were never mentioned at all —
`Content-Type` appeared nowhere in the normative spec, and `ETag` appeared twice
without a definition, in a protocol that depends on `If-None-Match` for its
delta behaviour. Two implementations agreeing perfectly on bytes can still fail
to talk.

`ETag` on a manifest `GET` is the manifest's own content hash, as an RFC 7232
strong validator. Strong matters: a weak validator is defined as "equivalent for
practical purposes", which is exactly the judgement the merge algorithm must not
make. The value already exists and is already canonical, so the alternative —
an opaque server-chosen token — would have added a second identity for a thing
that has one, and made `304` mean something the client could not verify.

For `Content-Type`, servers must accept a `; charset=utf-8` parameter rather
than string-comparing the header, and must **not** treat a missing
`Content-Type` as an error, since the body's interpretation is fixed by the path
in every case. Rejecting an unsupported one with `415` is permitted but not
required. This is deliberately the most permissive rule in the contract: no
correctness property rests on the header, so every additional strictness here
buys nothing and creates one more way for a conforming client to be turned away.

### Status codes

| Code | Meaning |
| --- | --- |
| `200` | OK. |
| `201` | Blob or manifest created. |
| `204` | Deleted. |
| `304` | Manifest unchanged (`If-None-Match` matched). |
| `400` | Malformed request. |
| `401` | Missing or malformed `Authorization`. |
| `403` | Sync ID fails the structural rule — four hyphen-separated words (see Security). |
| `404` | No such blob, manifest or device. |
| `409` | **Epoch mismatch** — the client's epoch is not the store's. |
| `413` | Payload exceeds a cap. |
| `415` | Unsupported `Content-Type` (optional; see below). |
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
4. Upload every local record; download every remote record. **Inbound rejection
   applies here as in steady state** — a blob whose `existenceAt` or `updatedAt`
   is out of window is refused and reported, rather than admitted because this is
   an attach. The case is worth naming: a restore-triggered fresh attach drops
   the whole baseline, and the power loss that prompted a restore is also a
   common cause of a wrong clock, so the two arrive together more often than
   independently.
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
6. Persist the epoch and the resulting manifest as the new baseline. **Quarantine
   and repair run after this**, never during the union, so a wipe never presents
   a record to the missing-entry rule looking like one that was never agreed, and
   a locally quarantined record — which is not uploaded — cannot win the union
   with a value this device already knows is impossible. A record
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

**`normalizeTitle` is specified by reference, not paraphrase**, and the reason
is a defect caught in round 30 rather than a stylistic preference. The normative
spec had restated the rule in four steps — NFC, trim, collapse whitespace,
lowercase — which is a fair description of what a title normaliser *usually*
does and is not what this one does. The shipped function also folds diacritics,
replaces punctuation with spaces, and strips a single leading `the`/`a`/`an`.
A second implementation built faithfully from that restatement would agree with
the client on every lowercase ASCII fixture anyone would think to write, and
disagree on `The Nice Combination` — which is *precisely* the case dedupe is for.

Because this comparison merges records **silently**, a disagreement here is not
a missed merge that a user could notice and repeat: it is two devices holding
different opinions about how many dances exist, with no prompt and no queue
entry on either. So the paraphrase is gone. Where a document names real code and
then also describes it, it has published two definitions and only one of them is
under test.

The NFD hazard is worth calling out because it is not obvious even with the
implementation in front of you. The diacritic fold is a lookup table keyed on
*precomposed* characters, so a combining mark misses it entirely and is then
caught by the punctuation rule, which turns it into a **space**. `résumé` folds
to `resume` in NFC and to `re sume` in NFD. A *trailing* accent is harmless, as
the injected space gets trimmed — so the failure shows up only on interior
accents, which is exactly the distribution that makes a bug get filed as
"sometimes duplicates my French dance titles" and never reproduced. Requiring
NFC on ingest fixes this at the boundary; extending the fold table would not,
since the combining sequence has no single character to key on.

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
schema change beyond the sync migration alongside `id_aliases`. Deferring an
item is a write,
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
   | absent from baseline, present locally | absent remotely | upload (new here) |
   | absent locally | absent from baseline, present remotely | download (new elsewhere) |
   | absent from baseline, present locally | absent from baseline, present remotely | resolve as `changed`/`changed` |

   **The last row was missing for twenty-nine review rounds**, and its absence
   is the most consequential defect this design has carried: the two rows above
   it were each written one-sided, with a `—` that reads as "not applicable"
   but functions as "anything". A record absent from the baseline and present on
   *both* sides matched both, so the table said "upload" **and** "download" for
   a single case. Two engineers implementing it faithfully would pick different
   halves and their devices would disagree forever — in the one table whose
   entire purpose is convergence, and with nothing in either implementation
   looking wrong.

   What makes it worse than a typo is that the case is ordinary. Settings
   records are keyed by the settings key itself rather than a UUID, so two
   devices that each set `theme_mode` create the same id independently; 47 of
   the settings keys carry the shareable `_preference` classification. Records
   with UUID ids get there too, since archive import preserves ids.

   The fix invents nothing. `changed`/`changed` already means "both sides moved
   away from a common reference", which is exactly this — the reference is just
   absence rather than a hash. And the correct rule was already written down in
   the fresh-attach union above, which specifies precisely this collision; it
   had simply never been lifted into steady state. That is the recurring shape:
   not an unanswered question, but an answer living in only one of the two
   places that need it.

   **A quarantined record is excluded from this table entirely**, in steady state
   exactly as in a fresh attach's union: its local row is retained, nothing is
   uploaded, and repair is its only route back. Leaving it in would be worse than
   inert — `local.updatedAt` has no source but the live local row, which for a
   quarantined record is the poisoned value, so no honest peer could ever exceed
   it and the record would sit permanently frozen while appearing to participate.
   The exclusion was first written for the union, where the wrong outcome was
   easiest to see; it governs both, and the merge table is where an implementer
   looks.

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
   `settings`, gain it in the sync migration. A kind without a modification timestamp
   cannot participate in this rule at all, which is why the migration is a prerequisite
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

#### No write may stamp a timestamp and change nothing else

> **Every write that advances `updatedAt` must also change the record's `body`
> or its existence state.**

The converse of the invariant above, and load-bearing for the *repair*
classifier rather than the merge. Repair decides whether this device edited by
comparing body hashes; a write that moved a timestamp while leaving both the body
and the existence state untouched would be invisible to that comparison, and the
record would be classified as unedited and have its timestamp adopted from a
peer.

Today no such write exists — every `updatedAt`-poisoning path either changes the
body, where the comparison is correct, or changes existence, where content is
moot. That is currently a **coincidence of the write paths**, not a guarantee,
and it is written down here so it stops being one: a "touch", a favourite flag, a
sync-envelope field held outside the body hash, or any metadata-only re-stamp
would break repair silently and without resembling a sync change at the point it
was added. Any new write is checked against this the way new write paths are
checked against the discriminator rule above.

5. `POST /v1/blobs/missing` with the hashes to upload; `PUT` only what is
   missing.
6. `GET /v1/blobs/{hash}` for each needed hash. **Verify the hash before
   applying.**
7. Apply in one transaction, **read-modify-write** (below). Rebuild derived
   indexes.
8. `PUT /v1/manifests/{self}`.
9. Store the new baseline. A record's entry advances only where a peer's
   manifest was observed to carry **this device's current content hash** — an
   upload not yet reflected by any peer is not agreement, and quarantine repair
   reads this table to decide whether *this* device edited. Keyed to the current
   hash rather than to whatever was last published, so that a quarantined
   record's advertised fallback cannot echo back and read as agreement.

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
no more evidence against them than a re-seeded store is. `published_records`
does not clear either, and unlike `pending_deletions` it needs no revalidation:
its rows are read only when the record they name is about to be hard-deleted, so
one left pointing at a record the restore removed is simply never consulted.

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

**`Programs.venueId` is the one exception, and it is resolved rather than
skipped.** It is a soft reference — no database foreign key, integrity enforced
at the app layer — so a dangling value cannot corrupt the batch, and skipping the
program would withhold a caller's whole set list because one venue has not
arrived. Apply therefore **nulls a `venueId` with no matching local venue before
the program reaches the repository**, exactly as the import path already does,
and reports it; the program arrives complete apart from its venue link, and a
later pass carrying the venue does not restore the link automatically.

This step is required rather than optional. `ProgramRepository` **throws** on a
non-null `venueId` with no matching venue — it is the only write path for
programs — so an apply that passed one through would abort. The precedent is
exact: `ArchiveRestorer` already clears a dangling `venueId` before writing a
program from an untrusted bundle, for the same reason and with the same effect.
A draft asserted that such a program "commits fine and simply arrives without its
venue link", which was true of neither the repository nor the skipped-and-reported
rule above it: three sections gave three different answers, and only this one is
implementable.

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

**Every path that turns a caller-supplied hash into a filesystem path validates
it against `^[0-9a-f]{64}$` first.** An earlier draft argued traversal-safety
from the hash being "verified" — but verification happens on `PUT`, where the
body is hashed. Everywhere else the hash is attacker-controlled path input
fanned into `blobs/<aa>/<bb>/<hash>` with nothing checking it. The guard
belongs on every path, not on the one that happens to compute a hash.

**Stating that as a list of methods got it wrong twice**, which is the argument
for stating it as a property. The draft said "on `GET` and `DELETE` as well as
`PUT`" — but blobs have no `DELETE` endpoint at all (removal is GC), so a third
of the enumeration guarded nothing, while `POST /v1/blobs/missing` takes a
caller-supplied list of hashes and was not named despite being the one endpoint
that accepts them in bulk. The property "caller-supplied hash becomes a path"
selects the right set without needing the contract re-read each time it changes.

The GC sweep reads hashes from the database rather than from a caller, so it is
not covered by that property, and it applies the check anyway: a row written
before this rule existed would otherwise escape it.

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

**Reachability alone is not a safe collection rule, and the first draft of this
section used it as one.** The client uploads blobs at step 5 and publishes its
manifest at step 8, with a full download-and-apply in between, so every upload
spends a window referenced by no manifest at all. A concurrent peer's manifest
`PUT` during that window triggers store-scoped GC and deletes a blob that is
about to be published; the hourly sweep does the same thing with one device.
Implemented literally, the rule deletes live user data under ordinary
two-device concurrency — not under a race that needs arranging.

The mistake is worth naming precisely, because it is not a missing case: the
rule was written from the steady state, where "referenced by a manifest" and
"live" coincide, and it silently assumed publication was atomic with upload.
The protocol is deliberately *not* atomic there — the whole point of uploading
before publishing is that a manifest never names a blob a peer cannot fetch.
So the safety property that makes step 8 correct is exactly what makes the GC
rule wrong, and reading either half alone reads as sound.

A recent upload is therefore a temporary root: unreferenced blobs younger than
24 hours are never collected. The alternatives — an upload session, or a
client-declared set of intended hashes — both give the server per-client state
and a new endpoint to manage it, which is precisely the interpretation-free
posture the rest of §7 buys its testability with. An age bound needs one column
and no protocol.

The number is chosen against the window it protects rather than tuned: steps 5
to 8 are a single pass bounded by request timeouts, so the exposure is seconds
to minutes and 24 hours is three orders of magnitude of margin. Being generous
is close to free, because unreferenced blobs are already bounded by the 250 MB
store cap, and because an abandoned upload is *reused* rather than duplicated —
the next pass's `POST /v1/blobs/missing` reports it present.

The residual case is a pass that stalls past the grace period and then
publishes, naming a blob that was collected. That resolves without a new rule:
a peer that cannot fetch a blob treats it as an unresolved reference and skips
and reports the record, and the origin device re-uploads on its next pass
because `blobs/missing` reports it missing again. That downstream behaviour had
to be written down too — the spec said what a client does when a *record*
reference cannot be resolved and said nothing about a failed blob fetch, and
the dangerous default reading is that an unfetchable record has gone away.
Absence never deletes, on this path as on every other.

Being generous is close to free in *space*, but it is not free in *time*, and
that is a second residual worth stating because §5.3 quietly assumes otherwise.
`507` is documented as something only user action clears — which is true of the
cause and false of the timing. Grace-protected blobs are immune for 24 hours, so
a user who hits the quota, deletes records and detaches a device can do
everything right and still see `507` on the next pass. The bound on *space* says
nothing about the duration of denial. The only in-band remedy that acts at once
is `DELETE /v1/store`, which is destructive and must not be the first thing
offered. So the client's obligation is presentational rather than protocol-level:
report the quota error as temporary and not as a failure of what the user just
did. Making the grace window shorter would trade this against the correctness
margin above, which is the wrong direction — a confusing error beats a deleted
blob.

**That sentence was, strictly, not yet true when it was written.** "The only
in-band remedy that acts at once is `DELETE /v1/store`" presumes the wipe
ignores the grace window, and the grace rule was scoped to "after each manifest
`PUT`, and during the sweep" — it never named `DELETE`, so a server author
following the letter had every reason to apply the age bound there too and leave
recently-uploaded blobs behind. The user's escape hatch from a quota error would
then not clear the quota, and the one remedy offered as immediate would be the
one that visibly did nothing. `DELETE /v1/store` now deletes unconditionally.

The recurring shape is worth naming, because this is two rounds running: a fix
and the rule it depends on land in the same commit, each correct, and their
*interaction* goes unstated. Last round it was a no-op blob `PUT` refreshing
`uploaded_at`, which the no-op rule did not cover because it spoke only of
*bytes*. The grace window and the wipe were written a few paragraphs apart in
one sitting. Reading either one alone raises nothing.

### Who mints the epoch

Only the server, and this needs saying because the client-facing half of the
mechanism reads as complete without it: the manifest carries an `epoch`, a
client compares it every pass and fresh-attaches when it differs, and the
status table lists `409 Epoch mismatch`. None of that says who produces the
value, and an implementer building strictly from the server section would ship
a server that never emits `409` at all.

Two facts belong to the server alone. A client cannot mint an epoch, because
two devices creating the same store concurrently would choose different values
and each would read the other as a reset; the atomic upsert that resolves the
creation race must hand *both* callers the same row. And every re-creation must
mint a **fresh** value — first contact, after `DELETE /v1/store`, and after a
TTL reap — never derived from the sync ID and never reused.

That last rule is the load-bearing one, and its failure mode is silent in the
worst way. Reset detection is the *only* mechanism by which a peer learns the
store was wiped. An implementation that derives the epoch from the `id_key`, or
restores it with a backup, looks correct in every test that does not wipe a
store: peers keep syncing, their baselines still describe a store that no
longer exists, and each one believes every record the store now lacks was
deleted by someone. Nothing reports an error. Deriving the epoch is the obvious
convenience — it removes a random value from a schema — which is why it is
prohibited explicitly rather than left to judgement.

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
- **Two checks, not one, and they are enforced in different places.** The
  **format** is fixed at four hyphen-separated words, which rejects
  `isaac-banner-dances` structurally, and is enforced on **both** sides — the
  server returns `403` for it, because it is a mechanical rule two
  implementations cannot disagree about. That last clause was aspirational
  until round 30: the rule also required each word to fall "within the length
  bounds", and no section defined them, so the one check described as
  disagreement-proof was the one carrying an undefined constant. The bounds are
  now stated as numbers — 1 to 32 code points per word — and chosen to be far
  looser than anything the client emits, since generated IDs run 15 to 39
  characters against an EFF wordlist whose words are 3 to 9 long. The minimum
  of 1 exists to reject an *empty* word and nothing else: a one-character word
  is weak, but weakness is the client's business, and a server tightening the
  minimum to look sensible would be re-implementing the estimator the next
  paragraph forbids. Normalisation is pinned for the same reason — trim, NFC,
  locale-independent lowercase, applied identically on both sides before the
  HMAC — because a disagreement there does not produce a `403`, it produces a
  second, empty store and a sync that reports success.

  A **strength floor of ~2⁴⁰**, scored on the actual string, then rejects four
  *weak* words that satisfy the pattern; that one is enforced **client-side, at
  the point of choice**, and
  the server deliberately does not re-run it. Estimating the strength of an
  arbitrary string is a heuristic with no canonical definition, so a server
  even slightly stricter than the client would reject an ID the user had
  already adopted — and because the ID *is* the store address, that is a
  lockout from their own data, indistinguishable from an outage. The permissive
  direction costs a weak self-chosen ID whose residual risk is bounded by rate
  limits and borne by the chooser. A warning alone would have stopped neither.
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
- **Redirects are followed manually with per-hop validation**, taking the
  pattern from `_sendFollowingHttpsRedirects` in `artifact_downloader.dart`, and
  `package:http`'s default `followRedirects = true` is not used. This is a
  **recurring** defect class in this codebase — found and fixed once in the
  ContraDB search path (#765), still open in the update-manifest fetcher (#784)
  — so the sync client adopts the hardened pattern from the start rather than
  becoming the third instance.
- **Every hop must match the configured endpoint's origin, and the credential
  must never cross one that does not.** This was missing until round 31, and how
  it went missing is the more useful part. The spec cited the precedent and then
  paraphrased it as "https only, no userinfo, default port, hop cap" — an
  accurate list of that helper's *incidental* checks and a complete omission of
  its actual safety property, the `isAllowedArtifactHost` call re-run on every
  hop (`artifact_downloader.dart:412`), which its own doc comment names as what
  closes "the downgrade/exfil hole". Every rule that survived the paraphrase
  constrains what a hop looks like; the one that was dropped constrains where it
  can go.
- **The precedent is also weaker than what sync needs, which the citation
  concealed.** The artifact downloader sends no `Authorization` at all, so for
  it a followed redirect leaks nothing but the fact of a download. The sync
  client puts the sync ID in `Authorization` on every request, and that ID is
  not a session token: it is the store address *and* the full read, write and
  `DELETE` credential, with no accounts, no rotation and no revocation. One
  credentialed hop to a foreign origin is unrecoverable, total compromise of
  everything the user has ever synced. Inheriting a precedent's rules is only
  safe when the new caller's exposure is no greater than the old one's, and here
  it is strictly greater.
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
- **A record new on both devices at once converges** — the row that was missing
  until round 30. Two devices each set the same shareable settings key (whose id
  *is* the key, so they collide without coordination), then sync. Assert they
  agree afterwards. Mutation-proved twice, and it must be both: resolve the case
  as unconditional upload, then as unconditional download. Each mutation is one
  of the two one-sided rows applied in isolation, each passes every
  single-device test, and each leaves two devices permanently divergent — which
  is why the fixture has to be two-device to mean anything.
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
- **A fresh-attach tie is reported, not swallowed** — two devices attach holding
  the same id with different bodies and identical `updatedAt`; assert neither
  body is applied over the other, that both devices report the divergence, and
  that a following steady pass reports it again. Mutation-proved by dropping the
  report, **not** by changing which body survives: keeping local *is* the
  specified behaviour, so a mutation that picks local is indistinguishable from
  the rule and the test would pass against it. The harm here is silence rather
  than the pick — the two devices do not converge either way, which is why this
  sits in the deferred list — and a divergence nobody is told about is the one
  outcome the rule excludes. Fresh attach is also the case the tie rule's own
  justification cites as a same-second-edit generator, so leaving it unspecified
  would have manufactured exactly the state the rule exists to surface.
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
  This is the guard that would have caught the non-convergent tie-break before
  it reached review; a one-sided test passes happily
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
  already holds the key the suffix would produce; assert the apply commits and
  that the escalation lands on the full 32-digit form, not an intermediate
  length. Mutation-proved three ways, since each leaves the others passing:
  switch the derivation to a `_2` counter, which violates `UNIQUE` and fails
  every retry identically; derive the suffix from the **surviving** UUID instead
  of the losing one, which hands two distinct losers the same key and so needs a
  three-device fixture to catch — two devices agree on the survivor, so a
  two-device test passes against both derivations; and lengthen progressively,
  which makes the second candidate depend on how many keys a device happens to
  hold rather than on the collision itself.
- **Alias chains resolve transitively** — build `Z→Y` then `Y→X` across three
  devices, then apply a blob referencing Z; assert it reaches X's live row.
  Mutation-proved by resolving a single hop, which lands on a UUID with no row
  and discards the batch.
- **A pending tombstone is never republished** — device B still cites a
  choreographer A deleted; assert B holds the deletion pending, does **not**
  re-upload the entity as live, and applies the deletion once its last citation
  goes. Mutation-proved by republishing instead: A then downloads its own
  deletion back and the entity is live everywhere, permanently.
- **A published record tombstones instead of hard-deleting** — publish a record
  in one pass, then trigger a hard-delete path (an import undo) before any peer
  has echoed the hash; assert a tombstone is written and the row is not removed.
  Mutation-proved by testing forfeiture against the baseline instead of the
  publication marker: the baseline advances only once a peer carries the hash, so
  the record reads as "never published" for a full pass after its bytes went up,
  the hard delete goes through, and the peer that already downloaded it
  republishes it on every pass afterwards. The window is narrow, which is the
  point — it is a one-pass version of the hole the forfeiture rule exists to
  close, and it reopens without anyone misreading the rule.
- **Detach and re-attach does not reverse a completed deletion** — publish a
  record, detach, hard-delete it locally, then re-attach against a peer that
  still holds it live; assert the deletion stands. Mutation-proved by clearing
  `published_records` on detach, which is what the first draft of this rule
  specified: the forfeiture check then reads "never published", the row is
  removed with no tombstone, and the re-attach union — having nothing local to
  compare against — downloads the peer's live copy back. Worth its own test
  rather than folding into the bullet above, because that one exercises the
  crash-timing window and passes happily against a detach that clears.
- **Reconciliation carries the publication marker onto the survivor** — mark a
  pre-existing record as published, reconcile a just-imported record onto it
  such that the *imported* id survives, then hard-delete the survivor via the
  import's undo while a peer still advertises the losing id. Assert a tombstone
  is written. Mutation-proved by remapping `id_aliases` without remapping the
  marker: the survivor reads as never published, the hard delete proceeds, and
  the peer's next manifest reintroduces the record through the alias. The union
  direction matters — a marker on *either* id must mark the survivor.
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
- **Title normalisation agrees across both implementations on the cases the
  paraphrase missed** — a leading article, interior punctuation, folded
  diacritics, and NFC versus NFD. Mutation-proved by implementing the four-step
  paraphrase (NFC, trim, collapse, lowercase), which passes every lowercase
  ASCII fixture and fails on `The Nice Combination`. Assert against
  `normalizeTitle` directly rather than a copy, or the test re-creates the
  second definition it exists to prevent.
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
  clock-suspect, rebuilds nothing, and reverts no deletions. Mutation-proved by
  restoring the `localNow` fallback, which quarantines every record, repairs them
  all downward, and lets the peers' live copies outrank a subsequent deletion.
  This is the direction the one-sided bounds invert on, and no other test covers
  it.
- **Repair does not push stale content** — a peer legitimately edits a record
  while the poisoned device is offline holding older content; repair the poisoned
  device and assert the peer's edit survives. The poisoned device never edited,
  so its content still matches its own baseline and the peer value is adopted
  verbatim. Mutation-proved two ways, both of which make the stale copy outrank
  the peer and lose its edit fleet-wide: restamp `peer + 1 tick`
  unconditionally, or
  classify on local content differing from **the peer's** rather than from the
  baseline — the latter is the subtler mutation, because a poisoned discriminator
  causes exactly the staleness that makes those two comparisons disagree.
- **A timestamp-only change is not read as an edit** — soft-delete a record on a
  clock-broken device without touching its content, then repair; assert the
  verbatim branch is taken. Mutation-proved by comparing the **whole-blob** hash
  instead of the body hash: `softDelete` moves `deletedAt` and `updatedAt`, so
  the blob hash always differs and every quarantined record is misclassified as
  edited — the comparator answering constantly in the one case it exists for.
- **An unconfirmed upload is not agreement** — a device with a fast clock uploads
  a poisoned blob that every peer refuses; assert its baseline does **not**
  advance, so a later repair still classifies the record as locally edited.
  Mutation-proved by advancing the baseline on upload, after which repair
  compares the record against a baseline set by the very write being repaired,
  matches, adopts the peers' older `updatedAt`, and strands newer content at an
  equal timestamp where the strict-`>` gate moves nothing in either direction.
- **A local edit made while poisoned survives repair** — the mirror case: the
  device edits a quarantined record, so its content diverges from its own
  baseline; assert the repaired `updatedAt` outranks the peer's and the edit
  propagates. This and the test above are the pair that must *both* pass, which
  is what the baseline classifier buys and what no local-versus-peer rule could
  provide.
- **An in-window `updatedAt` is never touched by repair** — edit a quarantined
  record locally so its `updatedAt` is recent and plausible, then repair; assert
  it survives untouched while the out-of-window `existenceAt` is rebuilt.
  Mutation-proved by rebuilding every field rather than only out-of-window ones,
  which back-dates the genuine edit to the peer's timestamp and loses it to an
  older edit elsewhere. This and the poisoned-`updatedAt` test below are the pair
  an earlier draft could not satisfy at once; they are compatible now because the
  window classifies the value, not its magnitude against the peer's.
- **A solo device is not clock-suspect** — quarantine a record with no peers
  observable at all; assert the device does *not* declare itself the outlier,
  the record stays quarantined and reported, and repair resumes when a peer
  attaches. Mutation-proved by treating the empty set as "every observed value is
  out of range", which condemns every single-device install on no evidence.
- **Clock-suspect clears itself and does not stop the app** — assert it is
  recomputed per pass rather than stored, that a corrected clock recovers on the
  following pass with no explicit transition, and that user creates, edits and
  deletes still succeed while it holds.
- **Concurrent repairers with differing content tie rather than converging** —
  two devices repair the same record in the same window against the same peers;
  assert the documented outcome, which is a reported bilateral divergence, not a
  silent winner. This asserts a limitation rather than a guarantee, and exists
  because an earlier draft claimed convergence here.
- **An out-of-window `updatedAt` is rebuilt, even when only it is poisoned** —
  a record whose `existenceAt` is fine but whose `updatedAt` is far future;
  assert it quarantines and repairs. Mutation-proved by quarantining on
  `existenceAt` alone, which leaves the poison uncatchable for ever, since
  `updatedAt` has no inbound rejection to stop it either.
- **The fast-clock report fires on rejection, not on staleness** — a healthy
  device paired with a peer that has not synced in a month; assert it does *not*
  report. Then refuse its uploads for three consecutive passes and assert it
  does. Mutation-proved by testing whether peer values trail this device's by
  more than the window, which fires on the healthy pairing — the app's central
  usage pattern — and stays silent for a create-dominant device whose refused
  records no peer stores at all.
- **A poisoned `updatedAt` never enters circulation** — a device with a dead RTC
  makes an ordinary content edit, so its `existenceAt` is untouched and only its
  `updatedAt` is poisoned; assert peers refuse the blob rather than accepting it.
  Mutation-proved by rejecting inbound on `existenceAt` alone, after which the
  poison spreads, becomes the only value in circulation for that record, and
  repair — which reads no clock and sources only from peers — has nothing honest
  left to adopt.
- **A peer poisoned in one field is excluded only for that field** — a peer with
  a sound `existenceAt` and a poisoned `updatedAt`; assert it is still eligible
  when rebuilding `existenceAt` and excluded when rebuilding `updatedAt`.
  Mutation-proved by filtering both rebuilds on `existenceAt`, which adopts a
  value outside the local window and re-quarantines the record immediately.
- **A rebuilt value is re-checked before the record is called repaired** — assert
  a rebuild that would still land outside the local window leaves the record
  quarantined rather than reported as fixed. Include the peer-exactly-at-the-
  ceiling case, and assert the record stays quarantined there too. Mutation-proved
  by clamping to the ceiling instead: that is the *only* case the clamp can fire
  in, it ties the peer it was meant to outrank, and on `existenceAt` the standing
  tie rule then silently reverts a user's un-delete.
- **An upgraded record is not treated as never-agreed** — a device attached
  under the wire-hash-only scheme holds a record its peers have since edited
  past; poison its clock and repair. Assert the record is **quarantined**, not
  classified as locally edited. Mutation-proved by routing a wire-hash-only entry
  through the never-agreed comparison, which reads the device's stale content as
  its own edit and pushes it over the peers' genuine one.
- **An upgraded record poisoned *and* edited does not resolve on its own** — the
  sub-case the trivial upgrade test misses: local body differs from every peer's,
  so the record stays quarantined; assert that running passes does **not** clear
  it, and that a fresh in-window local write does. Mutation-proved by asserting
  it clears after one pass, which is what an earlier draft promised — agreement
  needs a peer to advertise this device's current hash, the wire hash covers the
  timestamps, and a quarantined record is never uploaded, so the three rules
  close a cycle and the record waits for ever.
- **An upgraded record poisoned but unedited repairs immediately** — local body
  equals a peer's, so content never diverged; assert the verbatim branch runs
  without waiting. This is the `softDelete`-poisoned case and the common one.
- **Repair adopts the matching peer's timestamp, not the greatest** — peer B
  holds the pre-poison body, peer C edited it later and in-window; assert the
  repaired record takes B's `updatedAt` alongside B's body. Mutation-proved by
  taking the global maximum, which pairs B's content with C's clock, leaves the
  pair at equal `updatedAt` against C, and permanently blocks C's genuine edit
  behind a strict-`>` gate.
- **A record citing a quarantined entity is withheld too** — create an entity on
  a broken clock, correct the clock, create a record citing it, and sync; assert
  the citing record is withheld until the entity is publishable. Mutation-proved
  by publishing it, after which a peer's batch fails at COMMIT on the cascading
  foreign key — the citing record is freshly stamped and not itself quarantined,
  so nothing else stops it.
- **Withholding reaches the second hop** — a program citing a dance citing a
  quarantined choreographer; assert the program is withheld too. Mutation-proved
  by testing only direct citations, where the dance is withheld but not
  quarantined, so the program publishes and its peer's batch fails on the same
  foreign key the rule exists to protect.
- **A program citing a quarantined venue still publishes** — assert the venue
  exemption holds, that the receiving peer nulls the dangling `venueId` before
  the write, and that the program applies with the rest of its content intact.
  Mutation-proved two ways: withhold the program, which costs a caller their set
  list because one venue has not arrived; or apply it without the resolve-or-null
  step, which throws in `ProgramRepository` and aborts the record.
- **Withholding is scoped by whether the reference is a database FK** — assert
  `ProgramSlots.danceId` and `DanceLinks.targetDanceId` trigger withholding and
  `Programs.venueId` does not. Mutation-proved by scoping on `onDelete`
  semantics, which exempts both real edges, since every FK in this schema is
  `cascade` or `setNull` and none is `restrict`.
- **A never-agreed quarantined entity does not clear by syncing** — assert that
  repeated passes leave it and its dependents withheld, that only a fresh
  in-window local write clears it, and that the report names how many records it
  is holding back. Mutation-proved by asserting it self-clears on the pass after
  repair, which is what a draft claimed and which no pass can deliver for a
  record with no peer copy and no baseline.
- **A quarantined record is excluded from the steady-state merge table** — assert
  it is neither uploaded nor treated as a conflict while quarantined, and that
  repair is its only route back. Mutation-proved by leaving it in the table,
  where its poisoned `local.updatedAt` cannot be exceeded by any honest peer and
  the record freezes while appearing to participate.
- **An advertised fallback does not read as agreement** — a quarantined record
  whose manifest advertises the last agreed hash; assert the baseline does not
  advance when a peer echoes it. Mutation-proved by keying agreement on "the hash
  it published", which records this device's own fallback as agreement, populates
  a null body hash from the poisoned body, and lands the edited sub-case on the
  verbatim branch.
- **A quarantined record advertises its last agreed hash** — assert the manifest
  entry names a hash peers can actually fetch, that the poisoned blob is not
  uploaded, and that a fresh-attaching peer downloading a dance citing that
  entity commits successfully. Mutation-proved two ways: advertise the current
  hash, and the entry names a blob nobody holds; omit the entry, and the peer's
  batch fails at COMMIT on the cascading foreign key.
- **A locally quarantined value is excluded from the union, not overwritten** —
  assert the local row survives arbitration and is handed to repair afterwards.
  Mutation-proved by letting the peer's value replace it, which discards a
  genuine local edit before any classifier runs.
- **A wiped baseline never reaches the never-agreed rule** — restore a backup,
  which drops the baseline and forces a fresh attach; assert the baseline is
  repersisted and quarantine/repair run only afterwards. Mutation-proved by
  running repair during the union, where a wiped entry is indistinguishable from
  a new record.
- **A quarantined record is not uploaded** — assert a locally quarantined record
  is absent from what the device publishes, including during a fresh attach.
  Mutation-proved by publishing it, after which "higher `updatedAt` wins" lets a
  value the device already knows is impossible beat a peer's genuine edit.
- **A create-then-edit before agreement is classified as edited** — create a
  record with a good clock, let peers accept it, then edit it while the clock is
  broken, all before a pass observes agreement; assert repair takes the
  differs-branch and the edit propagates. Mutation-proved by reading a missing
  baseline entry as agreement, which adopts the peers' older `updatedAt` and
  strands the newer content at an equal timestamp for ever.
- **An upgraded device recovers without inventing a baseline** — start from a
  device attached under the wire-hash-only scheme; assert the body hash is null
  after upgrade, that the missing-entry rule carries it, and that it populates on
  the first pass observing agreement. Mutation-proved by backfilling from current
  local content, which records every in-flight edit as agreed.
- **A poisoned `updatedAt` does not travel** — poison both fields on a deleting
  device, repair, and assert the blob peers receive carries neither. Mutation-
  proved by taking `max(local, peer + 1 tick)`: the poisoned value dominates the
  max, the record's clean tombstone then wins the existence decision, and the
  blob is applied wholesale — carrying the poison fleet-wide, where every
  honestly-stamped later edit loses until wall-clock time catches up.
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
- **Every read that resolves a soft-deletable parent id is enumerated** — the
  bullet above tests one join; this tests the *class*. The rule is stated in
  §3.1 as a property, and a property with no enumeration has no failure signal:
  a new read path that omits the filter compiles and passes. It has already
  decayed once, in shipped code — issue #1016, where
  `VenueRepository.externalIdToVenueId` resolved an archive re-import onto a
  tombstoned venue, so a program was written referencing a tombstone with no
  error, while `listAllIds` on the same class filtered correctly. #1018 fixed
  that read and changed nothing about the class. Two things make
  that instructive: the correct behaviour was already present *in the sibling
  method*, and the write-time guard that would have caught it exists but is
  bypassed on the `knownVenueIds` fast path. Neither a reviewer reading the
  class nor one reading the guard would see it. Mutation-proved by dropping the
  predicate from any one enumerated read.
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
- **RFC 8785 conformance vectors**, run directly. Adopting a standard by
  reference is only worth anything if the test suite comes with it.
- **A fractional shareable value hashes identically on two encoders** — set
  `custom_field_values.value_num` to a value whose shortest round-trip form and
  naive `toString()` differ, and assert one hash. Mutation-proved by emitting
  `double.toString()`. This is the case that makes JCS load-bearing rather than
  decorative: a real, shareable, user-entered `double` that rides inline in the
  `dance` blob.
- **NFC/NFD titles converge** — ingest the same title in both forms and assert
  one hash and one record. Mutation-proved by skipping normalisation on ingest,
  which reproduces a permanent `changed`/`changed` between two devices whose
  screens show the identical string.
- **A locally-created NFD title uploads as NFC** — create it through the app's
  own edit path, never through sync, and assert the first upload's bytes.
  Mutation-proved by scoping normalisation to inbound values, which is what the
  spec said until round 31. This one is worth writing even though the bullet
  above looks like it covers it: that test ingests *both* forms through the sync
  path, so it passes against the mutation. Only a string that never crossed the
  wire distinguishes the two scopes.
- **A `shareable` string carrying an unpaired surrogate is rejected** — not
  repaired. Mutation-proved by substituting `U+FFFD`: the record then syncs and
  converges against any implementation that made the same choice, and diverges
  silently against one that threw or emitted WTF-8.
- **The surrogate check runs before encoding** — assert the rejection happens
  on the string. Mutation-proved by moving the check after `utf8.encode`, which
  passes against a naive assertion because the encode *succeeds*: Dart has
  already substituted `U+FFFD` by then. Assert the specific failure, not merely
  that something failed. This is the case where two devices agree on a hash
  while holding different strings, so no later pass repairs it.
- **A row written before the normalising build is NFC afterwards** — seed a row
  in NFD, run the upgrade, assert it is NFC. Mutation-proved by normalising only
  on write: a library nobody has edited since is untouched, and §6.2 step 4
  uploads it verbatim. Neither NFC/NFD test above catches this, because both
  create their fixture through a path the fix already covers.
- **The backfill does not move `updated_at`** — capture the stamp before and
  after. Mutation-proved by bumping it: every normalised row is then won by
  whichever device upgraded last, which is a conflict storm over rows nobody
  touched.
- **A colliding pair is detected before any write, not by catching the
  violation** — seed two rows whose names normalise to the same `UNIQUE` value
  and assert **both** are left in their stored form. Mutation-proved by
  try-and-catch: the first row writes successfully, because the second still
  holds its own un-normalised value and nothing occupies the target yet, so
  exactly one member is normalised and which one depends on row order.
- **A tombstone blocks, and the block is temporary** — seed a live row whose
  only colliding partner is soft-deleted, assert the live row is skipped, purge
  the tombstone, re-open, assert the live row is now NFC. Mutation-proved twice:
  by excluding soft-deleted rows from the grouping, which makes the write fail
  against an index that does not filter `deleted_at`; and by treating the skip
  as final, which leaves a live row blocked forever by a record the user cannot
  see, list or act on.
- **Editing a blocked row succeeds** — mutation-proved by applying the write-path
  normalisation rule unconditionally, which rejects the user's edit to satisfy
  an internal invariant.
- **A retry is judged against the live column, not the recorded group** — record
  a skipped pair, create a third row holding the target in NFC, rename one
  member, re-open. Mutation-proved by judging membership: the group is down to
  one, the retry writes, and it raises against the third row — reintroducing at
  retry time the failure the initial pass forbids.
- **A tag and a choreographer sharing a name are both normalised** —
  mutation-proved by grouping on the target value alone rather than `(table,
  column, target)`. Worse than the collision it emerges from: a cross-table
  collision never stops colliding, so retry can never repair it.
- **A restore re-runs the pass** — restore a library holding an un-normalised
  row after the pass completed. Mutation-proved twice: keep the marker across
  restore, and the row is never scanned; or revalidate the recorded entries
  instead of clearing the marker, and nothing discovers a row that is in no
  entry.
- **A recorded mutually-colliding pair survives re-open still whole** —
  mutation-proved in both directions, because the two halves of the retry test
  fail oppositely: test live occupancy alone and neither member occupies the
  target, so the first row reached is written and the pair is split along an
  unspecified iteration order; test recorded-row grouping alone and a pair whose
  survivor was later renamed reads as a singleton, so the retry writes it into a
  third row that took the target in the meantime.
- **A crash between the pass's commit and its derived rebuild still leaves
  search matching the repaired rows** — mutation-proved twice: write the
  completion marker inside the mutation transaction, and the indexes hold
  pre-normalisation text forever, because every later pass writes nothing and
  a pass that wrote nothing must not rebuild; or omit the durable rebuild-owed
  flag, and the re-run's own rescan finds nothing left to rewrite and concludes
  no rebuild is owed.
- **No primary key enters the live in-scope set** — mutation-proved by deriving
  it as string ∩ `shareable` with no identity exclusion: `_key` is `shareable`,
  so every id column joins the scan and `settings.key` is renamed rather than
  repaired. The vector must assert the derived set, because a ratchet shaped
  like the classification coverage test passes this mutation unchanged.
- **A retry that rebuilds leaves no rebuild owed** — mutation-proved by clearing
  the flag alongside the completion marker, which retry never writes, so the
  next open performs a second whole-library rebuild nobody owed.
- **A crash between a *retry* write and its rebuild leaves search matching that
  row** — mutation-proved by setting the rebuild-owed flag only on the one-time
  pass: retry repairs a row, dies before the rebuild, and its next rescan finds
  nothing left to write and is forbidden from rebuilding.
- **The rebuild-owed flag is the key the generic pre-check reads** —
  mutation-proved by using a flag private to the pass, which nothing else
  consults, so the owed rebuild is never performed by anyone.
- **A column reclassified out of `shareable` and back in re-runs the pass** —
  mutation-proved by testing containment rather than inequality: the removal
  contracts nothing, the re-entry is contained, and rows that accrued NFD while
  out of scope are never scanned.
- **A newly `shareable` column enters the live in-scope set with no list
  edited** — mutation-proved by hand-enumerating the string columns, which
  disables the widening comparison at its input rather than at its logic.
- **A reclassified column re-runs the pass, with no migration involved** —
  mutation-proved by gating the re-run on a migration hook, which never fires,
  because changing a field's egress class is an edit to a map entry rather than
  a schema change.
- **Both writers of `normalisation_skips` spell `(table, column)` identically**
  — mutation-proved by giving the write-path carve-out the Dart accessor name
  while the pass uses the registry's snake_case form: entries for one column
  never group, the retry test stops correlating them, and nothing anywhere
  raises.
- **The retirement check reads through a lookup unfiltered by `deleted_at`** —
  mutation-proved by using the existing `getById` in any of the three
  repositories, which filters, so a tombstoned row is indistinguishable from a
  deleted one and an owed repair is dropped with no error raised anywhere.
- **A row recorded twice across an interrupted pass is still repairable** —
  mutation-proved by inserting rather than upserting: the duplicate satisfies
  the retry test against its own twin and the row is blocked forever for a
  collision that never existed.
- **Widening the set of `shareable` columns re-runs the pass** —
  mutation-proved by reclassifying a column and leaving the completion marker
  standing, after which its rows are never judged, never recorded, and repaired
  only if a user happens to rewrite each one by hand.
- **An entry whose row was hard-deleted is retired; one whose row was
  soft-deleted is not** — mutation-proved by retiring on soft delete, which
  drops a repair that is still owed because the tombstone still occupies the
  key, and by retiring on neither, which leaves entries accumulating behind an
  ordinary import undo with nothing for retry to recompute from.
- **`normalisation_skips` survives an epoch reset and a detach** —
  mutation-proved by clearing it with the baseline as `id_aliases` and
  `review_queue` do, which drops every owed repair on the next `409` while the
  marker still asserts the scan completed.
- **The pass does not rewrite `settings.key`** — mutation-proved by taking
  "every `shareable` string column" literally: the settings record is renamed
  rather than repaired. Inert today, since settings keys are ASCII constants,
  which is why the test matters more than the current behaviour.
- **An operation claiming I1's exception is proved over two databases, not two
  runs** — run it against a database where its cross-row dependency fires and
  one where it does not. Mutation-proved by asserting only the same-database
  property: it is satisfied by any deterministic operation, including one that
  reads every other row, so a deterministic sibling read whose result differs
  between devices passes unchanged. This is the hole §4.1's collision skip went
  through while its justifying sentence claimed the pass read nothing outside
  the row.
- **A record that would need NaN or ±Infinity is rejected** — not coerced to
  `null` or `0`. Mutation-proved by coercing: the record then syncs, silently
  carrying a value the user never entered, and still fails to converge.
- **A redirect to a foreign origin is refused and never credentialed** — assert
  both halves: the request fails, *and* no request bearing `Authorization` was
  issued to the other host. Mutation-proved by validating only scheme, userinfo
  and port, which is what the spec required until round 31: an https `302` to an
  attacker's host on port 443 with no userinfo passes every one of those checks
  and takes the sync ID with it. Asserting only that the download failed would
  pass against the mutation, because the leak happens before the failure.
- **Hostile peer blob** — the `ArgumentError` case; a malformed date rejects one
  record and does not abort the batch or escape the isolate.
- **An unmanifested blob survives collection** — upload a blob, have a *second*
  device `PUT` its manifest before the first publishes, then assert the blob is
  still fetchable. Mutation-proved by collecting every unreferenced blob
  regardless of age. A single-device version of this test cannot fail, because
  nothing triggers GC in the window.
- **`DELETE /v1/store` removes grace-protected blobs** — upload a blob, do not
  manifest it, wipe the store, assert nothing remains and the quota reads zero.
  Mutation-proved by applying the age bound to the wipe, which leaves the user's
  only immediate quota remedy silently ineffective.
- **A repeat blob `PUT` does not renew the grace window** — `PUT` an
  unreferenced blob, advance past 24 hours while re-`PUT`ting it each pass, and
  assert it is collected. Mutation-proved by refreshing `uploaded_at` on the
  no-op path, which makes the grace window bound nothing: a client that
  re-uploads the same never-manifested blob every pass keeps it forever. The
  no-op rule says the server must not overwrite the stored *bytes*, and
  `uploaded_at` is not bytes — the fix and the column it depends on landed in
  the same pass, and their interaction went unstated.
- **A wiped store is detected as wiped** — `DELETE /v1/store`, recreate, and
  assert a peer holding the old baseline fresh-attaches. Mutation-proved by
  deriving the epoch from the `id_key` so re-creation reproduces it; the peer
  then syncs happily against a store with no content and treats the absence as
  deletions.
- **A blob `GET` that 404s does not delete** — serve a manifest naming a hash
  the store lacks; assert the record is skipped and reported, the baseline does
  not advance, and nothing local is removed.
- **A weak-but-structurally-valid sync ID is accepted by the server** — the
  guard against re-implementing the strength estimator server-side, where a
  disagreement with the client is a lockout rather than a rejection.
- **Client and server derive one `id_key` from one typed ID** — feed the same ID
  with differing leading whitespace and in NFD, and assert a single store.
  Mutation-proved by normalising on the client only. This is the nastiest
  failure in the HTTP contract because it produces *no error*: the second device
  authenticates fine, gets a real store that happens to be empty, and reports a
  successful sync of nothing. Every other ID disagreement surfaces as a `403`.

## Resolved since first draft

Recorded so the reasoning is not re-litigated.

| Question | Ruling |
| --- | --- |
| Settings merge granularity | Per-key blobs, plus an `updated_at` column on `settings` in **the sync migration**, stamping existing rows at migration time. |
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
