# Design: Renaming, merging and deleting tags, authors and sources

*Design note N2 for audit findings FIND-3 and LIFE-5. Written 2026-10-29
against `origin/main` at `acacb05`, and re-checked after merging `main` at
`296b594`. Every `file:line` below is for `296b594` unless it names another
branch. Of the files cited, only `ux.md` moved between the two.*

**Status: decided, not built.** The maintainer asked for this note (below), and
on 2026-10-29/30 answered all seven of its questions, each as the note
recommended (N2-1 … N2-7 in `maintainer-decisions-2026-10-30.md` on
`claude/app-audit-categories-k2pdon`; this note's D-N2-*n* is the file's
N2-*n*). [Decisions](#decisions) quotes them. N2-1 leaves one choice to T1: the
fix for the open risk under [Merge](#merge). Everything still marked
**Recommendation** without a decision beside it is my view as the note's
author, with the alternative I rejected.

## What is already decided

The audit material lives on branch `claude/app-audit-categories-k2pdon`, under
`docs/dev/audits/2026-10-behavior/`. The maintainer's answers that bind this
note, quoted from `maintainer-decisions-2026-10-29.md` on that branch:

| Decision | Where | What it means here |
| --- | --- | --- |
| design-tags-people = (a) "Design note now" | `:322-325` | This note. |
| D-3 = (a): "people are 'author'" | `:24-27` | User-facing text says **author**, never "choreographer". The code and tables keep `choreographers`. Renaming existing strings belongs to U4, not to this work. |
| trash-policy = (b) "Trash doesn't protect" | `:127-130` | A dance in Recently deleted never blocks or changes a rename, merge or delete. |
| design-duplicates (FIND-9) = (c) "Drop it" | `:327-330` | This note does not propose a duplicate *dance* finder. Merging duplicate *sources* is in scope, because LIFE-5 names sources. |

The work plan's section for this note (`decided-work-plan.md:823-840` on the
same branch) lists the questions, and `:787-796` sets the constraints common to
all five notes. Each question has its own section below.

**Out of scope.** D-11 is still open, so nothing here places a Save or New
button or changes a screen header. The managers proposed below need neither:
they write immediately with Undo, and they create nothing.

## How it works today

| | Tags | Authors | Sources |
| --- | --- | --- | --- |
| Table | `tags` (`tables.dart:390-410`) | `choreographers` (`tables.dart:154-179`) | `published_sources` (`tables.dart:450-467`) |
| Natural key | `name`, `UNIQUE` | `name`, `UNIQUE` | none. `title` is not unique |
| Join | `dance_tags` (`:414-422`) | `dance_authors`, ordered (`:184-198`) | `dance_sources`, ordered, with `page` and `number` (`:473-489`) |
| Rename in the app | nowhere | the author details dialog, refused on a collision (`dance_editor_screen.dart:744-779`) | the source details dialog (`dance_editor_screen.dart:837-842`) |
| Delete in the app | only an Undo of batch tagging removes an *unused* tag it created (`dance_list_screen.dart:1516-1538`) | nowhere | nowhere |
| Merge in the app | only the sync review queue (`settings.md:1200-1225`) | the same | nowhere |
| Purge GC | erased with the last dance (`dance_repository.dart:2251-2316`) | the same | the same |

Four details shape every proposal below.

1. **Name matching is wider than the index.** The `UNIQUE` index compares
   bytes, but `naturalKeyMatchKey` folds case and composes NFC
   (`shareable_text.dart:40-53`), and `TagRepository.idByName` uses it
   (`tag_repository.dart:260-280`). So "Flowy" and "flowy" can both be stored,
   and the app treats them as the same name.
2. **A tag delete keeps its join rows.** `TagRepository.delete` tombstones the
   tag and leaves `dance_tags` alone, so a revived tag comes back with its
   dances (`tag_repository.dart:459-534`). Dance reads hide the tombstoned tag
   (`dance_repository.dart:3386-3410`), and a dance write leaves those rows in
   place (`:726-751`). Re-creating a tag under a deleted tag's name adopts the
   tombstone's id but **clears its join rows** (`existence.dart:385-400`), so
   the old dances do not get it back. Only a revival under the same id keeps
   them.
3. **Author and source deletes are guarded.** Both refuse while a *live*
   dance cites the row (`choreographer_repository.dart:267-291`,
   `published_source_repository.dart:143-161`). Dances in Recently deleted do
   not count, which already matches trash-policy (b).
4. **The GC erases silently and only sometimes.** The retention purge erases
   any author, source or tag that the purged dances were the last to cite, as
   long as the row was never published to Device Sync
   (`dance_repository.dart:2251-2316`). The GC takes a tag's colour, and an
   author's email, location and notes, with it. Removing the same tag from
   the same dance in the editor never removes the tag (LIFE-5).

Two comments in the code describe a feature that does not exist. Both get
fixed in the first branch below:

- `tag_repository.dart:465` says the tombstoning delete "is what the tag manager
  calls". No tag manager exists.
- `tag_colors_screen.dart:24-27` and `display_defaults.dart:158` both say
  nothing renames a tag. Those comments become false when this work lands.

## One model for all three kinds

Each kind gets the same three operations in `compendium_core`: **rename**,
**merge** and **delete**. The managers and the dance editor call these; no
screen writes join rows itself.

### Rename

A rename is an ordinary edit of the row's name. Its existing `upsert` path
already handles normalisation and sync stamping (`tag_repository.dart:89-212`,
`choreographer_repository.dart:65-200`).

- **Collision test.** Before writing, find **every** row, live or
  tombstoned, whose `naturalKeyMatchKey` equals the new name's, other than
  the row itself. That needs a new all-matches lookup; `idByName` will not
  do.
  - `idByName` returns a single id, with live rows sorted first
    (`tag_repository.dart:260-280`). On a case-only rename of a live "flowy"
    to "Flowy", it returns the row itself. That hides a tombstone holding the
    exact bytes "Flowy", and `upsert` then throws on it
    (`tag_repository.dart:98-100`, `duplicate_natural_key.dart:97-104`). It
    also hides a live case-variant whose id sorts after the renamed row, so
    the merge offer never appears.
  - A case-only rename is a plain rename only when that lookup finds
    nothing.
  - The default `idByName` skips tombstones (`tag_repository.dart:260-266`).
    A rename onto a name a tombstone holds would then reach `upsert` and
    throw `DuplicateNaturalKeyError` (`existence.dart:368-383`).
  - **Recommendation:** free **every** tombstone the lookup finds before
    anything writes the name, using the name-only tombstone write described
    under Merge. This applies whether or not a live match also exists: a
    folded match may hold different bytes from the name being written, but
    freeing it is harmless and saves working out which bytes collide.
    Rejected alternative: refuse, which would block a name the user can no
    longer see anywhere.
  - That write must not go through `upsert`. `applyUpsertExistence` clears
    `deleted_at` on every upsert (`existence.dart:250-256`), and with
    `localUserEdit` the upsert also cancels pending deletions
    (`tag_repository.dart:190-199`). Renaming a tombstone through `upsert`
    would therefore bring it back to life.
- **On a collision, offer a merge.** Don't refuse. The dialog says:
  "'Flowy' already exists. Merge 'Flowing' into it?", with **Keep editing**
  and **Merge**.
  - **More than one live match.** This can happen because the index compares
    bytes, so "flowy" and "FLOWY" can both be live. The dialog then lists
    every match, and **Merge** merges all of them and the renamed entry into
    one entry under the typed name.
  - Merging only one of them would leave a second live entry that the app
    treats as the same name.
  - **The user picks which match to merge into.** The dialog asks, and
    preselects the match whose bytes equal the typed name, if there is one.
    The chosen match is the one merged *into* in the sense used below: its
    fields, such as a tag's colour, are the survivor's. Every other match,
    and the renamed entry, is a loser.
  - The losers are merged into it one at a time, in ascending id order, in
    one transaction and with one Undo. That fixes the order for authors'
    fill-the-blanks (option (b) below). The dialog's discard list covers
    every loser.
  - The smaller-UUID rule still picks the surviving *id*, across all of
    them.
  - This is a question, not a destructive-action confirm. The user may not
    know the name is taken. `ux.md:201-202` limits *confirms* to actions with
    no Undo, and a merge has an Undo (below).
  - Button order follows D-1's pattern for the discard dialog.
- **Undo** writes the old name back. A snackbar through `showUndoSnackBar`
  (`undo_snack_bar.dart:52`) offers it.
- **Sources have no natural key,** so a source rename never collides.
- **Authors:** `ChoreographerRepository._refreshAuthorIndex`
  (`choreographer_repository.dart:203-222`) already keeps the search index's
  `authors` column in step with a rename. `PublishedSourceRepository` has no
  counterpart for the index's `sources` column (`database.dart:25-31`). I did
  not check whether another path rebuilds that column after a source edit.
  The source branch must check, and fix it if the column goes stale.

### Merge

A merge moves every citation of the **losing** row onto the **surviving** row,
then removes the loser. The user chooses what the merged entry is called and
holds. The user does not choose which *id* survives:

- **The surviving id is the lexicographically smaller UUID.** sync-spec §6.6
  requires this of "every 'which record survives' decision"
  (`sync-spec.md:3230-3232`), because a rule based on "this one" versus "that
  one" does not converge.
- This matters for a user merge too. If device A merges L into S while
  device B, offline, merges S into L, each device's alias would rewrite the
  other's dances back, bump them and re-upload them on every pass. Neither
  pending deletion would ever land.
- With the id rule, both devices keep the same id. The two merges then differ
  only in the survivor's fields, and last-writer-wins settles that like any
  edit.

So "Merge 'Flowing' into 'Flowy'" means: the result is called "Flowy" and holds
"Flowy"'s colour, whichever row's id it keeps. In the rest of this note, the
**survivor** is that result: the entry the user merged *into*, written under
the surviving id. The **loser** is the other entry.

The steps run in one transaction:

1. **Free the loser's name.** The loser is renamed to `<name>_<suffix>`, where
   `<suffix>` is the first eight hex digits of its UUID, with hyphens
   removed. If that name is taken, the suffix becomes all 32 digits, as
   §6.6's custom-field rule does (`sync-spec.md:3377-3392`).
   - Only this device derives the name, so it need not be deterministic the
     way the custom-field rule must be. The rule is borrowed for its shape,
     not for its convergence argument.
   - The rename goes through a new **name-only write**: it sets the name and
     bumps `updatedAt`. It leaves `deleted_at` and `existence_at` alone
     (§6.4) and cancels no pending deletion.
   - That write is valid under I2, because the body changes. It is not
     `upsert`, which revives (see [Rename](#rename)).

   Without step 1, three things go wrong, because the `UNIQUE` index also
   covers tombstones (§4.1):
   - **The survivor can't take the name.** When the smaller id belongs to
     "Flowing", the survivor needs "Flowy", which the loser holds.
   - **Re-creating the name adopts the merged-away row.** Typing "Bouncey"
     again would adopt the merged-away tombstone (`existence.dart:401-436`),
     while the alias still sends every inbound reference to that id onto the
     survivor.
   - **A peer's own record gets queued.** A peer that created the name on its
     own would put the pair in the review queue as "a device deleted
     something another device still has" (`settings.md:1203-1210`).
2. **Re-point the joins.** Every `dance_tags`, `dance_authors` or
   `dance_sources` row that names the loser moves to the survivor. Where a
   dance already cites both, the loser's row is dropped. Dances in Recently
   deleted are re-pointed too (trash-policy (b)), so restoring one shows the
   survivor.
   - Sync's reconciliation already does this in
     `CompendiumSyncStorage._rewriteLocalReferences`
     (`sync_storage.dart:5223-5425`).
   - **Recommendation:** extract that method into a storage helper that both
     sync and the user merge call. Rejected alternative: a second copy, which
     would let the two drift.
   - The method does no search-index refresh, so the merge must rebuild the
     index rows of every affected dance itself.
3. **Bump every affected dance** (`sync-spec.md` §6.5 I1, `:3093-3094`). Its
   serialised `tagIds`, `authorIds` or `sourceCitations` changed. The same
   helper already does this (`sync_storage.dart:5408-5424`).
4. **Write the survivor's fields.** It gets the chosen name, and fields
   combined as described under
   [Merging two authors' private details](#merging-two-authors-private-details)
   and the per-kind rules below.
5. **Tombstone the loser.** Do not erase it:
   - An erase leaves peers holding the loser live. With no tombstone, the next
     pass downloads it back (§3.1, `sync-spec.md:148-153`), and the alias
     would then apply that live copy to the survivor.
   - A tombstone is ordinary deletion evidence. A peer whose dances still cite
     the loser holds the deletion pending until the last citation goes
     (§6.8, `sync-spec.md:3724-3734`).
   - Sync's reconciliation erases its loser (`sync_storage.dart:5181-5182`),
     and can afford to, because every device reaches the same decision. A
     user merge is made on one device, so its peers learn of it only through
     the tombstone.
6. **Record the alias, loser to survivor,** through
   `SyncLocalRepository.remapIdentity` (`sync_local_repository.dart:752-802`).
   Use that, not the bare `upsertAlias`: it also collapses alias chains,
   moves retained sync fields, and unions publication markers, as §6.6
   requires (`sync-spec.md:3433-3440`).
   - Sync rewrites each inbound record through the aliases before applying it:
     both its references and its **own** id (`_rewriteCandidate`,
     `sync_storage.dart:4012-4033`; `rewriteSyncInboundReferences`,
     `sync_reconciliation.dart:60-110`).
   - So when a peer that tagged a dance with the loser *while offline* syncs,
     this device files the tag under the survivor, bumps the dance and
     re-uploads it. The peer then drops its last citation, and its pending
     deletion of the loser lands.
   - A peer's edit *of the loser itself* lands on the survivor too. After the
     merge they are one entry, so that is the intended reading, but the §6.6
     amendment must say so.
7. **Rewrite `default_import_tag_names`** (tags only). The loser's name is
   replaced by the chosen name, then de-duplicated. See
   [The import-tags setting](#the-import-tags-setting).

**Undo** restores the transaction's before-image:

1. the survivor's fields are restored first, so that its old name is free
   again for the loser;
2. the loser is revived under its old name, and its fields restored;
3. the captured joins are put back, with author and source positions and
   citation page and number;
4. what `remapIdentity` changed is put back from its before-image:
   - the new alias is removed, and the `id_aliases` rows its chain collapse
     rewrote are restored;
   - the `retained_sync_fields` of both ids are restored
     (`moveRetainedSyncFields`, `sync_local_repository.dart:657-684`, deletes
     the loser's and may copy them to the survivor);
   - the survivor's `published_records` marker **stays**. §6.6 says a marker
     is never dropped (`sync-spec.md:3433-3440`), and a pass between the
     merge and the Undo may have published the survivor in its own right.
     Over-marking costs only that the purge GC never erases the survivor;
5. the import-tags setting is restored;
6. every touched dance is bumped again.

If a sync pass ran in between, the revival stamps above the tombstone (§6.4,
`sync-spec.md:3036-3040`), so peers converge on the undone state as ordinary
edits. Sync itself removes aliases only by retirement (`retireAliases`,
`sync_local_repository.dart:804-833`) and by clearing the baseline (`:522`).
Reversing `remapIdentity` is new; T1 adds it.

**This needs no wire change and no capability.** A merge adds no record kind
and no settings key, so §6.15's gate (`sync-spec.md:4417`) does not apply. It
uses only edits, tombstones and local aliases, which every build since sync
shipped already applies.

It does need a dated amendment to §6.6's "The remap"
(`sync-spec.md:3427-3443`). Today two things write aliases: reconciliation,
and the fresh-attach dance merge (§6.10, `sync-spec.md:4084-4088`). The
amendment adds the user merge, together with the rules above. The maintainer
approved the amendment (D-N2-1 = N2-1 (a), 2026-10-30); T1 writes it.

**What the alias does not cover.** An alias is retired once no current peer
manifest lists the losing id (`sync-spec.md:3430-3431`), and every alias is
dropped when the baseline is cleared at an epoch reset. Suppose a peer has
been offline since before the merge and syncs after either of those. Its old
citations of the loser then arrive as citations of a local tombstone, and are
not rewritten. I did not trace what apply does with such a citation. T1 must
test it and say what it found.

**Cases T1's two-device tests must pin.** I traced these from the code and
the spec. I did not run them.

- Opposite merges on two offline devices: both keep the smaller id, and the
  survivor's fields settle by last-writer-wins.
- A merge on A while B, offline, renames the loser: B's edit lands on the
  survivor on A, and the tombstone should win on B (§6.4: a rename is an
  edit, not a revival).
- **The open risk: a peer that holds the deletion pending.** §6.8 keeps a
  held row live, under its old name (`sync-spec.md:3730`), so the suffixed
  name never reaches that peer's row.
  - When the survivor arrives renamed onto that name, the peer queues it as
    "renamed onto a name this device already uses" (§6.6 step 1,
    `sync-spec.md:3246-3262`).
  - While that row stands, the peer skips the survivor's update on every
    pass (`sync-spec.md:3263-3264`). That lasts as long as the peer's own
    citations of the loser do, which is exactly the offline-citation case
    the alias exists for.
  - The same happens briefly, on any peer, if the survivor's rename is
    applied before the loser's tombstone.
  - **Two other operations have the same exposure.** An Undo of a merge
    renames the survivor away and revives the loser under the old name, so a
    peer that applies the revival first queues it too. A rename that frees a
    name held by a tombstone (see [Rename](#rename)) collides on a peer
    holding that tombstone's deletion pending. T1 tests both, and also
    whether an unheld peer takes a name edit to a tombstone it has already
    applied.
  - T1 must settle this before it builds anything else. The candidate fixes
    are: apply a held row's name from its tombstone while keeping the row
    live, or order natural-key tombstones before renames. Both are spec
    changes, so they belong in D-N2-1's amendment. N2-1's decision text says
    so: "T1 must still choose the fix for one open risk." Choosing it is T1's
    call, stated with its rejected alternative in the PR, not a maintainer
    decision.
  - It arises whenever the survivor's final name equals, byte for byte, a
    name a loser held before step 1 freed it. In a two-entry merge, that
    means the smaller id is the entry being renamed. In a merge of several
    matches, it can also be a loser that held the typed name's exact bytes.
    If no loser held those bytes, nothing collides.
- **A known limit: three-way merges.** A merges L into S while B merges L
  into T. If L has the smallest id on A but T is the smaller on B, A keeps L,
  while B tombstones L and aliases it to T. B's dances that still cite S can
  then reach A rewritten onto a tombstone. The smaller-id rule settles the
  two-way case only. T1 should test this, and the amendment should state it
  as a limit if T1 cannot close it.
- A peer whose advertised tombstone of the loser is rewritten onto the
  survivor by the alias: that must never tombstone the survivor.

### Delete

The work plan asks for a delete "with a count of affected dances, and Undo".

**Tags.** Deleting a tag removes it from every dance that has it, then
tombstones it. The steps run in one transaction:

- remove the `dance_tags` rows from live dances and from dances in Recently
  deleted, recording them for Undo;
- bump each of those dances;
- tombstone the tag (`TagRepository.delete`, default path);
- drop its name from `default_import_tag_names`.

**Decided: strip the joins, rather than keep them as `TagRepository.delete`
does today** (D-N2-7 = N2-7 (a), 2026-10-30, as recommended). The reason is sync:

- A dance whose tag is tombstoned no longer lists it in its wire
  body (`dance_repository.dart:726-732`), so its serialised content changes
  and I1 requires a bump. A peer applying the bumped dance writes `tagIds`
  without the tag while the tag is still live there, so it deletes the join
  (`dance_repository.dart:736-741`). This holds whatever the apply order,
  because the peer's pending deletion keeps the tag live until those dances
  arrive (§6.8).
- Keeping the joins here therefore leaves the devices holding different
  hidden state. Only a *revival* of the same tag would show the difference:
  this device would re-tag the old dances, and its peers would not.

The rejected alternative keeps today's behaviour (joins kept, dances bumped),
under which a revival on this device brings the dances back. No UI deletes an
in-use tag today, so nothing depends on the current behaviour yet. The option
text names the consequence: "bringing the tag back does not re-tag old
dances".

**Authors and sources. Decided:** keep the existing guard (D-N2-4 = N2-4 (a),
2026-10-30, as recommended). Delete
is offered only for a row no live dance cites. For a row in use, the manager
offers **Merge into…** instead.

- Taking an author off a dance leaves it uncredited, and an uncredited dance
  is worse than a dance that lost a mood tag.
- The rejected alternative strips the credit like a tag. It would need
  per-dance positions renumbered, plus a warning for dances left with no
  author.

**The count and the Undo.** The manager shows each row's count of live
dances before the user acts, and the delete reports it afterwards: "Deleted
'Bouncey' from 12 dances. **Undo**". There is no confirm, following
`ux.md:201-202`, because Undo exists. Dances in Recently deleted are not
counted: they don't protect the row (trash-policy (b)), and they lose the tag
too.

**How long Undo lasts.** The snackbar is the only Undo. Recently deleted lists
only dances and programs (`recently_deleted_screen.dart:326-367`), and a venue
delete is already permanent (`settings.md:128-133`).

- `ux.md:201`'s "restore within 30 days" would need tags in Recently deleted.
- Restoring a tag weeks later onto dances edited since would be a merge of
  its own.
- **Decided:** snackbar Undo only (D-N2-5 = N2-5 (a), 2026-10-30, as
  recommended). Not chosen: a Tags tab in Recently deleted.

## Per kind

### Tags

- **Rename** with merge-on-collision, as above. A tag's colour lives in its
  row, so it survives a rename.
- **Merge:** the survivor keeps the colour of the tag merged into. **Recommendation:** if the
  survivor has none, it takes the loser's. Rejected alternative: always the
  survivor's, which silently drops a colour the user chose.
- **Delete**, with the count and Undo, as above.

### Authors

- **Rename** in the details dialog stops refusing a taken name. Today a
  collision shows `danceEditorChoreographerDuplicate` and saves nothing
  (`dance_editor_screen.dart:759-777`). Instead it offers the merge dialog,
  from the dance editor as well as from the manager.
- **Merge** re-points `dance_authors`. A dance credited to both keeps the
  survivor at its own position. The search index's `authors` column must
  follow for every affected dance; the branch checks that the shared helper
  does this, and adds it if not.
- **Delete** only when unused, as above.

#### Merging two authors' private details

An author row holds third-party personal data about someone who never uses
this app:

| Field | Egress (`field_registry.dart`) |
| --- | --- |
| `website` | shareable, `:467-472` |
| `notes` | shareable, `:473` (`_freeformNote`, `:296-305`) |
| `email` | deviceLocal, `:474-481` |
| `location` | deviceLocal, `:482-487` |
| `deceased` | deviceLocal, `:488-493` |

When the user merges "Gene Hurbert" into "Gene Hubert", the losing row's
details have to go somewhere or be discarded. The options:

| Option | What happens | For | Against |
| --- | --- | --- | --- |
| (a) The survivor's details win whole | The loser's details are discarded. This is what the sync **Merge** does (`sync-spec.md:3253-3257`). | Simplest; matches sync | Loses an email typed only on the misspelled row, which is the usual case for a typo |
| (b) **Fill the blanks** | Each empty field on the survivor takes the loser's value. Where both hold different values, the survivor's wins, and the merge dialog lists what will be discarded. `deceased` is set if either row sets it. | Keeps everything that doesn't conflict, and shows the rest before it goes | A longer dialog when the rows conflict |
| (c) Choose per field | Where both hold values, the dialog asks which to keep for each field | Full control | The most UI, and on a phone it is a form inside a dialog |

**Decided: (b)** (D-N2-2 = N2-2 (b), 2026-10-30, as recommended). It doesn't create data: every value it keeps was
already on this device. Notes are not concatenated, because joining two
people's notes is a guess about whether they are the same person, and the
merge already says they are.

Two consequences of (b):

- **No value changes egress class.** A website or note that moves came from
  a row that already synced. An email moves only to another deviceLocal
  field.
- **Discarded values are gone once Undo times out.** Before then, Undo
  restores them.

**A limit no option avoids.** deviceLocal fields never sync. Another device's
own private details for the loser stay on that device's tombstoned loser row,
out of sight, and are not moved onto its survivor. Moving them would need a
wire change.

- This matches the sync merge's existing warning (`settings.md:1220-1223`).
- The user docs must say it in the same words.

### Sources

- **Rename** is a plain edit: no natural key, no collision.
- **Merge** is the only way to join duplicates such as "Zesty Contras" and
  "Zesty Contras (2nd ed.)". The app never detects them, because sources
  insert without reconciliation (`sync-spec.md:3449-3450`).
  - The survivor keeps its own `author`, `year`, `url` and `notes`. Empty
    ones take the loser's, as for authors (b).
  - A dance that cites both keeps the survivor's citation. **Recommendation:**
    an empty `page` or `number` on that citation takes the loser's. Rejected
    alternative: drop the loser's citation whole, which is what
    `_rewriteLocalReferences` does today (`sync_storage.dart:5291-5318`).
- **Delete** only when unused, as above.
- **Not proposed:** a "possible duplicates" hint by folded title. It is close
  to the dropped FIND-9, and the maintainer can ask for it separately.

## The manager screens

One shared list screen, used three times: **Tags**, **Authors**, **Sources**.

**Placement.** The options:

- (a) **Settings → General → Library** (`settings.md:45-57`) gains three
  entries. **Settings → Appearance → Tag colours** (`settings.md:272-279`,
  `appearance_section.dart:178`) opens the Tags manager, so existing users
  find colours where they left them. Venues set the precedent: their manager
  is in Settings (`settings.md:128-133`).
- (b) The same three entries in Collection's ⋮ menu.
- (c) Both.

**Decided: (a)** (D-N2-3 = N2-3 (a), 2026-10-30, as recommended). It adds
nothing to the Collection toolbar, which B14 and B15 are already changing.

**Layout, phone first:**

- a search field at the top, filtering the list as you type;
- a **Not used** filter chip;
- sort by name or by number of dances;
- one row per entry, showing:
  - for tags, the chip preview `TagColorsScreen` already draws;
  - for authors and sources, the name or title;
  - the live dance count ("12 dances", or "Not used");
- a trailing ⋮ on each row, holding:
  - **Rename**;
  - **Merge into…**, which opens a searchable picker of the other entries;
  - **Colour…** (tags);
  - **Edit details…** (authors and sources, reusing
    `ChoreographerDetailsDialog` and `PublishedSourceDetailsDialog`);
  - **Delete** (tags; authors and sources when unused).
- Tapping a row opens the same ⋮ actions as a bottom sheet on a phone. No row
  swipe actions: they would be a third gesture model for one list.

**Tag colours move into the Tags manager** (FIND-3). `TagColorsScreen` is
retired. The manager lists live tags through `TagRepository.watchAll`
(`tag_repository.dart:451-456`), as that screen does today.

**Not proposed here:** a "show these dances" action. It would open Collection
filtered to the row, and B15 is changing how an external tag filter behaves
(`dance_list_screen.dart:503-530`). Add it after B15 lands, using whatever
rule B15 settles.

## The purge GC (LIFE-5 option c)

The question: should the GC spare rows the user has edited? The options:

| Option | Rule | For | Against |
| --- | --- | --- | --- |
| (a) Keep today's GC | Erase every unpublished row the purge leaves uncited | No change | Silently loses a colour or an author's contact block, and only for users without sync |
| (b) **Spare rows with details** | Erase only a *bare* row: a tag with no colour; an author with no website, notes, email, location or deceased mark; a source with no author, year, URL or notes | No schema change and no new field, so no registry entry. What the user entered survives, and the manager shows it as **Not used** | Keeps third-party contact data after the dance that explained it is gone |
| (c) Stop the GC | Uncited rows stay until the user deletes them in the manager | One rule for everyone: published rows are never collected today either (`dance_repository.dart:2255-2296`) | Bare rows from imports pile up |
| (d) Spare rows "the user edited" | The audit's wording, taken literally | Exact | Needs a per-row edit marker: a new column, a migration, and a registry entry on all three axes |

**Decided: (b)** (D-N2-6 = N2-6 (b), 2026-10-30, as recommended). The test
reads only data that is already there, so it adds no persisted field.

The decision text summarises the details as "a colour, website, notes or
email". *My reading* (an open ambiguity in `design-work-plan.md`): it is the
option's short form, and the full list in the table above stands, so an
author's location or deceased mark, and a source's author, year or URL, also
spare a row. Rejected: the narrower list, which would erase a source with a URL
the user typed.

- The third-party-data cost is real. An author's email outlives their last
  dance until the user deletes the author.
- But that email was typed deliberately, and today's alternative erases it
  without a word.
- Imported details count as details. An author whose website came from a
  ContraDB import is spared too. The user chose that import.

The doc comment on
`_garbageCollectOrphanedRefs` (`dance_repository.dart:2194-2250`) and
`storage.md:847-849` must describe the new rule.

## The import-tags setting

`default_import_tag_names` stores tag **names**, so that it survives sync
re-identification (`display_defaults.dart:153-162`,
`settings_registry.dart:269-278`). A rename or merge must rewrite it; a delete
should drop the name.

- **Where.** The key is defined in the app (`display_defaults.dart:162`), so
  the rewrite runs in the app's controller, inside the same
  `repos.transaction` as the core operation, as `_undoBatchTag` does
  (`dance_list_screen.dart:1520-1538`). Moving the key into core is the
  rejected alternative: the setting would gain nothing, and two packages
  would gain a coupling.
- **Delete drops the name.** Today a name with no live tag is ignored at
  import (`settings.md:432-434`). Leaving it would make a future tag created
  under that name join imports without the user choosing it. Undo puts the
  name back.
- **Sync.** The setting is `shareable` and travels as an ordinary settings
  record, so peers take the rewrite by last-writer-wins. Its registry entry
  does not change.

## Privacy registry

**The recommended design adds no persisted field.** It changes no column, no
settings key and no data-entry surface's classification:

- the managers edit fields that are already classified
  (`field_registry.dart:454-496`, `:623-658`);
- the alias goes in `id_aliases`, which sync already owns;
- GC option (b) reads existing columns.

Two choices *would* need registry entries in the PR that introduces them:

- **GC option (d).** An edit marker would be `deviceScoped` sync metadata
  about the user's own action, and its subject axis needs a stated reason.
- **Tags in Recently deleted (D-N2-5, not chosen).** A delete strips the joins
  (D-N2-7), so restoring weeks later needs the removed `(dance, tag)` pairs
  stored somewhere. That is new persisted data and needs entries for its
  columns. A per-kind retention setting would also be a new settings key.

**The managers' list state is session-only:** the search text, the
**Not used** filter and the sort. Persisting any of them would add a settings
key, which needs its own entry.

**Merging author details moves third-party data between rows.** The two rows
stay in the same egress class (see the table above), so the registry is
unchanged. The registry's note on `choreographers.email`
(`field_registry.dart:478-480`) stays true.

## Sync, summarised

| Operation | What peers receive | Spec text it rests on |
| --- | --- | --- |
| Rename | An edit of the row, plus a renamed tombstone when a tombstone held the name | §6.3; §6.6 step 1 if a peer independently holds the new name, or holds that tombstone's deletion pending |
| Merge | The survivor's edit, the loser's renamed tombstone, and the bumped dances | §6.5 I1; §6.8 pending deletion; §6.6 survivor rule and "The remap" (amended) |
| Delete (tags) | The tombstone, plus the bumped dances | §6.5 I1; §6.8 |
| Undo | A revival, plus the bumped dances | §6.4 |

**No new record kind, no new key, no capability.** The commonly-applied
constraint "§6.6 aliases and §6.15" (`decided-work-plan.md:794`) is met by
reusing §6.6's alias table and needing nothing from §6.15. The sync "Merge"
choice (`settings.md:1212-1218`) keeps working as it does. Because the loser's
tombstone gives up its name, a peer that created that name on its own gets no
"deleted something this device still has" review row
(`settings.md:1203-1210`). A step-1 collision can still arise on a peer that
holds the loser's deletion pending. That is the open risk described under
[Merge](#merge).

## Docs to change with the code

Each implementation branch updates these in the same PR:

- `docs/user/collection.md:81-90`: tags can be renamed, merged and deleted,
  and where.
- `docs/user/settings.md`:
  - `:45-57`: the new Library entries;
  - `:272-279`: Tag colours now opens the Tags manager;
  - `:432-434`: "imports simply skip it" becomes "the name is removed";
  - `:1220-1223`: the private-details limit, worded the same way for a user
    merge.
- `docs/user/authoring.md:582-597`: a rename onto an existing author offers a
  merge.
- `docs/design/sync-spec.md` §6.6: the dated amendment (D-N2-1).
- `docs/design/storage.md:847-849`: the GC rule (D-N2-6).
- The code comments listed under [How it works today](#how-it-works-today).

## Decisions

The maintainer answered all seven on 2026-10-29/30, each as recommended. Each
entry quotes the decision as `maintainer-decisions-2026-10-30.md` (on
`claude/app-audit-categories-k2pdon`) records it. The maintainer left no notes
on these seven.

1. **D-N2-1 = N2-1, amend sync-spec §6.6.** "(a) Yes, amend sync-spec §6.6.
   Merges record an alias, so a device that tagged dances offline lands on the
   merged entry; T1 must still choose the fix for one open risk." This note's
   amendment (its scope, not the decision's wording) covers five rules: the surviving id is the smaller UUID; the
   loser's tombstone gives up its name; the merge records an id alias; a peer's
   edit of the loser lands on the survivor; and the fix T1 settles for a peer
   that holds the loser's deletion pending (see [Merge](#merge)).
2. **D-N2-2 = N2-2, merging two authors' private details.** "(b) Fill the
   blanks, list what's dropped. Empty fields take the other author's values,
   and the dialog lists conflicting values it will drop; a longer dialog on
   conflict."
3. **D-N2-3 = N2-3, where the managers live.** "(a) Settings, General,
   Library. Three new Library entries, and Tag colours in Appearance opens the
   Tags manager; nothing added to Collection."
4. **D-N2-4 = N2-4, deleting an author or source still cited.** "(a) No, offer
   Merge into instead. Delete appears only for unused entries; an entry in use
   offers a merge, so no dance loses its credit."
5. **D-N2-5 = N2-5, how long a tag delete can be undone.** "(a) Only from the
   Undo snackbar. Undo lasts as long as the snackbar, and nothing new is
   stored."
6. **D-N2-6 = N2-6, the purge GC.** "(b) Keep entries that hold details. Bare
   entries go; ones with a colour, website, notes or email stay as Not used,
   keeping third-party contact data."
7. **D-N2-7 = N2-7, what a tag delete does to its join rows.** "(a) Remove it
   from every dance. Each dance loses the tag and is updated, so all devices
   agree; bringing the tag back does not re-tag old dances."

Two smaller choices are my recommendations, not decisions, and the
implementing branch should confirm them with the maintainer in its PR:

- a merged tag keeps the loser's colour when the survivor has none;
- a "show these dances" action waits for B15.

**Where the brief's line numbers differ.** The work plan cites
`settings.md:1158-1168` for the sync **Merge** choice and `ux.md:186-187` for
the undo rule. Those sections are at `settings.md:1200-1225` and
`ux.md:192-193` on `acacb05`, and at `ux.md:201-202` on `296b594`. This note
cites the current lines. The plan's B8 constraint applies
through trash-policy (b): T1 waits for B8, and nothing here counts a trashed
dance as protecting a row.

## Branches

The format and sizes follow `decided-work-plan.md`. Size counts changed lines,
tests included: S < 150, M 150–400, L 400+. Updated 2026-10-30 for the decisions
and for what has merged (`main` at `90fe5e8`: B12 #2037 and B23 #2035 have
merged; B7 is in flight; B8 and B13 have not started). In the audit branch's
`design-work-plan.md` these are N2-T1 … N2-T4.

| # | Branch | Items | Size | Model | Depends on |
| --- | --- | --- | --- | --- | --- |
| T1 | `feat/reference-rename-merge-core` | Core rename, merge, delete and Undo for the three kinds; the shared reference-rewrite helper; the §6.6 amendment, including T1's chosen fix for the held-peer risk | L (~900) | Opus | B7 and B8 merged; after B13 on `dance_repository.dart` (B12 has merged). D-N2-1 and D-N2-7 are decided. |
| T2 | `feat/tag-manager` | FIND-3: the Tags manager with colours, rename, merge and delete; the import-tags rewrite; retire `TagColorsScreen` | L (~500) | Opus: the import-tags rewrite shares a transaction and an Undo with T1's operations (the work plan's model rule; the note first said Sonnet). | T1. D-N2-3 and D-N2-5 are decided. |
| T3 | `feat/author-and-source-managers` | LIFE-5 (a): the Authors and Sources managers; the merge offer in the dance editor; the private-details merge | L (~450) | Opus | T2. D-N2-2 and D-N2-4 are decided. Serialize with N4-S6 on `dance_editor_screen.dart`. |
| T4 | `fix/purge-gc-spares-details` | LIFE-5 (c) | S (~120) | Sonnet | B7 merged; any order against T1, but serialize the merge on `dance_repository.dart`. D-N2-6 is decided. |

### T1 `feat/reference-rename-merge-core`

- **Scope:**
  - `TagRepository`, `ChoreographerRepository` and
    `PublishedSourceRepository` gain `rename`, `mergeInto` and an
    in-use-aware `delete` (tags only), each returning an undo token, plus
    the matching `undo`.
  - `_rewriteLocalReferences` (`sync_storage.dart:5223-5425`) moves into a
    storage helper that both sync and the merge call. Sync keeps its
    behaviour exactly; its existing tests are the guard.
  - The surviving id by the smaller-UUID rule, and the freeing of the
    loser's name with the suffix.
  - The alias through `remapIdentity`, and an Undo that restores what
    `remapIdentity` wrote to `id_aliases` and `retained_sync_fields`
    (`sync_local_repository.dart:752-802`), keeping the publication marker
    as described under [Merge](#merge).
  - A search-index rebuild for every dance a merge touches, plus the
    `sources` column after a source rename if the check above finds it
    stale.
  - The stale comments at `tag_repository.dart:465`,
    `tag_colors_screen.dart:24-27` and `display_defaults.dart:158`.
- **Tests:**
  - every step of each operation, and its Undo;
  - Undo after a merge whose loser had a prior alias chain, and one whose
    loser had retained sync fields;
  - a rename whose lookup finds two live matches with different colours and
    a tombstone, checking the colour of the entry merged into wins;
  - a held peer of a multi-match merge, where a loser that is not the
    renamed entry held the typed name's exact bytes;
  - the two-device cases listed under [Merge](#merge): an offline peer's
    new citation, opposite merges, rename versus merge, apply order, and a
    rewritten tombstone;
  - a citation from a peer that was offline past alias retirement.
  - Prove each guard can fail (`AGENTS.md`).
- **Docs:** the sync-spec §6.6 amendment, and the matching `storage.md` text.
- **Hot files:** `dance_repository.dart` (B7 → B12 → B13), `sync_storage.dart`,
  and `sync-spec.md` (B7 and B8 also edit it). Merge alone, because it moves
  a method.

### T2 `feat/tag-manager`

- **Scope:**
  - the shared manager list widget;
  - the Tags manager, with the colour editing from `TagColorsScreen`
    (`tag_colors_screen.dart`) moved in;
  - the Settings entries (`appearance_section.dart:178`, plus Library per
    D-N2-3);
  - the `default_import_tag_names` rewrite in the app controller.
- **UI text:** keys in all six ARBs, beside the existing tag-colour keys. A
  `changelog.d/<id>.json` fragment.
- **Docs:** `collection.md:81-90`, `settings.md:45-57`, `:272-279` and
  `:432-434`.
- **Hot files:** the six ARBs and `settings.md` (many branches).

### T3 `feat/author-and-source-managers`

- **Scope:**
  - the Authors and Sources managers, built on T2's widget;
  - the merge offer in place of the refusal at
    `dance_editor_screen.dart:759-777`;
  - the private-details merge dialog;
  - citation page and number fill.
- **UI text:** ARB keys, and a changelog fragment. The new strings say
  "author" (D-3). Renaming the existing "Choreographer details" title is
  U4's job, so coordinate with U4 rather than duplicate it.
- **Docs:** `authoring.md:582-597`, `settings.md:1220-1223`.
- **Hot files:** `dance_editor_screen.dart`, which B23 edited (merged, #2035)
  and N4-S6 also edits; the ARBs.

### T4 `fix/purge-gc-spares-details`

- **Scope:** the candidate filter in `_garbageCollectOrphanedRefs`
  (`dance_repository.dart:2251-2316`), following D-N2-6 (b): spare a row that
  holds any detail in the table under [The purge GC](#the-purge-gc-life-5-option-c).
- **Tests:** the existing `dance_hard_delete_test.dart` watcher guard still
  passes, and a new test shows a coloured tag surviving the purge.
- **Docs:** `storage.md:847-849`, and the method's doc comment.
- **No UI text,** so no ARB keys. Add a changelog fragment only if the
  maintainer treats a spared row as user-visible.
