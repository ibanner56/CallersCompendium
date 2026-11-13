# LIFE — What create, rename, duplicate and delete actually do to your data

Auditor key: `LIFE`. Tree: `a6665db` (v0.8.1-beta prep). Read-only; nothing was built or run. No `dart test` was run because `packages/compendium_core` has no `.dart_tool/package_config.json`, and running `pub get` would have changed the tree. Every **Traced** finding below comes from reading the call path end to end.

## Scope & method

User guides read: `docs/user/collection.md` (tidy/delete/duplicate/custom fields), `programs.md` (create/duplicate/delete, slots, alternates, venue, calling history), `settings.md` (Deleted items, Venues, Import defaults, Level, Sync decisions), `getting-started.md` (deletion promise), `dialects.md` (program dialect), `authoring.md` (author/source details).
Design docs read: `docs/design/storage.md` (delete model, tombstone adoption, Durability), `domain-model.md` (principles, ALT invariant), `sync.md`/`sync-spec.md` (published-tombstone retention only).
Code traced:
- Core repositories: `dance_repository.dart` (softDelete/restore/purgeDeleted/duplicate/GC), `program_repository.dart` (duplicate/softDelete/restore/purgeDeleted/venue guard/calling history), `venue_repository.dart`, `tag_repository.dart`, `custom_field_repository.dart`, `difficulty_level_repository.dart`, `user_glossary_repository.dart`, `repositories.dart#deleteUserFigure`, `sync_local_repository.dart` (published_records lifecycle), `existence.dart#stampExistenceTransition`.
- Models: `Dance.duplicate`, `Program.duplicate`, `Program.alternateGroupsForSlots`, `DanceLink`.
- App: `recently_deleted_screen.dart`, `main.dart` startup sweep, `soft_delete_retention.dart`, `dance_list_screen.dart`, `dance_detail_screen.dart`, `programs_list_screen.dart`, `program_editor_screen.dart`, `program_summary_screen.dart`, `program_slot_list_editor.dart`, `venue_manager_screen.dart`, `venue_label.dart`, `custom_fields_screen.dart`, `settings/defaults_section.dart` (levels), `settings/dialect_section.dart`, `dialect_library_controller.dart`, `program_dialect.dart`, `tag_colors_screen.dart`, `glossary/custom_figure_detail.dart`, `dance_editor_screen.dart` (choreographer/source create/edit), `utils/confirm_delete.dart`, and the relevant `app_en.arb` strings.

### Entity × operation matrix (as built)

