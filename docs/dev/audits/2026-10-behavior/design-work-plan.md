# Work plan for the five design notes (N1–N5)

Planning only. No app code was changed, built or tested.

**Basis:**

- The maintainer's answers N1-1 … N5-5 in `maintainer-decisions-2026-10-30.md` are the source of truth. Where a maintainer note expands or changes the picked option, the note wins.
- The five design notes on `main`, as amended by the docs PR on `claude/design-notes-decisions` to record those answers:
  - `docs/design/history-filters.md` (N1, FIND-1);
  - `docs/design/tags-and-people.md` (N2, FIND-3, LIFE-5);
  - `docs/design/add-to-program-sheet.md` (N3, FIND-17);
  - `docs/design/bulk-selection.md` (N4, FIND-8);
  - `docs/design/selectable-text.md` (N5, PLAT-17).
- `decided-work-plan.md` (B1–B31, its waves, "Hot files" and "Landing rules"). This plan interleaves with it and does not change it.
- Checked against `origin/main` at `90fe5e8`. Line numbers are the notes' own; each note says which tree its numbers are for.

**Format and conventions** are `decided-work-plan.md`'s, with two changes the brief for this plan set:

- **IDs** keep each note's branch number, prefixed by the note, so they are unique: N1-H1, N2-T1, N4-S3, N5-S1. N3's own branch numbers (N3-1, N3-2) collide with its decision IDs, so here they are **N3-A1** and **N3-A2**.
- **Model:** Opus for transactions, sync or schema; Sonnet otherwise. Three branches change model from their note under this rule, and the docs PR changes the notes to match: N1-H3 (Opus → Sonnet), N2-T2 (Sonnet → Opus), N4-S5 (Sonnet → Opus). Each section gives the reason.
- Size counts changed lines, tests included: S < 150, M 150–400, L 400+.
- Every branch that adds UI text adds keys to all six ARBs, beside related keys, and a `changelog.d/<id>.json` fragment.
- "*My call*" marks a choice made by this planning session, with the alternative it rejected. It is not a maintainer decision.

## Summary

| Note | Branches | Total size | Decisions that changed scope |
| --- | --- | --- | --- |
| N1 history filters | N1-H1, N1-H2, N1-H3 | L + M + L | N1-2's note (presets 1, 3, 6 months plus "Since a date", no 1 year, a never-called choice); N1-4 (b) from today; N1-6 (c) whole program |
| N2 tags, authors, sources | N2-T1 … N2-T4 | L + L + L + S | none (all as recommended); N2-1 leaves T1 to choose the held-peer fix |
| N3 add-to-program sheet | N3-A1, N3-A2 | M + M | N3-4 (b) asks first |
| N4 bulk selection | N4-S1 … N4-S6 | M + S–M + M + M + M + M–L | N4-5 (b) builds all together, and its note drops mixer and mixed level, so S4 becomes `feat/batch-status` |
| N5 selectable text | N5-S1 … N5-S3 | M + S + S | none (all as recommended) |

**18 branches.** None adds a persisted field, column or settings key, so none joins the registry and `data-classification.md` serialisation queue (see "Privacy registry").

**Waves** (details under "Sequencing"). They share the B-plan's cap of four implementation sessions, so each design branch takes a slot as one frees:

