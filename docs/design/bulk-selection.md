# Design: Bulk selection

*Design note N4 for audit finding FIND-8 · v0.1 (2026-10-29) · **Status: proposal.**
The maintainer chose "design note now" for `design-bulk-select` in
`maintainer-decisions-2026-10-29.md`. That is the only decision recorded here.
Everything else is a recommendation from the session that wrote this note, and
each one says what it rejected. Line numbers are against `origin/main` at
`acacb05`. The audit files (`docs/dev/audits/2026-10-behavior/`, including
`reports/FIND.md` and `decided-work-plan.md`) live on the branch
`claude/app-audit-categories-k2pdon`, not on `main`. Conforms to
[ux.md](ux.md) §1 and its cross-cutting rules.*

## Scope

This note covers Collection's multi-select ("selection mode") and what it can do
to the selected dances. It answers the four questions the work plan set:

1. Select all, or select visible?
2. What happens to selections a new search hides?
3. Should *Group by category* stay on while selecting?
4. Which batch actions to add: delete, status, mixer, mixed level, add to
   program, source?

It adds a fifth question the first four force: where do six more actions go on a
phone-width selection bar?

**Out of scope.** Save, New and header placement belong to D-11, which is still
open. This note changes which controls sit in the *selection* bar. It does not
move the bar's title or close button, the New-dance button (hidden during
selection, `dance_list_screen.dart:2019`) or any editor Save control. The
Add-to-program sheet's own design is note N3, and tag, choreographer and source
management is N2.

## What exists today

All paths are under `app/lib/src/` unless stated.

**Selection state.** `screens/dance_list_screen.dart` keeps `_selectionMode` and
`_selectedIds` (`:374-375`), a `Set<String>` that remembers tap order. A
long-press on a row (`:3131-3133`) or *Select dances* in the ⋮ menu (`:2206-2207`,
`:2222-2226`) enters the mode. `_exitSelectionMode` clears the set (`:1349-1354`).
Every batch handler exits selection mode when it succeeds.

**The selection bar** (`_buildSelectionAppBar`, `:2330-2400`). A close button,
a live-region title `"{count} selected"`, then Add tags, Remove tags and Set
level as icons, and a ⋮ menu holding Set rating, Add tunes, Clear tunes and Edit
custom field. The menu is `enum _BatchMoreAction` (`:159`). There is no *Select
all* anywhere in `app/lib`: the audit grepped for `selectAll`, and this note
re-ran the grep and also searched `select_all`.

**Batch writes.** Each handler captures the dances' prior values, writes in one
transaction, announces the result to screen readers, then offers Undo through
`showUndoSnackBar` (`utils/undo_snack_bar.dart:52`).
- Tags: `_applyTags` (`:1385`) and `_undoBatchTag` (`:1516`), both inside
  `_repos.transaction`.
- Level, rating, tunes and custom fields call the core `*ForMany` methods.
  `setLevelForMany` is at `packages/compendium_core/lib/src/storage/repositories/dance_repository.dart:2482`.
  All of them funnel through `_updateMany` (`:2424`), which runs one
  transaction and writes each dance through `_upsert(..., localUserEdit: true)`.
- Undo is a second transaction (`_undoBatchLevel`, `:1627`).
- **F14 has merged** (#1993). Every handler now has the failure path: the
  `catch` calls `_reportBatchFailure` (`:1365`) and leaves selection mode open.
  The audit's FIND-11 describes the tree before that PR. This note builds on
  the merged state and does not redesign the Undo or the failure path.

**Search never touches the selection.** The search field stays live in
selection mode. `_runSearch` (`:814`) replaces `_results` (`:857-862`) and never
reads `_selectedIds`. The data-change path (`_onCollectionData`, `:645`) does
not either. A selected dance that a search hides stays selected, and every batch
handler reads `_selectedIds`, not the visible rows. (The audit cites `:1230-1248`
for this. The file has moved since; the lines above are current.)

**Selection mode flattens the list.** `_selectionMode ? null : _buildGroupedItems()`
(`:2994`) drops the *Group by category* sections whenever the mode is on. The
code comment says this keeps the batch flow "a single flat, uninterrupted list".
The audit cites `:2787-2793`; this is now `:2989-2994`. Grouping state
(`_groupTagId`, `:275`) is session-only and is not cleared, so the sections come
back on exit.

**Online mode does not end selection.** Turning online search on
(`_onOnlineToggled`, `:944`) swaps the body to online results but leaves
`_selectionMode` and `_selectedIds` alone. The caller can then be looking at
online results with a local selection behind them.

**Delete exists only per row.** `_softDeleteFromList` (`:2446`) is reached from
the row's ⋮ menu (`:3108-3115`, gated by `confirmDeleteIfEnabled`,
`utils/confirm_delete.dart:20`) and from the swipe action (`:3172`). Selection
mode turns the swipe off (`:3161-3165`). The function has no `try`/`catch`, and
its Undo calls the full `_boot()` reload (`:2461`).