| Entity | Create | Rename/edit | Duplicate | Delete (storage) | In Recently deleted? | Undo snackbar | Confirm says dependents? | Dependents on delete | Restore | Permanent delete / retention |
|---|---|---|---|---|---|---|---|---|---|---|
| Dance | yes | yes | yes (keeps status, rating, tags; drops provenance; links re-minted, `transitive` dropped) | soft | yes | yes | no (optional generic "You can undo this") | slots keep `dance_id`; editor shows "(deleted dance)", summary "Dance unavailable" | yes, all joins intact | purge → slots become text tombstones; GC of orphan tags/authors/sources. **Published rows never purge** |
| Program | yes | yes | yes (draft, pay dropped, **event date and venue kept**, performed marks dropped) | soft | yes | yes | no | its slots drop out of every dance's calling history | yes | purge cascades slots. Countdown hard-coded to 30 days |
| Slot / alternate | yes | Edit slot / Replace | n/a | hard (cut) | no | editor undo | no | **alternates re-parent to the previous slot** | editor undo only | n/a |
| Venue (+ contacts) | yes | yes (id-based) | no | soft (tombstone kept indefinitely) | no | no | UI says "Permanently delete… can't be undone" | blocked by live programs only | **no UI** | no sweep |
| Choreographer / author | via dance editor | yes (id-based); a rename onto an existing name is refused | no | **no UI** | — | — | — | — | — | erased by the dance-purge GC when unreferenced and unpublished |
| Published source | via dance editor | yes | no | **no UI** | — | — | — | — | — | the same GC |
| Tag | via dance editor / batch | **no rename UI** (colour only) | no | **no UI** (only import-undo cleanup) | — | — | — | — | — | the same GC |
| Difficulty level | yes | yes (id-based) | no | soft | no | no | no confirm (already reported) | blocked by any dance, **including trashed ones** | no UI | no sweep |
| Custom field def | yes | label yes; key/type locked when in use | no | soft | no | no | "cannot be undone", then refuses if in use | blocked by **live** dances only | no UI | no sweep |
| Custom field choice option | add (also inline) | **no rename** | — | removal blocked if used by any dance (trash included) | — | — | — | — | — | — |
| Custom (user) figure | yes | yes; switch to a built-in | no | soft + **irreversible freeze** of uses into text | no | no | yes: counts live/trashed uses and defaults (best in app) | live uses frozen; dialect wording and matrix column dropped; shorthands kept | no UI | no sweep |
| Dialect | yes | rename (by name) | yes | hard (settings blob) | no | no | "permanently removed", no program count | programs keep a dangling name → shown "unavailable" | no | — |
| Theme / shorthand / compound shorthand / snippet | yes | yes | theme yes | hard (settings) | no | no | (already reported) | n/a | no | — |
| Formation colour / matrix column config | edit | rename columns | — | reset | — | — | — | — | — | — |

---

## Findings (ranked)

### LIFE-1 — High — "Permanently delete" on one trashed item silently purges every other item deleted more than 30 days ago, regardless of the retention setting (Traced)

**Scenario.** A caller sets *Settings › Keep deleted dances for* to **Never** (or 90 days) because they use the trash as a parking lot. Over a few months they delete several dances. Then they open Recently deleted and permanently delete one item they are sure about.
**Expected.** Only that item goes.
**Actual.** Every dance deleted more than 30 days ago is hard-deleted at the same moment, with no mention of it. The same happens with programs on the programs trash screen.
**Evidence.**
- `app/lib/src/screens/recently_deleted_screen.dart:340-345`: `permanentlyDelete` = `softDelete(dance.id, at: DateTime.utc(1970))` followed by `purgeDeleted(now: DateTime.now().toUtc())`, with **no `retention:`** argument. Lines 368-373 do the same for programs.
- `packages/compendium_core/lib/src/storage/repositories/dance_repository.dart:1932-1950`: the default is `retention = const Duration(days: 30)` and the selection is `deletedAt <= now - retention` over **all** rows, not just the one requested. `program_repository.dart:1428-1440` is identical.
- The startup sweep does honour the setting (`app/lib/main.dart:1555-1581`), and its comment says a "never" user must not lose items. The manual path bypasses that guarantee.

**Fix shape.** Delete by id. The code already has an id-scoped erase in `hardDelete` (`dance_repository.dart:2295`), which includes slot cleanup.

### LIFE-2 — High — A dance or program that was ever synced can never be removed from Recently deleted, but "Permanently delete" reports success anyway (Traced)

**Scenario.** A caller who has used Device Sync (even once, even if it is now off) deletes a dance, then chooses **Permanently delete** in Recently deleted.
**Expected.** The dance is gone, as the snackbar says, and as `collection.md:370-374` promises ("delete it permanently… purged automatically after 30 days").
**Actual.**
- The snackbar says *"“X” permanently deleted."*
- The list reloads and the dance is **still there**, now with a red **"Scheduled for deletion"** label (its `deletedAt` was rewritten to 1970).
- It stays forever. Auto-purge also skips it.
- Its full content (notes, and through its joins any private choreographer data) stays on disk and in every backup.