- **D1, start now, alongside W2:** N5-S1, N1-H1, N2-T1 (open-risk tests first), N2-T4 (once B7 merges).
- **D2, after B14 → B15 merge:** N4-S1, then N4-S2, N4-S3 (after B9) and N4-S4; N1-H2 (after N1-H1); N2-T2 (after N2-T1 and B10).
- **D3, after F11 (#2040) merges, alongside W3:** N3-A1 → N3-A2; N2-T3 (after N2-T2); N4-S6 (after N4-S4); N4-S5 (after N4-S4 and N3-A2).
- **D4, after W3's B4 → B5, B22 and B29:** N1-H3, N5-S2, N5-S3.

### State on `main` at `90fe5e8`

The plan depends on these, so they are recorded once here:

| Merged | Open | In flight, no PR seen | Not on `main`, no open PR |
| --- | --- | --- | --- |
| B1 #2032, B2 #2043, B6 #2042, B11 #2039, B12 #2037, B16 #2036, B20 #2038, B23 #2035, B26 #2034; F10 #2022, U3 #2016, U7 #2033, U9 #2027, U12 #2028, D-1 #2023 | F11 #2040, B27 #2045, B30 #2046, B31 #2044 | B7 (per the brief for this plan) | B13 and B17 (W1); every W2 and W3 branch. *Update 2026-10-30, from the orchestrating session:* B13 is open as #2048; B7, B17, B14 and B25 are building and hold all four slots, so D1 starts as slots free. |

Two facts from that state change the notes' dependencies, and the docs PR records both:

- **B1 delivered the shared date helper** N1 asked for, as `callingHistoryDateSql` (`calling_history_scope.dart:47-52`). History order and the Last-called sort read it. B1 kept `last_called` in the bulk counts as the newest **performed** slot, dated `COALESCE(event_date, performed_at)`, with a `last_called_dated` variant. N1-H1 shrinks a little; N1-H3 still adds the counted-slot variant.
- **F10 and U7 have merged,** so every "after F10, F11 and U7" in the notes reduces to "after F11".

---

## N1: history filters (FIND-1)

### N1-H1 `claude/called-filter-scopes`

- **Scope:**
  - `CalledFilter` gains `venue` (a venue key, N1-1 = a), `since` (a calendar-date cutoff) and `currentProgramId`.
  - `currentProgramId` leaves out **every** slot of that program (N1-6 = c): `AND p.id <> ?`. Collection never sets it.
  - The recency date is B1's expression without `updated_at` (N1-3 = a): a new `callingHistoryRecencyDateSql` beside `callingHistoryDateSql`. The window has no end, so future programs count (N1-9 = a).
  - `cc_venue_key(text)`, a Dart SQL function registered in `applyCompendiumSqliteSetup`. The repeated-venues summary calls the same Dart function.
  - Pass the setup in the two shared test helpers and the core tools and benchmarks the note lists (Q1), so a `text:` scope cannot fail with "no such function" there.
  - A query that lists the venue keys with a counted call, for N1-H2's chooser.
- **Files:** `filter.dart`, `filter_compiler.dart`, `calling_history_scope.dart`, `database_setup.dart`, `dance_repository.dart`, `program_repository.dart` (the summary's fold, `:1222-1254` at `296b594`), `test_database.dart`, `test_repositories.dart`, `write_head_database.dart`, `search_benchmark.dart`, `scalability_benchmark.dart`.
- **Size:** L (~450). **Model:** Opus. *My call:* it registers a SQL function on every connection, the sync isolate's included, and that is storage setup. Rejected: Sonnet under a narrow reading of "schema", for the branch that changes the one definition of "called".
- **Depends on:** B1 (merged). Hot files: `dance_repository.dart` / `filter_compiler.dart` after B7 and B13; the `program_repository.dart` chain B9 → B3 → **N1-H1** → B4 → B5.
- **Guard tests, each shown to fail first:**

  | Test | Mutation it must catch |
  | --- | --- |
  | The venue scope and the repeated-venues summary agree on every key, including "Salle  Église" (two spaces, non-ASCII capitals) | SQL `LOWER(TRIM(p.venue))` in place of `cc_venue_key` |
  | A typed "Grange" does not match the record "Grange" | Matching by displayed name (GIG-7's rejected option) |
  | "Not called at V within 3 months" is `NOT EXISTS` a counted slot at V in the window | `EXISTS (a slot not at V)` |
  | An undated, unperformed slot is called but never in a recency window | The recency variant reading B1's full expression, `updated_at` included |
  | A program dated next month counts inside "within 3 months" | A window closed at today |
  | `currentProgramId` hides a **performed** slot of that program | The note's old rule, unperformed slots only |
  | SQL, `effectiveDate` and the detail page's `callingHistoryDisplayDate` pick the same date for the same rows, for both date variants | One of the three edited alone (today nothing compares the display date with the others) |
  | Each production connection has `cc_venue_key` | Registration removed from `applyCompendiumSqliteSetup` |

- **Docs:** `docs/design/search.md:69` and `:160-161` (the `CalledFilter` rows, adding `requireEventDate`, the alternate rule and the new scopes). No ARB, no changelog: nothing user-visible yet.
- **Privacy:** nothing persisted. The SQL function is code.

### N1-H2 `claude/history-filter-controls`

- **Scope:**
  - The Filters panel's Calling history section gains **At venue** and **Within**.
  - **Within** offers 1 month, 3 months and 6 months, **Since a date…**, and a never-called choice (N1-2 = a, with the maintainer's note). No 4-week and no 1-year preset. Ambiguities 1 and 2 (accepted readings) settle the never-called choice and "1 month".
  - Every window counts back from today (N1-4 = b).
  - The inert state with the hint "Applies with Called or Not called", and active counts that include each scope.
  - The venue chooser: distinct keys with a counted call, the program count per row, and "typed" on a typed key.
  - Both `FacetPanel` hosts get the section.
- **Files:** `facet_panel.dart`, `collection_query.dart`, `collection_data.dart`, `dance_list_screen.dart`, `collection_picker.dart`, ARBs ×6, `changelog.d/`.
- **Size:** M (~400). **Model:** Sonnet.
- **Depends on:** N1-H1; B14 → B15, which own both host files. B15 now builds R2-tag-tap's AND/OR toggle, which may sit in the same `FacetPanel` Tags section, so H2 rebases after it.
- **Guard tests:**

  | Test | Mutation it must catch |
  | --- | --- |
  | With neither or both polarities chosen, a set scope changes no result and the active count leaves it out | The scope applied without a polarity |
  | "1 month" selects the cutoff today minus one calendar month | A 4-week preset (the option text's, which the note replaced) |
  | No 1-year preset is offered | The option text's preset list copied verbatim |
  | The section's badge counts an active scope | Badge counting polarity only |
  | The never-called choice with **Not called** returns exactly today's Not-called set | A new predicate that drifts from it |

- **Docs:** `docs/user/collection.md:157` (Filters: Calling history).
- **Privacy:** nothing persisted. Scopes live in `FacetSelections`, session-only.

### N1-H3 `claude/picker-history-context`

- **Scope:**
  - The picker takes an optional `programContext`: id, `venueId` and typed venue. *My call (in the docs PR):* no event date, because N1-4 = (b) counts from today. Rejected: an unused date parameter.
  - The **Not called here** chip, off for each program (N1-5 = a), and the **here** marker (icon and word, never colour alone).
  - The picker's scopes, row values and "called ×N" leave out the whole program being edited (N1-6 = c).
  - `CollectionTileField.lastCalled`: "3 mo ago", "in 3 wk", or "undated" (N1-7 = a). The card-fields allow-list is unchanged (N1-8 = a), so customised users turn it on themselves.
  - `lastCalledFor(performedOnly, requireEventDate:)` over the newest **counted** slot, dated by the recency variant, plus a `currentProgramId` variant of the bulk counts. B1 left `last_called` performed-only, so this is new.
  - Four mounts pass `programContext`: `program_editor_screen.dart` ×3 and `perform_adjust_sheet.dart`.
- **Files:** `collection_picker.dart`, `dance_list_tile.dart`, `collection_tile_fields_scope.dart`, `dance_list_entry.dart`, `collection_data.dart`, `program_repository.dart`, `program_editor_screen.dart`, `perform_adjust_sheet.dart`, ARBs ×6, `changelog.d/`.
- **Size:** L (~500). **Model:** Sonnet. *My call:* read-only aggregates and widgets, with no transaction, sync or schema change, so the rule gives Sonnet; the note said Opus for "two hot files and the last-called value". Rejected: keeping Opus, which the rule reserves for writes.
- **Depends on:** N1-H1, N1-H2, B14; F11 for the editor mounts. Hot files: one open PR in the `program_editor_screen.dart` group; after B5 in the `program_repository.dart` chain. So D4.
- **Guard tests:**

  | Test | Mutation it must catch |
  | --- | --- |
  | A dance only in the edited program reads uncalled, with "in program ×1" | `currentProgramId` not passed from the editor mount |
  | A dance **performed** in the edited program is not "here" (N1-6) | Unperformed-only exclusion |
  | The chip starts off when the editor opens a different program on the two-pane layout | Chip state kept across programs |
  | "within 3 months" in the picker of a program dated two months ahead counts back from today | Counting back from the program's date (the rejected N1-4 option) |
  | The chip is hidden for a user whose saved card-field list lacks `lastCalled` | A migration that adds it |
  | A dance whose only counted call is undated and unperformed shows "undated" | The chip reading B1's `updated_at` fallback |
  | With "Require mark performed" off, the chip's date covers unperformed counted slots | Reading B1's performed-only `last_called` |

- **Docs:** `docs/user/programs.md:160-163` (the here marker, the chip, what "called ×N" counts in the picker), `docs/user/settings.md:382-386` (card fields), `docs/user/collection.md:52-58` (Last called). The changelog says where to turn the chip on (N1-8).
- **Privacy:** `collection_tile_visible_fields` gains a value; the key is already `_preference`, so its entry is unchanged and no capability gate is needed (the note's Q4).

---

## N2: tags, authors and sources (FIND-3, LIFE-5)

### N2-T1 `claude/reference-rename-merge-core`

- **Scope:** as the note's T1 section, under N2-1 = (a) and N2-7 = (a).
  - Core `rename`, `mergeInto`, an in-use-aware tag `delete` that strips joins, and `undo`, for the three kinds.
  - `_rewriteLocalReferences` extracted into a storage helper that sync and the merge share.
  - Smaller-UUID survivor; the loser's name freed with a suffix by a name-only write; the alias through `remapIdentity`; an Undo that reverses `remapIdentity`'s writes and keeps the publication marker.
  - **First, before anything else:** the two-device tests for the held-peer risk, then T1's choice of fix, written into the §6.6 amendment with the rejected alternative. N2-1's text leaves this choice to T1; it is not a maintainer decision.
  - Search-index rebuild for every touched dance, and the `sources` column after a source rename if it is stale.
  - The stale comments at `tag_repository.dart:465`, `tag_colors_screen.dart:24-27`, `display_defaults.dart:158`.
- **Files:** `tag_repository.dart`, `choreographer_repository.dart`, `published_source_repository.dart`, `sync_storage.dart`, `sync_local_repository.dart`, a new storage helper, `dance_repository.dart` (index refresh), `existence.dart` (read only), `docs/design/sync-spec.md`, `docs/design/storage.md`.
- **Size:** L (~900). **Model:** Opus (sync and transactions).
- **Depends on:** B7 and B8 merged (both amend `sync-spec.md`, and B8 sets which guards ignore trashed rows); after B13 on `dance_repository.dart`. B30's §6.7 amendment also edits `sync-spec.md`; serialize that file's merges. **Merges alone** (landing rule 3), because it moves a method.
- **Guard tests:** the note's T1 list, each shown to fail. The mutations to name in the PR:

  | Test | Mutation it must catch |
  | --- | --- |
  | Sync reconciliation's existing tests, unchanged, against the extracted helper | A behaviour change in the move |
  | Opposite merges on two offline devices keep the same id | Survivor chosen by "this one" |
  | A rename onto a tombstoned name does not revive the tombstone | Freeing the name through `upsert` |
  | Undo of a merge whose loser had an alias chain restores `id_aliases` | Undo removing only the new alias |
  | A held peer converges under T1's chosen fix | The fix reverted |
  | A tag delete strips joins from trashed dances too, and a re-created tag does not re-tag them (N2-7) | Today's keep-joins delete |

- **Docs:** the dated §6.6 amendment (five rules, N2-1), `storage.md`.
- **Privacy:** none. Aliases go in `id_aliases`, which sync owns. If T1's fix adds a column or a sync-metadata table, it is classified in `field_registry.dart` in T1 (likely `deviceScoped` sync metadata, subject `none`, with the reason in `note`).

### N2-T2 `claude/tag-manager`

- **Scope:** the shared manager list widget; the Tags manager with colours moved in from `TagColorsScreen` (retired); Settings › General › Library entry, and Appearance › Tag colours opening the Tags manager (N2-3 = a); delete with the count and a snackbar-only Undo (N2-5 = a); the `default_import_tag_names` rewrite inside the same `repos.transaction` as the core operation.
- **Files:** a new `settings/library_manager_list.dart` (name is the implementer's), `tag_manager_screen.dart`, `tag_colors_screen.dart` (removed), `appearance_section.dart:178`, the Library section, `display_defaults.dart`, ARBs ×6, `changelog.d/`.
- **Size:** L (~500). **Model:** Opus. *My call:* the import-tags rewrite runs in the same transaction as T1's merge and delete, and its Undo restores both, so the rule gives Opus; the note said Sonnet. Rejected: Sonnet, for a branch that writes a shared setting and records in one transaction.
- **Depends on:** N2-T1; B10 (edits `appearance_section.dart:462-482`). B15's tag-filter rule decides the "show these dances" action, which stays out of T2.
- **Guard tests:**

  | Test | Mutation it must catch |
  | --- | --- |
  | Rename onto an existing name offers a merge, and Merge leaves one entry | Refusing on collision |
  | Delete reports "from N dances", counting live dances only | Counting trashed dances |
  | Undo after delete restores the joins **and** the import-tags name | Undo restoring only the tag |
  | A merge rewrites `default_import_tag_names` and de-duplicates | Rewrite skipped |
  | Delete offers no confirm (Undo exists) | A confirm dialog |

- **Docs:** `collection.md:81-90`, `settings.md:45-57`, `:272-279`, `:432-434`.
- **Privacy:** none new. `default_import_tag_names` is already registered and stays `shareable`; the manager's search, filter and sort are session-only.

### N2-T3 `claude/author-and-source-managers`

- **Scope:** the Authors and Sources managers on T2's widget; the merge offer replacing the refusal at `dance_editor_screen.dart:759-777`; fill-the-blanks author merge with the discard list (N2-2 = b); delete only for unused entries, Merge into for used ones (N2-4 = a); citation page and number fill.
- **Files:** two manager screens, `dance_editor_screen.dart`, `choreographer_details_dialog.dart`, `published_source_details_dialog.dart`, a merge dialog, ARBs ×6, `changelog.d/`.
- **Size:** L (~450). **Model:** Opus (the private-details merge is a multi-row transaction over deviceLocal fields).
- **Depends on:** N2-T2. Serialize with N4-S6 on `dance_editor_screen.dart`. Coordinate with U4 on the "Choreographer details" title (D-3).
- **Guard tests:**

  | Test | Mutation it must catch |
  | --- | --- |
  | An empty survivor email takes the loser's; a conflicting one is listed and dropped | Survivor-wins-whole (N2-2 option a) |
  | `deceased` is set if either row sets it | Survivor's value only |
  | An in-use author offers no Delete | Delete shown for every row |
  | A dance citing both sources keeps one citation with the loser's page filling an empty page | Loser's citation dropped whole |
  | A rename in the dance editor onto an existing author offers a merge | The old refusal |

- **Docs:** `authoring.md:582-597`, `settings.md:1220-1223` (the private-details limit, in the same words as the sync merge).
- **Privacy:** no new field. Merged values stay in their egress class (website and notes `shareable`; email, location and deceased `deviceLocal`); `field_registry.dart`'s notes stay true. The reviewer checks that no deviceLocal value is copied into a shareable field.

### N2-T4 `claude/purge-gc-spares-details`

- **Scope:** `_garbageCollectOrphanedRefs` erases only bare rows (N2-6 = b). The details list is the note's full table, not the decision text's short form (ambiguity 7, an accepted reading).
- **Files:** `dance_repository.dart`, `storage.md:847-849`, the method's doc comment.
- **Size:** S (~120). **Model:** Sonnet.
- **Depends on:** B7 merged (same purge path). Any order against N2-T1; serialize on `dance_repository.dart` (B13, N2-T1, N4-S3, N4-S4, N4-S6).
- **Guard tests:** a coloured tag, an author with only a location, and a source with only a URL each survive the purge (mutation: the old GC); a bare tag is still erased (mutation: GC disabled, option c); the existing `dance_hard_delete_test.dart` watcher guard still passes.
- **Docs:** `storage.md:847-849`. A changelog fragment, *my call*: a spared row is visible as **Not used** in the managers, so it is user-visible once T2 lands; before T2 it is not, so if T4 lands first its fragment says the change shows once the managers ship. Rejected: no fragment.
- **Privacy:** none new. It keeps third-party contact data the maintainer chose to keep ("keeping third-party contact data").

---

## N3: add-to-program sheet (FIND-17)

### N3-A1 `claude/add-to-program-contains-and-new`

- **Scope:**
  - The "already contains" marker, alternates included (N3-6 = a), from one core getter on `Program`; the picker's `_danceSlotCounts` reads it.
  - **Ask first** on a marked program (N3-4 = b): the dialog, its buttons and Cancel behaviour as the note's §4.3 sets out (ambiguity 4, an accepted reading).
  - "New program with this dance" as a pinned first row in every state (N3-5 = a).
  - A named exception beside `ux.md`'s confirm rule (my call in the docs PR).
- **Files:** `widgets/add_to_program_sheet.dart`, `widgets/collection_picker.dart` (count source), `program_editor_screen.dart` (`_danceSlotCounts`), `packages/compendium_core/lib/src/model/program.dart`, ARBs ×6, `docs/user/collection.md`, `docs/design/ux.md`, `changelog.d/`.
- **Size:** M (~330). **Model:** Sonnet.
- **Depends on:** F11 (#2040), which rewrites the sheet's Undo. After B14 on `collection_picker.dart`. One open PR in the `program_editor_screen.dart` group; its hunk there is a few lines, so it goes first in D3.
- **Guard tests:** the note's §6 rows for the marker, the ask-first dialog (prompt skipped; Cancel still adding; unmarked tap prompting; alternate-only match not prompting), the pinned row with 0, 1 and 100 programs, and marker count = picker count.
- **Docs:** `collection.md:306`, `ux.md` §1/§2 and the cross-cutting confirm rule.
- **Privacy:** none.

### N3-A2 `claude/add-to-program-order-and-search`

- **Scope:** open programs first, soonest event first, then by last edit (N3-2 = a); a collapsed "Performed (N)" row with auto-expand (N3-1 = c); status on rows; search above about 8 programs over titles and resolved venue labels with `foldForTitleMatch` (N3-3 = c); sizing from the available height; the list extracted into its own widget for N4-S5.
- **Files:** `widgets/add_to_program_sheet.dart`, a new list widget beside it, `program_status_chip.dart` (reuse), ARBs ×6, `docs/user/collection.md`, `docs/user/programs.md`, `changelog.d/`.
- **Size:** M (~350). **Model:** Sonnet.
- **Depends on:** N3-A1 (same file).
- **Guard tests:** the note's §6 rows for grouping, auto-expand, folding and venue match, and 360×640 with a keyboard inset; plus "7 programs: no search field; 9: a search field" (mutation: always or never shown).
- **Docs:** `collection.md:306`, `programs.md` (adding to a Performed program does not mark it performed).
- **Privacy:** none; the query and the expanded state are session-only.

---

## N4: bulk selection (FIND-8)

### N4-S1 `claude/collection-select-all`

- **Scope:** Select all over current results only (N4-2 = a); keep hidden selections and show "14 selected (9 not shown)" with *Deselect those not shown* (N4-1 = b); prune ids that no longer exist; end selection when online search turns on; the `CollectionSelection` class; the Select all icon where it fits (N4-6 = a).
- **Files:** `search/collection_selection.dart` (new), `dance_list_screen.dart`, ARBs ×6, `changelog.d/`.
- **Size:** M (~300). **Model:** Sonnet.
- **Depends on:** B14 → B15 (same file).
- **Guard tests:** a search that hides a selected row keeps it and counts it "not shown" (mutation: count against `_results` only, or prune on search); Select all is disabled while a search is pending (mutation: enabled); a synced-away dance leaves the count (mutation: no prune); online mode ends selection (mutation: selection kept).
- **Docs:** `collection.md:388-410`, `ux.md:58-60`. Measure a 5,000-dance Select all then Add tags on the lowest-end target and quote it after the final rebase (the note's risk).
- **Privacy:** none; selection is widget state.

### N4-S2 `claude/selection-keeps-groups`

- **Scope:** grouping stays on while selecting; a tri-state checkbox on each section header with its own semantics node (N4-3 = a).
- **Files:** `dance_list_screen.dart`, ARBs ×6, `changelog.d/`.
- **Size:** S–M (~200). **Model:** Sonnet.
- **Depends on:** N4-S1.
- **Guard tests:** entering selection keeps the sections (mutation: `_selectionMode ? null :` restored); the header checkbox selects only that section's rows in `_results` (mutation: it also clears hidden selections); a screen reader reaches the checkbox (mutation: `ExcludeSemantics` kept over it).
- **Docs:** `collection.md:388-410`.
- **Privacy:** none.

### N4-S3 `claude/batch-delete`

- **Scope:** `softDeleteMany` and `restoreMany` over the single-dance `softDelete` and `restore`, each in one transaction; Delete last in the ⋮ menu, in the error colour; confirmation only through *Confirm before delete* (N4-4 = a), with a plural body; "Deleted 12 dances" with Undo; the failure path.
- **Files:** `dance_repository.dart`, `dance_list_screen.dart`, `utils/confirm_delete.dart`, ARBs ×6, `changelog.d/`.
- **Size:** M (~350). **Model:** Opus (transactions, sync tombstones, shares the restore path with B9).
- **Depends on:** N4-S1; B9 (restore revives references, so `restoreMany` must reuse B9's `restore`). Check §6.8 tombstone hold-back before shipping (the note's open point).
- **Guard tests:** a failure on the 7th of 12 leaves all 12 live (mutation: per-dance transactions); bulk Undo revives a dance whose level B8 let be deleted (mutation: a second SQL restore path that skips B9's revival); with the setting off no dialog shows, and with it on one dialog names the count (mutation: always confirm, option b).
- **Docs:** `collection.md:377-382`, `:388-410`. Measure a 5,000-dance delete and its sync pass.
- **Privacy:** none.

### N4-S4 `claude/batch-status`

- **Scope:** `setStatusForMany` beside `setLevelForMany`, through `_updateMany`; a status dialog; the grouped ⋮ menu (Details: Set rating, Status; Other: Add tunes, Clear tunes, Edit custom field, Add source; Programs: Add to program; Delete). **No mixer or mixed level** (N4-5's note). Renamed from the note's `feat/batch-details`.
- **Files:** `dance_repository.dart`, a batch status dialog, `dance_list_screen.dart` (`_BatchMoreAction`, the bar), ARBs ×6, `changelog.d/`.
- **Size:** M (~220). **Model:** Sonnet. *My call:* it reuses `_updateMany`'s existing transaction and the level handler's Undo, writing no new transaction. Rejected: Opus by a literal "transactions" reading.
- **Depends on:** N4-S1. Menu slots for Add source, Add to program and Delete are added by their own branches; S4 sets the group order they slot into.
- **Guard tests:** only changed dances are stamped and Undo restores each prior status (mutation: stamp every dance); "no changes" when all already match (mutation: snackbar with 0); the menu has no Mixer or Mixed level entry (mutation: the note's original three-field branch).
- **Docs:** `collection.md:388-410`.
- **Privacy:** none; `dances.status` is classified.

### N4-S5 `claude/batch-add-to-program`

- **Scope:** Add to program for a list of dances, in list order, through N3-A2's list widget; the multi-dance marker and the ask-first question (ambiguity 5, an accepted reading).
- **Files:** `widgets/add_to_program_sheet.dart`, N3's list widget, `dance_list_screen.dart`, a core helper for a multi-slot append and its Undo, ARBs ×6, `changelog.d/`.
- **Size:** M (~350). **Model:** Opus. *My call:* it appends many slots to a program and restores them on Undo through F11's compare-and-replace, a new transactional write; the note said Sonnet. Rejected: Sonnet.
- **Depends on:** N4-S4 (menu), N3-A2 (list widget), F11.
- **Guard tests:** slots land in on-screen order (mutation: tap order); Undo restores the program's prior slot list exactly, and refuses when the program changed since (mutation: blind overwrite); when 4 of 12 are already in the program the question names 4 and **Skip those 4** adds 8 (mutation: no question, or per-dance prompts).
- **Docs:** `collection.md:388-410`.
- **Privacy:** none.

### N4-S6 `claude/batch-add-source`

- **Scope:** Add source, add only: pick or create a `PublishedSource`, append a citation with no page or number to each selected dance that does not cite it; extract the editor's source picker.
- **Files:** `dance_editor_screen.dart` (`:801-840`), a new picker widget, `dance_repository.dart` (`addSourceForMany`), `dance_list_screen.dart`, ARBs ×6, `changelog.d/`.
- **Size:** M–L (~450). **Model:** Sonnet (it reuses `_updateMany`, as N4-S4).
- **Depends on:** N4-S4. Serialize with N2-T3 on `dance_editor_screen.dart`; either order, but the second rebases on the first.
- **Guard tests:** a dance already citing the source keeps its page and is not counted (mutation: replace); Undo restores each prior citation list (mutation: Undo removing every citation of that source); the editor's picker still works after extraction (mutation: none; it is a refactor guard, run before and after).
- **Docs:** `collection.md:388-410`.
- **Privacy:** none; `dance_sources.*` is classified, and a citation names a third-party work already covered by its entry.

---

## N5: selectable text on desktop (PLAT-17)

### N5-S1 `claude/selectable-detail-text`

- **Scope:** `SelectableContent`, gated to desktop in one place (N5-1 = a); the dance detail `ListView` wrapped; the tag row, figure beats column and import-gap badge in `SelectionContainer.disabled`; copies are what the screen shows (N5-3 = a); Perform untouched (N5-5 = a).
- **Files:** `widgets/selectable_content.dart` (new), `dance_detail_screen.dart`, `widgets/figure_table.dart`, tests, `changelog.d/`.
- **Size:** M (~250). **Model:** Sonnet.
- **Depends on:** nothing in flight. It is the one design branch with no blocker.
- **Guard tests:** a drag over a figure row copies text and note without beats (mutation: drop the beats `SelectionContainer.disabled`); a chip click still filters (mutation: chip row not disabled); a drag across a `WidgetSpan` link copies its text once and a click still opens the dance; a secondary tap on text shows the selection toolbar; on Android and iOS the child is returned unchanged (mutation: gate removed); a figure row's semantics label is unchanged (`ensureSemantics`). Record a manual NVDA or VoiceOver pass in the PR.
- **Docs:** `ux.md:62-72`, `accessibility.md:119` (Cmd/Ctrl-C and -A; the figure screen-reader limit), the user docs on a copy following the canonical toggle and differing from Copy dance on verbose text and capitals.
- **Privacy:** none.

### N5-S2 `claude/selectable-summary-text`

- **Scope:** the summary header block (title, detail rows, notes) is selectable; the set list is not (N5-2 = a).
- **Files:** `program_summary_screen.dart`, tests.
- **Size:** S (~100). **Model:** Sonnet.
- **Depends on:** N5-S1; F11; after B4 → B5 and B22 on the same file. So D4.
- **Guard tests:** a set-list row tap still opens the dance and its toggle still marks it (mutation: region wrapping the set list); header notes copy (mutation: region missing).
- **Docs:** `ux.md` (summary line), `changelog.d/`.
- **Privacy:** none.

### N5-S3 `claude/selectable-right-click-rule`

- **Scope:** one test file pinning N5-4 = (a): a secondary tap on detail text shows Copy and Select all; on a list row it opens the ⋮ menu.
- **Size:** S (~50). **Model:** Sonnet.
- **Depends on:** B29 and N5-S1. *My call:* fold it into B29 if B29 lands after N5-S1; otherwise a separate PR right after B29. N5-4 binds B29's design either way.
- **Guard tests:** both assertions, each shown to fail by removing B29's row handler and by wrapping a list in `SelectionArea`.
- **Docs:** none beyond B29's.
- **Privacy:** none.

---

## Privacy registry

No design branch adds a persisted field, column, settings key or data-entry surface, and none changes an existing classification. Checked per branch above. So none regenerates `data-classification.md`, and none joins the B-plan's serialisation queue for it (B30, B12, B19, B4, B7).

Three conditional cases, for the reviewer to watch:

- **N2-T1:** if the held-peer fix needs a new column or table, classify it in T1 (sync metadata, likely `deviceScoped`, subject `none`, with the reason in `note`).
- **N3-A1:** a "don't ask again" box would be a settings key. The plan does not build one.
- **N1-H3:** if the implementer moves card fields to a deny-list key (N1-8 chose not to), that is a new key, a migration and a §6.15 gate. Out of scope.

---

## Sequencing

### Hot files (merged with `decided-work-plan.md`'s table, state at `90fe5e8`)

"→" is landing order. Design branches are in **bold**. Landing rule 4 applies: at most one open PR per group.

| File or group | In flight | Landing order |
| --- | --- | --- |
| `program_editor_screen.dart` | F11 #2040 | F11 → **N3-A1** (few lines) → B4 → B5; B24; B29; **N1-H3** (three mounts) |
| `program_summary_screen.dart` | F11 | F11 → B4 → B5 → B22 → **N5-S2** |
| `perform_program_screen.dart`, `perform_adjust_sheet.dart` | F11 | B28 → B29; **N1-H3** (`perform_adjust_sheet.dart` only) |
| `add_to_program_sheet.dart` | F11 | F11 → **N3-A1** → **N3-A2** → **N4-S5** |
| `main.dart` | — | B21; B4; B29 |
| The six ARBs | — | every UI branch. Keys beside related keys. U5b-2 in a quiet window. |
| `privacy/*_registry.dart`, `data-classification.md` | B30 #2046 | B30, B12 (merged), B19, B4, B7. No design branch. |
| `program_repository.dart` | — | B9 → B3 → **N1-H1** → B4 → B5 → **N1-H3** |
| `dance_repository.dart`, `filter_compiler.dart` | B7 | B7 → B13 → **N1-H1**; then **N2-T1**, **N2-T4**, **N4-S3**, **N4-S4**, **N4-S6** one at a time |
| `calling_history_scope.dart`, `filter.dart`, `database_setup.dart` | — | **N1-H1** |
| `dance_list_screen.dart` | — | B14 → B15 → **N1-H2** → **N4-S1** → (**N4-S2**, **N4-S3**, **N4-S4**, merges serialized) → **N4-S5**, **N4-S6** |
| `collection_picker.dart`, `facet_panel.dart` | — | B14 → B15 → **N3-A1** (count source) → **N1-H2** → **N1-H3** |
| `dance_detail_screen.dart`, `figure_table.dart` | — | **N5-S1** |
| `dance_editor_screen.dart` | — | **N2-T3** and **N4-S6**, either order |
| `sync_storage.dart`, `sync_local_repository.dart`, `docs/design/sync-spec.md` | B7, B30 | B7 → B8 → **N2-T1**; B30 (§6.7) in any order, serialized |
| `custom_fields_screen.dart`, settings sub-lists, `appearance_section.dart` | — | B8 → B10 → **N2-T2** |
| `docs/design/ux.md` | D2 | B14, B15, B28, B29, UX6-2; **N3-A1**, **N4-S1**, **N5-S1**, **N5-S2**, one line each |
| `docs/user/collection.md` | — | many: B11 (merged), B14, B15; **N1-H2**, **N1-H3**, **N2-T2**, **N3-A1**, **N3-A2**, every **N4** branch. Each edits its own section. |
| `docs/user/settings.md` | D2 | many. Keep each edit to its own section; U4 last. |

### Waves

The cap is still **four implementation sessions at once, B-branches and design branches together**. W2 is starting now with nine branches, so the design branches below fill slots as they free; they never push the count past four.

1. **D1, start now** (in this order, as slots free):
   1. **N5-S1.** No dependencies and no hot file.
   2. **N1-H1.** B1 has merged. It can be built now and becomes ready for review after B13 and B3 land on its hot files.
   3. **N2-T1.** Start with the held-peer tests and the choice of fix; the rest waits for that result. Ready for review only after B7, B8 and B13 merge.
   4. **N2-T4**, as soon as B7 merges.
2. **D2, after B14 → B15 merge:**
   - **N4-S1**, then **N4-S2**, **N4-S4**, and **N4-S3** (also after B9);
   - **N1-H2** (after N1-H1);
   - **N2-T2** (after N2-T1 and B10).
3. **D3, after F11 (#2040) merges**, alongside W3:
   - **N3-A1** first in the `program_editor_screen.dart` group (its hunk is small), then B4 → B5 proceed; **N3-A2** after N3-A1;
   - **N2-T3** (after N2-T2), **N4-S6** (after N4-S4), serialized on `dance_editor_screen.dart`;
   - **N4-S5** (after N4-S4 and N3-A2).
4. **D4, after W3's B5, B22 and B29:** **N1-H3** (after B5, N1-H2 and B14), **N5-S2** (after B5 and B22), **N5-S3** (with or after B29).

**The first four I would start,** in order: N5-S1, N1-H1, N2-T1, N2-T4. Each starts the longest chain it heads (N1's three branches; N2's four), or is free (N5-S1, N2-T4). N4 cannot start before B15, and N3 not before F11.

### Landing rules

`decided-work-plan.md`'s six rules apply unchanged. Two additions for these branches:

7. **N2-T1 merges alone** (it moves `_rewriteLocalReferences`), and the next merge waits for `main`'s own CI.
8. **N1-H1 registers a SQL function on every connection.** Any branch that opens a new connection in a test helper or tool after H1 lands passes `applyCompendiumSqliteSetup`, or a `text:` venue search fails there with "no such function". The H1 PR body says so, for the sessions that rebase over it.

---

## Ambiguities the answers leave open

Each has the planner's recommended reading. **All eight are now the planner's reading, accepted by the maintainer 2026-10-30.** The maintainer chose "Accept all 8 (Recommended)" in a question dialog put by the orchestrating session, whose option read "Builders follow these readings, labelled as the planner's reading that you accepted." The orchestrating session relayed the answer (one hop). Builders follow these readings; they are not re-asked. The notes on `main` (PR #2049) carry the same label where a branch depends on one.

1. **N1-2's "an option for dances which haven't been called".** Today's **Not called**, with no scope, already selects exactly those dances. *Reading:* the **Within** control gets a "no window" choice labelled so that, with **Not called**, it reads "never called"; no new predicate. Alternative: a separate "Never called" chip, which would duplicate Not called. N1-H2 shows the wording in its PR.
2. **N1-2's "1mo".** *Reading:* one calendar month, counted like 3 and 6 months. Alternative: 4 weeks, which the option text had and the note replaced.
3. **N1-6 in Perform.** The option text names the cost. *Reading:* nothing compensates in Perform's live-swap sheet beyond the existing "in program ×N". Alternative: an in-program marker in Perform, which no answer asked for.
4. **N3-4's prompt.** The answer fixes *that* the sheet asks, not how. *Reading:* "'{dance}' is already in '{program}'. Add it again?", **Cancel** / **Add again** in D-1's order; Cancel keeps the sheet open; an alternate-only match asks too (N3-6); no "don't ask again". `ux.md` gets a named exception, because the option text calls this a break of its rule.
5. **N3-4 for a batch (N4-S5), and the multi-dance marker** (N3 §4.8 left it to N4, and no answer settles it). *Reading:* one question per program tapped, "4 of 12 dances are already in 'Friday dance'", with **Add all**, **Skip those 4** and **Cancel**; the marker reads "4 of 12 in this program". Alternative: a prompt per dance, which is twelve dialogs.
6. **N4-5 and the programs warning.** The note folded "should delete warn when selected dances appear in programs?" into question 5; the answer does not mention it. *Reading:* no warning in N4-S3, as the note recommended, because the single-row delete does not warn either.
7. **N2-6's list of details.** The decision text says "a colour, website, notes or email"; the option it picks, in the note, also counts an author's location and deceased mark and a source's author, year and URL. *Reading:* the note's full list. Alternative: the short list, which would erase a source whose URL the user typed.
8. **N4-5's "All six together".** *Reading:* the four remaining actions are built in the same wave, as separate branches (N4-S3 … N4-S6), not one PR. One PR would break landing rule 4 on `dance_list_screen.dart` and mix an Opus delete with Sonnet dialogs.

R2-tag-tap's AND/OR toggle is B15's, not a design branch's. It matters here only as a hot-file neighbour: if B15 puts the toggle in `FacetPanel`'s Tags section, N1-H2 rebases on it, and if B15 persists the mode, B15 classifies that key.

---

## Check list: every decision, placed once

| Decision | Branch | | Decision | Branch |
| --- | --- | --- | --- | --- |
| N1-1 | N1-H1 | | N3-1 | N3-A2 |
| N1-2 (+ note) | N1-H2 | | N3-2 | N3-A2 |
| N1-3 | N1-H1, N1-H3 | | N3-3 | N3-A2 |
| N1-4 | N1-H2, N1-H3 | | N3-4 | N3-A1; N4-S5 for a batch |
| N1-5 | N1-H3 | | N3-5 | N3-A1 |
| N1-6 | N1-H1, N1-H3 | | N3-6 | N3-A1 |
| N1-7 | N1-H3 | | N4-1 | N4-S1 |
| N1-8 | N1-H3 | | N4-2 | N4-S1 |
| N1-9 | N1-H1 | | N4-3 | N4-S2 |
| N2-1 | N2-T1 | | N4-4 | N4-S3 |
| N2-2 | N2-T3 | | N4-5 (+ note) | N4-S3, N4-S4, N4-S5, N4-S6 |
| N2-3 | N2-T2 | | N4-6 | N4-S1, N4-S4 |
| N2-4 | N2-T3 | | N5-1, N5-3, N5-5 | N5-S1 |
| N2-5 | N2-T2 | | N5-2 | N5-S2 |
| N2-6 | N2-T4 | | N5-4 | N5-S3, B29 |
| N2-7 | N2-T1 | | | |