**Line drift in the work plan.** `decided-work-plan.md` cites the undo rule as
`ux.md:186-187`; on `acacb05` it is `ux.md:192-193`, and this note uses that.

**Clear tunes confirms even though Undo exists** (`_batchClearTunes`, `:1818-1840`).
That is the one batch precedent that contradicts `ux.md:192-193`
("destructive confirms only where undo is impossible"). Question 4 returns to it.

## Q1. Select all, or select visible?

**Finding.** The two only differ if "visible" means the part of the list on
screen. Collection renders `_results` with a lazy `SliverList.builder`
(`:3011-3014`), but `_results` is the whole result set, not a page. So the real
choice is between two scopes:

| Scope | Selects | Cost |
| --- | --- | --- |
| **Results** | Every dance in `_results`: the current search, facets, By phrase and Advanced filter | One scope, always what the caller sees counted in the result line (`:2854`) |
| **Whole collection** | Every live dance, whatever is filtered | A second control; a one-tap path to a huge, invisible selection |

**Recommendation: Results only.** One verb, *Select all*, whose scope is
exactly the list the caller is looking at. To select the whole collection, the
caller clears the filters first, which is the same gesture that lets them see
what they are about to change. We reject a Gmail-style "select all N in the
collection" second step: Collection has no pages to cross, so it would buy a
control and a hidden scope for nothing.

**Rules that follow.**
- *Select all* is a toggle. When every row in `_results` is selected it reads
  *Deselect all*, and it clears only the rows in `_results`. Hidden selections
  are Q2's concern.
- It is disabled while `_searching` is true or the debounce timer
  (`_debounceTimer`, `:377`) is pending, so it never selects a list that is
  about to be replaced.
- It is disabled in online mode. Entering online mode **ends selection mode**
  (see Q2); selection is a local-collection feature.
- Placement is the selection bar's action row, with `Icons.select_all` and a
  tooltip that includes the count ("Select all 143"). The result-count line
  (`_buildResultCount`, `:2854`) shows the same count, so the number the caller
  sees before tapping is the number they get.
- **Desktop.** Ctrl/Cmd-A selects all, but only while keyboard focus is in the
  list, never in the search field, where it must keep selecting text. B29 owns
  the desktop shortcut map (`decided-work-plan.md`, B29), so this binding goes
  through B29's intents and waits for it. Until then *Select all* is
  pointer-and-touch only, and that is acceptable because the button works with a
  keyboard.

## Q2. Selections a new search hides

**The conflict.** The audit's two scenarios want opposite behaviour:
- *Scenario A* (hidden selections surprise the caller): wants hidden rows
  dropped.