**Evidence.**
- `dance_repository.dart:1950-1959` and `program_repository.dart:1441-1449`: purge excludes `publishedSyncRecordIds`.
- `sync_local_repository.dart:725-750`: `published_records` rows are only ever inserted. A grep finds no deletion anywhere in the code, and `clearOnDetach` (`:526-539`) does not clear them, so turning sync off does not help.
- `recently_deleted_screen.dart:219-225` shows the success snackbar unconditionally.
- `storage.md:887-890` does document "retained as tombstones indefinitely", but nothing user-facing says so.
- Side effect: `existence.dart:185-197` also sets `updated_at` to 1970 on that row. A record's content timestamp therefore moves backwards. I did not check what sync makes of that.

**Decision.** Options:
- (a) Hide published tombstones from the trash once "permanently deleted" (for example with a "removed" flag), and blank their content while keeping the tombstone. Blanking would also address the privacy concern.
- (b) Tell the user the item will be removed from other devices but kept as a deletion record, and change the copy to match.
- (c) Retire `published_records` entries once every known peer has the tombstone.

### LIFE-3 — Medium — The programs trash shows a fixed 30-day countdown, but programs are actually purged according to the dances-only setting (Traced)

**Scenario.** With *Keep deleted dances for* = **Never**, a caller deletes a program. In the programs trash it counts down from 30 days, then shows red **"Scheduled for deletion"** forever, and the empty state says programs are kept "for 30 days". With **90 days**, the program shows "Scheduled for deletion" from day 30 to day 90.
**Evidence.**
- `recently_deleted_screen.dart:357-361`: "Programs use a fixed 30-day retention window (no user-configurable setting)", with `loadRetention` omitted.
- `main.dart:1569-1581`: the sweep purges programs with the same user `retention` as dances.
- The setting is labelled *"Keep deleted dances for"* (`app_en.arb:3672-3676`) and `settings.md:75-78` says it applies to dances only.

All three disagree with each other.

### LIFE-4 — Medium — Venue delete: the guide's promises are false in both directions; a restored program silently loses its venue, and duplicating it then fails with no feedback (Traced)

**Scenario.**
1. Delete last season's program P, which is linked to venue V.
2. In *Manage venues*, delete V. This is allowed, although `settings.md:119-121` says a venue "can't be deleted while any program is still linked to it".
3. Restore P from Recently deleted. The venue line silently disappears, or falls back to stale free text.
4. **Duplicate** P from the Programs list. Nothing happens.

**Evidence.**
- `venue_repository.dart:236-266`: the guard counts `programs.deleted_at IS NULL` only. Its own comment says "a tombstoned venue can be restored alongside the program that names it", but `ProgramRepository.restore` (`program_repository.dart:1351-1366`) never revives the venue, and no venue restore UI exists.
- `venue_label.dart:23-32`: a non-resolving `venueId` falls back to free text or null.
- `Program.duplicate` copies `venueId` (`program.dart:558`). `create` then runs `_upsert` with `enforceVenueExists = true` (`program_repository.dart:468-494`). For a new id, `storedVenueId` is null ≠ `venueId`, so it throws `StateError`.
- `programs_list_screen.dart:456-473` has no try/catch, so the user sees nothing.
- `settings.md:118` and the dialog *"Permanently delete “{name}”? This can’t be undone."* (`app_en.arb:12085`) describe a hard delete. The row is actually tombstoned and kept indefinitely: `storage.md:890-893` says there is "no retention sweep yet" for these kinds. That includes contact names, phones and emails of third parties.

### LIFE-5 — Medium — Tags, choreographers and published sources can be created but never deleted, renamed (tags) or merged by the user, yet the trash purge erases them behind the scenes (Traced) — **Decision**

