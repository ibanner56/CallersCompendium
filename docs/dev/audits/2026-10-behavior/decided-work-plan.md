# Work plan for the maintainer's 2026-10-29 decisions

Planning only. No app code was changed, built or tested.

**Basis:**

- `maintainer-decisions-2026-10-29.md` is the source of truth. Where a maintainer note expands or changes the picked option, the note wins.
- `batch-plan.md`, `intake.md`, `reports/*.md` and `ux-followups-intake.md` give the background.
- Every item was re-checked against `origin/main` at `acacb05`, after #1977–#2017 merged. **Line numbers below are for that tree.**

**Format and conventions:**

- The format follows `batch-plan.md`. Size counts changed lines, tests included: S < 150, M 150–400, L 400+.
- **Model:** Sonnet for contained work; Opus for stateful or cross-cutting work.
- Every branch that adds UI text adds keys to all six ARBs (beside related keys, never at the end of the file) and a `changelog.d/<id>.json` fragment.
- "*My call*" marks a choice made by this planning session, with the alternative it rejected. It is not a maintainer decision.

## Summary

| Group | PRs | Items |
| --- | --- | --- |
| Fix branches for the behaviour and residual decisions | **31** (B1–B31) | 45 finding IDs, plus UX5-4a |
| UX copy branches | U4, U5 (U5 as 3 PRs) | UX3-2, UX3-5, UX3-6 |
| German "beats" sweep | G1 | ratify-german-beats |
| Design notes | **5** (N1–N5) | FIND-1, FIND-3, LIFE-5, FIND-8, FIND-17, PLAT-17 |
| Closed with no work | — | 6 dropped design questions, AUTH-13, all ratify items, D-7, D-8, D-12 |
| Waiting on D-11 | UX6-2 | unchanged; see the end |

**Waves** (details under "Sequencing"):

- **W1, start now:** B1, B2, B6, B7, B11, B12, B16, B17, B20, B23, B26, B30, B31, plus N1–N5.
  - B8 → B9 follow B7.
  - B13 follows B12.
  - B27 follows B26.
- **W2, after #2016 (U3), U9 and the D-1 branch merge:** B3, B10, B14 → B15, B18, B19, B21, B25, G1.
- **W3, after F10, F11 and U7 merge:** B4 → B5, B22, B24, B28 → B29.
- **W4, after D2:** U4, then U5a → U5b-1 → U5b-2.

**Concurrency:**

- At most **four** implementation sessions at a time.
- **One merge at a time**, each on a head that has merged the current `main` and is green on that exact commit. See "Landing rules".

### Already fixed, or partly fixed, on main

Nothing decided today is fully fixed on main. Six items are partly fixed. The branch below covers only the remainder.

| Item | Done by | What remains |
| --- | --- | --- |
| OUT-2 | #2002 (F6): received programs arrive as Draft, with the date and marks cleared (`compendium_archive_import.dart:164-176`) | Pay, dialect and dance rating still travel in share files (B19) |
| GIG-2 | #1984 (F7) shows a stamp near the event date as that date; #1998 (F5) moved Last-called to `COALESCE(performed_at, event_date, …)` | `performed_at` still wins for history order, `effectiveDate` and `last_called` (B1) |
| PLAT-12 | #1984: the System format includes the year | It still follows the app language, not the region (B31) |
| PLAT-8 | #1986 (F17): copyright strings | The menu bar (B29) |
| FIND-15 | #1991 (F18): `foldForTitleMatch` exists; only the command palette uses it | Sort keys don't use it (B13) |
| FAIL-10 | #1987 (F15): update and collection failures are logged with typed, prose-free messages | The scrub allow-list and the export from the startup screen (B25) |

**Now in flight, so not planned here:**

- **D-1 (UX2-2).** It started as its own session on `claude/fix-discard-dialog-buttons` after #2012 merged. The parent session reported this on 2026-10-29.
- **D-7, D-8 and D-12** are done: D-7 in #2015 (merged), D-8 and D-12 in #2013 (open).

### Decisions that conflict with another decision or with a design doc

These are flagged for the maintainer. Where a branch can go ahead regardless, its section says so.

1. **LIFE-2 note against sync-spec §3.2.** The note asks to clear the deletion record once every device has synced past the delete. `sync-spec.md` §3.2, under `published_records`, says "**No retirement rule, deliberately**": a wrongly retired marker "silently resurrects a deletion". The note cannot be done safely with what the app knows. See B7 for the reasons and for what can be done.

2. **trash-policy (b) against three docs.** "Trash doesn't protect" contradicts:
   - **ADR-005** (`:32-33`, `:53`);
   - `storage.md:646`;
   - the normative **sync-spec §6.8**: "For difficulty levels the citation count includes **tombstoned** dances".

   B8 must amend all three. The ADR gets an erratum, not a rewrite; the spec gets a dated amendment, as §6.6 has.