- *Scenario B* (tag every Roodman dance) wants *Select all*, which only works if
  the selection survives until the caller applies it. A caller who builds a
  selection **across several searches** ("these three from one query, those four
  from another") wants hidden rows **kept**.

A pruning rule that serves A destroys that workflow. Silently, because typing is
what triggers it.

**Options.**

| | Rule | Gains | Loses |
| --- | --- | --- | --- |
| **A. Prune** | Drop selected ids missing from `_results` whenever a search finishes | No hidden state; the title always matches the screen | Accumulating across searches is impossible; one slip of the keyboard loses the selection with no Undo for it |
| **B. Keep and say so** | Keep the selection; show how many are not in the list; offer one tap to drop them | Accumulation works; nothing is silent; one tap restores A | A selection the caller cannot see; a bigger result-line |
| **C. Act on shown only** | Keep the set but let batch actions touch only the shown rows | The action matches the screen | The count in the title lies; the same selection does different things per search; hardest to explain |

**Recommendation: B.** The audit already notes the current title is "the right
total", so the gap is that the caller cannot tell the rows are off-screen. B
fixes the information, not the data. In detail:

- The result-count line shows `143 dances · 14 selected (9 not shown)` and a
  *Deselect those not shown* action when the second number is above zero. We put
  it there, not in the bar title, because that line is where the eye is while
  typing, and the live-region title stays a plain count.
- Every batch action's snackbar and screen-reader announcement already say how
  many dances changed (`collectionBatchTagged(count)` etc.). They keep doing
  that, and the count includes hidden dances. Delete (Q4) additionally names the
  hidden share in its confirmation.
- Two cases are pruned regardless, because they are not "hidden", they are
  **gone**:
  1. A selected id that is no longer in `CollectionData.dancesById` (deleted on
     another device and synced, or the caller deleted it from the row menu).
     Drop it in `_onCollectionData`. Without this the title says "14 selected"
     while 13 dances exist, and the batch handlers silently `continue` past the
     missing one (`:1417`, `:1562`).
  2. Entering **online mode** ends selection mode, closing the gap above. The
     toggle's handler is `_onOnlineToggled` (`:944`).
- When `_searchError != null` the search failed and `_results` was set to empty
  (`:871`). The "not shown" count must not read as "all 14 are hidden". The
  batch actions are disabled while the error shows, and the count line is
  replaced by the error.
- Implementation shape: move the set, the "not shown" arithmetic and the
  reconcile rule into a small `CollectionSelection` class
  (`app/lib/src/search/collection_selection.dart`) so that the policy is a pure
  function with unit tests. This also keeps the diff in `dance_list_screen.dart`
  (3,214 lines, contended by U9, B14, B15 and B16) small.

**Rejected:** A, as the default. It stays available if the maintainer prefers a
simpler model; the switch is one line in the reconcile rule. See Decisions
needed.

## Q3. Keep *Group by category* while selecting?

**What goes wrong today.** The caller groups by *Contra Level*, long-presses a
row to select, and the sections vanish. The row under their finger moves, and
the list is a different shape from the one they started in (`:2994`).

**Does grouping need to be suppressed?** The code comment's reason ("a single flat
list") is not a correctness argument. Grouping is a pure partition of
`_results` (`_buildGroupedItems`, `:3023-3050`), and selection changes no tag,
so no row moves between sections while the caller is selecting. The only moves
come from an outside write, such as a sync, which would also move rows in the
flat list when it re-sorts. The exception is the *batch tag* flow itself: if
the caller adds the grouping tag to the selection, the rows move on exit. That
is expected, and it already happens today because exit restores the sections.

**Recommendation: keep grouping on.** Remove the `_selectionMode ? null :` at
`:2994`. Give each section header a tri-state checkbox that selects or clears
that section's rows. This answers "batch-tag within a drawer" directly and costs
no extra bar control.

**What the PR has to get right.**
- `_buildSectionHeader` (`:3055`) wraps its child in `ExcludeSemantics` under a
  single header node. A checkbox needs its own semantics: one node whose label
  reads "{label}, {count} dances, {n} selected" with a toggle action. A test must
  show that a screen reader can reach it (`ux.md` §1 and `accessibility.md`).
- The checkbox applies to the section's rows in `_results`, not to hidden
  selections, matching Q1.
- The header count (`count`) is the section's total, not the selected number.

**Rejected:** keeping the flat list and adding a "select by tag" action. It
re-creates grouping inside the bar and leaves the reflow bug standing.

## Q4. Which batch actions to add

The audit lists delete, status, mixer, mixed level, add to program and source.
The table gives each one's repository path, what Undo restores and what is new.
"New" means a core method or a dialog that does not exist yet.

| Action | Fields written | Core call | Undo | Size of new work |
| --- | --- | --- | --- | --- |
| **Delete** | `deleted_at`, `existence_at` | New `softDeleteMany` over the existing `softDelete` (`:1882`) | New `restoreMany` over `restore` (`:1914`) | Core + dialog + snackbar |
| **Status** | `dances.status` | New `setStatusForMany` beside `setLevelForMany` (`:2482`) | Per-dance prior status | Core + one dialog |
| **Mixer** | `dances.mixer` | New `setMixerForMany` | Per-dance prior value | Core + one dialog |
| **Mixed level** | `dances.mixed_level` | New `setMixedLevelForMany` | Per-dance prior value | Core + one dialog |
| **Add to program** | `program_slots` | Existing program `update`, as the single-dance sheet does (`widgets/add_to_program_sheet.dart:196-247`) | Restore each program's prior slot list | Depends on N3 |
| **Source** | `dance_sources` | New `addSourceForMany` (add only) | Per-dance prior citation list | Core + picker reuse |

All five new writes are `_updateMany` calls. That gives them the transaction and
the `localUserEdit` stamp the existing handlers use, and `Dance.copyWith`
already carries `status`, `mixer`, `mixedLevel` and `sourceCitations`
(`packages/compendium_core/lib/src/model/dance.dart`).

### Delete

**What it must do.** Soft-delete every selected dance in one transaction, so a
failure leaves the collection untouched, and restore them in one transaction on
Undo (F14's pattern: `_undoBatchLevel`, `:1627`). The trash holds them for the
retention window (30 days by default; `docs/user/collection.md:377-382`).

**Why a core method, not a loop in the screen.** `restore` also rebuilds the
dance's derived rows and clears a pending sync deletion (`:1914-1932`). B9 is
about to add reference revival to that same method (`decided-work-plan.md`, B9).
`restoreMany` must therefore **call the same single-dance logic inside one
transaction**, never a second SQL path, so B9's revival applies to bulk Undo
without a second change.

**Interaction with B8 (trash does not protect).**
- Dances have no referential guard to flip: programs may already reference a
  trashed dance. Programs resolve it with `resolveDeletedSlotDances`
  (`screens/perform_program_screen.dart:1638`), and a later purge sets the
  slot's dance to `NULL` (`dance_repository.dart:1952-1958`).
- B8's rule that restore copes with a missing level or custom field applies to
  bulk Undo through B9, as above.
- Bulk delete therefore never refuses and never warns about programs. The
  single-row delete does not either. A "used in N programs" line in the
  confirmation is possible (one query over `program_slots`), but we do not
  recommend it for the first PR: it would make the bulk path stricter than the
  row path for no stated reason. It is listed as a decision.

**Confirmation.** `ux.md:192-193` says to confirm only where Undo is impossible,
and bulk delete has Undo and a trash. Options:

| | Rule | Gains | Loses |
| --- | --- | --- | --- |
| **A. Follow the setting** | `confirmDeleteIfEnabled`, as the row menu does (`:3108`) | One rule for delete everywhere; `ux.md` stays true | A 200-dance delete with the setting off is one tap; the Undo snackbar is timed |
| **B. Always confirm** | A count-bearing dialog every time | No accidental mass delete | Breaks `ux.md:192-193`; contradicts the *Confirm before delete* setting, which then means nothing for this path |
| **C. Confirm above a size or when hidden dances are included** | Dialog only for large or partly hidden selections | Protects the case the audit worried about (a bad 200-dance import clean-up goes wrong) | A threshold nobody chose; two rules to document |

**Recommendation: A, with the count and the trash named in the snackbar.** The
snackbar reads "Deleted 12 dances" with *Undo*, and its screen-reader text points
at Recently Deleted so the recovery path outlasts the snackbar. The
`confirmDeleteIfEnabled` body (`confirmDeleteBody(itemLabel)`) gets a plural
variant for N dances. We recommend A because the app already built the trash for
exactly this and the cost of a mistake is one trip to Recently Deleted.
We note that `_batchClearTunes` (`:1818`) already breaks `ux.md:192-193`, so
the maintainer may judge the rule as already bent. That is the maintainer's call, not this
note's.

**Other requirements.**
- A failure path from the start: `try`/`catch`, `logCaughtError`,
  `_reportBatchFailure`. `_softDeleteFromList` has none today.
- Delete is **not** an icon on the bar. It goes in the ⋮ menu, last, separated
  and in the error colour, so it never sits beside Set level. The icon, when
  shown (menu leading icon, confirmation button), is the bin that decision D-10
  (part of U12) reserves for "delete"; the minus-circle means "remove from
  this list".
- After the write, drop the rows from `_results` as `_softDeleteFromList` does
  (`:2452`) if the `dances` stream is not fast enough in the widget test; do not
  call `_boot()` from Undo as `:2461` does. The stream already carries a restore.
  The PR's test settles which.
- Sync. N dances become N tombstones in the next pass. §6.8 only holds back a
  tombstone for an entity that is still *cited*. Program slots cite dances
  and survive the delete, so whether any dance tombstone is held back is **not
  verified here**; S3 checks it against §6.8 before it ships. The cost of a very large delete (every dance in a 5,000-row
  collection) has **not been measured** and is a risk named below.

### Status, mixer and mixed level

**Fit.** All three are plain columns on `dances`, classified
(`privacy/field_registry.dart:365-368`) and edited today in the dance editor
(`screens/dance_editor/dance_editor_form.dart:667`, `:369`, `:684`). The Collection
already filters on them (`search/collection_query.dart:54`, `:60`), so the batch
action closes the "find, then fix" loop the audit describes.

**Shape.**
- *Status*: a single-choice dialog over `DanceStatus.values` (active, deprecated,
  broken, draft, variation), as `showBatchLevelDialog` does for level. The
  labels reuse the editor's.
- *Mixer* and *Mixed level*: a two-choice dialog ("Mark as mixer" and "Not a
  mixer"), with the same cancel and apply rules as the level dialog. There is no
  "clear" because they are booleans, not nullable.
- Each follows `setLevelForMany`: skip dances already at the target, stamp
  `updatedAt` only on those that change, return the count, and let the handler
  report "no changes" when it is zero (`collectionBatchNoChanges`).
- Undo restores each dance's prior value, narrowed to the dances that changed,
  exactly as `_batchSetLevel` does (`:1582-1585`).

**Options for the menu.** One entry per field is consistent with level and
rating. A single *Edit details…* dialog with three sections, each defaulting to
*leave unchanged*, is shorter in the menu and one transaction for all three, but
it is a new pattern and a bigger dialog. **Recommendation: one entry per field,
under one divider**, because it matches the existing handlers and the three
`*ForMany` methods stay independently testable. See "Selection bar layout" for
the menu length this causes.

### Source

**What it can mean.** Sources attach as `SourceCitation(sourceId, page, number)`
(`model/source_citation.dart:11`). A batch can reasonably set *which* source,
but not the page or number, which differ per dance.

**Recommendation: add only.** *Add source* picks (or creates) a
`PublishedSource` and appends a citation with no page or number to every
selected dance that does not already cite it. A dance that already cites the
source, with whatever page, is left alone and not counted. We reject *replace*
and *remove*: a replace discards page numbers the caller typed by hand, and
Undo of a replace is a second multi-field restore. Remove can come later.

**Dependencies.** The picker and the create dialog are private to the dance
editor (`screens/dance_editor_screen.dart:801-840`; the citations editor is
`dance_editor_form.dart:756`), so a reusable picker has to be extracted first.
N2 is also deciding how sources are renamed and merged, and a batch add must
not pre-empt that. **Recommendation: build this last, after N2 decides.** It is
the lowest-value action in the list: the audit's own cleanup scenarios (bad
import, duplicates) are served by delete, tags and status.

### Add to program

**What exists.** The single-dance sheet appends one slot and offers Undo by
writing the program's prior slot list back (`widgets/add_to_program_sheet.dart:196-247`).
N3 designs that sheet's search, "already contains" and past-program rules. N4
must not redesign any of them.

**What bulk adds.** The sheet takes a *list* of dances. Two questions are real:
- **Order.** `_selectedIds` keeps tap order, but nothing on screen shows it (no
  numbers on rows), and *Select all* has no meaningful tap order.
  **Recommendation: insert in list order** (the order the caller sees, under the
  active sort), because the caller can predict it. The rejected alternative is
  tap order, which is invisible and breaks with accumulate-across-searches.
  The program editor reorders afterwards in either case.
- **Duplicates.** Whether a dance already in the program is skipped, added again
  or flagged is N3's "already contains" answer. Bulk reuses it.

**Dependencies.** N3 (the sheet), plus F10 and F11 (they edit the program editor
and summary, and F11 fixes the program Undo this reuses). So this action is not
sized until N3 is decided, and it should not be the first thing built.

### Order of value

Recommended order, by what the audit's scenarios need: **Select all and the
hidden-selection count**, then **delete**, then **status, mixer and mixed level**,
then **add to program**, then **source**.

## Selection bar layout

With these additions the bar would carry up to thirteen actions. At the 48 dp
slot width the file already assumes (`_actionSlotWidth`, `:2032`), a 360 dp
phone fits the close button, a count, and about three icons.

**Recommendation.** Keep the three icons that exist (Add tags, Remove tags, Set
level). Add *Select all* as a fourth icon, only on widths that fit it. The ⋮
menu becomes a grouped menu, with dividers between:
1. *Details*: Set rating, Status, Mixer, Mixed level.
2. *Other*: Add tunes, Clear tunes, Edit custom field, Add source.
3. *Programs*: Add to program.
4. *Delete* (error colour).

If *Select all* does not fit it moves to the top of the ⋮ menu. The width test
follows `_glyphsThatFit` (`:2037`), which already moves bar glyphs into the menu
when the width runs out, so the PR reuses that mechanism instead of inventing
one.

**Alternatives.**
- A **bottom action bar** (Material 3 contextual bar) gives each action a visible
  label but replaces the phone's bottom navigation while selecting, which is an
  app-shell change and a larger blast radius.
- A **bottom sheet** of grouped actions behind one *Actions* button scales
  better than a menu but costs a tap for the commonest actions.

We reject both for now. The ⋮ menu is the existing pattern, and the PR measures
the menu at 320 × 568 and at the largest text scale before it ships.

## Constraints

**Sync (`sync-spec.md`).** None of the new actions adds a record kind, a column
or a settings key, so **§6.15 (capability gate, `:4417`) and §6.6 (id aliases,
`:3197`) are not engaged.** Each changed dance is an ordinary dance edit with
`localUserEdit: true`, the provenance §6.8 (`:3722`) counts as a deliberate
local edit. `restoreMany` goes through `restore`, which clears a pending
deletion itself (`:1914-1932`). If a later
decision adds a new kind (for example, a persisted saved selection), that goes
through §6.6 and §6.15 first. Nothing here should.

**Privacy registry (`AGENTS.md`; `field_registry.dart`).** No new persisted field
is introduced. The selection, the hidden count and the grouping choice are
session-only widget state, like `_groupTagId` (`:275`). The columns written
(`dances.status`, `.mixer`, `.mixed_level`, `dance_sources.*`) are already
classified (`field_registry.dart:365-368`, `:654-658`). Persisting a selection or
a per-device "selection mode default" would need entries on all three axes and is
not proposed. Subject-axis note: a source citation names a third-party work, and
a bulk add writes more of those; the existing classification already covers
them.

**`ux.md`.**
- *Undo/soft-delete everywhere, confirm only where Undo is impossible*
  (`ux.md:192-193`): every action here has Undo. Delete's confirmation is
  Decision 4.
- *Phone first*: Question 4's layout section is the check. The note's tests
  include a 320 dp width and 2× text scale.
- `ux.md:58-60` lists Collection's actions ("new dance, import, duplicate, batch
  tag") and must change in the implementing PRs.

**F14 (merged, #1993).** Batch writes stay single-transaction with transactional
Undo and a failure path. The new handlers copy `_batchSetLevel` and
`_undoBatchLevel` (`:1545`, `:1627`) and `_finishBatch` (`:1646`).

**B8 and B9.** Covered under Delete. `restoreMany` calls the single `restore`
inside one transaction.

**B14 (picker parity).** B14 extracts Collection's private search controls into
shared widgets, and the picker has **no multi-select** (`widgets/collection_picker.dart`
has no selection state), so no selection code is shared. The two branches
overlap only as edits to the same large file. Land the first N4 branch after B14
and B15.

**D-11.** Nothing here places Save, New or the header. The one title touched is
the selection bar's count, whose wording and position this note leaves as they
are.

**Docs the implementing PRs must update in the same PR (`AGENTS.md`).**
- `docs/user/collection.md:388-410` ("Change many dances at once") lists the
  actions and says what happens to hidden rows.
- `docs/user/collection.md:377-382` (Delete) gains the bulk path.
- `docs/design/ux.md:58-60`.
- ARB keys in all six locales, each beside related keys, and a
  `changelog.d/<id>.json` fragment per user-visible PR.

## Decisions needed

Each is a recommendation, not a decision.

1. **Hidden selections (Q2).** Recommend **B, keep and say so**, with
   *Deselect those not shown*. The alternative is A, prune on every search.
2. **Select all scope (Q1).** Recommend **the current results only**, no
   "whole collection" step.
3. **Grouping while selecting (Q3).** Recommend **keep grouping on**, with a
   tri-state checkbox per section header.
4. **Bulk delete confirmation (Q4).** Recommend **follow the *Confirm before
   delete* setting** (option A). Options B (always) and C (above a threshold or
   with hidden dances) are in the Delete section. Say whether `_batchClearTunes`'s
   unconditional confirmation is the pattern you want for bulk delete.
5. **Which actions, and in what order (Q4).** Recommend delete, then status,
   mixer and mixed level now; **defer source until N2** and **add to program
   until N3**. Also whether delete should warn when selected dances appear in
   programs (not recommended for the first PR).
6. **Selection bar structure.** Recommend the **grouped ⋮ menu** with *Select
   all* as a bar icon where it fits. Alternatives: a bottom bar, a combined
   *Edit details…* dialog.

## Proposed branch breakdown

Format and sizing follow `decided-work-plan.md`: S < 150, M 150–400, L 400+
changed lines, tests included. Each UI branch adds its keys to all six ARBs and
a `changelog.d` fragment. The sizes are this session's estimates, not
measurements.

| # | Branch | Items | Main files | Size | Model | Depends on |
| --- | --- | --- | --- | --- | --- | --- |
| S1 | `feat/collection-select-all` | Select all; "N not shown" and *Deselect those not shown*; drop ids that no longer exist; end selection when online search turns on; `CollectionSelection` class | `search/collection_selection.dart` (new), `screens/dance_list_screen.dart` (`:374`, `:645`, `:814`, `:944`, `:2330`, `:2854`), ARBs, `docs/user/collection.md`, `docs/design/ux.md:58-60`, tests | M (~300) | Sonnet | B14 and B15 (same file) |
| S2 | `feat/selection-keeps-groups` | Keep grouping while selecting; section checkbox with semantics | `screens/dance_list_screen.dart` (`:2994`, `:3055`), ARBs, tests | S–M (~200) | Sonnet | S1 |
| S3 | `feat/batch-delete` | `softDeleteMany`, `restoreMany`, Delete in the menu, confirmation, snackbar, failure path | `dance_repository.dart` (`:1882`, `:1914`), `dance_list_screen.dart`, `utils/confirm_delete.dart`, ARBs, core and widget tests | M (~350) | Opus (transaction, sync tombstones, shares the restore path with B9) | S1, B9 |
| S4 | `feat/batch-details` | Status, mixer, mixed level: three core methods, three dialogs, grouped ⋮ menu | `dance_repository.dart` (beside `:2482`), new batch dialogs, `dance_list_screen.dart` (`:159`, `:2330`), ARBs, tests | M (~400) | Sonnet | S1 |
| S5 | `feat/batch-add-to-program` | Add to program for a list of dances, in list order | `widgets/add_to_program_sheet.dart`, `dance_list_screen.dart`, ARBs, tests | M (size after N3) | Sonnet | N3 decided, F10, F11, S1 |
| S6 | `feat/batch-add-source` | Add source (add only); extract the editor's source picker | `screens/dance_editor_screen.dart` (`:801-840`), `dance_repository.dart`, new picker widget, ARBs, tests | M–L (~450) | Sonnet | N2 decided, S4 |

**Order.** S1, then S2, S3 and S4 in parallel (they edit different parts of the
selection bar, so serialise their merges), then S5 and S6 when their
dependencies land. All six edit `dance_list_screen.dart`, so none starts while
U9, B14 or B15 is unmerged, and merges go one at a time.

**Every branch.** Run `python3 tools/preflight.py`. For each new behaviour,
show the guard test failing against the naive version first
(`docs/dev/agents/verification.md`): for S1, a search that hides a selected row
must fail the "not shown" assertion if the count is computed against the wrong
list; for S3, a failure mid-batch must leave every dance live.

## Risks not measured

- **Large selections.** The batch handlers read each dance with `getById` before
  writing to capture priors (`:1560-1563`, `:1415-1417`). With *Select all* on a
  collection of thousands, that is thousands of hydrations, each decoding
  `figures_json`, before the write begins. `CollectionData` already holds the
  hydrated dances (`data.dancesById`), so priors could come from there. Nobody
  has timed either path, and the S1 and S3 PRs must measure a 5,000-dance
  *Select all* then Add tags and Delete on the lowest-end target, and quote the
  figures in the PR body after the final rebase.
- **Sync after a mass delete.** 5,000 tombstones in the next pass is untested.
- **Menu length** at 320 × 568 with the grouped menu (13 entries) is unchecked.
