# Design: Renaming, merging and deleting tags, authors and sources

*Design note N2 for audit findings FIND-3 and LIFE-5. Written 2026-10-29
against `origin/main` at `acacb05`; every `file:line` below is for that tree
unless it names another branch.*

**Status: proposal.** This note decides nothing. The maintainer asked for it
(below). Everything marked **Recommendation** is this note's author's view,
with the alternative it rejected; the [Decisions needed](#decisions-needed)
list at the end collects what only the maintainer can settle.

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
   (`shareable_text.dart:40-52`), and `TagRepository.idByName` uses it
   (`tag_repository.dart:260-280`). So "Flowy" and "flowy" can both be stored,
   and the app treats them as the same name.
2. **A tag delete keeps its join rows.** `TagRepository.delete` tombstones the
   tag and leaves `dance_tags` alone, so a revived tag comes back with its
   dances (`tag_repository.dart:459-534`). Dance reads hide the tombstoned tag
   (`dance_repository.dart:3386-3410`), and a dance write leaves those rows in
   place (`:726-751`). Re-creating a tag under a deleted tag's name adopts the
   tombstone (`tag_repository.dart:145-157`), so its old dances get it back.
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

- **Collision test.** Before writing, look the new name up with `idByName`
  (or the author equivalent), excluding the row itself. A case-only change
  ("flowy" to "Flowy") matches only itself, so it is a plain rename.
- **On a collision, offer a merge.** Don't refuse. The dialog says:
  "'Flowy' already exists. Merge 'Flowing' into it?", with **Keep editing**
  and **Merge**.
  - This is a question, not a destructive-action confirm. The user may not
    know the name is taken. `ux.md:192-193` limits *confirms* to actions with
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
then removes the loser. The user picks the survivor: it is the row they merge
*into*, and on a rename collision it is the row that already holds the name.

The steps run in one transaction:

1. **Re-point the joins.** Every `dance_tags`, `dance_authors` or
   `dance_sources` row that names the loser moves to the survivor. Where a
   dance already cites both, the loser's row is dropped. Dances in Recently
   deleted are re-pointed too (trash-policy (b)), so restoring one shows the
   survivor.
   - Sync's reconciliation already does exactly this in
     `CompendiumSyncStorage._rewriteLocalReferences`
     (`sync_storage.dart:5223-5425`).
   - **Recommendation:** extract that method into a storage helper that both
     sync and the user merge call. Rejected alternative: a second copy, which
     would let the two drift.
2. **Bump every affected dance** (`sync-spec.md` §6.5 I1, `:3093-3094`). Its
   serialised `tagIds`, `authorIds` or `sourceCitations` changed. The same
   helper already does this (`sync_storage.dart:5408-5424`).
3. **Combine the survivor's own fields.** See
   [Merging two authors' private details](#merging-two-authors-private-details)
   and the per-kind rules below.
4. **Tombstone the loser under its own name.** Do not erase it and do not
   rename it. Each choice matters for sync:
   - A rename onto the survivor's name would reach each peer as "another
     device renamed a record onto a name this device already uses". That
     sends the peer to the review queue (`sync-spec.md:3246-3262`,
     `settings.md:1212-1218`), asking the user a question they have already
     answered.
   - An erase leaves peers holding the loser live, so the next pass downloads
     it back (§3.1, `sync-spec.md:148-153`).
   - A tombstone is ordinary deletion evidence. A peer whose dances still cite
     the loser holds the deletion pending until the last citation goes
     (§6.8, `sync-spec.md:3724-3734`).
5. **Write an id alias, loser to survivor,** in `id_aliases`
   (`SyncLocalRepository.upsertAlias`, `sync_local_repository.dart:582`).
   - Sync rewrites inbound references through these aliases before applying
     them (`rewriteSyncInboundReferences`, `sync_reconciliation.dart:60-110`,
     called from `_rewriteCandidate`, `sync_storage.dart:4012-4033`).
   - So when a peer that tagged a dance with the loser *while offline* syncs,
     this device files the tag under the survivor, bumps the dance and
     re-uploads it. The peer then drops its last citation, and its pending
     deletion of the loser lands.
   - Without the alias, the result depends on how apply treats a dance that
     cites a local tombstone. I did not trace that path.
6. **Rewrite `default_import_tag_names`** (tags only). The loser's name is
   replaced by the survivor's, then de-duplicated. See
   [The import-tags setting](#the-import-tags-setting).

**Undo** restores the transaction's before-image:

- the loser is revived, and its fields restored;
- the captured joins are put back, with author and source positions and
  citation page and number;
- the survivor's fields are restored;
- the alias is removed, and the setting restored;
- every touched dance is bumped again.

If a sync pass ran in between, the revival outranks the tombstone by
construction (§6.4, `sync-spec.md:3772-3774`), so peers converge on the undone
state as ordinary edits. Removing an alias is new, because sync only ever
adds them. The core branch adds it.

**This needs no wire change and no capability.** A merge adds no record kind
and no settings key, so §6.15's gate (`sync-spec.md:4417`) does not apply. It
uses only tombstones, edits and local aliases, which every build since sync
shipped already applies. It does need a dated amendment to §6.6's "The remap"
(`sync-spec.md:3427-3443`). That paragraph names reconciliation as the only
producer of aliases, and the amendment adds the user merge. That makes the
amendment a maintainer decision (D-N2-1).

**What the alias costs.** An alias is retired only once no current peer
manifest lists the losing id (`sync-spec.md:3430-3431`). A peer that holds a
pending deletion advertises the loser as a tombstone, so in practice the alias
lasts as long as the tombstone does. Every later inbound reference to the
loser is filed under the survivor. That includes a peer that deliberately
re-creates the loser's name (re-creation adopts the tombstone, `tag_repository.dart:145-157`). Sync's own
reconciliation aliases have the same property, so this adds no new kind of
behaviour. But it is a trade-off, and the amendment should say so.

**A concurrent case to test.** Device A merges "Bouncey" into "Bouncy" while
device B, offline, renames "Bouncey" to "Bouncy!".

- `_rewriteCandidate` resolves an inbound record's **own** id through the
  aliases, not only its references (`sync_storage.dart:4016-4021`). So on A,
  B's edit of "Bouncey" is applied to "Bouncy", and may rename the survivor
  to "Bouncy!".
- That is arguably right: after the merge they are one tag. But it means a
  peer's edit to the loser reaches the survivor, and the §6.6 amendment must
  say so.
- On B, A's tombstone meets B's edit in §6.4's existence comparison. A rename
  is an edit, not a revival, so the tombstone should win.
- I traced this from the code and the spec, not by running it. T1's
  two-device test must pin the outcome.

### Delete

The work plan asks for a delete "with a count of affected dances, and Undo".

**Tags.** Deleting a tag removes it from every dance that has it, then
tombstones it. The steps run in one transaction:

- remove the `dance_tags` rows from live dances and from dances in Recently
  deleted, recording them for Undo;
- bump each of those dances;
- tombstone the tag (`TagRepository.delete`, default path);
- drop its name from `default_import_tag_names`.

**Recommendation: strip the joins, rather than keep them as
`TagRepository.delete` does today.** Two reasons:

- **Sync.** A dance whose tag is tombstoned no longer lists it in its wire
  body (`dance_repository.dart:726-732`), so its serialised content changes
  and I1 requires a bump. A peer applying the bumped dance writes `tagIds`
  without the tag while the tag is still live there, so it deletes the join
  (`dance_repository.dart:736-741`). Keeping the joins on this device only
  makes the two devices hold different hidden state.
- **Surprise.** With the joins kept, typing the deleted name months later
  revives the old tag, and it reappears on every dance it used to be on.

The rejected alternative keeps today's behaviour (joins kept, dances bumped).
Re-creating a tag would then bring its dances back, which is a kind of
long-term restore. No UI deletes an in-use tag today, so nothing depends on
the current behaviour yet.

**Authors and sources.** **Recommendation:** keep the existing guard. Delete
is offered only for a row no live dance cites. For a row in use, the manager
offers **Merge into…** instead.

- Taking an author off a dance leaves it uncredited, and an uncredited dance
  is worse than a dance that lost a mood tag.
- The rejected alternative strips the credit like a tag. It would need
  per-dance positions renumbered, plus a warning for dances left with no
  author.

The decision is D-N2-4.

**The count and the Undo.** The manager shows each row's count of live
dances before the user acts, and the delete reports it afterwards: "Deleted
'Bouncey' from 12 dances. **Undo**". There is no confirm, following
`ux.md:192-193`, because Undo exists. Dances in Recently deleted are not
counted: they don't protect the row (trash-policy (b)), and they lose the tag
too.

**How long Undo lasts.** The snackbar is the only Undo. Recently deleted lists
only dances and programs (`recently_deleted_screen.dart:326-367`), and a venue
delete is already permanent (`settings.md:128-133`).

- `ux.md:192`'s "restore within 30 days" would need tags in Recently deleted.
- Restoring a tag weeks later onto dances edited since would be a merge of
  its own.
- **Recommendation:** snackbar Undo only. Rejected alternative: a Tags tab in
  Recently deleted. The decision is D-N2-5.

## Per kind

### Tags

- **Rename** with merge-on-collision, as above. A tag's colour lives in its
  row, so it survives a rename.
- **Merge:** the survivor keeps its colour. **Recommendation:** if the
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

**Recommendation: (b).** It doesn't create data: every value it keeps was
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

The choice between (a), (b) and (c) is D-N2-2.

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

**Recommendation: (a).** It adds nothing to the Collection toolbar, which B14
and B15 are already changing. The decision is D-N2-3.

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

**Recommendation: (b).** The test reads only data that is already there, so
it adds no persisted field.

- The third-party-data cost is real. An author's email outlives their last
  dance until the user deletes the author.
- But that email was typed deliberately, and today's alternative erases it
  without a word.
- Imported details count as details. An author whose website came from a
  ContraDB import is spared too. The user chose that import.

The decision is D-N2-6. Whatever is chosen, the doc comment on
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
- **Tags in Recently deleted (D-N2-5).** This needs no column today, but a
  per-kind retention setting would be a new settings key.

**Merging author details moves third-party data between rows.** The two rows
stay in the same egress class (see the table above), so the registry is
unchanged. The registry's note on `choreographers.email`
(`field_registry.dart:478-480`) stays true.

## Sync, summarised

| Operation | What peers receive | Spec text it rests on |
| --- | --- | --- |
| Rename | An edit of the row | §6.3; §6.6 step 1 if a peer independently holds the new name |
| Merge | The loser's tombstone, plus the bumped dances | §6.5 I1; §6.8 pending deletion; §6.6 "The remap" (amended) |
| Delete (tags) | The tombstone, plus the bumped dances | §6.5 I1; §6.8 |
| Undo | A revival, plus the bumped dances | §6.4 |

**No new record kind, no new key, no capability.** The commonly-applied
constraint "§6.6 aliases and §6.15" (`decided-work-plan.md:794`) is met by
reusing §6.6's alias table and needing nothing from §6.15. The sync "Merge"
choice (`settings.md:1212-1218`) keeps working as it does. A user merge never
creates a collision for it to resolve, because the loser keeps its own name.

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

## Decisions needed

1. **D-N2-1: amend sync-spec §6.6 so a user merge writes an id alias.**
   Recommendation: yes, with the trade-off stated in the amendment. Without
   it, an offline peer's citations of the loser are left to however apply
   treats a citation of a tombstone.
2. **D-N2-2: merging two authors' private details.** Options (a) the
   survivor's details win whole, (b) fill the blanks and list what is
   discarded, (c) choose per field. Recommendation: (b).
3. **D-N2-3: where the managers live.** Options (a) Settings → General →
   Library, (b) Collection's ⋮ menu, (c) both. Recommendation: (a).
4. **D-N2-4: deleting an author or source that dances still cite.** Options:
   keep the guard and offer Merge instead, or strip the credit like a tag.
   Recommendation: keep the guard.
5. **D-N2-5: how long a tag delete can be undone.** Options: the snackbar
   only, or a Tags tab in Recently deleted. Recommendation: the snackbar only.
6. **D-N2-6: the purge GC.** Options (a) unchanged, (b) spare rows with
   details, (c) stop it, (d) spare rows the user edited. Recommendation: (b).

These choices are the author's recommendations, not decisions, but each
stands unless the maintainer overrules it: a tag delete strips its joins
rather than keeping them; a merged tag keeps the loser's colour when the
survivor has none; and a "show these dances" action waits for B15.

## Proposed branches

The format and sizes follow `decided-work-plan.md`. Size counts changed lines,
tests included: S < 150, M 150–400, L 400+.

| # | Branch | Items | Size | Model | Depends on |
| --- | --- | --- | --- | --- | --- |
| T1 | `feat/reference-rename-merge-core` | Core rename, merge, delete and Undo for the three kinds; the shared reference-rewrite helper; the §6.6 amendment | L (~600) | Opus | D-N2-1; B7 and B8 merged; after B12 and B13 on `dance_repository.dart` |
| T2 | `feat/tag-manager` | FIND-3: the Tags manager with colours, rename, merge and delete; the import-tags rewrite; retire `TagColorsScreen` | L (~500) | Sonnet | T1; D-N2-3, D-N2-5 |
| T3 | `feat/author-and-source-managers` | LIFE-5 (a): the Authors and Sources managers; the merge offer in the dance editor; the private-details merge | L (~450) | Opus | T2; D-N2-2, D-N2-4 |
| T4 | `fix/purge-gc-spares-details` | LIFE-5 (c) | S (~120) | Sonnet | D-N2-6; B7 merged; any order against T1, but serialize the merge on `dance_repository.dart` |

### T1 `feat/reference-rename-merge-core`

- **Scope:**
  - `TagRepository`, `ChoreographerRepository` and
    `PublishedSourceRepository` gain `rename`, `mergeInto` and an
    in-use-aware `delete` (tags only), each returning an undo token, plus
    the matching `undo`.
  - `_rewriteLocalReferences` (`sync_storage.dart:5223-5425`) moves into a
    storage helper that both sync and the merge call. Sync keeps its
    behaviour exactly; its existing tests are the guard.
  - The alias write, and a new alias removal for Undo
    (`sync_local_repository.dart`).
  - Search-index refresh for `authors`, plus `sources` if the check above
    finds it stale.
  - The stale comments at `tag_repository.dart:465`,
    `tag_colors_screen.dart:24-27` and `display_defaults.dart:158`.
- **Tests:**
  - every step of each operation, and its Undo;
  - a two-device sync test of a merge against an offline peer's new
    citation;
  - the concurrent rename-versus-merge case.
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
- **Hot files:** `dance_editor_screen.dart`, which B23 also edits; the ARBs.

### T4 `fix/purge-gc-spares-details`

- **Scope:** the candidate filter in `_garbageCollectOrphanedRefs`
  (`dance_repository.dart:2251-2316`), following D-N2-6.
- **Tests:** the existing `dance_hard_delete_test.dart` watcher guard still
  passes, and a new test shows a coloured tag surviving the purge.
- **Docs:** `storage.md:847-849`, and the method's doc comment.
- **No UI text,** so no ARB keys. Add a changelog fragment only if the
  maintainer treats a spared row as user-visible.