3. **GIG-12: the option against its own note.** The pick was (a), "keep separate, say so". The note asks for option 2: Mark all performed sets the status, controlled by a setting that is on by default. The note wins.
   - The helper text "status is separate" would be false with the setting on.
   - It is **already false in the other direction**: Status → Performed stamps every primary slot (#356 via #390, `program_repository.dart:548-565`).
   - B4's helper text therefore describes the coupling and follows the setting.

4. **The queued D2 docs PR would now document behaviour the maintainer chose to change.** Remove four of its bullets, and give each to the branch that changes the behaviour:

   | D2 bullet | Why it must go | New owner |
   | --- | --- | --- |
   | FIND-5 (`collection.md` "Type any words" as exact phrase) | FIND-5 = (b) splits words | B11 |
   | FIND-4 (scope `dialects.md:52-54` and `search.md` to role words) | FIND-4 = (a) adds move names | B11; it also narrows `search.md:545` (type-aheads are deferred) |
   | PLAT-3 (`faq.md:125`, `sharing.md:200`) | PLAT-3 = (a) registers the file type | B21 |
   | PLAT-7 (stop claiming a desktop keyboard map) | PLAT-7 = (b) builds one | B29 documents the map |

   The rest of D2 stands. *My call:* moving these lines changes an approved PR's scope, so the D2 session should confirm the change with the maintainer before it starts.

5. **PRES-1 against ADR-004.** ADR-004 (`:747`) says "settings included". B30 needs an ADR erratum, as D1 did for text scale.

6. **FAIL-3 against ADR-002 §5 and `releasing.md:866-882`.** Both say a failed check is silently "no update". The decision applies to the **manual** check only. The automatic check must stay silent, and both docs get a note saying so.

7. **OUT-2's note.** "These fields should still travel in sync and export" is ambiguous. In the user docs, "Share / export" *is* the share file (`sharing.md:343-352`), so a literal reading cancels the decision. B19 assumes "export" means **Backup**. **The maintainer should confirm before B19 starts.**

8. **FIND-14 against the Tags facet's rule.** Tags are "any" within the facet (`collection.md:166-170`, `search.md` Q7), so adding a tapped tag to the facet *widens* the results. **Question for the maintainer:** is that fine, or should a tapped tag narrow (AND)? B15 waits on it.

9. **PRES-12 against `settings.md:257`.** The guide says mixers "always get the mixer accent". Does a user's formation colour beat the mixer accent? *My call, pending confirmation:* no; the mixer accent stays, because it is a safety cue for the band.

10. **D-4 (c), "normalise all quotes", gives no direction.** It doesn't say curly or straight, or whether apostrophes count; there are 318 strings at stake. **U5b waits on the answer.**

11. **startup-dead-ends.** The maintainer's premise, that Check again would always fail, holds for two of the four screens but not the other two. See B25. The pick stands; whether to add Check again on those two screens is a new question.

---

## Fix branches

### Overview

| # | Branch | Items | Size | Model | Wave | Severity |
| --- | --- | --- | --- | --- | --- | --- |
| B1 | `fix/history-uses-event-date` | GIG-2 (residual) | M | Opus | W1 | M |
| B2 | `fix/matrix-break-separates` | GIG-8 | S | Sonnet | W1 | L |
| B3 | `feat/link-typed-venues` | GIG-7 | M | Sonnet | W2 | L |
| B4 | `feat/mark-all-sets-performed` | GIG-12 + setting | M–L | Opus | W3 | L |
| B5 | `fix/program-delete-warns-history` | LIFE-6 | M | Sonnet | W3 | L |
| B6 | `fix/dialect-rename-follows-programs` | PRES-11, LIFE-11 | S–M | Sonnet | W1 | L |
| B7 | `fix/permanent-delete-hides-and-blanks` | LIFE-2 (+ the note, scoped) | M | Opus | W1 | M |
| B8 | `fix/trash-does-not-protect` | LIFE-9, GIG-17 | M | Opus | W1 after B7 | L |
| B9 | `fix/restore-copes-with-missing-refs` | LIFE-4, restore half of LIFE-9 | M | Opus | W1 after B8 | L |
| B10 | `fix/settings-deletes-say-deleted` | UX5-4a | S–M | Sonnet | W2 | — |
| B11 | `fix/search-words-and-dialect-moves` | FIND-5, FIND-4 (both residual) | L | Opus | W1 | L/M |
| B12 | `fix/search-index-honours-searchable` | FIND-6, FIND-13 | M | Opus | W1 | M, L |
| B13 | `fix/sort-folds-accents` | FIND-15 (folds PLAT-15) | M | Sonnet | W1 after B12 | L |
| B14 | `feat/picker-parity` | FIND-7, PRES-15 | L | Opus | W2 | L, L |
| B15 | `fix/tag-chip-adds-filter` | FIND-14 | S | Sonnet | W2 after B14 | L |
| B16 | `fix/online-import-reuse-and-undo` | INTAKE-5, INTAKE-3 | M | Opus | W1 | M, M |
| B17 | `fix/share-file-custom-field-match` | INTAKE-2 | M | Opus | W1 | M |
| B18 | `fix/batch-reimport-choreography-only` | INTAKE-7 | M | Opus | W2 after B17 | M |
| B19 | `fix/share-files-omit-private-fields` | OUT-2 (residual) | S–M | Sonnet | W2 | M |
| B20 | `fix/android-ccshare-generic-type` | PLAT-4 | S | Sonnet | W1 | L |
| B21 | `feat/desktop-open-ccshare` | PLAT-3 (residual) | L | Opus | W2 | L |
| B22 | `fix/card-fields-and-set-list-colours` | OUT-6, PRES-12, PRES-10 | M | Sonnet | W3 | L ×3 |
| B23 | `fix/editor-move-blur-and-dropped-groups` | AUTH-1, AUTH-2 (both residual) | L | Opus | W1 | M, M |
| B24 | `fix/autosave-failures-visible` | FAIL-8 | S | Sonnet | W3 | L |
| B25 | `fix/startup-screens-and-diagnostics` | FAIL-11 (b), FAIL-10 (d) | M | Sonnet | W2 | M, M |
| B26 | `fix/update-check-says-why` | FAIL-3 (c) | M | Sonnet | W1 | M |
| B27 | `fix/updater-install-kind` | PLAT-5, PLAT-6 | M | Sonnet | W1 after B26 | L, L |
| B28 | `feat/perform-full-screen-and-scroll-keys` | PLAT-9, PLAT-10 | M | Opus | W3 | L, L |
| B29 | `feat/desktop-shortcuts-and-mac-menu` | PLAT-7, PLAT-8 (both residual) | L | Opus | W3 after B28 | M, L |
| B30 | `fix/per-device-screen-settings` | PRES-1 | M | Opus | W1 | L |
| B31 | `fix/locale-follow-through` | PLAT-12 (residual), PLAT-13 | S | Sonnet | W1 | M, L |

The severities are the intake's re-ratings where it gave one, and the report's own rating otherwise.

### Programs and calling history

#### B1 `fix/history-uses-event-date`: history shows the event date (GIG-2 = a)

- **Scope:**
  - Calling history uses the program's event date when there is one. The tap stamp becomes a "called" flag, and its time is used only for undated programs.
  - Flip to `COALESCE(event_date, performed_at, updated_at)` in four places:
    - history order, `program_repository.dart:1199-1201`;
    - `effectiveDate`, `:74`;
    - `last_called` / `last_called_dated` (`MAX(performed_at)`), `:1047-1051`;
    - the display fallback, `calling_history_section.dart:415`.
  - Drop #1984's 5-minute heuristic (`:385-416`), which becomes unnecessary.
  - Re-dating then moves history, with no data migration.
- **Tests:** lockstep tests across Called ×N, history rows, last-called, the Last-called sort, venue counts and half stats. The single-predicate rule is from F5/F6.
- **Docs:** `programs.md` (calling history), `collection.md` (Last called), `domain-model.md:62-75` and `:220`.
- **Size:** M (~250). **Model:** Opus, because it touches every history query.
- **Depends on:** nothing in flight. Serialize with the other `program_repository.dart` branches (B3, B4, B5, B6, B9).
- **Severity:** M.

#### B2 `fix/matrix-break-separates` (GIG-8 = a)

- **Scope:** `_neighborRowIndices` (`analysis/program_matrix.dart:575-604`) skips a neighbour in a different section when both sections are non-null. The sections already reach the matrix (`:839-855`). A break separates two dances; a waltz or a note does not. The PDF follows automatically.
- **Docs:** `programs.md:285-290`.
- **Size:** S (~100). **Model:** Sonnet. No ARB, no keys, core only. It doesn't collide with F10, which edits row building in the editor.
- **Severity:** L.

#### B3 `feat/link-typed-venues`: offer to link old programs (GIG-7 = b)

- **Scope:**
  - Add `linkTypedVenues(venueId, name)` in `program_repository.dart`. It bumps `updatedAt` for sync and keeps the typed text, so the link is lossless.
  - **Where the offer appears:**
    - when venue records are turned on (`program_section.dart:167-176`);
    - **and** when a venue record is created, in the manager and from the editor's add-on-the-fly path. When the mode is first switched on there are usually no records, so an offer at that moment alone would usually match nothing.
  - *My call:* link live programs only; a trashed program keeps its typed venue.
  - Don't remember a "declined" answer, so no settings key is needed.
- **Docs:** `settings.md:121-137`.
- **Size:** M (~300). **Model:** Sonnet. ARB: yes.
- **Depends on:** U9, which touches the Venues empty state in the same manager screen. B4 later edits `program_section.dart`, so B3 lands first.
- **Severity:** L.

#### B4 `feat/mark-all-sets-performed`: program status follows Mark all performed (GIG-12, with the maintainer's note)

- **Scope (from the note):**
  - Add a setting in Settings › Programs › Calling history, beside "Require mark performed", "Require an event date" and "Show mark-performed toggles". It is **on by default**.
  - **On:** Mark all performed, in the editor (`program_editor_screen.dart:2398-2440`) and the summary (`program_summary_screen.dart:866-920`), also sets the status to Performed.
  - **Off:** today's behaviour (option 1).
- **Undo must restore marks and status together:**
  - The editor Undo also restores `_status`. Check that the dropdown (`:4065-4097`) repaints: it has a const key and `initialValue`.
  - The summary Undo (`:1108-1135`) uses `clearPerformedAtIfMatches`, which touches slots only. It needs a compare-and-set that also restores the status.
- **Helper text under the dropdown follows the setting:**
  - It says that Performed stamps every unmarked primary (#390), and that changing the status back keeps the marks.
  - With the setting on, it adds that Mark all performed sets the status.
  - *My call:* un-marking a dance doesn't reset the status. That mirrors "reverting the status never unstamps" (`:550-553`), and the alternative would fight F5b's per-row toggles.
- **Setting plumbing**, following F5b's `show_performed_toggles` (#2008):
  - `settings_keys.dart`;
  - a live `*_scope.dart`;
  - `main.dart` (key list and scope wrap);
  - `settings/program_section.dart` (`:395-430`);
  - `backup_settings_schema.dart`;
  - `sync_setting_labels.dart`;
  - classify it in **`privacy/settings_registry.dart`** (settings keys live there, not in `field_registry.dart`), then regenerate `docs/dev/data-classification.md` with its tool.
- **Docs:** `programs.md:234` and `:477-478`, `settings.md`, and the `app/assets/docs/user` mirrors.
- **Changelog:** a default-on behaviour change, so the fragment says so.
- **Size:** M–L (~400). **Model:** Opus (two Undo paths, a status transition that stamps).
- **Depends on:** F10, F11 and U7, which all edit the same editor and summary action code. Also B3 (`program_section.dart`) and B30 (registry; serialize the regenerated doc).
- **Severity:** L.

#### B5 `fix/program-delete-warns-history` (LIFE-6 = a)

- **Scope:**
  - A count query in `program_repository.dart` that reuses the called predicate (alternates, performed, event date, caller), so N matches what the user sees.
  - An optional body line in `utils/confirm_delete.dart:20-48`: "N dances will lose this from their calling history".
  - Three call sites: list `programs_list_screen.dart:771`, summary `:551-557`, editor `:2930-2951`.
  - Docs: `programs.md:53` and `:449`.
- **Limitation, which the PR body must state:** confirm-before-delete is **off by default**, and the list swipe (`:748`) skips the confirm. So the warning reaches only callers who opted in. Whether the Undo snackbar should repeat N is a question for the maintainer, not part of this branch.
- **Size:** M (~200). **Model:** Sonnet. ARB: a plural.
- **Depends on:** F11, whose LIFE-14 rewrites the editor's `_delete`; U7; and B4 (same action code).
- **Severity:** L.

#### B6 `fix/dialect-rename-follows-programs` (PRES-11, LIFE-11 = a)

- **Scope:**
  - Add `renameDialect(old, new)` in `program_repository.dart`. It compares normalized names (`:606-609`), includes trashed programs, and bumps `updatedAt`.
  - Call it from the rename flow (`data/dialect_library_controller.dart:157-169`, used at `settings/dialect_section.dart:120`).
- **Check:** the dialect list syncs as a setting, but programs sync as records. Add a test, or a written trace, that a rename on device A converges on device B.
- **Docs:** `dialects.md:339-342`. Delete still unpins; rename now follows.
- **Size:** S–M (~180). **Model:** Sonnet. No ARB, no keys.
- **Severity:** L.

### Trash and deletion

#### B7 `fix/permanent-delete-hides-and-blanks`: LIFE-2 (a), and what can be done of the note

**The decided part (a):**

- "Permanently delete" on a published record hides it from Recently deleted, and blanks its content so that only the deletion record remains.
- The snackbar stops claiming something that didn't happen (`recently_deleted_screen.dart:219-223`).
- Backups and the trash no longer show the content.

**Feasibility of the note ("clear the deletion record if every device has a more recent sync than the timestamp on the delete"): not safe with what the app knows.**

What the app can see:

- the store's current device list;
- each current peer's last manifest, with `writtenAt` and the tombstone hash it carries (`sync-spec.md` §4.5).

So "every device *currently in the store* has published a manifest after the delete, carrying this tombstone" is observable.

What the app cannot see, and why it matters:

- **Departed devices.**
  - A device that detached is invisible: detach clean-up may delete its manifest (§3.3).
  - So is a device whose manifest was removed.
  - So is a device that left before the delete.
  - If such a device re-attaches holding the record live, the surviving tombstone is what makes it lose the existence comparison (§6.4, §6.10).
  - Once the tombstone is gone, a re-attaching live copy is "absent from baseline, present remotely → download", and the record comes back on every device (§6.3; §3.1 calls this the specified consequence of forfeiting).
- **The spec already decided this.**
  - §3.2 says of `published_records`: "**No retirement rule, deliberately**".
  - It rejects retiring against peer manifests, because this device's own manifest also keeps the record reachable.
  - It notes the asymmetry: a wrongly retired marker "silently resurrects a deletion".
- **The delete has no usable timestamp.** Permanent delete backdates the record with `softDelete(at: DateTime.utc(1970))` (`recently_deleted_screen.dart:338-345`, and the program equivalent at `:379`). The LIFE report traced `updated_at` going to 1970 as well, through `existence.dart`; B7 must re-check that on main.
- **Clocks differ.** `writtenAt` is each peer's own clock.

**What can be done:**

1. **Blanking removes all the content**, which was the privacy goal behind LIFE-2.
   - The remainder is kind, id and existence stamps: a few dozen bytes, no names and no text.
   - Blanking must carry a fresh content stamp so the blank body wins on peers. A 1970 stamp would lose last-writer-wins and leave the content on other devices.
   - Check that peers then replace their copies of the body, and say in the PR which layer was verified.
2. **Retiring the record is a separate, maintainer-only decision.** Retirement would need a dated amendment to sync-spec §3.2 that accepts resurrection from departed devices. The narrowest safe-looking rule would be: every device in the store's device list has published a manifest carrying the identical tombstone hash, **and** no device has left the store since the delete. The second condition is not observable today: the server keeps no departure log.
   - **Recommendation:** don't build retirement. Report it back to the maintainer with this explanation.
   - *My call:* B7 implements (a) plus blanking, and does not retire anything.

**Also in B7:**

- **Files:** `recently_deleted_screen.dart` (snackbar `:219-223`, delete callbacks `:338-345` and `:379`), the published-record exclusions in `dance_repository.dart:2003-2011` and `program_repository.dart:1505`, `:1570`, `existence.dart`, and a "removed" flag or an equivalent filter.
  - If the flag is a new column, classify it in `field_registry.dart` on all three axes in this PR. It is likely `deviceScoped`.
- **Docs:** `collection.md:370-374`, `storage.md:887-890`, and a `sync-spec.md` note that a hidden tombstone still advertises.
- **Size:** M (~300). **Model:** Opus (sync existence semantics).
- **Depends on:** nothing in flight; LIFE-1/3 have merged. It goes before B8 and B9, which edit the same repository delete and restore paths.
- **Severity:** M.

#### B8 `fix/trash-does-not-protect`: the guards (trash-policy = b)

- **Flip the three guards that count trashed records:**

  | Guard | Where |
  | --- | --- |
  | Custom field `isInUse`, which locks type and key | `custom_field_repository.dart:307-315`; used at `custom_fields_screen.dart:125`, `:505-506` |
  | Choice option in use | `listUsedChoiceValues` `:321-330`; lock at `custom_fields_screen.dart:787-800` |
  | Difficulty level | `difficulty_level_repository.dart:160-215`; message at `defaults_section.dart:1412` |

  The venue, custom-field delete, choreographer, tag and source guards already ignore trashed records.
- **Amend the three docs from conflict 2:**
  - ADR-005 (`:32-33`, `:53`): an erratum.
  - `storage.md:646`.
  - sync-spec §6.8's level clause: a dated amendment. The pending-deletion citation count then counts live owners only, as every other kind does.
- **Watch the cascade.** Erasing a parent that a *tombstoned* dance cites still destroys the join row (sync-spec §3.1 retention table). Trash-doesn't-protect must mean "the delete is allowed and tombstones the parent". It must not mean "the hatch erases".
- **Docs:** `settings.md:128-133` (venue) and `:446-449` (level).
- **Size:** M (~250). **Model:** Opus (spec amendment, guard semantics).
- **Depends on:** B7.
- **Severity:** L.

#### B9 `fix/restore-copes-with-missing-refs`: restore half of the trash policy, plus LIFE-4

- **Restore:**
  - Program and dance restore (`program_repository.dart:1456-1472`, `dance_repository.dart:1914-1932`) revive a tombstoned venue, level or custom field they reference, in the same transaction. That revival syncs.
  - Where a reference is gone outright, restore falls back cleanly: a typed venue, or no level.
- **LIFE-4:**
  - `ProgramRepository.duplicate` (`:1423-1443`) copies a dangling `venueId`, and `_upsert` throws a `StateError` (`:520-546`).
  - Fix it in core: revive the venue, or drop the dead id. That keeps the change off the hot screens.
- **Docs:** `collection.md` (restore), `settings.md` (venues).
- **Size:** M (~250). **Model:** Opus.
- **Depends on:** B8.
- **Severity:** L.

#### B10 `fix/settings-deletes-say-deleted` (UX5-4a = b)

- **Scope:** after the confirm, show the existing `commonDeletedSnack`. #2009 added only the *failure* snackbar.
- **Sites:**
  - dialect: `dialect_section.dart:123-143`;
  - theme: `appearance_section.dart:462-482`;
  - shorthand and compound shorthand: `shorthand_mappings_screen.dart:188-215`, `:366-400`;
  - snippet: `walkthrough_snippets_screen.dart:97-121`;
  - custom field: `custom_fields_screen.dart:239-264`;
  - custom figure: `glossary/custom_figure_detail.dart:240-253`. Capture the messenger before the narrow layout pops.
- **Size:** S–M (~180). **Model:** Sonnet. No new ARB.
- **Depends on:**
  - B6 (`dialect_section.dart`);
  - U9, whose one-line empty states touch the same settings sub-list screens;
  - B8 (`custom_fields_screen.dart`).
- This item came from the UX decisions, not the behaviour group. It is planned because no in-flight branch covers it.

### Search and Collection

#### B11 `fix/search-words-and-dialect-moves` (FIND-5 = b, FIND-4 = a)

The two are one branch because both rewrite `_compileFullText` (`filter_compiler.dart:406-470`), and FIND-4's substitution must run before FIND-5's split.

- **FIND-4:**
  - Build a substitutor from `_moveReverse` (`:129-138`): dialect name → id → taxonomy display name.
  - Apply it before `canonicalizeMoveSearchText`, on the canonical branch only.
- **FIND-5:**
  - Split the query on whitespace and AND the words. This **reverses part of #1005**; the maintainer noted that knowingly.
  - It is feasible but not mechanical:
    - **Words under 3 characters** match nothing in the trigram index. Route them to the `dance_fts` prefix index, or OR in the whole phrase.
    - **Multi-word terms** (roles, moves, dialect names) must be substituted before splitting.
    - The `(canonical OR raw)` choice moves **inside each word**, so "Robin Hayden swing" works. FTS5 can express this in one MATCH.
    - F18's `_hasInternalRoleTokenFragment` / `_figureMatchWithoutRoleTokens` (`:45-95`) become per-word.
    - Best match (bm25, ≤2 characters) is unaffected.
- **Docs:**
  - `search.md:16-17`, `:28-29` and the canonicalization section;
  - narrow `search.md:545`, because type-aheads are deferred;
  - `collection.md:108-110`, `:112`, `:122-125`;
  - `dialects.md:52-54`, which becomes true for moves;
  - the `fts_query.dart` doc comments.
  - These replace D2's FIND-4 and FIND-5 bullets (conflict 4).
- **Size:** L (~450). **Model:** Opus.
- **Severity:** FIND-5 L/M, FIND-4 L.

#### B12 `fix/search-index-honours-searchable` (FIND-6, FIND-13 = a)

- **Indexing** (`dance_repository.dart:1557-1585`, `:1605-1632`): skip fields with `searchable` off, and stop indexing booleans as "true"/"false".
  - *My call:* skip booleans in the text index, because the yes/no facet already exists. Rejected alternative: index the field label when true. The implementer may choose otherwise, but must say so.
- **Re-index when `searchable` flips** on a local edit, following `reindexDancesUsingUserFigure` (`:1236`). The sync path already passes `customFieldIds`.
- **Existing indexes:** add a one-shot rebuild marker, following `gripSingleFileCanonicalInclusionDoneKey`. Register the internal key in `privacy/settings_registry.dart`.
- **Strings and docs:**
  - `customFieldsSearchableSubtitle` also says it controls the search bar (six ARBs);
  - `collection.md:122-125`, `settings.md:~400`, `search.md:25-26`, `domain-model.md:243`.
- **Size:** M (~250). **Model:** Opus.
- **Depends on:** serialize the regenerated `data-classification.md` with B30 and B4.
- **Severity:** FIND-6 M (unchecked), FIND-13 L.

#### B13 `fix/sort-folds-accents` (FIND-15 = a)

- **Scope:**
  - `titleSortKey` (`title_sort_key.dart:23-34`) reuses `foldForTitleMatch`.
  - So do the Dart title and author sorts (`dance_repository.dart:2994-3021`, `:3023+`) and `programs_list_screen.dart:336`.
  - The SQL `COLLATE NOCASE` path (`filter_compiler.dart:237-249`) needs a Dart post-pass whenever the sort is by title, whatever the articles setting.
  - No new dependency: `unorm_dart` is already present.
  - Scope the other 26 `toLowerCase().compareTo` sites in or out explicitly.
- **Docs:** `collection.md` (sort), `search.md:338-357`.
  - They must **not** claim locale-correct sorting: NFD folding leaves Æ and Ø after Z and folds Danish Å to A. That trade-off is inherent in (a).
- **Size:** M (~200). **Model:** Sonnet.
- **Depends on:** B12 (same file).
- **Severity:** L.

#### B14 `feat/picker-parity` (FIND-7, PRES-15 = b, full parity)

- **Scope.** The picker (`widgets/collection_picker.dart`) gets Collection's:
  - Search in (`scope:`, `:364-373`);
  - sort (`:374-379`);
  - online scopes (today title-only, `:566`);
  - card fields (`visibleFields`, `:1031`).
- **Shared widgets:** Collection's controls are private to `dance_list_screen.dart` (`:172`, `:235-254`, `:806`). Extract them into shared widgets.
- **Keep the picker's constructor API stable**, so its five mount points need no change. Three of them are in `program_editor_screen.dart` (`:3206`, `:3663`, `:3781`), which F10 and F11 are editing.
- *My call:* the picker's sort is session-only, seeded from `kDefaultCollectionSortKey`, so no new key is needed. Rejected: a persisted picker sort, which would need a key and a registry entry for little gain.
- **Note for N1:** this branch also delivers FIND-1's option (d), the Last-called sort in the picker.
- **Docs:** `programs.md:158-161`, `settings.md:382-386`, `ux.md:125`.
- **Size:** L (~500). **Model:** Opus.
- **Depends on:** U9 (Collection empty state in `dance_list_screen.dart`). If the API cannot stay stable, it also waits for F11.
- **Severity:** L, L (unchecked).

#### B15 `fix/tag-chip-adds-filter` (FIND-14 = a)

- **Scope:**
  - `_applyExternalTagFilter` (`dance_list_screen.dart:506-530`) stops clearing text, facets, By phrase and Advanced, and adds the tag instead.
  - Online mode is still left, because tags are local only.
  - Update the tooltip `commonShowDancesTaggedTooltip`.
- **Blocked on conflict 8:** whether the tapped tag joins the "any" Tags facet (widening the results) or narrows them.
- **Docs:** `collection.md:35`, `ux.md:55`.
- **Size:** S (~120). **Model:** Sonnet.
- **Depends on:** B14 (same screen).
- **Severity:** L (unchecked).

### Import and sharing

#### B16 `fix/online-import-reuse-and-undo` (INTAKE-5 = a, INTAKE-3 = a)

Both share the identical-match branch of `commitPreviewedOnlinePlan` (`data/online_search.dart:353-447`).

- **INTAKE-5:**
  - A hand-entered match (no provenance, `:394-395`) gets the existing dialog with neutral wording. Today's body says "from a different source", at `app_en.arb:8025`.
  - The import snackbar offers Undo through `OnlineImportResult.session` and `ImportPipeline.undo`, as `program_import_rollback.dart` does.
  - Route the four snackbar sites through one helper: `collection_shell.dart:467`, `dance_list_screen.dart:1239`, `:1289`, `main.dart:1505-1511`.
  - Flip the pins that marked the old behaviour as intended (`callersbox_online_test.dart:1293`, `contradb_online_test.dart`).
- **INTAKE-3:**
  - `contradb_program_import.dart:172-182` first resolves without forcing a duplicate, and links the slot to an identical dance (the #685 rule).
  - Still no per-dance prompt (#797). This makes `programs.md:131`'s promise true.
- **Docs:** `imports.md:571-580`, `docs/design/imports.md:42`.
- **Size:** M (~350). **Model:** Opus.
- **Depends on:** nothing in flight. `main.dart` is shared with B21: land B16 first.
- **Severity:** M, M.

#### B17 `fix/share-file-custom-field-match` (INTAKE-2 = a)

- **Scope:**
  - `_sameField` (`share_metadata_import.dart:406-416`) compares key, type and choices. The receiver's own label and display flags win, which also fixes the "Card"/"card" trigger.
  - A **plan-time** metadata check in `compendium_archive_import.dart` raises an `ImportIssue` that review shows, instead of a throw at commit (`:343-348`).
- **Open: what a real conflict does once shown.** The decision says to show it, not how to resolve it.
  - *My call, pending confirmation:* follow the `.USR` precedent (`callers_companion_usr_import.dart:924-935`): import into `<key>_2` with a review note.
  - Rejected: refusing the whole file, which is today's behaviour.
- **Docs:** `sharing.md:87-90` and its mirror.
- **Size:** M (~250). **Model:** Opus.
- **Severity:** M.

#### B18 `fix/batch-reimport-choreography-only` (INTAKE-7 = a)

- **Scope:**
  - `CommitAction.reimport` replaces only figures, formation and progression. Today `_rebuildWithIdentity` (`import_pipeline.dart:886-905`, `:1481-1530`) copies rating, tags, links, notes and status.
  - `replaceDanceChoreography` is app-side (`data/dance_reimport.dart:12-50`). Move it into core.
- **Question for the maintainer before starting:** the same branch serves every source:
  - `.ccshare` and other archives;
  - `.USR`;
  - ContraDB identity re-import;
  - online re-import.

  `docs/design/imports.md:483` says an archive re-import "replaces a dance's content from the file". Does choreography-only apply to native archives too, or only to Caller's Box and ContraDB? `CommitAction.link` uses the same code and is out of scope.
- **Docs:** `imports.md:631-660`, `docs/design/imports.md:42-43`, `:124-126`, `:483-490`.
- **Size:** M (~300). **Model:** Opus.
- **Depends on:** B17 (same import path and review screen), and the answer above.
- **Severity:** M.

#### B19 `fix/share-files-omit-private-fields` (OUT-2 = a, with the note)

**Egress paths, as checked:**

| Path | Mode | Change |
| --- | --- | --- |
| Dance share file (`dance_share_bundle.dart:79-90`) | share | drop rating |
| Program share file and Export JSON (`program_share_bundle.dart:209-223`) | share | drop pay, dialect and rating |
| Backup (`backup_document.dart:274`, `:376`) | backup | unchanged |
| Device Sync (own codec, filtered by registry egress) | — | unchanged |
| PDF and text set lists | — | no pay today |
| Import-side re-encodes (`generic_json_adapter.dart:386-395`, `published_collection.dart:286-302`) | share | unchanged |

- **Feasible.**
  - Strip in the app's share bundles, as `share_sanitization.dart` already does.
  - Don't change the codec's share mode: that would also drop rating during the import-side re-encodes.
- **Registry:**
  - **Keep egress `shareable`** for `programs.pay_minor_units`, `dialect_name` and `dances.rating`. `deviceLocal` means "never serialised" and would stop sync, against the note.
  - Rewrite their notes: "own devices and backups yes, share files no". Give `rating` its own entry instead of the shared `_choreography` constant.
  - `.github/instructions/privacy-registry.instructions.md` has no guidance for this case. Add one line there in the same PR.
  - Regenerate `data-classification.md`.
- **Sync can still reach another person.** Under ADR-004, a store can be shared with another person (`storeAddress`), so "travels in sync" can reach someone else. Say this in the registry notes; don't change it.
- **Blocked on conflict 7:** what "export" means.
- **Docs:** `sharing.md:172-173` and its mirror.
- **Size:** S–M (~180). **Model:** Sonnet, with a registry review.
- **Depends on:** the answer to conflict 7; serialize `data-classification.md` with B12, B30 and B4.
- **Severity:** M.

#### B20 `fix/android-ccshare-generic-type` (PLAT-4 = a)

- **Scope:**
  - Add `application/octet-stream` to the picker (`data/import_io.dart:240-248`) and to the VIEW and SEND filters (`AndroidManifest.xml:37-48`).
  - Validate in the app, and say plainly when a file is not a share file.
- **Risk:** an octet-stream VIEW filter puts the app in Open-with for every unknown binary file. Add a `pathPattern` for `.ccshare` where it works; it is unreliable for `content://` URIs.
- **Needs a check on a real device;** the intake could not verify this here. The maintainer or a tester must do it before merge.
- **Docs:** `imports.md:277`, `sharing.md:~200`.
- **Size:** S (~100). **Model:** Sonnet.
- **Severity:** L.

#### B21 `feat/desktop-open-ccshare` (PLAT-3 = a)

- **Scope:**
  - **Windows:** Inno `[Registry]` plus `ChangesAssociations`.
  - **Linux:** a `.desktop` `MimeType` and `%f`, and a shared-mime-info XML.
    - Linux ships only as an AppImage and a tar.gz, with no installer, so registration is best-effort.
    - The docs and `tools/release/test_linux_desktop_integration.py` must say so.
  - `main()` reads the path (`main.dart:139`).
  - A running instance receives it over the single-instance channel (`single_instance_guard.dart:21`, `:260-275`, which today acts only on `raise`) and hands it to `incoming_file_channel.dart:78-90`.
- **Security:**
  - The loopback channel is unauthenticated.
  - An `open <path>` message must be validated (extension, size, regular file) and must only ever open import review, never commit.
- **Docs:** `faq.md:125`, `sharing.md:~200`, `imports.md:270-281`, `installation.md:74-82`. These replace D2's PLAT-3 bullet.
- **Size:** L (~450). **Model:** Opus.
- **Depends on:** B16 (`main.dart`).
- **Severity:** L.

### Exports

#### B22 `fix/card-fields-and-set-list-colours` (OUT-6, PRES-12, PRES-10, all = a)

- **OUT-6:**
  - Add sources and hook to `DanceShareField` (`export/dance_share_fields.dart:20-60`), `dance_card_content.dart:30-75`, and the checklist (`defaults_section.dart:1981-2075`).
  - Thread published-source titles through the PDF and share call sites.
  - Store them in the existing `kProgramDanceShareFieldsKey` set, so no new key is needed.
  - *My call:* both default off, like tunes.
- **PRES-12:**
  - A helper in `theme/set_list_accents.dart` (`resolveFormationLabelColor` `:142-150` is close).
  - Use it at the summary (`program_summary_screen.dart:1307-1309`) and the builder (`program_slot_list_editor.dart:448-457`).
  - The mixer accent still wins (conflict 9). Settle how high contrast treats a user colour.
- **PRES-10:** one line in `settings.md:71-72`, like Capitalize.
- **Docs:** `settings.md:254-270`, `:388-394`, `sharing.md:141-147`.
- **Size:** M (~300). **Model:** Sonnet.
- **Depends on:** F11 and U7 (`program_summary_screen.dart`), and U7 for the builder rows.
- **Severity:** L ×3.

### Editor

#### B23 `fix/editor-move-blur-and-dropped-groups` (AUTH-1 = a, AUTH-2 = b)

- **AUTH-1:**
  - On focus loss, `move_autocomplete.dart` applies an exact name or a shorthand, using #2003's `_namesExactly` / `submitsAsText` (`:243-253`, `:296-313`). Anything else reverts the text.
  - Call sites: `figure_list_editor.dart:2539`, `:2655`, `:2758`, `:3986`. The last covers the Settings default figures.
  - **Traps:**
    - Save and Back must flush pending Move text, as F1 does for the composer, because tapping Save doesn't reliably take focus.
    - Opening the compact phone sheet is not a blur.
    - Choosing an overlay option must not race the revert.
- **AUTH-2:**
  - Compute warnings from drafts (`figureDrafts` `:261`), not built figures (`recomputeWarnings` `dance_editor_controller.dart:897-909`).
  - Mark the row, and list the warning in `WarningsCard` (`dance_editor_form.dart:537`). No dialog.
- **Docs:** `authoring.md`, including `:499-502`.
- **Size:** L (~450). **Model:** Opus.
- **Depends on:** nothing in flight. Rebase after the D-1 branch if it touches `dance_editor_screen.dart`.
- **Severity:** M, M.

#### B24 `fix/autosave-failures-visible` (FAIL-8 = c)

- **Scope:**
  - Log the first draft-save failure per session with `logCaughtErrorTypeOnly`. The message could carry draft text.
  - Show a marker in both editor bars.
  - Sites: `dance_editor_controller.dart:1211-1214`, `program_editor_screen.dart:1341-1344`.
- **Docs:** `authoring.md:621-625`.
- **Size:** S (~130). **Model:** Sonnet. ARB: 1 string.
- **Depends on:** F11, which changes the program draft key in the same autosave code, and B23 (the controller).
- **Severity:** L.

### Startup, updates and diagnostics

#### B25 `fix/startup-screens-and-diagnostics` (FAIL-11 = b, FAIL-10 = d)

- **FAIL-11 (b):**
  - All four terminal screens in `widgets/app_bootstrap.dart` get **Copy details**, scrubbed through `CrashRedactor` as #1986 did for the generic screen, and a **Releases link**:
    - downgrade (`:80-98`);
    - below-floor (`_BelowFloorRecoveryScreen`, `:261+`), which keeps its two reset actions;
    - snapshot-aborted (`:112-131`);
    - relocation-blocked (`:137-172`).
  - Downgrade shows both version numbers.
  - No Check again, per the decision.
- **FAIL-10 (d):**
  - `scrubbed()` (`crash_log_record.dart:142-148`) keeps messages for an allow-list of typed errors: `UrlFetchException`, `PublishedCollectionFetchException`, `_UpdateDownloadError`, `SyncFailure`.
  - The bootstrap screens get an export.
  - At startup failure, the scrub cannot read the sensitive terms from the database, so the export there withholds messages outside the allow-list and scrubs paths. Never offer a full export there (the CWE-209 note at `diagnostics_section.dart:336`).
  - Fix the FAQ: `faq.md:165-168` gives the log path for Linux only. Also update `settings.md:551-553`.
- **Size:** M (~350). **Model:** Sonnet.
- **Depends on:** #2016 (U3), which rewrites the startup error text in this file (`:174`, `:395`) and the ARBs.
- **Severity:** M (unchecked), M (unchecked).

**Answer to the maintainer's question: "I don't think check again would ever succeed, so it's a button that always fails, right?"**

It is right for two screens and wrong for two. Retry (`_retry` → `_retryReopen`, `main.dart:2031-2060`) closes the connection and re-runs the whole preflight, including relocation and the snapshot. So a condition that clears while the app is open would let it succeed.

| Screen | What raises it | Can it clear without restarting the app? |
| --- | --- | --- |
| **Downgrade** (`DatabaseDowngradeError`) | The library was written by a newer build | **No.** Only a newer app binary fixes it, which means a restart. Check again would always fail. |
| **Below floor** (`DatabaseBelowFloorError`) | The library is older than the minimum schema | **No.** Only the bridge release (another binary) or a reset fixes it, and the screen already offers reset. Check again would always fail. |
| **Snapshot aborted** (`MigrationSnapshotAborted`, `migration_guard.dart:309`) | The pre-migration backup couldn't be written (disk full, or an unwritable backups folder), and the caller declined to go on without it | **Yes.** Freeing disk space or fixing the folder while the app is open lets a re-run write the snapshot and migrate. If it still fails, the re-run asks the "continue without a backup?" question again. Today the screen says "reopen the app", which on a phone means force-quitting. |
| **Relocation blocked** (`DatabaseRelocationBlocked`, `migration_guard.dart:357-394`) | Moving the library out of Documents was unsafe | **Yes, for every reason, on desktop:** `bothExist` / `multipleLegacy` once the caller moves or renames a copy in the file manager; `moveFailed` once another process releases the database or lock, or space is freed; `legacyUnreachable` once the network share or drive is back. |

**Recommendation:** ship (b) as decided. Then ask the maintainer whether Check again should appear on the **snapshot-aborted and relocation-blocked screens only**. It would be about 30 lines in the same file, reusing `onRetry`.

#### B26 `fix/update-check-says-why` (FAIL-3 = c)

- **Scope:**
  - `checkManifest` returns a typed result (`update_service.dart:115-165`, `update_manifest.dart:290-294`): unreachable, unauthentic, or unsupported format.
  - **The manual check only** gets two new statuses:
    - "Couldn't check"; and
    - for an authentic but unsupported manifest, "A newer version is available from the Releases page".
  - `checkIfEnabled` (`update_controller.dart:878-882`) also calls `checkNow`, so the automatic check must stay silent (ADR-002 §5).
  - *My call:* an artifact for an unknown platform or architecture counts as "newer format".
- **Docs:** `settings.md:494-497`, `releasing.md:866-882`, and an ADR-002 §5 erratum (conflict 6).
- **Size:** M (~220). **Model:** Sonnet. ARB: 2 strings.
- **Severity:** M.

#### B27 `fix/updater-install-kind` (PLAT-5, PLAT-6 = a)

- **Scope:** a new `install_kind.dart` that detects:
  - iOS: always a store build.
  - Android Play: a `--dart-define` on the separate `appbundle` step (`.github/workflows/release.yml:1214`), so the release-tooling path instructions apply.
  - Windows portable: no Inno uninstaller beside the exe.
  - Linux tar.gz: `APPIMAGE` unset.
- **Behaviour:**
  - Store builds don't check for updates.
  - Portable builds say "download the new zip from the release".
  - macOS dmg and zip are the same `.app`, so nothing changes there.
- **Files:** `updates_section.dart`, `update_banner.dart`, `update_controller.dart`.
- **Docs:** `installation.md:239-243`, `settings.md:~490-501`.
- **Size:** M (~300). **Model:** Sonnet.
- **Depends on:** B26 (same controller and section).
- **Severity:** L, L.

### Platform, Perform and settings

#### B28 `feat/perform-full-screen-and-scroll-keys` (PLAT-9 = a, PLAT-10 = a)

- **PLAT-9:**
  - A mixin modelled on `PerformWakelockMixin` (`perform_wakelock.dart:54`), used by `perform_program_screen.dart:210` and `perform_dance_screen.dart:57`.
  - Phones go immersive. Desktop gets a toolbar toggle plus F11 (Ctrl-Cmd-F on macOS) through `window_manager`.
  - Restore on exit, dispose and app close.
  - **Trap:** `onWindowResized` → `_captureAndPersist` (`window_service.dart:300-350`) would save the full-screen bounds as `window_frame`. Suppress persistence while in full screen.
- **PLAT-10:**
  - Pass a `ScrollController` into `PerformCard` (`perform_card.dart:167`, `:235`).
  - Down and Page Down scroll to the end before advancing (`perform_program_screen.dart:1196-1206`). Reset the scroll on slot change. Pedals keep working.
  - *My call:* Up and Page Up mirror this (scroll to the top, then go back). The decision covers only Down.
- **Docs:** `perform.md:20`, `:118-123`; `ux.md:168`, `:173-174`; `accessibility.md`.
- **Size:** M (~400). **Model:** Opus.
- **Depends on:** F10 and F11; F11 rewrites Perform's persist code in this file.
- **Severity:** L, L.

#### B29 `feat/desktop-shortcuts-and-mac-menu` (PLAT-7 = b, PLAT-8 = b)

- **PLAT-7.** The report's minimal map:
  - Ctrl/Cmd-S save;
  - Ctrl/Cmd-N new dance;
  - Ctrl/Cmd-F focus search;
  - Cmd-, Settings;
  - Esc / Cmd-W back;
  - right-click on `dance_list_tile.dart:352` and `program_list_tile.dart:100` opens the ⋮ menu;
  - mouse Back does `maybePop`.

  Root intents go at `main.dart:2754`. Settings and new-dance routing need a hook into `app_shell.dart` (`_Destination` `:67` is private).
- **Esc in Perform** must not exit: `ux.md` §5 requires a deliberate exit. Esc in an editor reaches #2012's discard prompt, which is right.
- **PLAT-8:**
  - A localized `PlatformMenuBar` with Settings, New dance, Import, Guide, and the standard items, sharing PLAT-7's intents.
  - It replaces the whole xib menu.
  - `PlatformProvidedMenuItem` has no Cut/Copy/Paste, so the **Edit menu disappears**. Text shortcuts still work in Flutter. The PR body must say this.
  - Use the provided `toggleFullScreen` item, which ties in with B28.
- **Docs:** `accessibility.md:119+`, `ux.md:24`, `ux-modernization.md:664-665`. These replace D2's PLAT-7 bullet.
- **Size:** L (~550). **Model:** Opus.
- **Depends on:** B28 (Esc and full screen), F11 and U7 (editor app bars), and D2 (`ux.md`).
- **Coordinate with N5:** right-click conflicts with a text-selection context menu.
- **Severity:** M, L.

#### B30 `fix/per-device-screen-settings` (PRES-1 = a)

- **Scope:**
  - In `privacy/settings_registry.dart`, `app_locale` (`:112`), `reduce_motion` (`:95`), `auto_size_perform_cards` (`:288`) and `perform_stage_mode` (`:301`) become `deviceLocal`. Follow the `perform_text_scale` precedent at `:302-310`.
  - Write each note with the reason: these keys are withheld for what they *mean* (screen-bound), not what they contain. Say why `deviceLocal` was chosen over `deviceScoped`: `deviceScoped` would drop them from backups.
  - `theme_mode` and `active_custom_theme` keep syncing.
- **How sync decides:** sync reads `classifySettingsKey(key).egress` on both send and receive, so no other list changes.
- **No migration is needed:**
  - Upgraded devices stop sending these keys.
  - A value from an older peer is kept whole as retained (§6.7) and never applied.
  - Trace whether the retained copy is republished, and say in the PR which layer was verified.
- **Hidden cost:** four sync tests use `reduce_motion` as their shareable fixture and need another key:
  - `sync_device_scoped_settings_trigger_test.dart:77-147`
  - `sync_controller_test.dart:1180`
  - `sync_coordinator_test.dart:5549`
  - `sync_conflict_sheet_test.dart:428`
- **Docs:**
  - regenerate `data-classification.md`;
  - an ADR-004 erratum (conflict 5);
  - `settings.md`, following the pattern at `:947`.
- **Size:** M (~250). **Model:** Opus.
- **Depends on:** nothing in flight. Serialize the regenerated doc with B12, B19 and B4.
- **Severity:** L.

#### B31 `fix/locale-follow-through` (PLAT-12 = b, PLAT-13 = a)

- **PLAT-12:**
  - The `system` branch of `formatEventDate` (`regional_formats.dart:183-202`) formats with `PlatformDispatcher.instance.locale`. `intl` is already a dependency, and `pay_currency.dart:65` already reads the platform locale.
  - This makes the doc comments at `:9`, `:33`, `:66` and `:185-187` true.
  - Update the live example at `settings/regional_section.dart:204`.
- **Question, settled in the PR:** a Danish-region phone with an English UI would show Danish month names. *My call:* use the region's numeric date (`yMd(region)`), which shows no month names and so can't mix languages. Rejected: the region's field order with the app language's month names, which needs a hand-built pattern. Confirm that date symbols load for a locale other than the app's (`initializeDateFormatting`).
- **PLAT-13:** "The Guide is in English" for any `languageCode != 'en'`, shown both in `user_guide_screen.dart` (index at `:150`) and in `user_guide_doc_view.dart`, because help links open a document directly.
- **Docs:** `settings.md:327-331`, `docs/dev/localization.md:~305`.
- **Size:** S (~150). **Model:** Sonnet.
- **Severity:** M, L.

---

## UX copy branches: U4 and U5, re-sequenced

**State:**

- #2016 (U3) is open and edits about 40–50 keys in all six ARBs.
- D2 is queued after F11 and edits `settings.md`.
- U4 edits `settings.md`, `authoring.md` and `glossary.md`, so it lands after both.

### U4 `fix/copy-one-name-each` (D-3 = a)

- **Scope:**
  - "Unrecognized figure" for unparsed text only. The **Custom Figures** setting and the existing names for the user's own figures stay as they are, which is what option (a) means.
  - The trash is "Recently deleted".
  - Files are "share file".
  - People are "author".
  - "Add note or break".
  - "Perform mode" instead of "performance view".
  - Re-sync the bundled guide with `tools/ci/sync_user_docs.py`.
- **Main files:** ARB ×6 (about 25–45 keys), `authoring.md`, `settings.md`, `glossary.md`, test expectations.
- **Overlap:** B7, B10, B19 and B21 add text using "Recently deleted" and "share file". Write those strings in D-3's terms from the start, so U4 has nothing to chase.
- **Size:** M (~400). **Model:** Sonnet.
- **Wave:** W4, after #2016 and D2.

### U5: style sweep (D-4 = c), split three ways

There are 318 English strings with straight quotes; 261 of those contain `'`, mostly as apostrophes. The risk is not volume but **repeated conflicts** with every branch that adds strings, and **semantic hazards** in strings that show text the user must type. So U5 is split, and the quote half is driven by a gate rather than a one-shot edit, following `session-cost.md`'s "prefer a gate to a remembered rule".

- **U5a `fix/copy-case-and-spelling`** (M, Sonnet, after U4):
  - Write the D-4 rule into `docs/user/style-guide.md`, saying that it covers app strings.
  - Fix the 8 Title Case strings, the 20 "colour" strings, and the 11 other British spellings.
- **U5b-1 `tools/arb-quote-style`** (S–M, Sonnet, after U5a):
  - A re-runnable normaliser for `app_en.arb`.
  - A ratchet in `tools/ci/` that fails any **new** string breaking the rule. It holds an allow-list of today's violations.
  - Exceptions the tool must honour:
    - strings that show literal text the user types: shorthand tokens and search syntax;
    - ICU syntax: `l10n.yaml` sets no `use-escaping`, so apostrophes are literal today. Keep it that way.
    - test fixtures that assert English.
- **U5b-2 `fix/copy-quotes`** (L, mechanical):
  - Run the tool, burn down the allow-list, and fix the tests.
  - On a conflict, re-run the tool on the fresh `main` instead of resolving ARB hunks by hand.
  - Land it in a quiet window, when no other ARB-heavy PR is ready to merge.
- **Locales:** English only.
  - *My call:* German, French, Danish, Dutch and Japanese have their own quote conventions („…“, « … », 「…」). Forcing English marks on them would be wrong.
  - Rejected: normalising each locale to its own convention, which is a translator's job.
- **Blocked on conflict 10:** curly or straight, and whether apostrophes count. *Recommendation:* curly quotes and curly apostrophes in prose (a typographic app; curly double quotes are already the majority, 78 strings to 70), straight wherever the user types the character.

## G1 `fix/de-beats-schlaege`: German "beats" (ratify-german-beats = a)

- **Scope:**
  - `app_de.arb` has 26 strings containing "Takt", which usually means bar, not beat. The English source has **no** strings meaning bar, so nearly every one is a beat.
  - **Not all of them should change:**
    - "Mindestens zweimal im Takt klopfen" (`performTapTwiceHint`) uses "im Takt", meaning "in time". It is correct.
    - "Takt aufzeichnen" (`performRecordBeatHint`) and the matrix "Taktüberschneidung" strings need judging in context.
    - Plurals must keep their ICU form: "{beats, plural, =1{1 Schlag} other{{beats} Schläge}}".
  - Add a `beat` entry to `tools/ci/i18n_glossary.json`, pinning "one count of music, never a bar or measure; de: Schlag/Schläge". This stops the assisted translator reintroducing "Takte".
  - Regenerate with `fvm flutter gen-l10n`.
  - *Optional, for the same reviewer pass:* check whether da, nl and fr make the same bar/beat slip.
- **PR body:** a three-column table (key, English, old German → new German) so a non-developer can review it without reading ARB JSON.
- **What the maintainer must arrange:**
  - A **German-speaking caller** (contra or ECD, so they know how "beats" is used in calling) to review the table.
  - A way for them to respond: a GitHub review, or comments relayed by the maintainer.
  - **Agreement that the PR merges only after their sign-off**; nobody is named yet.
  - If no reviewer is found within a set time, the maintainer decides whether to merge on the glossary's authority alone.
- **Size:** S (~80). **Model:** Sonnet.
- **Wave:** W2, after #2016, which edits all six ARBs.

---

## Design notes (design group, "Design note now")

Each note is a docs-only PR under `docs/design/`, written before the next planning round. All five can start in W1, because they conflict with no code branch. Each note must answer its questions, cite the constraints, and end with a proposed branch breakdown sized like this plan.

**Constraints common to all five:**

- **Privacy registry:** any persisted filter state, setting or column is classified on all three axes. The subject axis needs care with choreographer data.
- **Sync:** any new record kind or merge goes through sync-spec §6.6 (id aliases) and §6.15 (the capability gate).
- **`ux.md`'s rules:** undo everywhere (`:186-187`), confirm only where Undo is impossible, and phone-first layouts.
- **D-11 is still open,** so no note may settle Save, New or header placement.

| # | Note | Target file | Model |
| --- | --- | --- | --- |
| N1 | History filters (FIND-1) | `docs/design/history-filters.md` | Opus |
| N2 | Tags, choreographers and sources (FIND-3, LIFE-5) | `docs/design/tags-and-people.md` | Opus |
| N3 | Add-to-program sheet (FIND-17) | `docs/design/add-to-program-sheet.md` | Sonnet |
| N4 | Bulk selection (FIND-8) | `docs/design/bulk-selection.md` | Sonnet |
| N5 | Selectable text on desktop (PLAT-17) | `docs/design/selectable-text.md` | Sonnet |

### N1 History filters (FIND-1)

**Questions:**

- **Venue scope for `CalledFilter`** (`filter_compiler.dart:280-298`). Does it match by venue record id, typed text, or both? This depends on B3's linking.
- **A recency scope:** "not called since <date>", or "in the last N weeks".
- **The picker:** should it default-exclude, or only flag, dances called at this program's venue?
- **Picker rows:** should they show when and where a dance was last called?

**Constraints:**

- Every scope must reuse the **one** called predicate that F5, F6 and B1 keep in lockstep: alternates, performed, event date, caller (#583).
- It must use B1's event-date rule.
- B14 already delivers the Last-called sort in the picker (FIND-1 option d).
- `search.md:160-161` (design table) gets updated.
- Filter state is session-only unless the note argues otherwise, which would need registry entries.

### N2 Tags, choreographers and sources (FIND-3, LIFE-5)

**Questions:**

- Rename with merge-on-collision; the natural key is the name (`TagRepository.idByName`).
- Delete with a count of affected dances, and Undo.
- A manager screen that also hosts tag colours (`tag_colors_screen.dart`).
- Choreographer and source merge: re-point `dance_authors` / `dance_sources`.
- **Merging two choreographers' private details:** email, location and notes are third-party data, so whose details win, and what is discarded?
- Should the purge GC spare rows the user has edited (LIFE-5 c)?
- Rewriting `default_import_tag_names` on rename.

**Constraints:**

- A merge on one device must converge on others: sync-spec §6.6 aliases, and the existing sync "Merge" choice (`settings.md:1158-1168`).
- Trash-policy (b) and B8.
- Cascade retention: sync-spec §3.1.

### N3 Add-to-program sheet (FIND-17)

**Questions:**

- Search.
- Hiding past or Performed programs, and the order.
- An "already contains" marker; the picker shows "in program ×N".
- Always offering "new program with this dance" (`add_to_program_sheet.dart:61-70`).

**Constraints:**

- Its Undo is fixed by F11 (GIG-19), so the note must not redesign it.
- Counts use F10's `plannedDanceCount`.
- Phone layout follows U7.

### N4 Bulk selection (FIND-8)

**Questions:**

- Select all, versus select visible.
- Pruning hidden selections when the search changes (`dance_list_screen.dart:1230-1248`).
- Keeping Group by category while selecting, to stop the reflow (`:2787-2793`).
- Which batch actions to add: delete (to the trash, with Undo), status, mixer, mixed level, add to program, source.

**Constraints:**

- Batch writes stay single-transaction, with transactional Undo (F14).
- Delete goes through the trash, which no longer protects references (B8).
- Coordinate with B14, which extracts Collection's controls.

### N5 Selectable text on desktop (PLAT-17)

**Questions:**

- **Surfaces:** dance detail figures, calling notes, the program summary. Is Perform excluded?
- **Gesture conflicts:** `SelectionArea` against tap-to-filter chips, long-press preview and swipe actions.
- What a copy contains: the rendered text in the active dialect, or canonical text?
- Desktop only, or phones too?
- Screen-reader behaviour.

**Constraints:**

- **B29 makes right-click open the ⋮ menu**, which conflicts with a selection context menu. The note must settle which wins, and where.
- The Guide's existing use (`user_guide_doc_view.dart`) is the precedent.

---

## Closed: no work

| Item | Decision | Why it leaves the backlog |
| --- | --- | --- |
| design-duplicates (FIND-9) | (c) drop | Not planned |
| design-provenance (INTAKE-8) | (c) drop | Not planned |
| design-second-instance (PLAT-18) | (c) drop | Not planned |
| design-seed (INTAKE-12) | (c) drop | Not planned; D-5 (a) adds the import card in U9 |
| design-settings-ia (PRES-13) | (c) drop | Not planned |
| design-tidy-filters (FIND-10) | (c) drop | Not planned |
| bare-hey (AUTH-13) | (c) accept as documented | No change |
| ratify-F5b, ratify-F8 (OUT-8), ratify-F6, ratify-F3 (AUTH-9) | ratified | No work |
| ratify-F16-ecd (INTAKE-15) | keep at launch | No work |
| D-7, D-8, D-12 | (a) each | Done in #2015 (merged) and #2013 (open) |
| D-1 | (b) | In flight on `claude/fix-discard-dialog-buttons` |
| D-2, D-5, D-6, D-9, D-10 | decided | In flight as U7, U9 and U12 |
| D-3, D-4 | decided | U4 and U5 above |

**Still undecided: D-11 (UX6-2).** The maintainer asked for renderings, which another agent is preparing. UX6-2 stays unplanned. Once D-11 is decided, it waits on **F11** (it edits the program editor and summary) and **D2** (it edits `ux.md`), as `ux-followups-intake.md` says. B29 also edits `ux.md` and app-bar actions, so land UX6-2 after B29, or coordinate the two.

---

## Sequencing

### Hot files

| File | In flight | Planned here, in landing order |
| --- | --- | --- |
| `program_editor_screen.dart` | F10 (opening), U7, F11 (queued), the D-1 branch | B4 → B5; B24 (autosave hunk); B29 (shortcuts); B14 only if the picker API changes (it shouldn't) |
| `program_summary_screen.dart` | F10, U7, F11 | B4 → B5; B22 (accent call) |
| `perform_program_screen.dart` | F10, F11 | B28 → B29 |
| `main.dart` | #2016 (one line) | B16 → B21; B4 (scope wrap); B29 (intents, menu bar) |
| The six ARBs | #2016, U7, U9, U12, D-1 | every branch except B1, B2, B13 and B30. Keys go beside related keys. U5b-2 lands in a quiet window. |
| `privacy/settings_registry.dart`, `field_registry.dart`, the generated `data-classification.md` | none | B30, B12, B19, B4, and B7 if it adds a column. **Serialize:** the regenerated doc conflicts every time. |
| `program_repository.dart` | none (F10 doesn't touch it) | B1 → B6 → B9 → B3 → B4 → B5; separate regions, but serialize the merges |
| `dance_repository.dart`, `filter_compiler.dart` | none | B7 (purge) → B12 → B13; B11 (`filter_compiler` only) |
| `dance_list_screen.dart` | U9 | B14 → B15; B16 (one snackbar site) |
| `app_bootstrap.dart` | #2016 | B25 |
| `custom_fields_screen.dart`, settings sub-lists | U9 | B8 → B10 |
| `docs/design/ux.md` | U10 (#2013, one line), D2 | B14, B15, B28, B29 (after D2), UX6-2 |
| `docs/user/settings.md` | D2 | many. Keep each edit to its own section; U4 last. |

### Waves

1. **W1, start now** (13 branches and 5 notes; run at most four at once, in this order):
   1. B7, B1, B16, B17, B23 and B26 (the Medium items).
   2. Then B12, B11, B31 and B30.
   3. Then B6, B20 and B2.
   4. As each predecessor lands: B8 → B9 after B7, B13 after B12, B27 after B26.
   5. N1–N5 run alongside; they are docs-only and need no full preflight.
2. **W2**, after #2016, U9 and the D-1 branch merge:
   - B25 and G1 (after #2016);
   - B3, B10, B14 → B15 (after U9);
   - B21 (after B16);
   - B18 and B19, once their questions are answered.
3. **W3**, after F10, F11 and U7 merge: B4 → B5, B22, B24 (also after B23), and B28 → B29 (B29 also after D2).
4. **W4**, after D2: U4 → U5a → U5b-1 → U5b-2. UX6-2 follows once D-11 is decided.

### Landing rules (to stop the merge races that broke main twice today)

Both breaks today were **semantic** races: each PR was green on its own base, and the combination wasn't. #2017 fixed a renamed `_figuresError` field that a parallel PR still referenced.

1. **One merge at a time.** Before merging, merge the current `main` into the PR head, and wait for CI to go green on **that exact commit**. A green run on a base that is now stale doesn't count.
2. **After every merge, every other ready PR re-runs on the new `main`** before it merges. This is cheapest when at most two PRs are ready at once.
3. **A PR that renames or removes a symbol, an ARB key or a settings key merges alone,** and the next merge waits for `main`'s own CI to finish.
4. **At most one open PR per hot-file group** in the table above. Others may be in progress, but not ready for review.
5. **At most four implementation sessions at once.**
   - A full `tools/preflight.py` peaks above 5 GB and takes a machine-wide lock, so a fifth session only queues.
   - Subagents use `--fast` or `--only`. Each owning session runs the full preflight once, on the final tree (`AGENTS.md`).
   - Per `session-cost.md`, each session costs resident context times turns. Four focused sessions cost less than eight that each rebase three times.
6. Run `python3 tools/ci/check_pr_review_gates.py all <PR> --closes <ISSUE>...` before each merge.

---

## Check list: every decided item, placed once

| Item | Placement | | Item | Placement |
| --- | --- | --- | --- | --- |
| INTAKE-2 | B17 | | GIG-7 | B3 |
| INTAKE-3 | B16 | | GIG-8 | B2 |
| INTAKE-5 | B16 | | FIND-7, PRES-15 | B14 |
| INTAKE-7 | B18 | | PRES-10 | B22 |
| FAIL-3 | B26 | | FIND-15 (PLAT-15) | B13 |
| LIFE-2 (+ note) | B7 | | PLAT-4 | B20 |
| FAIL-10 | B25 | | OUT-6 | B22 |
| FAIL-11 | B25 | | FIND-14 | B15 |
| FIND-6, FIND-13 | B12 | | PRES-11, LIFE-11 | B6 |
| LIFE-9, GIG-17 | B8 (guards), B9 (restore) | | PRES-12 | B22 |
| LIFE-4 | B9 | | AUTH-13 | Closed |
| LIFE-6 | B5 | | OUT-2 (+ note) | B19 |
| PLAT-9 | B28 | | GIG-2 | B1 |
| FAIL-8 | B24 | | AUTH-2 | B23 |
| PRES-1 | B30 | | AUTH-1 | B23 |
| GIG-12 (+ note) | B4 | | PLAT-12 | B31 |
| PLAT-10 | B28 | | PLAT-7 | B29 |
| PLAT-5, PLAT-6 | B27 | | FIND-4 | B11 |
| PLAT-13 | B31 | | FIND-5 | B11 |
| UX5-4a | B10 | | PLAT-8 | B29 |
| D-3 | U4 | | PLAT-3 | B21 |
| D-4 | U5a, U5b | | ratify-german-beats | G1 |
| design ×5 "now" | N1–N5 | | design ×6 "drop" | Closed |