**Scenario (story items "rename a tag", "rename a misspelled choreographer").**
- **Tags.** There is no rename or delete anywhere. `tag_colors_screen.dart:23-26` says so explicitly. A typo tag ("bouncey") lives in every picker and filter forever, even after the caller removes it from every dance.
- **Choreographers.** A rename to a name that already exists (the usual case: "Gene Hubert" imported, "Gene Hurbert" misspelled on another import) is refused with "not changed" (`dance_editor_screen.dart:686-702`). There is no merge and no batch "set author", so the caller must re-attribute each dance one by one. The misspelled author then stays in the picker forever.
- **Silent erasure.** If the last dance holding a tag, author or source is trashed and then purged, the GC hard-deletes the parent (`dance_repository.dart:1979`, `2196-2246`). That takes the tag's colour with it, and the choreographer's private email, location and notes. Removing the same tag from the same dance by editing it never removes the tag. Same end state, opposite outcomes.
- **Guide drift.** `settings.md:402` says "If you later delete one of the tags, imports simply skip it", but there is no way to delete a tag.
- **Inconsistency with sync.** *Sync decisions* offers **Merge** for choreographers and tags (`settings.md:1158-1168`), so merging exists in the product, but only when two devices collide.

**Options.**
- (a) A tag/author manager with rename-with-merge and delete, which tells the user how many dances it affects.
- (b) At minimum, a batch "replace author/tag" action.
- (c) Make the GC apply only to rows the user never edited (colour, notes).

### LIFE-6 — Medium — Deleting a program silently erases its dances' calling history (Traced) — **Decision**

**Scenario.** A caller tidies up by deleting old programs. Every dance in them loses those calling-history entries and the "repeated venues" counts. These are exactly the data callers use to avoid repeating dances. The confirm (when enabled) says only *"“X” will be deleted. You can undo this."* (`app_en.arb:282`). After the retention window the loss is permanent.
**Evidence.** `program_repository.dart:1094-1108`: history is derived live from `program_slots JOIN programs … AND programs.deleted_at IS NULL`. `programs.md:424` says "Every program feeds a dance's calling history" but never mentions that deleting a program removes it.
**Options.**
- (a) Say it in the confirm and the guide ("N dances will lose this from their calling history").
- (b) Offer **Archive**, which hides the program but keeps the history.
- (c) Snapshot history on delete.

### LIFE-7 — Medium — Duplicating last month's program immediately double-counts every dance as called on last month's date (Traced)

**Scenario.** `programs.md:49` suggests: "Duplicate a program … to reuse last month's shape". The copy keeps the original **event date** and venue. With the default "any program that contains the dance counts" setting (`programs.md:430`), every dance now shows two calling-history entries on the same date. The "Called / Not called" filter and the repeated-venue summary count it twice, until the caller notices and changes the date.
**Evidence.** `program.dart:548-584` copies `eventDate`, `venue` and `venueId`, while it does reset `status` and `performedAt`. `program_repository.dart:1094-1108` applies no status filter.
**Fix shape.** Clear `eventDate` on duplicate, as is already done for pay ("belongs to one event", `program.dart:566-567`). The same reasoning applies to the date.

### LIFE-8 — Medium — A trashed dance's program slots hide its title exactly while it is still recoverable, and the three program views disagree (Traced)

**Scenario.** A caller deletes a dance that appears in three old programs. The delete gives no hint that programs use it. Opening one of those programs:
- **Editor** slot list and matrix: **"(deleted dance)"**, with no title (`program_slot_list_editor.dart:146-149`, `program_editor_screen.dart:3171-3180`; the lookup is live-only, `:1799-1834`).
- **Summary**: **"Dance unavailable"**, no title, non-interactive (`program_summary_screen.dart:474-479` uses `getById` without `includeDeleted`; render at `:1031-1060`).
- **Perform**: **"Title (deleted dance)"**, resolved properly (`perform_program_screen.dart:688`).

The caller cannot tell *which* dance to restore from the trash. Once the dance is **purged**, the slot becomes a text tombstone that *does* show the title (`dance_repository.dart:1999-2010`). The information appears only when it is no longer actionable.
**Fix shape.** Use `resolveDeletedSlotDances` (already used for Perform) in the editor and summary. Add a "Restore" affordance on the slot. Optionally make the dance delete confirm say "in N programs".

