# Follow-ups triage, 2026-10-31

Triage of `followups-log.md` against `origin/main` at `e0d6ce9d` (#2097). Read-only: no app code changed.

**How verified.** Code and docs were read at that commit; `git log` and `git log -S` were used for "done" claims. I ran no builds or tests. Where a line says *by absence*, I found no code that does the thing, which is weaker than a failing test. Several older items were checked by subagents reading code, and I spot-checked B26, B9, B23, N4-S4 and B29 myself. The `main` fetch is shallow (50 commits), so a fix older than 2026-10-28 would not show in `git log`; every "done" cites a commit inside the window.

**Authority.** `maintainer-decisions-2026-10-29.md` and `-30.md` were read for the decisions cited. Where I decided something myself, the row says so.

**Out of scope.** U5a (`claude/copy-case-and-spelling`) owns English strings and user-guide spelling and case. Nothing below edits those. Two rows touch ARBs for non-spelling reasons and are flagged.

Size: S ≲ 60 changed lines, M ≲ 200, L larger.

---

## Part 1: every item

### Reported most recently

| # | Item | Class | Evidence and files | Size |
| --- | --- | --- | --- | --- |
| 1 | B29: Ctrl/Cmd-A in the Collection | open-code | `design/bulk-selection.md:134` already specifies it (only while focus is in the list). `app/lib/src/widgets/app_shortcuts.dart` has no `keyA` binding and no select-all intent; `dance_list_screen.dart:1337-1354` has `_toggleSelectAll` but no key. Files: `app_shortcuts.dart`, `dance_list_screen.dart`. | S |
| 2 | B29: import review screen has no back guard | open-code | `import_review_screen.dart:2548` `PopScope(canPop: _phase != _Phase.committing)` blocks only mid-commit. Leaving during review discards the queue silently. Reuse `widgets/confirm_discard_changes.dart`. | S |
| 3 | B29 / PLAT-16: macOS system menu titles not localized | human-check | `app_menu_bar.dart` header comment: About, Services, Hide, Quit, Minimize and Zoom are titled by macOS and the engine, not the app language. Nothing to fix in app code unless a Mac shows otherwise. See H-4. | n/a |
| 4 | B28: single-dance Perform scroll keys | open-code | `perform_dance_screen.dart:392` wraps only `buildPerformFullScreenShortcuts` (F, F11, Esc). `perform_program_screen.dart:1358-1384` has the arrow/Page keys. PLAT-10 (scroll first) was decided for the program view; the single-dance view has nothing to advance to, so scroll-only is the natural reading. My call, not the maintainer's. Files: `perform_dance_screen.dart`, `perform_full_screen.dart`. | S |
| 5 | U4: design docs say "custom figure" for unparsed text | open-docs | Still present: `ux.md:120,137`; `dialect.md:249,263,333,369,522,551`; `figure-taxonomy.md:309,370,685,1341`; `imports.md:43,412,976,1368,1459,1558,2197`. "Custom Figures" the setting name (capitalised) is correct and stays. Only the unparsed-text sense changes. Judge each instance, per `AGENTS.md`. | M |
| 6 | D2: `collection.md` juxtaposes "exactly as typed" with "matched by meaning" | open-docs | `docs/user/collection.md:166-171` still reads as one sentence. Split into two statements. Not spelling or case. | S |
| 7 | N4-S4: level, rating, tunes, custom-field handlers read priors one `getById` per dance | open-code | `dance_list_screen.dart` lines 1563, 1753, 1893, 1976, 2062 loop `getById`; `setStatusForMany` at 1826 already uses `getByIds`. Add the same batched read to the other five handlers. Perf motivation: N4-S1 saw ~21 s for 5,000. Files: `dance_list_screen.dart`, `dance_repository.dart` (`getByIds`). | M |
| 8 | N2-T1: stale step-1 "renamed onto a name this device already uses" rows are never cleared | open-code | *By absence.* Rows are created at `sync_storage.dart:3720,3958` and resolved only by the user (`:2318` `_resolveNaturalKeyRenameCollision`). `sync_conflict_review_test.dart` covers `refreshConflictReviews` for conflicts only. Write the failing test first. Files: `sync_storage.dart`, `sync_review.dart`. Opus: sync. | M |
| 9 | B9: Recently deleted snackbar when a peer blanks an item mid-list | open-code | Split. *Permanent delete*: done in #2053 (`PermanentDeletion.none` shows nothing; `recently_deleted_screen.dart:~235`). *Restore*: `_restore` (`:~190`) always shows `restoredMessage`; I did not check whether `config.restore` can report that nothing was restored. Files: `recently_deleted_screen.dart` and its config. | S |
| 10 | B9: a Caller's Companion re-import keeps a dead venue link | open-code | `callers_companion_usr_import.dart:464` skips venue resolution when `prior.venueId != null`; `:1606` carries `priorVenueId ?? src.venueId` forward unconditionally. Caveat: #2076 left a dead `venueId` on restore on purpose, because a peer's program can arrive before its venue. So test for "no venue row, live or tombstoned" before relinking. Files: `callers_companion_usr_import.dart`. | S |
| 11 | Flake: "coalescing window reduces re-reads" | open-code | `app/test/search/dance_editor_reference_data_watch_test.dart:172-193` compares two real-time bursts with a 200 ms wall-clock wait (`:219`). Failed once with `windowed=2 unwindowed=2`. Fix with a fake clock or a looser, deterministic assertion; do not weaken the "can fail" property. | S |

### Older notes

| # | Item | Class | Evidence and files | Size |
| --- | --- | --- | --- | --- |
| 12 | B23: compound editor, shorthand editor and Settings default figures should settle the Move box on Save | open-code | `PendingMoveTextController` is used only by `dance_editor_controller.dart`, `figure_list_editor.dart`, `move_autocomplete.dart`. `compound_editor_screen.dart:1297` and `defaults_section.dart:2347,2393,2442` embed `FigureListEditor` without calling `settle()` on Save. The shorthand editor was not located; check when building. | S |
| 13 | B23: `diagnostic_labels_test` "every mapped code is non-generic" can't fail in debug | open-code | Tests at `app/test/data/diagnostic_labels_test.dart:40,161` unchanged since #2052. I did not re-derive why they cannot fail; the log says "pre-existing". Prove with a mutation (`AGENTS.md`). | S |
| 14 | B26: a failed manual re-check clears a previously found update | open-code | `update_controller.dart:~930` sets `_available = result` where `result` is `checked?.update`, and `checked` is null on `UpdateCheckFailed`. A failure therefore nulls it. Keep `_available` on failure. | S |
| 15 | U7: alternate slot title is ~77 dp at 360 dp | needs-maintainer | Design call. See Q-5. | n/a |
| 16 | U9: 8 machine-translated keys need fluent review | human-check | See H-3. | n/a |
| 17 | G1 / U9: German "Takte" sweep | done | f818aa0d (#2058), "German calls a beat Schlag, not Takt". | n/a |
| 18 | G1: Danish has the same bar/beat slip ("takt/takter", 3 strings) | human-check | Still present, e.g. `app_da.arb:2643,2647,2711`. Which Danish word replaces "takt" needs a native speaker. See H-2. | S after answer |
| 19 | B1: undated, unperformed slots dated by `updated_at` | needs-maintainer | Partly done: the recency window excludes them (`calling_history_scope.dart:55-71`, #2059). The history order and Last-called sort still use `program.updated_at` (`calling_history_scope.dart:48-52`, `program_repository.dart:1435`, `dance_repository.dart:3766`) and the code comments call that deliberate under GIG-2. See Q-2. | S |
| 20 | F10 (a): Perform jump-sheet numbering | open-code | `perform_program_screen.dart:830` numbers every row `index + 1`, so breaks get numbers. GIG-10 rule: dances only, using `Program.danceNumbersForSlots` (core `model/program.dart:118`). | S |
| 21 | F10 (b): author of a trashed dance with a trashed author missing from exports | open-code | `program_summary_screen.dart:861` builds `choreographerFor` from `choreographersById`, which excludes trashed authors. `deletedDances.authorNames` is passed to Perform only. `program_export_menu.dart:166` `_authorNamesFor` returns nothing for them. | S-M |
| 22 | F10 (c): LIFE-8 Restore button on a trashed-dance slot | open-code | `reports/LIFE.md:133` asks for it. No restore action in the program editor, summary, slot-list editor or Perform. Only the title and "deleted" marking exist (`resolveDeletedSlotDances`). | M |
| 23 | U2 (a): `_ParameterizedColumnDialog` stray dismissal | open-code | `settings/matrix_column_editor.dart:704`, shown at `:202,316` with the default barrier and no `PopScope`. The log never says what "stray" meant; a tap outside discards edits is my reading, unconfirmed. | S |
| 24 | U2 (b): dance editor `_save` does not scroll to first invalid field | open-code | `dance_editor_screen.dart:446-453`: its own comment says nothing scrolls; no `ensureVisible`. | S-M |
| 25 | U6: advanced-query leaf section dropdown and online result count overflow at 360 dp / 2x | open-code | `advanced_query_builder.dart:1043-1075` `_SectionDropdown` is a bare `DropdownButton` (no `isExpanded`) in a `Wrap`. The result count at `dance_list_screen.dart:3070` is already a `Wrap` and may be fixed. Judged from layout code only; add a 360 dp / 2x widget test first. | S-M |
| 26 | U11: radii and dropdowns | open-code | `app/lib` has 25 `BorderRadius.circular(<literal>)`: 9 on-scale, 16 off-scale (counts differ from the log's 12 / 17 by grep method). About 47 raw dropdown widgets remain across ~22 files (`defaults_section.dart` 5, `advanced_query_builder.dart` 5, `editor_fields.dart` 4). Shared: `EnumDropdown`, `LevelDropdown`, `SettingsDropdownRow`, tokens in `theme/app_shapes.dart`. Do radii only; dropdown conversion is its own change. | M (radii) / L (dropdowns) |
| 27 | U12: unboxed notice rows (sync pairing, device sync tiles) | open-code | `widgets/notice_card.dart` has no use in `settings/sync_pairing_screen.dart` (own `_Disclosure` rows, `:434-491`) or `settings/device_sync_section.dart` (bare `ListTile`s). | S-M |
| 28 | U9: "Browse published collections" button on the import card | open-code | `_buildImportCardSliver` (`dance_list_screen.dart:2873`) offers only `_startActions`. No such string in `app_en.arb`. Screen exists: `published_collection_catalog_screen.dart`. New ARB key in six files. | S |
| 29 | B20: needs a real-device Android check | human-check | See H-1. | n/a |
| 30 | B20: reword `importFileNotText` to "not a share file" for binary picks | open-code | `app_en.arb:10464` unchanged. All six ARBs. Not a spelling or case change, but it edits English strings, so land it after U5a. | S |
| 31 | B16 (a): "Imported X" wording after "Same dance" | open-code | `OnlineImportKind` has only `created` (`online_search.dart:168`); `onlineImportMessage` (`online_search_labels.dart:36`) maps it to `Imported "{title}".` I did not trace the replace path end to end. | S |
| 32 | B16 (b): Caller's Box fallback in ContraDB program import declines identical dances | open-code | Decision INTAKE-3 (a): reuse an identical dance (#685). `program_import_online_resolver.dart:313-343` returns `_SourceDeclined()` for identical figures; the ContraDB-direct path links via `confidentIdenticalMatchId` (`contradb_program_import.dart:181`). | S |
| 33 | B16 (c): ContraDB confident match with differing figures imports a duplicate, not a variation (#686) | needs-maintainer | `contradb_program_import.dart:199` passes `DedupeResolution.duplicate()`; the Caller's Box path imports a variation. INTAKE-3 decided only the identical case. See Q-3. | S-M |
| 34 | B12 (a): tombstone adopted under a recreated custom field leaves a trashed dance's search entry stale | open-code (unconfirmed) | `custom_field_repository.dart:184,248`: the reindex fires only if `indexedBefore != _indexesValues(id)`; whether adoption triggers it is not settled by reading. Write the failing test first; if it passes, reclassify as not reproducible. | S |
| 35 | B12 (b): whole-number custom values may index as "3.0" | open-code | `dance_repository.dart:1592` calls `value.value.toString()` on a `num`. | S |
| 36 | B30: withdrawn-key drop, spec amendment, queued conflict rows | done | #2046, #2077 (09ec281a). `sync-spec.md:3792-3846` has the dated amendments; the old-build false notice is in `settings.md:1081`. | n/a |
| 37 | B30: old-build device detaching after all peers upgraded skips cleanup | won't-fix | Orchestrator log: "accept". Self-limiting once every device upgrades. | n/a |
| 38 | B11: FIND-4 Advanced / By-phrase type-aheads deferred | needs-maintainer | See Q-4. | n/a |
| 39 | B6: stamp-bump guard shown to fail | done | Log 2026-10-30 14:47: test goes red under both mutations. | n/a |
| 40 | B6: editor open keeps old name after a rename elsewhere | open-code | `dialect_editor_screen.dart:357,390,448` saves under `widget.initial.name`; `dialect_section.dart:53` then `controller.upsert(edited)` matches by name (`dialect_library_controller.dart:136-152`) and adds a second dialect. | M |
| 41 | B6: deleted-dialect name reuse | open-code | Same path: nothing checks the dialect still exists, so Save revives a deleted one or re-attaches a reused name to programs carrying the old name. Fix with item 40. | M |
| 42 | B31: other `DateFormat.yMMMd(appLocale)` sites follow app language | open-code | Five sites bypass `resolveDateLocale` (`regional_formats.dart:255`): `sync_conflict_details.dart:118,1063`, `device_sync_section.dart:790`, `dance_editor_screen.dart:650`, `migration_error_labels.dart:99`. | S |
| 43 | B31: PLAT-13 glossary not built | done | Decision PLAT-13 was a one-line notice only; the string `userGuideEnglishOnly` exists (`app_en.arb:12572`). I did not check where it is shown. | n/a |
| 44 | B31: en_DK region fallback | done | c434ef3a (#2050). | n/a |
| 45 | B27: store builds, end-of-support, store links | done | d3a5c411 (#2045). | n/a |
| 46 | B7: slot shows a dash when a peer adds a dance before receiving the blank | open-code | By absence (design says purges never rewrite citers, `storage.md:958-978`). Needs a decision on what the slot should show. See Q-6. Opus: sync. | M |
| 47 | B7: `review_queue` blobs can hold blanked content | open-code | By absence: no code blanks `review_queue` blobs. Opus: sync. | M |
| 48 | B7: older builds can restore a blank "—" record | won't-fix | Documented as a known limit: `sync-spec.md:395-398`, `changelog.d/life2-permanent-delete-synced.json`. Cannot be fixed in builds already shipped. | n/a |
| 49 | B7: citations of blank tombstones | open-code (unconfirmed) | Only partly covered by citer rewriting on the user's own Permanently delete. Fold into item 46. | M |
| 50 | B7 retention follow-up and startup sweep | done | 21cee9aa (#2061). | n/a |
| 51 | F11 (a): Save overwrites a program's details changed elsewhere while the builder holds unsaved detail edits | open-code | `program_editor_screen.dart:~2299-2313`: on a remote change while dirty, only slots take it, but `_existing = stored` follows, so the next Save writes stale details. | M |
| 52 | F11 (b): false "changed elsewhere" notice after a bulk-mark Undo | not reproducible | I read `_undoMarkAllPerformed` and `_pendingBulkUndo*` (`program_editor_screen.dart:~2660-2810`) and found no handling, but did not trace it. Needs a repro test before anyone changes code. | n/a |
| 53 | F11 (c): the first draft by key is offered, not the most recent | open-code | `program_editor_screen.dart:1472-1486` `_maybeStageDraft` sorts keys and takes the first. | S-M |
| 54 | Windows CompanyName blocker | done | c911542e (#2057). | n/a |
| 55 | N5-S1: manual NVDA / VoiceOver / highlight-contrast check | human-check | See H-5. | n/a |
| 56 | B8: sync-borne custom-field type mismatches | open-code | `_reconcileCustomFieldTypeMismatch` (`sync_storage.dart:5070`) handles the definition; #2062 trims values only on local writes. Values arriving through sync are not trimmed. Opus: sync. | M |
| 57 | B8: stale comment in `existence.dart` | open-docs | `adoptTombstonedNaturalKey` doc says only `tags` can reach this state; false after #2062. Also a stale "Until then it surfaced as the raw ..." (#1348 landed). Code comment only. | S |
| 58 | B8 / B9: "a trashed dance restored from a backup or share comes back with no level" must be noted | open-docs (unverified) | I found no user-doc text about it (`docs/user` grep). Confirm whether it is true of current behaviour before writing. | S |
| 59 | B9: restore leaves a `venueId` that names no venue at all | done (by design) | d8c65337 (#2076); comment in `program_repository.dart` says it is left alone on purpose, with Duplicate dropping it. | n/a |
| 60 | B18: re-import follow-ups (strings, revived share metadata, `.USR` links, unresolved-endpoint warnings, per-row title and credit) | done | 979b4611 (#2072). I did not read the maintainer's answer to the original "needs maintainer" item; #2072's title says per-row title and credit. | n/a |
| 61 | B25: no startup export button | won't-fix | Follows the FAIL-10 decision (log: "follows the FAIL-10 decision"). | n/a |
| 62 | B25: `SyncFailure` allow-list entry is inert | open-code | `crash_log_record.dart:141-146` lists `SyncFailure`, a plain value class never thrown (`sync_failure.dart:108`); thrown type is `SyncWorkerFailure extends StateError`. `scrub_allow_list_test.dart:24` pins only the name. Privacy-adjacent: classify in the same change. | S |
| 63 | B21: real Windows/Linux desktop check unconfirmed | human-check | See H-6. | n/a |
| 64 | B21: Windows parent-directory symlink walk | open-code | `desktop_open_path.dart:73-86` checks only the last component; its doc says a symlinked parent is followed. | M |
| 65 | B10: missing dialect/theme delete widget tests | open-code | Snackbars at `dialect_section.dart:148`, `appearance_section.dart:489`; only controller tests exist. | S |
| 66 | B10: `commonDeletedSnack` ARB description says "dance" | open-code | `app_en.arb:5063`. Metadata only; six ARBs. | S |
| 67 | N2-T4: changelog says managers ship "in a later release" | open-docs | `changelog.d/n2-t4-purge-spares-details.json:6`. Managers landed in #2082 and #2084. | S |
| 68 | B19: replacing from a share clears the receiver's rating | done | 51aba57a (#2078). | n/a |
| 69 | B3 review N1: venue-link offer races an open program editor | done | #2079 merged with the orchestrator's fix (c). I did not re-read the diff. | n/a |
| 70 | B9 / sync-spec §6.8: revival under a held peer tombstone stays advertised as a tombstone | needs-maintainer | See Q-1. | n/a |
| 71 | N2-T1: "the note's two small choices to confirm in T2" | not reproducible | The log does not say which two choices. T2 landed (#2082). Ask the T1 author, or drop. | n/a |
| 72 | N2-T1: documented limits (three-way merges, citations after alias retirement) | done | Recorded as limits in `design/tags-and-people.md`; nothing to build. | n/a |
| 73 | N3-A2: pinned New row can scroll away at 200% text with keyboard up | needs-maintainer | `add_to_program_sheet.dart:82-118` as built. See Q-7. | n/a |
| 74 | B28: Windows maximized window may keep its title bar; immersive mode on Android/iOS | human-check | See H-7. | n/a |
| 75 | B22 own calls: user colour honoured under high contrast; colour-coding off shows no accent | needs-maintainer | Fix-session decisions, not the maintainer's. See Q-8. | n/a |
| 76 | B4 own calls: status set even when nothing left to mark; un-marking never changes status | needs-maintainer | Behaviour confirmed at `program_editor_screen.dart:~2660-2700`, and GIG-12 plan text matches. Ratify or change. See Q-8. | n/a |
| 77 | B5: should the Undo snackbar repeat N? | needs-maintainer | Open question in the log. See Q-9. | n/a |
| 78 | B29: one-minute Mac check | human-check | See H-4. | n/a |
| 79 | B29 own calls: Esc via `DismissIntent`; app commands leave pages through each page's back guard | needs-maintainer | Fix-session decisions. Fold into Q-8. | n/a |
| 80 | U4: native review of da/de/fr/ja/nl for 38 refreshed keys per locale | human-check | See H-3. | n/a |
| 81 | U5a hand-off: B29 menu strings are Title Case on purpose | open-docs | Not mine to edit. The U5a session needs a menu exception to its sentence-case rule. Message it; no change here. | n/a |

### Counts

| Class | Items |
| --- | --- |
| done | 17, 36, 39, 43, 44, 45, 50, 54, 59, 60, 68, 69, 72 = **13** |
| open-code | 1, 2, 4, 7, 8, 9, 10, 11, 12, 13, 14, 20, 21, 22, 23, 24, 25, 26, 27, 28, 30, 31, 32, 34, 35, 40, 41, 42, 46, 47, 49, 51, 53, 56, 62, 64, 65, 66 = **38** |
| open-docs | 5, 6, 57, 58, 67, 81 = **6** |
| needs-maintainer | 15, 19, 33, 38, 70, 73, 75, 76, 77, 79 = **10** |
| human-check | 3, 16, 18, 29, 55, 63, 74, 78, 80 = **9** |
| won't-fix / not reproducible | 37, 48, 52, 61, 71 = **5** |

Total 81 rows (one per distinct item; a few log lines were split into sub-items).

---

## Part 2: proposed bundles

Five bundles. Merge order is chosen against the "Hot files" table in `decided-work-plan.md` and its Landing rules: one merge at a time, merge `main` in first, a PR that renames or removes a symbol, ARB key or settings key merges alone, and at most one open PR per hot-file group. U5a is in flight on the ARBs, so ARB-touching bundles come after it lands, or touch the six ARBs only for new keys placed beside related keys.

### 1. `claude/followups-collection-keys` (Sonnet)

- **Scope:** items 1 (Ctrl/Cmd-A), 2 (import review back guard), 4 (single-dance Perform scroll keys), 7 (batched priors), 28 (Browse published collections), 31 (post-"Same dance" wording).
- **Hot files:** `dance_list_screen.dart` (all of 1, 7, 28), `app_shortcuts.dart`, `import_review_screen.dart`, `perform_dance_screen.dart`, six ARBs (items 28, 31 add keys).
- **Size:** ~350 lines. If it runs over, move item 28 and 31 to bundle 5.
- **Order:** first. It is the one bundle that edits `dance_list_screen.dart`, so nothing else may open a PR against it.
- **Docs in the same PR:** `ux.md` shortcut table, `docs/user` keyboard page, a `changelog.d` fragment.

### 2. `claude/followups-editors-and-chrome` (Sonnet)

- **Scope:** items 12 (Move box settle), 24 (scroll to first invalid field), 23 (`_ParameterizedColumnDialog`), 25 (U6 overflow), 27 (U12 notice rows), 26 radii half of U11 only, 42 (date formats), 21 (trashed author in exports), 20 (jump-sheet numbering), 53 (draft by recency).
- **Hot files:** `defaults_section.dart`, `compound_editor_screen.dart`, `dance_editor_screen.dart`, `program_summary_screen.dart`, `perform_program_screen.dart`, `advanced_query_builder.dart`, `theme/app_shapes.dart`.
- **Size:** about 450 lines, the largest. Split off items 20, 21, 53 (program screens) into their own branch if the diff passes 500.
- **Order:** second, after bundle 1 merges. Items 20, 21, 53 sit in the `program_editor_screen` / `program_summary_screen` / `perform_program_screen` group, which no other open PR touches now.
- **Not included:** dropdown conversion (item 26, L); it needs its own plan and touches 22 files.

### 3. `claude/followups-sync-correctness` (Opus; sync, transactions, concurrency)

- **Scope:** items 8 (stale step-1 rename rows), 46 and 49 (dash slot, blank-tombstone citers), 47 (`review_queue` blobs), 56 (sync-borne field type mismatches), 51 (F11 detail overwrite), 62 (inert allow-list entry), 57 (stale `existence.dart` comment).
- **Hot files:** `sync_storage.dart`, `sync_review.dart`, `existence.dart`, `program_editor_screen.dart` (item 51 only), `privacy/` registry if item 62 changes it (regenerate `data-classification.md`; do not hand-resolve).
- **Size:** about 450 lines. Each item needs a failing test first (`verification.md`). Items 46 and 47 are blocked on Q-6 and may drop out.
- **Order:** third. Item 51 touches the program editor; run it after bundle 2's program-screen items merge, or drop item 51 to bundle 4.
- **Rule 3:** merges alone if it renames any symbol.

### 4. `claude/followups-import-and-restore` (Sonnet)

- **Scope:** items 10 (CC re-import dead venue), 32 (Caller's Box identical dances link), 35 (whole-number index), 34 (stale search entry; test first, drop if it passes), 40 and 41 (dialect editor stale name and deleted-name reuse), 9 (restore snackbar), 22 (LIFE-8 Restore button).
- **Hot files:** `callers_companion_usr_import.dart`, `program_import_online_resolver.dart`, `dance_repository.dart`, `dialect_editor_screen.dart`, `dialect_library_controller.dart`, `recently_deleted_screen.dart`, program editor and summary (item 22).
- **Size:** ~400 lines. If item 22 grows past M, move it alone.
- **Order:** fourth. Item 22 shares program screens with bundle 2, so it merges after bundle 2.

### 5. `claude/followups-docs-and-tests` (Sonnet)

- **Scope:** items 5 (U4 design docs), 6 (D2), 58 (if true), 67 (N2-T4 changelog), 11 (flaky test), 13 (diagnostic labels test, with a mutation proof), 14 (B26), 65 and 66 (B10 tests and ARB description), 64 (Windows symlink walk), 35 if bundle 4 runs late.
- **Hot files:** `docs/design/ux.md`, `dialect.md`, `figure-taxonomy.md`, `imports.md` (long, edit by instance), `docs/user/collection.md`, `update_controller.dart`, `desktop_open_path.dart`, ARBs (item 66 only).
- **Size:** docs-heavy; code is ~200 lines. If item 5 alone passes 150 doc lines, give it its own branch.
- **Order:** last, or anytime for the docs-only parts since they need no full preflight. Item 66 and item 30 (B20 reword) are ARB edits: run after U5a lands.

**Merge order:** 1 → 2 → 3 → 4 → 5, one at a time, `main` merged into each head before CI. Bundles 3 and 5 can run in parallel with 1 and 2 if the four-session cap holds, since they share no hot file until their program-screen items.

Item 30 (B20 reword) sits outside the five bundles; put it with bundle 5 once U5a is merged. Item 81 is a message to the U5a session, not a branch.

---

## Part 3: questions and checks, each standalone

### Maintainer questions

**Q-1 (§6.8, item 70).** A dance or program is revived on one device while a peer still holds its deletion record pending. Today the revived row stays advertised as a tombstone until the hold resolves. Should the revival propagate to the peer anyway, or keep waiting? Recommendation in the log: not stated. Blocks nothing today.

**Q-2 (B1, item 19).** The Calling history order and the Last-called sort currently date a program slot with no event date and no performed time by the program's `updated_at`. The recency filter (#2059) no longer does. Keep the order and sort as they are (the code calls this deliberate under GIG-2), or make them consistent so such slots sort as undated?

**Q-3 (B16, item 33; #686).** Importing a ContraDB program, when a confident match has differing figures, the app currently imports a duplicate dance. The Caller's Box path imports it as a variation of the match. INTAKE-3 only decided the identical case ("reuse an identical dance"). Should ContraDB differing-figures matches become variations, as in Caller's Box?

**Q-4 (B11, item 38; FIND-4).** You deferred type-aheads for Advanced search and By-phrase. Schedule them now (an M item; `filter_compiler.dart` is no longer contended), or leave them deferred?

**Q-5 (U7, item 15).** The alternate slot title is about 77 dp wide at a 360 dp screen. Accept as is, or shorten or reflow it? A design call; no code until you choose.

**Q-6 (B7, item 46).** When another device adds a dance to a program before it receives the blank for that dance, the slot shows a dash. What should it show: the dance's last known title, the word "Deleted dance", or the dash? This decides whether bundle 3 builds item 46.

**Q-7 (N3-A2, item 73).** At 200% text size with the keyboard up, the add-to-program sheet's pinned "New program" row can scroll away inside its 45% header cap, which departs from N3-5 ("always visible") in that case. Accept it, or drop the sheet title while the keyboard is up so the row stays visible?

**Q-8 (own calls by fix sessions, items 75, 76, 79).** These were decided by the building sessions, not by you; please ratify or change:
- B22: a user-chosen colour is honoured under high contrast; with colour-coding off there is no accent.
- B4: marking sets status even when nothing is left to mark; un-marking never changes status.
- B29: Esc is handled via a `DismissIntent` probe; app commands leave pages through each page's back guard.

**Q-9 (B5, item 77).** After deleting a program that warns "N dances lose calling history", should the Undo snackbar repeat that N?

### Human checks

**H-1 (B20).** On a real Android device, pick a `.ccshare` and a non-text file through the import picker; confirm the share opens and the binary file shows the error. Expected: no crash, correct error text.

**H-2 (G1 Danish).** A Danish speaker says what replaces "takt/takter" for "beat/beats" in `app_da.arb` (three strings, e.g. `settingsDefaultsUserFiguresSubtitle`). German now uses "Schlag". Answer with the word.

**H-3 (U4, U9).** Native review of the ~38 refreshed keys per locale in da/de/fr/ja/nl (listed in the #2097 PR body), and of the 8 machine-translated U9 keys.

**H-4 (B29, PLAT-16).** On a Mac: the menu bar shows Settings…, New Dance, Import Dances…, Close and no Edit menu; each item acts; then set the system language to Danish and see which titles stay English (About, Hide, Quit etc.). If only system items stay English, close PLAT-16 as a platform limit.

**H-5 (N5-S1).** NVDA and VoiceOver pass over the dance detail text: link rows, tunes, custom fields, citations, header lines, chips, warnings, A1 labels, history copy; plus highlight contrast.

**H-6 (B21).** On real Windows and Linux desktops, open a `.ccshare` from the file manager: starts the app, opens the file, no second window.

**H-7 (B28).** On Windows with a maximized window, enter Perform full screen; confirm the title bar hides (`window_manager 0.5.2` may keep it). On Android and iOS, confirm immersive mode hides system bars and restores on exit.
