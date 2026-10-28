# Batch fix plan: October 2026 behaviour audit, remaining findings

Planning only. Nothing in the repo was changed, built or tested. Basis: the nine reports, `intake.md` (its verdicts and re-rated severities override the reports), AGENTS.md, `docs/dev/agents/session-cost.md`, and the three maintainer decisions made today.

## Summary

| Group | PRs | Finding IDs |
| --- | --- | --- |
| Fix branches | **19** (18 for findings + F5b, a feature the maintainer asked for) | 71 |
| Docs PRs | **2** | 8, plus the intake's "Missing" items |
| Needs design first | none | 12 |
| Blocked on an open decision | none | 34 |
| Won't fix | none | 0 |
| **Total** | **21** | **125** |

F5 and F5b carry the maintainer's refined alternates rule. F6 carries today's decision on received and duplicated programs, and has **one confirmation to get before dispatch** (G2). Without it, an implementer would have to guess (see "Gate questions").

**Waves** (details under "Sequencing"):

- **W1, start now** (no overlap with in-flight branches): D1, F1, F4, F7, F12, F15, F17, F18
- **W2, after the in-flight branches merge**: F2, F5, F9, F13, F14, F16
- **W3**: F3, F5b, F6, F8
- **W4**: F10
- **W5**: F11, D2

## How to read this

- **Severity** is the intake's re-rating where it gave one. "(unchecked)" means the intake neither cited nor sampled the finding, so the report's own rating stands. The intake's calibration says about a third of those are one step too high.
- **Size** counts changed lines, tests included: S < 150, M 150–400, L 400+. Every branch that adds UI text adds strings to `app_en.arb` and the five locale ARBs, following `docs/dev/localization.md`, plus a `changelog.d/<id>.json` fragment.
- **Model**: Sonnet 5.5 for contained, mechanical work; Opus 5.5 for cross-module or stateful work.
- **Conflict analysis against in-flight branches** is based on each branch's stated scope. None of them is checked out locally (only `main` and the audit branch exist), so I could not diff them. Re-check before each wave starts.
- **"My call"** marks an implementation choice I made, with the alternative I rejected. None of these is a maintainer decision.

## Gate questions raised by today's decisions