### LIFE-9 — Medium — Referential delete guards disagree about trashed dances, and the gap loses data on restore (Traced) — **Decision**

| Guard | Counts trashed dances? | Order |
|---|---|---|
| Difficulty level (`difficulty_level_repository.dart:197-215`) | **yes** (documented `settings.md:418`) | check first, then no confirm |
| Custom field def (`custom_field_repository.dart:349-366`) | no | confirm "cannot be undone" → then refuse (`custom_fields_screen.dart:233-277`) |
| Venue (`venue_repository.dart:250-266`) | no (trashed programs) | confirm "permanently delete" → then refuse |
| Choice option removal (`custom_field_repository.dart:318-327`, `custom_fields_screen.dart:515-527`) | **yes** | refuse inline |

**Consequences.**
- A caller can delete a whole custom field used by a trashed dance, but cannot remove one *option* of it used by that same dance.
- After deleting the field, restoring the dance hides its value. No UI can restore the field.
- If the caller then re-creates a field with the same key, tombstone adoption **erases** the value (`storage.md:866-874`; `existence.dart:408-434`).
- With retention "Never", a trashed dance blocks a level indefinitely, and the "in use" message does not say the use is in the trash.

**Decision.** Pick one policy (trash protects, or trash does not) and apply it uniformly. Check before confirming.

### LIFE-10 — Medium — Cutting a primary slot silently re-parents its alternates to the slot above (Traced)

**Scenario.** Program: `… Break, B, B-alt, C`. The caller cuts **B**, expecting the backup to take its place. Instead **B-alt** stays `isAlt` and becomes an alternate of **Break** (or of whatever dance precedes it). The slot count drops by one. If B was first, B-alt becomes an "orphaned alt". Moving a primary by drag or move up/down has the same effect.
**Evidence.** `program_editor_screen.dart:2218-2224` (`_removeSlot` just removes and renumbers). `program.dart:393-399` (an alt belongs to the "nearest preceding non-alt"). `domain-model.md:254-261` lists "a deleted primary" as a known way to produce bad ALT ordering. It is tolerated as a warning, but the user is not told.
**Fix shape.** When cutting a primary that has alternates, promote the first alternate or ask the caller.

### LIFE-11 — Low/Medium — A dialect rename or delete silently disconnects every program that uses it; no other rename in the app behaves this way (Traced; documented) — **Decision**

`dialect_library_controller.dart:157-186` rewrites only the active pointer. `Program.dialectName` is a name (`program_dialect.dart:5-12`). `dialects.md:339-342` documents that the program "quietly goes back" and the editor shows "unavailable". Venues, levels, choreographers and custom field labels all rename by id, so "rename" is a true rename everywhere except here. Neither the delete confirm (`app_en.arb:2413`) nor rename says how many programs are affected.
**Options.**
- (a) Rewrite `dialectName` on matching programs during rename, and leave delete as is.
- (b) Count affected programs in both dialogs.

### LIFE-12 — Low — Dance duplicate drops related-dance-group membership and creates one-way links; it is also two non-atomic writes (Traced for the model; UI effect Inferred)

- `dance.dart:393-402` re-mints links **without `transitive`**, so a copy of a grouped dance gets plain links.
- `DanceRepository.duplicate` → `create` bypasses the reverse-link maintenance in `related_dance_links.dart`. I did not run the UI to confirm how the missing back-links render.
- `dance_list_screen.dart:2276-2287` creates the copy under the original title, then updates it to "(copy)" in a second write. A failure between the two leaves an exact-title twin. The doc comment also says it "confirms with a snackbar"; it navigates instead.

### LIFE-13 — Low — Deleting a custom figure leaves its compound shorthands behind, and the delete dialog does not mention them, although the switch dialog counts them (Inferred)