- **G1 (alternates): resolved by the maintainer's refinement.**
  - An alternate slot counts only when that slot is marked performed. A primary slot keeps the documented default (#583).
  - Predicate: `NOT is_alt OR performed_at IS NOT NULL`.
  - Alternates stamped by the old bulk paths look the same as hand marks, so they keep counting. Nothing in the data can tell them apart, so the plan includes no clean-up migration. That is my call; if the maintainer wants a clean-up, it is a separate question.
- **G2 (F6, received and duplicated programs).** This is not a new decision: it is a gap in how today's decision applies, and the branch cannot be written correctly without the answer. When, if ever, does a received or duplicated program start counting as the caller's history?
  - Under "never", a default-mode caller who builds every gig by duplicating last month's program would stop collecting history at all.
  - Options: (a) never; (b) once the caller marks a slot performed or sets status Performed; (c) once the caller sets or changes its event date.
  - **F6 must not be dispatched until this is answered.**

---

## Fix branches

### Overview

| # | Branch | Findings (folded dups) | Size | Model | Wave | Severity mix |
| --- | --- | --- | --- | --- | --- | --- |
| F1 | `fix/editor-unsaved-input` | AUTH-1, AUTH-2, AUTH-6 | M | Opus | W1 | 3 M |
| F2 | `fix/editor-snapshots-drafts` | AUTH-5, AUTH-10, AUTH-17 | M | Opus | W2 | 1 M, 2 L |
| F3 | `fix/editor-entry-paths` | AUTH-7, AUTH-8, AUTH-9, AUTH-11, LIFE-13 | L | Opus | W3 | 3 M, 2 L |
| F4 | `fix/group-notes-and-parser` | AUTH-3, AUTH-4, AUTH-12, AUTH-14, AUTH-16 | L | Opus | W1 | 3 M, 2 L |
| F5 | `fix/called-alternates-and-sort` | GIG-1, GIG-9, FIND-2 (GIG-5), PRES-4, + Missing: unused alternates | L | Opus | W2 | 2 M, 2 L |
| F5b | `feat/summary-performed-toggles` | none (maintainer-requested feature) | M | Sonnet | W3 | n/a |
| F6 | `fix/program-origin-history` | OUT-2, GIG-13, LIFE-7 | L | Opus | W3 (gated G2) | 3 M |
| F7 | `fix/event-dates` | GIG-2, PRES-3 (GIG-18, OUT-3), PLAT-12 | S | Sonnet | W1 | 3 M |
| F8 | `fix/export-files-and-pdfs` | OUT-4, OUT-8, OUT-9, OUT-10 | M | Sonnet | W3 | 1 M, 3 L |
| F9 | `fix/backup-version-safety` | OUT-5, FAIL-16 | M | Opus | W2 | 2 L |
| F10 | `fix/program-slot-resolution` | GIG-10, GIG-11 (LIFE-8, OUT-7), LIFE-10 | M | Opus | W3 | 1 M, 2 L |
| F11 | `fix/program-stale-state` | GIG-6, GIG-14, GIG-19, LIFE-14 | M | Opus | W4 | 4 L |
| F12 | `fix/program-import-resolve` | INTAKE-4, INTAKE-13, FAIL-2 (FAIL-6 scenario B) | L | Opus | W1 | 2 M, 1 L |
| F13 | `fix/import-review-followups` | INTAKE-6, INTAKE-9, INTAKE-14, INTAKE-16, FAIL-4, PLAT-2 | L | Opus | W2 | 3 M, 3 L |
| F14 | `fix/action-failures-visible` | FAIL-6, FAIL-15, FIND-11, LIFE-12 | M | Sonnet | W2 | 4 L |
| F15 | `fix/network-failure-classes` | FAIL-5, FAIL-9, FAIL-13 | M | Sonnet | W1 | 3 L |
| F16 | `fix/app-lifecycle-hooks` | FAIL-7, FAIL-12, PLAT-19, INTAKE-15 | M | Opus | W2 | 4 L |
| F17 | `fix/copy-and-platform-metadata` | PRES-2, GIG-15, FAIL-14, PLAT-8, PLAT-14, PLAT-16 | M | Sonnet | W1 | 6 L |
| F18 | `fix/render-and-sort-helpers` | PRES-7, AUTH-15, PRES-9, PRES-14, FIND-12, FIND-16 | M | Sonnet | W1 | 6 L |

Across the 71 IDs: 33 Medium and 38 Low. None is High: all three remaining Highs are in flight.

### F1 `fix/editor-unsaved-input`: Save, Back and Undo keep what's on screen

- **Findings:**
  - **AUTH-1 (decided today).** Give the composer's on-screen "Done" a new label that means "finished entering figures". A non-empty composer counts as unsaved, so Save and Back either commit the line or warn. The relabelled button must not silently discard non-empty text.
    - The label wording goes to the maintainer in review.
    - *My call:* Save submits the pending line through the same path as the keyboard's Enter, and Back includes it in the dirty check. The rejected alternative, warning on Save, adds a dialog for the common case of forgetting to press Enter.
  - **AUTH-2, decision-free parts only.** The beat Total excludes groups that won't be saved (~5 lines). A move-less row that has a note is kept as a custom figure (~10 lines, as #679 does for sides).
  - **AUTH-6.** `undo()` flushes the pending 500 ms text snapshot before stepping back, instead of cancelling it.
- **Main files:** `app/lib/src/widgets/figure_list_editor.dart` (composer `:753-758`, `:1129-1187`; Total `:852-866`), `app/lib/src/screens/dance_editor_screen.dart` (`_save` `:385-450`, back `:807`), `app/lib/src/screens/dance_editor/dance_editor_controller.dart` (`_figures` `:258-268`, `scheduleUndoPush` / `undo` `:877-899`), `app/lib/src/editor/figure_draft.dart` (`toFigure` `:340-356`), ARB (new label), `docs/user/authoring.md`.
- **Size:** M (~300). **Model:** Opus (editor state: dirty flag, undo timer).
- **Depends on:** nothing. Run it first among the editor branches (F2 and F3 rebase on it).
- **Severity:** AUTH-1 M, AUTH-2 M, AUTH-6 M.
- **Left open:** whether the Move box commits on blur (AUTH-1, structured mode), and a "N rows won't be saved" prompt (AUTH-2). The prompt would change the documented meanwhile rule. Both are listed under "Residual decisions".

### F2 `fix/editor-snapshots-drafts`: snapshots and drafts round-trip what the editor holds

- **Findings:**
  - **AUTH-5:** `FigureDraftSnapshot` captures `beatsTouched`, and the existing round-trip test asserts it.
  - **AUTH-10:**
    - Store a baseline (`updatedAt`) in the draft. On restore, say when the dance has changed since, and give the draft's age.
    - Give each new dance its own draft key instead of the shared `editor_draft:new`.
  - **AUTH-17:** canonicalize figure notes and custom text against the dialect they were rendered in, not the dialect at save time.
- **Main files:** `app/lib/src/editor/editor_snapshot.dart`, `editor_draft_codec.dart`, `dance_editor_controller.dart` (`applyRestoredDraft` `:677-860`, `updateDialect` `:466-471`, draft key `:454`, render/canonicalize `:97-126`), `dance_editor_screen.dart` (restore prompt), ARB, `docs/user/authoring.md`.
- **Size:** M (~250). **Model:** Opus.
- **Depends on:** F1, because both edit the undo and snapshot code in the controller.
- **Severity:** AUTH-10 M, AUTH-5 L, AUTH-17 L.
- **Check:** the draft-codec change must still read old drafts. If the draft format is a persisted settings key, confirm its privacy-registry entry is unaffected.

### F3 `fix/editor-entry-paths`: every way of making a row behaves the same

- **Findings:**
  - **AUTH-7:** apply Move defaults on the free-text and shorthand paths, but only to parameters the parser left at their defaults, so an explicit "half hey" is not overridden.
  - **AUTH-8:** pressing Enter in a Move box prefers an exact name, then a shorthand token, before falling back to the first substring match.
  - **AUTH-9:** retyping a row keeps its progression mark and note, the same as `_selectMove`.
    - *My call:* #1177 D2 decides that the row is *replaced*, and says nothing about losing the mark.
    - Rejected alternative: document the loss, which leaves the two paths disagreeing.
  - **AUTH-11:** a group's shared beats follow its sides until the caller types a count.
  - **LIFE-13:** the custom-figure delete dialog counts compound shorthands, as the switch dialog already does. Check what a dangling token now inserts.
- **Main files:** `dance_editor_controller.dart` (`replaceWithFreeTextFigures` / `placeShorthandDrafts` `:1432-1503`, Add meanwhile/modifier `:1377-1383`), `app/lib/src/editor/figure_draft.dart` (`fromFreeTextFigure` `:74-101`), `app/lib/src/widgets/move_autocomplete.dart` (`:142-146`, `:252-261`), `figure_list_editor.dart` (`_selectMove` `:1560-1592`, side editor `:3492-3515`), `shorthand_mapping_editor_screen.dart` (`:121-139`), `glossary/custom_figure_detail.dart` (`:177-203`), `user_figure_shorthands.dart`.
- **Size:** L (~420). **Model:** Opus.
- **Depends on:** F1, then F2. Serialize on the controller.
- **Severity:** AUTH-7 M (unchecked), AUTH-8 M (unchecked), AUTH-11 M, AUTH-9 L, LIFE-13 L (unchecked).

### F4 `fix/group-notes-and-parser`: what is typed is what is shown (core)

- **Findings:**
  - **AUTH-3 and AUTH-4**, which the intake says share a root:
    - `renderSummary` includes notes on meanwhile sides and modifier children.
    - `_noteIsLeftover` demotes a parse whose note contains a move name, a turn token or a count token. Today it only demotes a note that *is* one of those.
    - Test with the probe rows from the AUTH report, plus the two inputs the AUTH-4 verifier added.
  - **AUTH-16:** "N bars" counts behave as authoring.md says.
  - **AUTH-12:** the dance detail view shows the editor's existing beat-mismatch warning, using the same strings.
    - *My call:* Perform and print stay unchanged, because a warning on stage isn't actionable.
    - If the maintainer wants it in Perform, that is a follow-up.
  - **AUTH-14:**
    - Editing a custom figure's text clears `CustomOrigin.importGap`.
    - The guide lists every role word that gets rewritten, including "women".
- **Main files:** `packages/compendium_core/lib/src/.../renderer.dart` (`:255-269`, `:460-500`), `figure_front_end_fan_out.dart` (`:52-59`, `:136-179`), `imports/free_text_entry.dart`, `app/lib/src/widgets/figure_table.dart`, `screens/perform_card.dart` (child notes `:1026-1049`), `figure_list_editor.dart` (one line at `:2393`), `docs/user/authoring.md`.
- **Size:** L (~450). **Model:** Opus (parser semantics; #1612 scope).
- **Depends on:** nothing. It overlaps F1 only at `figure_list_editor.dart:2393`, a one-line hunk that rebases cleanly.
- **Severity:** AUTH-3 M, AUTH-4 M, AUTH-12 M (unchecked), AUTH-14 L, AUTH-16 L (unchecked).
- **Note:** **Re-check custom figures** uses the same classifier (`reparse_custom_figures.dart:176-188`). Add a test that an honest custom figure is no longer "upgraded" into a wrong reading.

### F5 `fix/called-alternates-and-sort`: one "called" predicate (maintainer's refined rule, plus #583)

- **Findings:**
  - **GIG-1 and the intake's Missing item "unused alternates raise Called ×N".** Apply the maintainer's refined rule:
    - **Counting (maintainer ruling).** An alternate slot counts toward its dance only when that slot is marked performed; a primary slot keeps the documented default (#583). Example: Hull's Victory is the alternate to Chorus Jig, and only Chorus Jig is marked performed, so only Chorus Jig's count goes up.
    - The predicate `NOT is_alt OR performed_at IS NOT NULL` applies to the default-mode count, history rows, last-called (including the sort below), venue repeat counts and half stats.
    - **Bulk stamping (maintainer ruling).** Mark all performed, in the editor and the summary, stamps primaries only.
    - **Status → Performed (inference, not a separate ruling).** It goes through the same bulk stamp, `stampDanceSlotsPerformed`, so it also stamps primaries only. The audit session inferred this from the maintainer's rule. Label it that way in the PR body and code comments, and don't present it as a maintainer decision.
  - **GIG-9:** the half-stats closer is the last primary, or a performed alternate under the same rule.
  - **FIND-2 (folds GIG-5).** The Last-called sort uses the same caller-scoped query and performed setting as the count (#583, "in lockstep").
    - It sorts on the same `COALESCE(performed_at, event_date, updated_at)` the history list already orders by, so it does not depend on the open "which date" question.
    - Optional: show the date on the row while that sort is active.
    - Correct `collection.md:52`.
  - **PRES-4:** expose the default caller through a notifier, so Collection re-boots when it changes locally or arrives by sync (`_preferences`).
- **Main files:** `packages/compendium_core/.../program_repository.dart` (`_programDerivedRows` `:980-993`, `_callingHistoryRows` `:1095-1109`, venue counts `:1133-1147`, stamping `:506-512`), `model/program.dart` (`:606-616`), `analysis/half_calling_stats.dart` (`:112-121`), `dance_repository.dart` (`_sortByLastCalled` `:2996-3047`), `app/.../program_editor_screen.dart` (mark-all `:2298-2301`), `program_summary_screen.dart` (`:862-866`), `dance_list_screen.dart` (boot `:384-424`, `:507-515`), `settings/defaults_section.dart` (`:629-637`), `main.dart` (`_preferences`), `docs/user/programs.md`, `settings.md`, `collection.md`.
- **Size:** L (~450). **Model:** Opus.
- **Depends on:** GIG-3+GIG-4 (in flight), because both edit `program_editor_screen.dart`, which has the mark-all code.
- **Severity:** GIG-1 M, FIND-2 M, GIG-9 L, PRES-4 L.
- **Docs in the same PR:** `programs.md` and `settings.md` explain that an alternate counts only once it is marked performed, and that the bulk marks skip alternates.

### F5b `feat/summary-performed-toggles`: mark individual dances from the program view (maintainer request)

This is a new feature the maintainer asked for, not an audit finding. It is a separate branch because adding it to F5 would take F5 to about 600 lines. It ships right after F5 because it makes F5's rule usable: an alternate counts only once it is marked, so callers need a quick way to mark one.

- **Scope:**
  - Each dance row in `program_summary_screen.dart` gets a per-row "performed" toggle, alternates included.
  - Today the summary only shows the performed state (`:733`) and offers Mark all performed (`:853-866`).
  - Reuse the builder's per-slot behaviour (`widgets/program_slot_list_editor.dart:291-310`):
    - marking stamps with `nextStoredTimestamp`;
    - clearing removes the stamp.
  - Offer Undo, consistent with the existing bulk mark's Undo.
  - Accessibility: give the toggle a semantic label naming the dance and its state, and keep it reachable without swipe.
  - Write through `updateAndReadBack` / `replaceIfUnchanged` (the intake's "stale copies" pattern), not by writing back the summary's loaded copy.
- **Main files:** `program_summary_screen.dart` (row rendering around `:733`, mark-all `:853-866`), possibly a small helper extracted from `program_slot_list_editor.dart`, ARB (toggle label and semantics, Undo text), `docs/user/programs.md`, a `changelog.d` fragment.
- **Size:** M (~200 with widget tests). **Model:** Sonnet. It is contained and reuses an existing behaviour.
- **Depends on:** F5 (same summary mark-all code and the counting rule), and so transitively on GIG-3+GIG-4 (in flight).
- **Severity:** n/a. It carries no audit ID.
- **Privacy:** it adds no persisted field, because `performed_at` already exists and is classified.

### F6 `fix/program-origin-history`: received and duplicated programs are not the caller's history (decided today)

- **Findings:**
  - **OUT-2, the calling-history part.** A program imported from another caller is marked as received. It arrives as Draft with its performed marks cleared, and is excluded from counts, history, last-called, venue counts and half stats.
  - **LIFE-7:** **Duplicate** clears the event date (the same reasoning as pay, `program.dart:566-567`) and marks the copy.
  - **GIG-13:** covered by the two above. Its third bullet, that a future or cancelled draft counts, is the documented default (#583) and is left alone.
- **Mechanism (my call):** a new nullable `programs` column recording origin (received or duplicated).
  - Alternatives rejected:
    - Reusing `status` can't work, because default mode counts any status.
    - Clearing the event date alone still adds +1 to "Called ×N".
  - Consequences:
    - a schema bump, so it can't ride a PATCH release;
    - a migration;
    - a privacy-registry entry on all three axes, in the same PR (subject: the caller; record the reason in `note`);
    - a sync-spec entry;
    - archive and backup support, which must satisfy F9's version ratchet.
  - The importer sets the flag on import; it is not read from the file.
  - Existing received programs cannot be identified after the fact, so the flag applies from this release on.
- **Main files:** `storage/tables.dart`, `database.dart` (migration and the version-history gate), `model/program.dart` (`duplicate` `:548-584`), `imports/compendium_archive_import.dart` (`buildArchivePrograms` `:71-74`, `:140-171`), `program_repository.dart` (the same queries F5 edits), `serialization/archive_entity_codec.dart`, `privacy/field_registry.dart` (and regenerate `docs/dev/data-classification.md`; never hand-edit it), `docs/design/storage.md`, sync spec, `docs/user/programs.md`, `sharing.md`.
- **Size:** L (~550). **Model:** Opus.
- **Depends on:**
  - G2 answered;
  - F5 (same queries);
  - F9 (version pattern and ratchet);
  - INTAKE-1 and OUT-1, both in flight, because both edit `compendium_archive_import.dart`.
- **Severity:** OUT-2 M, GIG-13 M, LIFE-7 M.
- **Left open:** whether pay, star rating and Perform dialect should travel in share files (the rest of OUT-2). See "Residual decisions". D1 meanwhile corrects the pay note in the registry.

### F7 `fix/event-dates`: one date formatter, with a year

- **Findings:**
  - **GIG-2, the display part only.** Render a stamp copied from `eventDate` as a calendar date, not through `toLocal()`. The intake says this is decision-free (the stamp was approved in #356).
  - **PRES-3 (folds GIG-18, OUT-3):** pass `formatEventDate` with `DateFormatScope` into the set-list text, program PDF, matrix PDF and calling history.
  - **PLAT-12:** the "System" date format includes the year.
    - *My call:* always show the year, because printed set lists outlive the season.
    - Rejected alternative: show the year only when it differs from the current one.
- **Main files:** `app/lib/src/screens/dance_detail/calling_history_section.dart` (`:390-399`, `:424-427`), `widgets/program_export_menu.dart` (`:133-134`, `:176`, `:541`), `program_editor_screen.dart` (one line at `:3330`), `utils/regional_formats.dart` (`:190-201`), test `calling_history_section_test.dart` (add a stamp at eventDate midnight, run under a non-UTC TZ), `docs/user/settings.md`.
- **Size:** S (~140). **Model:** Sonnet.
- **Depends on:** nothing. It touches one line of `program_editor_screen.dart`, far from the GIG-3/4 hunks.
- **Severity:** GIG-2 M, PRES-3 M, PLAT-12 M.
- **Left open:** which date a call carries (tap time or event date for per-slot and mark-all stamps, and re-dating), and whether "System" follows the app language or the device region. Both are under "Residual decisions".

### F8 `fix/export-files-and-pdfs`: paper, pages and names

- **Findings:**
  - **OUT-4:** thread the print dialog's `format` through all three `layoutPdf` sites, using `format.landscape` for the matrix.
  - **OUT-9:** add page "x of y" and a running title, and repeat the matrix header row.
  - **OUT-10:** a dance with notes or a walkthrough but no structured figures still gets its card (`sharing.md:104-107`).
  - **OUT-8:**
    - Date backup file names in local time.
    - Keep Unicode letters in share file names and strip trailing `_`.
    - Give the matrix PDF its own job name.
    - *My call:* add the event date to program file names.
- **Main files:** `widgets/dance_export_actions.dart` (`:229`), `program_export_menu.dart` (`:231-233`, `:295`, `:535-536`), `program_editor_screen.dart` (`_exportMatrixPdf` `:3319-3322`), `export/dance_pdf.dart`, `program_pdf.dart`, `program_matrix_pdf.dart`, `dance_share_bundle.dart` (`:98-105`), `program_share_bundle.dart` (`:269-280`), `data/backup_service.dart` (`:805-808`).
- **Size:** M (~320). **Model:** Sonnet.
- **Depends on:** F7, because both edit the same export-menu and matrix call sites, and FAIL-1+PLAT-1, which is in flight and may touch `backup_service.dart`.
- **Severity:** OUT-4 M, OUT-8 L (unchecked), OUT-9 L, OUT-10 L.

### F9 `fix/backup-version-safety`: an older build refuses what it would silently drop

- **Findings:**
  - **OUT-5:**
    - Bump the **backup envelope** version when any program has pay or a Perform dialect.
    - The intake recommends this over an archive bump, which would make 0.7.0 and older refuse share files (the #1885 trade-off).
    - Add a ratchet that fails when `archiveDanceToJson` or `archiveProgramToJson` gains a key without a matching version case, then audit the other "only when set" keys.
  - **FAIL-16:**
    - Before the in-place macOS write, check that free space covers the payload, and refuse with a disk-full message.
    - Document the in-place write in `backup-portability.md`.
- **Main files:** `data/backup_document.dart` (`:20-22`), `backup_service.dart`, `serialization/archive_entity_codec.dart` (`:234-241`), `compendium_archive.dart` (`requiredSchemaVersion` `:147-177`), `data/backup_io.dart` (`writeDesktopBackup` `:287-310`), a new `tools/ci/` check, `docs/user/backup-portability.md`.
- **Size:** M (~220). **Model:** Opus (version-compatibility semantics).
- **Depends on:** FAIL-1+PLAT-1 (in flight; same `backup_io.dart` and `backup-portability.md`). F6 builds on it.
- **Severity:** OUT-5 L, FAIL-16 L (unchecked).

### F10 `fix/program-slot-resolution`: every program surface resolves a slot the same way

- **Findings:**
  - **GIG-11 (folds LIFE-8 and OUT-7):**
    - The editor slot list, the matrix (with figures), the summary and the set-list text/PDF all resolve trashed dances through `resolveDeletedSlotDances`, as Perform does.
    - A program share includes a trashed dance rather than silently omitting it.
  - **GIG-10:**
    - One count, `plannedDanceCount`, on every surface, labelled as dances.
    - The emailed and printed set list numbers dances only.
    - *My call on the waltz:* keep `plannedDanceCount` as the single definition, because programs.md is silent on free-text non-break slots.
    - *My call on breaks:* breaks are unnumbered, because "5. Break" confuses a band.
  - **LIFE-10:** cutting or moving a primary promotes its first alternate, instead of re-parenting the alternates to the slot above.
    - *My call.* Rejected alternative: a confirmation dialog on every cut.
- **Main files:** `program_editor_screen.dart` (lookup `:1799-1834`, `_removeSlot` `:2218-2224`, matrix rows `:3167-3181`, header `:3385`), `widgets/program_slot_list_editor.dart` (`:146-149`), `program_summary_screen.dart` (`:474-479`, `:691-693`, `:1031-1060`), `program_list_tile.dart`, `add_to_program_sheet.dart` (`:107-116`), `perform_program_screen.dart` (`:641-648`), `export/program_text.dart` (`:88-116`, `:221-222`), `program_share_bundle.dart` (`:118-123`), `model/program.dart`.
- **Size:** M (~380). **Model:** Opus (the 4,213-line editor; alternate-group invariants).
- **Depends on:** GIG-3+GIG-4 (in flight), F5 (same editor and summary files) and F5b (summary rows).
- **Severity:** GIG-10 M (unchecked), GIG-11 L, LIFE-10 L.

### F11 `fix/program-stale-state`: no stale program copy overwrites newer data

This is the intake's "stale copies overwrite newer data" pattern, applied to what GIG-3/4 leaves.

- **Findings:**
  - **GIG-6:** Perform adjustments write with `replaceIfUnchanged` against the program Perform started from, and tell the caller when the program changed underneath them.
  - **GIG-19:** add-to-program Undo uses compare-and-replace. This also fixes FIND-17's Undo bullet.
  - **LIFE-14:** deleting a program from the editor flushes or offers to save pending edits first.
  - **GIG-14:** resume state lives in the shell, keyed by program id, so it survives a rotation across the breakpoint.
- **Main files:** `perform_program_screen.dart` (`:213`), `program_summary_screen.dart` (`:609-647`), `program_editor_screen.dart` (`:1943-1951`, `:2796-2823`), `widgets/add_to_program_sheet.dart` (`:233-241`), `programs_shell.dart` (`:71-117`).
- **Size:** M (~330). **Model:** Opus.
- **Depends on:**
  - GIG-3+GIG-4: GIG-6 extends exactly the Perform-persist code that branch rewrites;
  - F10, to serialize edits to the editor, the summary and the sheet.
- **Severity:** GIG-6 L, GIG-14 L, GIG-19 L, LIFE-14 L.

### F12 `fix/program-import-resolve`: program imports keep Undo's promise and report offline honestly

- **Findings:**
  - **INTAKE-4 (folds FAIL-6 scenario B):**
    - Track the dances created during resolve. Remove them on Undo, and when the user backs out without creating the program (`programs.md:118`, `:63`).
    - If the ContraDB program write fails, roll back the dances it imported.
    - Default tags stay off: that is deliberate (#1476).
  - **INTAKE-13, decision-free part:** the program title-list lookup requires figures, as the Collection title-list import does (`imports.md:204-207`). The other differences, review versus automatic import and the sources searched, follow #797 and stay.
  - **FAIL-2:**
    - Keep `unreachable` separate from a miss, and stop after the first connection failure, as `title_list_import.dart` does.
    - Show progress and a Cancel, and stop the loop when the screen is popped.
    - The ContraDB program path stops the same way and does not create the program after the screen has gone. That last point is from the FAIL report's out-of-scope notes.
- **Main files:** `screens/plaintext_program_import_screen.dart` (`:177-259`, `:368-370`, `:490-499`), `contradb_program_import_screen.dart` (`:366-468`), `data/program_import_online_resolver.dart` (`:196-302`), `contradb_program_import.dart` (`:146-170`), `online_title_lookup.dart`, ARB, `docs/user/programs.md`.
- **Size:** L (~430). **Model:** Opus.
- **Depends on:** nothing in flight. F14 later changes `showUndoSnackBar`'s callback type, and this branch's Undo closures are already `async`.
- **Severity:** INTAKE-4 M, FAIL-2 M, INTAKE-13 L.

### F13 `fix/import-review-followups`: one review screen, honest outcomes

- **Findings:**
  - **INTAKE-6:**
    - The shared-bundle commit applies default import tags to dances it creates (`settings.md:392-395`, "from the import screen").
    - The result says created, re-imported and linked separately, instead of one sum of every entity.
  - **INTAKE-9:** hide **Import and edit** on `.USR` rows, as shared bundles already do. This also closes INTAKE-1 scenario C.
    - **Check first:** if the in-flight INTAKE-1 branch already does this, INTAKE-9 shrinks to a test.
  - **INTAKE-14:** pass `publishedCollectionService` from Settings → Import….
  - **INTAKE-16:** give shorthand seeding an Undo.
  - **FAIL-4:** `_chooseFile` and `_chooseUsrFile` catch encoding and file-system errors and say so, as the restore picker does.
  - **PLAT-2, minimum option (b):** intake recognises a `backupContainer` root and says "This is a backup. Use Settings › General › Restore", instead of "no dances".
- **Main files:** `screens/import_review_screen.dart` (`:632-693`, `:1404-1460`, `:1751-1775`, `:1932-1953`, `:2081-2094`, `:3523-3539`), `settings/general_section.dart` (`:519-528`), `data/archive_intake_service.dart` (`:226-230`), `main.dart` (`:1143-1177`), ARB, `docs/user/imports.md`.
- **Size:** L (~450). **Model:** Opus (commit routing).
- **Depends on:**
  - OUT-1 (in flight): it rewrites `_showSharedBundleUndo` `:2081-2095`, exactly the lines INTAKE-6 changes;
  - INTAKE-1 (in flight): Import and edit on `.USR`.
- **Severity:** INTAKE-6 M, INTAKE-9 M, PLAT-2 M, INTAKE-14 L, INTAKE-16 L, FAIL-4 L.

### F14 `fix/action-failures-visible`: user actions fail visibly and write atomically

- **Findings:**
  - **FAIL-6, scenario A** (B is folded into F12):
    - `showUndoSnackBar` takes an async callback and shows "Couldn't undo" on failure.
    - The intake notes one undo-failed string already exists; reuse it.
  - **FAIL-15:** Clear log catches and reports its failures.
  - **FIND-11:**
    - The batch level, rating, tunes and custom-field writes get the tag path's catch.
    - Their Undo becomes transactional.
    - The custom-field Undo restores only the field it changed.
    - The batch dialog gets "＋ new option".
  - **LIFE-12:** dance duplicate becomes one write that includes the "(copy)" title, keeps `transitive`, and maintains reverse links.
- **Main files:** `utils/undo_snack_bar.dart`, the `onUndo` call sites, `settings/diagnostics_section.dart` (`:222-230`), `dance_list_screen.dart` (`:1285-1818`, `:2276-2287`), `batch_custom_field_dialog.dart`, `model/dance.dart` (`:352-402`), `dance_repository.dart` (`duplicate`), `related_dance_links.dart`.
- **Size:** M (~350). **Model:** Sonnet.
- **Depends on:** OUT-1 (in flight), because `import_review_screen.dart:2096` is an `onUndo` site. Land it after F13 if that site needs editing.
- **Severity:** FAIL-6 L, FAIL-15 L, FIND-11 L (unchecked), LIFE-12 L (unchecked).

### F15 `fix/network-failure-classes`: say what actually failed (network features)

The intake's narrowed step 4, minus FAIL-2 (F12) and FAIL-3 (blocked).

- **Findings:**
  - **FAIL-5:**
    - Classify a write or flush failure as disk-full or permission, reusing `classifySnapshotFailure`, and an HTTP status as a server error.
    - Log the outcome message to Diagnostics.
  - **FAIL-9:**
    - Map the nine failure types to "offline", "needs a newer app" and "unavailable".
    - Add a Retry, and log the failures.
  - **FAIL-13:** the online-preview loader can be cancelled.
- **Main files:** `update/artifact_downloader.dart`, `update_controller.dart` (`:406-411`, `:611-622`), `update_failure_labels.dart`, `published_collections/published_collection_service.dart`, `screens/published_collection_catalog_screen.dart` (`:89-148`, `:242-247`), `dance_list_screen.dart` (`:1057-1065`), `data/migration_guard.dart` (reuse only), ARB.
- **Size:** M (~280). **Model:** Sonnet.
- **Depends on:** nothing.
- **Severity:** FAIL-5 L, FAIL-9 L, FAIL-13 L (unchecked).

### F16 `fix/app-lifecycle-hooks`: housekeeping never blocks opening; closing never hangs

- **Findings:**
  - **FAIL-7:** catch and log a failing startup purge, as the seed step does. Test it with a purge that throws.
  - **FAIL-12:** bound the wait for an in-flight sync pass on close, and show that the app is closing. Flush editor drafts before waiting on sync, not after.
  - **PLAT-19:** an `AppLifecycleListener` flushes editor drafts on pause and hide on mobile.
  - **INTAKE-15:**
    - The ECD conversion offers Undo, and is documented in `imports.md` and `settings.md`.
    - Moving the prompt to just after the import is a design question and is left out.
- **Main files:** `app/lib/main.dart` (`:187-191`, `:1033-1046`, `:1555-1581`, `:2159-2350`), `data/window_service.dart`, `editor_draft_shutdown_scope.dart`, `sync/sync_coordinator.dart` (`dispose`, read only unless a timeout hook is needed), ARB, docs.
- **Size:** M (~320). **Model:** Opus (shutdown ordering against the sync writer).
- **Depends on:** LIFE-1+LIFE-3 (in flight), which may touch the startup purge lines that FAIL-7 wraps.
- **Severity:** FAIL-7 L, FAIL-12 L, PLAT-19 L, INTAKE-15 L.

### F17 `fix/copy-and-platform-metadata`: text the app shows must be true on this platform

- **Findings:**
  - **PRES-2:** "Custom themes are saved on this device" is false. Fix the string and `settings.md:213-214`. The intake says this is a bug whatever PRES-1 decides.
  - **GIG-15:** single-dance Perform's exit dialog gets its own body, without the resume promise.
  - **FAIL-14:**
    - Replace "recovered" in the crash fallback.
    - The bootstrap screen's Copy details scrubs the stack through `CrashRedactor`, as the fallback does.
  - **PLAT-8, the part the report says needs no decision:** copyright and publisher strings in `AppInfo.xcconfig` and `Runner.rc`, matching the Inno script and AGPL-3.0. The menu bar itself is a residual decision.
  - **PLAT-14:**
    - Derive the undo, redo and search tooltip shortcuts per platform, as the rail button does.
    - Document Alt+↑/↓ and Ctrl/Cmd+Enter in `docs/user`.
  - **PLAT-16:** declare locales for the OS: `CFBundleLocalizations` on macOS, the Inno `[Languages]` section on Windows, and `localeConfig` on Android.
- **Main files:** ARB (en plus five locales), `screens/perform_dance_screen.dart` (`:285-286`), `diagnostics/crash_fallback.dart`, `widgets/app_bootstrap.dart` (`:359-361`), `app/macos/Runner/Configs/AppInfo.xcconfig`, `app/macos/Runner/Info.plist`, `app/windows/runner/Runner.rc`, `packaging/windows/CallersCompendium.iss`, `AndroidManifest.xml` (+ `res/xml/locales_config.xml`), `dance_editor_screen.dart` (`:861`, `:872`), `dance_list_screen.dart` (`:1915`), `programs_list_screen.dart` (`:489`), `docs/user/settings.md`, `authoring.md`.
- **Size:** M (~220, wide but shallow). **Model:** Sonnet.
- **Depends on:** nothing.
- **Severity:** all 6 L. PRES-2, PLAT-8 and PLAT-16 were checked; GIG-15, FAIL-14 and PLAT-14 are unchecked.

### F18 `fix/render-and-sort-helpers`: call sites use the shared helper

- **Findings:**
  - **PRES-7 and AUTH-15:**
    - Shorthand list previews, user-figure shorthand tiles, the import-review figure diff, sync-conflict shorthand values, `import_shorthand_seed_screen`, and the compound editor use `renderSummary` with the display scopes.
    - Today they use `render`.
  - **PRES-9:** Programs list title sort uses `titleSortKey`.
  - **FIND-12:**
    - The command palette folds diacritics.
    - It ranks exact and prefix matches before other substring matches, and ignores leading articles.
  - **FIND-16:** the canonical search branch does not match the internal `role1s`/`role2s` tokens in figure text.
  - **PRES-14:** the reduce-motion override reaches `MaterialApp` through `MediaQuery(disableAnimations:)` and `themeAnimationStyle`. Gate `program_matrix_table.dart:626`.
- **Main files:** `shorthand_mappings_screen.dart` (`:89-93`, `:586-587`), `figure_diff.dart` (`:300-315`), `sync_conflict_details.dart` (`:678-680`), `import_shorthand_seed_screen.dart` (`:82`), `compound_editor_screen.dart` (`:1609`), `programs_list_screen.dart` (`:330-334`), `command_palette.dart` (`:144-161`), `search/filter_compiler.dart` (`:335-344`), `main.dart` (`:2527-2556`), `program_matrix_table.dart`.
- **Size:** M (~260). **Model:** Sonnet.
- **Depends on:** nothing.
- **Severity:** all 6 L. PRES-14 is unchecked.

---

## Docs PRs

### D1 `docs/registry-note-and-contradicting-comments` (W1, S, Sonnet)

The intake's "Missing" items, ranked #9: the registry is the privacy boundary, so fix it promptly. No finding IDs.

- **Privacy-registry note on program pay** (`packages/compendium_core/lib/src/privacy/field_registry.dart:575-585`).
  - Today the note justifies `shareable` only as travel to the caller's own devices and archive. Share files carry pay to other people.
  - Correct the note to describe actual egress, and keep the classification until the rest of OUT-2 is decided.
  - Regenerate `docs/dev/data-classification.md` with its tool; never hand-edit it.
- **The four comments that contradict their sources:**
  - `update_signature.dart:4-5` ("never strands an install") contradicts `releasing.md`.
  - `venue_repository.dart:239-243` says a deleted venue is restored with its program; no code does that.
  - **ADR-004** gives text scale as its `deviceScoped` example, while the registry has `perform_text_scale` as `deviceLocal`.
    - *My call:* the registry is right, because the entry states its reason and PRES checked it as fine.
    - Fix the ADR with an erratum note rather than rewriting the accepted text.
  - `backup-portability.md` says the progress indicator closes "as soon as the share sheet opens".
    - **Coordinate:** the in-flight FAIL-1 branch corrects backup-portability.md. If it fixes this sentence, drop it here.

### D2 `docs/user-guide-drift` (W4, M, Sonnet)

The intake's docs batch (#15). Each finding's behaviour is decided or documented; only the prose is wrong.

- **PRES-5** (decided by the owner on #352; PR #392):
  - Add the swipe exception to `settings.md:67-68` and `accessibility.md:164-166`.
  - Fix the two ⋮ comments (`programs_list_screen.dart:760-762`, `dance_list_screen.dart:2904-2906`).
- **PRES-6:** `perform.md:49-50` "quick look" wording. Both persistence models are intended (#1554).
- **FIND-4:** `search.md:525-526` and `dialects.md:52-54` scope "dialect-aware" claims to role words.
- **FIND-5:** `collection.md:102-104` "Type any words" describes exact-phrase matching for 3+ characters (#1005).
- **PLAT-3:** `faq.md:125` and `sharing.md:200` say which platforms open a received file directly.
- **PLAT-7:** `ux.md:24` and `ux-modernization.md` UX-5 stop claiming a complete desktop keyboard map, and list what exists.
- **GIG-20:** `ux.md` §5 (no swipe in Perform) and §2 (history comes from any program by default).
- **INTAKE-11:** `getting-started.md:213-228`:
  - remove the "side-by-side" review claim;
  - add Caller's Companion;
  - use the real button name, **Import dances**.

D2 goes last because F5, F6 and F10 also edit `programs.md` and `collection.md`. The conflicts would be trivial, but there is no reason to have them.

---

## Needs design first (no PR count)

These are missing features or product design, not defects. Each needs a design note or issue before an agent can be scoped.

| ID | Severity | Design question |
| --- | --- | --- |
| FIND-1 | M | Venue and recency scopes for `CalledFilter`; calling-history aids and sort in the picker. Intake: a missing feature, no open issue. |
| FIND-3 | M | Tag rename, merge and delete, plus a manager screen. Any rename must also rewrite `default_import_tag_names`. |
| LIFE-5 | M | The same for choreographers and sources, and whether the purge GC may erase edited rows. Design together with FIND-3. |
| FIND-9 | M | A duplicate finder, merge (re-point slots, union tags), Duplicate-as-variation linking, authors in the related-dance picker. |
| FIND-8 | M (unchecked) | Bulk selection: Select all or visible, pruning hidden selections, and which batch actions to add (delete, status, mixer, add to program). |
| FIND-10 | M (unchecked) | Tidy-up filters: "no level" and "unrated" chips, level ranges (`LevelOp.lte`), Rating sort (the core already has `SearchSort.rating`). |
| FIND-17 | L (unchecked) | Add-to-program sheet: search, hiding past programs, "already contains", "new program" always offered. Its Undo bullet is fixed by F11 (GIG-19). |
| INTAKE-8 | L | Multi-valued provenance; keeping the original source and licence on received dances; an import-source facet. |
| INTAKE-12 | L (unchecked) | What the seed dance is (a marked sample?). Design with UX audit batch 5, which also covers the seed. |
| PRES-13 | L | Settings information architecture: card fields and filters under Defaults, the default-caller effect, the split figure-display settings, a stage-theme row. |
| PLAT-17 | L (unchecked) | Selectable dance and program text on desktop. |
| PLAT-18 | L (unchecked) | What a second instance shows when it can't reach the first. It exits before any UI exists. |

## Blocked on an open maintainer decision

Each decision is quoted from the report or intake. No decision here has been made, and I have not assumed any.

| Decision needed | IDs | Severity | Notes |
| --- | --- | --- | --- |
| Does the trash protect referenced records? Venue, custom field, level and choice-option guards disagree; restore doesn't revive the venue | LIFE-9, LIFE-4, GIG-17 | L, L, L | One policy unlocks all three. LIFE-4's silent Duplicate failure (an uncaught `StateError`) is decision-free and could ride F14 if wanted. |
| What does each program status mean? | GIG-12 | L | Stamping on the transition is maintainer-merged (#390). Open: does mark-all set Performed, does Draft unstamp, does the UI say so? |
| Text venue vs venue record in history | GIG-7 | L | Merge by label, or offer linking when venue records are switched on. |
| Are dances either side of a break or waltz back-to-back? | GIG-8 | L | #582 didn't consider breaks. |
| Deleting a program removes its calling history | LIFE-6 | L | Say so, add Archive, or snapshot. |
| "Permanently delete" on a synced tombstone | LIFE-2 | M | The UI-honesty fix needs a wording decision (intake #11). Also wait for LIFE-1/3 to merge, since they share `recently_deleted_screen.dart`. |
| Share-file custom-field matching | INTAKE-2 | M | Intake: about 20–25 lines "once the maintainer agrees"; includes the "Card"/"card" trigger. |
| ContraDB program import: link an identical dance per #685? | INTAKE-3 | M | No per-dance prompt is ruled (#797); the linking is not. |
| Online single import: prompt on a hand-entered match, Undo | INTAKE-5 | M | The current behaviour is pinned by a test as intended. |
| Batch Re-import blast radius | INTAKE-7 | M | Deferred as "Q-I1 (b) later" in #1480. |
| Dance-card fields (sources, hook, links) | OUT-6 | L (unchecked) | Add to the picker, or document choreography-only. |
| Which settings sync, and disclosure | PRES-1 | L | ADR-004 says settings sync. Exceptions and disclosure are open. |
| Decimal turns in exports | PRES-10 | L | Honour, or document the exclusion. |
| Program dialect beyond Perform; rename cascade | PRES-11 | L (unchecked) | LIFE-11 (documented) is related. |
| Formation colours in set lists | PRES-12 | L (unchecked) | |
| Program picker parity with Collection (Search in, sort, online scopes, card fields) | FIND-7, PRES-15 | L, L (unchecked) | Intake: FIND-7 ⊃ PRES-15. Or narrow `programs.md:135-138`. |
| What the search bar indexes; what "Searchable" means | FIND-6, FIND-13 | M (unchecked), L (unchecked) | The boolean "true"/"false" indexing in FIND-13 is a plain bug, but the fix depends on the indexing decision. |
| Tag-chip tap: add to filters, or Undo | FIND-14 | L (unchecked) | |
| Locale-aware sorting, article lists, author surname | FIND-15 (folds PLAT-15) | L | |
| Bare "hey": assumed markers | AUTH-13 | L (unchecked) | Options (a), (b) and (c) are in the report. |
| Manual update check: "couldn't check" wording | FAIL-3 | M | Intake: open. Also covers the future manifest-schema stranding risk. |
| Autosave failures: marker, log, or both | FAIL-8 | L | Logging (option b) would fit F16 once chosen. |
| Diagnostics: which typed messages survive scrubbing; export from the startup failure screen | FAIL-10 | M (unchecked) | |
| Terminal startup screens: "Check again", Releases link | FAIL-11 | M (unchecked) | The ADR keeps them terminal. |
| Android `.ccshare` MIME handling | PLAT-4 | L | Also needs a device check (intake: unverifiable here). |
| Updater awareness of store and portable installs | PLAT-5, PLAT-6 | L, L | The intake says to fix them together. |
| Perform full screen, or reword "fills the screen" | PLAT-9 | L | |
| Perform ↑/↓: scroll the card or change slot | PLAT-10 | L | |
| Guide in non-English locales: notice or translate | PLAT-13 | L | |

### Residual decisions inside planned findings (not extra IDs)

The decision-free part of each finding below is planned. These parts are not.

- **AUTH-1:** does the Move box commit on blur? (F1)
- **AUTH-2:** should Save show a "N rows won't be saved" prompt? It changes a documented rule. (F1)
- **GIG-2:** which date a call carries (tap time or event date), and what happens to stamps when a program is re-dated. Intake open question (b). (F7)
- **OUT-2:** do pay, star rating and Perform dialect travel in share files? D1 corrects the registry note meanwhile. (F6)
- **FIND-4:** should search learn a dialect's move names, as the editor does? (D2 fixes the claim.)
- **FIND-5:** cross-field multi-word search, and Best match for longer queries. (D2)
- **PLAT-3:** register `.ccshare` on Windows and Linux? (D2)
- **PLAT-7:** which desktop shortcuts to add. (D2)
- **PLAT-8:** a `PlatformMenuBar`, or wire up Cmd-, and Help. (F17)
- **PLAT-12:** should "System" follow the app language or the device region? (F7)

---

## Sequencing and conflicts

### Hot files

| File | In-flight branch | Planned branches, in landing order |
| --- | --- | --- |
| `program_editor_screen.dart` (4,213 lines) | GIG-3+GIG-4 | F7 (1 line, W1) → F5 → F8 → F10 → F11 |
| `program_summary_screen.dart` | GIG-3+GIG-4 (possibly) | F5 → F5b → F10 → F11 |
| `import_review_screen.dart` (4,001 lines) | OUT-1 (shared-result snackbar), INTAKE-1 (.USR Import and edit) | F13 → F14 (if it touches `:2096`) |
| `compendium_archive_import.dart` | INTAKE-1, OUT-1 | F6 |
| `backup_io.dart`, `backup-portability.md` | FAIL-1+PLAT-1 | F9, D1 (one sentence), F8 (`backup_service.dart`) |
| `recently_deleted_screen.dart`, repo purges | LIFE-1+LIFE-3 | none planned; LIFE-2 (blocked) must follow them |
| `main.dart` | LIFE-3 (startup sweep, possibly) | F18 (MaterialApp), F13 (incoming file), F5 (`_preferences`), F16 (sweep, shutdown, lifecycle) |
| `program_repository.dart` | LIFE-1/3 (purge only) | F5 → F6 (same queries) |
| `dance_editor_controller.dart`, `figure_list_editor.dart` | none | F1 → F2 → F3; F4 one line |
| `dance_list_screen.dart` | none | F15, F17 (one line each) → F5 → F14; separate hunks |
| `add_to_program_sheet.dart`, `perform_program_screen.dart` | none | F10 → F11 |
| ARB files (6) | most in-flight branches | nearly every branch |

**ARB files are the most likely source of repeated rebase work.** Place each new key next to related keys, never at the end of the file, so parallel branches don't all collide on the last lines.

### Waves

1. **W1, now (8 PRs):** D1, F1, F4, F7, F12, F15, F17, F18. None touches an in-flight file except F7's one distant line in `program_editor_screen.dart`, which rebases cleanly.
2. **W2, after the in-flight branches merge (6):**
   - F5 needs GIG-3/4.
   - F2 needs F1.
   - F9 needs FAIL-1.
   - F13 needs OUT-1 and INTAKE-1.
   - F14 needs OUT-1.
   - F16 needs LIFE-1/3.
3. **W3 (4):**
   - F3 after F2.
   - F5b right after F5.
   - F6 after F5, F9 and G2.
   - F8 after F7 and FAIL-1.
4. **W4 (1):** F10 after F5b.
5. **W5 (2):** F11 after F10; D2 last.

Each subagent verifies its own edits with `tools/preflight.py --fast` or `--only`. The session that owns each PR runs the full preflight once, on the final tree. A full run takes a machine-wide lock, so W1's eight full runs will queue; stagger dispatch.

---

## Check list: all 125 IDs, each placed once

| ID | Placement | | ID | Placement | | ID | Placement |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AUTH-1 | F1 | | GIG-13 | F6 | | PRES-5 | D2 |
| AUTH-2 | F1 | | GIG-14 | F11 | | PRES-6 | D2 |
| AUTH-3 | F4 | | GIG-15 | F17 | | PRES-7 | F18 |
| AUTH-4 | F4 | | GIG-17 | Blocked | | PRES-9 | F18 |
| AUTH-5 | F2 | | GIG-19 | F11 | | PRES-10 | Blocked |
| AUTH-6 | F1 | | GIG-20 | D2 | | PRES-11 | Blocked |
| AUTH-7 | F3 | | INTAKE-2 | Blocked | | PRES-12 | Blocked |
| AUTH-8 | F3 | | INTAKE-3 | Blocked | | PRES-13 | Design |
| AUTH-9 | F3 | | INTAKE-4 | F12 | | PRES-14 | F18 |
| AUTH-10 | F2 | | INTAKE-5 | Blocked | | PRES-15 | Blocked |
| AUTH-11 | F3 | | INTAKE-6 | F13 | | FIND-1 | Design |
| AUTH-12 | F4 | | INTAKE-7 | Blocked | | FIND-2 | F5 |
| AUTH-13 | Blocked | | INTAKE-8 | Design | | FIND-3 | Design |
| AUTH-14 | F4 | | INTAKE-9 | F13 | | FIND-4 | D2 |
| AUTH-15 | F18 | | INTAKE-11 | D2 | | FIND-5 | D2 |
| AUTH-16 | F4 | | INTAKE-12 | Design | | FIND-6 | Blocked |
| AUTH-17 | F2 | | INTAKE-13 | F12 | | FIND-7 | Blocked |
| GIG-1 | F5 | | INTAKE-14 | F13 | | FIND-8 | Design |
| GIG-2 | F7 | | INTAKE-15 | F16 | | FIND-9 | Design |
| GIG-6 | F11 | | INTAKE-16 | F13 | | FIND-10 | Design |
| GIG-7 | Blocked | | OUT-2 | F6 | | FIND-11 | F14 |
| GIG-8 | Blocked | | OUT-4 | F8 | | FIND-12 | F18 |
| GIG-9 | F5 | | OUT-5 | F9 | | FIND-13 | Blocked |
| GIG-10 | F10 | | OUT-6 | Blocked | | FIND-14 | Blocked |
| GIG-11 | F10 | | OUT-8 | F8 | | FIND-15 | Blocked |
| GIG-12 | Blocked | | OUT-9 | F8 | | FIND-16 | F18 |
| | | | OUT-10 | F8 | | FIND-17 | Design |
| | | | PRES-1 | Blocked | | LIFE-2 | Blocked |
| | | | PRES-2 | F17 | | LIFE-4 | Blocked |
| | | | PRES-3 | F7 | | LIFE-5 | Design |
| | | | PRES-4 | F5 | | LIFE-6 | Blocked |

| ID | Placement | | ID | Placement | | ID | Placement |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LIFE-7 | F6 | | FAIL-6 | F14 | | PLAT-4 | Blocked |
| LIFE-9 | Blocked | | FAIL-7 | F16 | | PLAT-5 | Blocked |
| LIFE-10 | F10 | | FAIL-8 | Blocked | | PLAT-6 | Blocked |
| LIFE-12 | F14 | | FAIL-9 | F15 | | PLAT-7 | D2 |
| LIFE-13 | F3 | | FAIL-10 | Blocked | | PLAT-8 | F17 |
| LIFE-14 | F11 | | FAIL-11 | Blocked | | PLAT-9 | Blocked |
| FAIL-2 | F12 | | FAIL-12 | F16 | | PLAT-10 | Blocked |
| FAIL-3 | Blocked | | FAIL-13 | F15 | | PLAT-12 | F7 |
| FAIL-4 | F13 | | FAIL-14 | F17 | | PLAT-13 | Blocked |
| FAIL-5 | F15 | | FAIL-15 | F14 | | PLAT-14 | F17 |
| | | | FAIL-16 | F9 | | PLAT-16 | F17 |
| | | | PLAT-2 | F13 | | PLAT-17 | Design |
| | | | PLAT-3 | D2 | | PLAT-18 | Design |
| | | | | | | PLAT-19 | F16 |

**Totals:** 71 fix (F1–F18; F5b carries no ID) + 8 docs (D2) + 12 design + 34 blocked + 0 won't-fix = **125**.

**Folded duplicates (not counted):**

- GIG-5 → FIND-2 (F5)
- GIG-18 and OUT-3 → PRES-3 (F7)
- LIFE-8 and OUT-7 → GIG-11 (F10)
- PLAT-15 → FIND-15 (Blocked)
- PLAT-11 → UX audit batch 2 (untracked; intake #16 says to file it)

**The intake's "Missing" items:**

- unused alternates raising "Called ×N" → F5;
- the privacy-registry note on program pay → D1;
- the four contradicting comments → D1.