`custom_figure_detail.dart:177-203` (delete body: uses, trash, defaults) vs `:283-296` (switch counts shorthands). `user_figure_shorthands.dart:30-33` keeps `figureName` "when the figure has since been deleted". I did not check what typing such a token now inserts.

### LIFE-14 — Low — Deleting a program from the editor discards unsaved edits, so Undo brings back the last-saved version (Inferred)

`program_editor_screen.dart:2796-2808` waits only for an *already-started* auto-commit, then `_clearDraft()`. Undo (`:2817-2823`) restores the stored row. This matters only when auto-commit is off or pending. I did not check whether a pending debounce counts as started.

---

## Cross-cutting patterns

1. **Storage soft-deletes, the UI hard-deletes.** Eleven kinds are tombstoned (`domain-model.md:18-22`), but only dances and programs have a trash. Venue, custom field, level and custom figure deletes are tombstones the user is told are permanent ("can't be undone"). They are not recoverable, and per `storage.md:890-893` they are not swept either. This combines the downsides of both designs: no restore (UX) and indefinite retention of third-party personal data such as venue contacts (privacy, contradicting `settings.md:118`). Behind LIFE-2, LIFE-4, LIFE-9.
2. **The trash has three different retention truths.** The setting label (dances), the startup sweep (dances and programs, honours the setting), and the manual purge (hard-coded 30 days, all rows) disagree. Published rows ignore all three. Behind LIFE-1, -2, -3.
3. **Delete never tells you what else it affects, except for custom figures.** The custom-figure dialog (uses, trash, defaults) is the model to copy. Dance delete (programs), program delete (calling history), dialect delete/rename (programs) and venue delete (trashed programs) say nothing. Behind LIFE-6, -8, -11.
4. **Shared reference entities have no lifecycle UI.** Tags, choreographers and sources can only be created. Merge exists only inside sync conflict resolution. Garbage collection substitutes for deletion and is invisible. Behind LIFE-5.
5. **Restore restores the row, not its neighbours.** Restoring a program does not revive its venue (LIFE-4). Restoring a dance does not revive its custom field definition (LIFE-9). Dance↔slot/tag joins do survive, which is good.

## Checked and fine

- A dance soft-delete keeps tags, authors, custom values and slots intact, so restore brings them all back. `restore` rebuilds FTS (`dance_repository.dart:1885-1905`).
- A dance purge keeps program slots valid: dance-only slots become captioned tombstones and dangling related links are removed (`dance_repository.dart:1985-2030`).
- The Undo snackbar exists on every dance and program delete path (list, detail, editor, summary, programs list).
- Program duplicate resets status, performed marks and pay. Slots get fresh ids.
- Level, venue, choreographer and source renames are id-based and propagate everywhere.
- The tag-tombstone revival/adoption semantics match `storage.md` ("adoption clears joins", `tag_repository.dart:470-530`).
- Custom figure delete has an accurate dependents count, including trashed dances and default lists.
- The calling history query excludes trashed programs consistently with the trash.
- "Starting program" template skips deleted dances, as documented (`programs.md:35-36`).

## Out of scope but noticed

- SYNC: the 1970 `updated_at`/`deleted_at` rewrite by "Permanently delete" on a published row (LIFE-2) may look like older content to a peer. Not traced into the engine.
- PRIVACY: tombstoned venues and choreographers keep contact personal data indefinitely, and LIFE-2 rows go into backups. The registry may need a retention note.
- UX: Recently deleted has no "Empty trash" or multi-select. Each per-item permanent delete also triggers LIFE-1.
- UX: the custom-field and venue delete flows confirm first and only then refuse, so the user is told the action is irreversible before being told it is impossible.
- Docs: `collection.md:363` says "every change here can be undone". Duplicate has no undo (you delete the copy), and batch-tag Undo leaves created tags as tombstones.
