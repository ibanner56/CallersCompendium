# Defensive intake of the October 2026 UX audit's follow-up batches 2–7

This is a second opinion on the follow-up batches of the October 2026 UX audit, written for the maintainer before anyone acts on them. The audit page is at <https://claude.ai/artifact/R8DAGdsagzTaVw6SGCA3m1>. Its batch 1 shipped in #1919, and the maintainer's four decisions from it shipped in #1921 and #1922. Batches 2–7 were never filed or fixed. This file checks every item in them against **main at 65b1c48** (#2000), after the behaviour-audit fix PRs #1977–#2001. It then plans fix branches in the format of `batch-plan.md`.

Planning only. No app code, docs or other file was changed, and no issue or PR was opened.

## Method

**Who checked what.** Six verifier agents each took one batch. They worked in scratch checkouts of `origin/main` outside the tree.

- **What each did:**
  - read the cited code on main;
  - looked for guards on the path, and for defaults and gating in `settings_keys.dart`;
  - ran `git log` on every file named. The clone is shallow: history before #1902 is squashed, so older provenance was traced through GitHub PRs and issues, read-only;
  - searched code comments, `docs/design`, `docs/user`, ADRs, changelog fragments, and the style and localization guides;
  - diffed the four in-flight PRs against main: #1993 (F14), #1994 (F16), #2002 (F6) and #2003 (F3).
- **Two verifiers ran throwaway widget tests** in private copies of `app/`, using the bundled fonts at 360×640 logical px:
  - **batch 4:** the real `ProgramSlotListEditor` and `PerformCard`, plus synthetic copies of a Settings row and the program editor's app bar;
  - **batch 6:** no test was needed in the end.
- **Everything else is code reading,** including the framework source for sheet dismissal (Flutter 3.47 `bottom_sheet.dart`, `modal_barrier.dart` and `form.dart`). Nothing was run on a device. Nothing was run in a full app build, so the audit's "Seen" items were re-checked in code, not on screen.

**What I re-checked myself:**

- **UX2-1:** none of the five editor files contains `PopScope` or `onPopInvoked` (grep on main).
- **UX3-1a/b, UX3-7:** `danceReimportJson` "Callers Compendium JSON", the two "title and caller match" strings, "Cute af" and "Save *" are present in `app_en.arb` at the lines cited.
- **UX6-2's "✓" reversal:** `AppBarTextAction` (`widgets/app_bar_text_action.dart:52-68`) draws the word "Save" whenever it fits in 40% of the screen width.
- **UX5-1:** the seed path in `seed_service.dart:52-69`.

**Calibration.** I used the behaviour intake's bar. For a beta app with a niche audience, **High** means silent loss of the caller's own data, or a core feature hiding content or failing while reporting success, on a path default settings reach. Display-only or cosmetic problems, and problems on opt-in or experimental paths, are Medium at most; polish is Low. The gates that mattered here:

- Free-text entry: off by default (`settings.md:289`). It is the only way into the shorthand editors.
- Device Sync: under Settings › Experimental, off by default (`settings_keys.dart:184-187`).
- Perform auto-size: **on** by default (`settings_keys.dart:42`).

**Decisions.** Where a verdict says something was decided, the entry names the PR or issue, and says when the author could not be confirmed as the maintainer rather than an agent working under the maintainer's account. Re-ratings and fix sketches in this file are mine and the verifiers', not maintainer decisions.

## Overall assessment

- **Nothing was fixed by a later PR.**
  - None of #1977–#2001 fixed or partly fixed any of the 30 items, and none of the four in-flight PRs touches them.
  - The behaviour-audit fixes changed nearby files: the dance editor's state, the program builder's writes, and import results. They did not change the widgets these items name.
  - The items are still live, and still untracked: there is no issue for any batch.
- **The mechanisms are reliable.**
  - No item is refuted outright. Every one of the 30 describes code that behaves as stated, at least in part.
  - Several sub-claims are wrong:
    - "Save ✓" on desktop;
    - the quote counts;
    - "no way in" on the first run;
    - an editor title "hiding the program's name";
    - the fixed-width dropdowns overflowing;
    - the dance and venue forms "scrolling to the error".
  - Two counts were **understated**:
    - the venue sheet has 21 fields, not "about 8";
    - there are 39 radius literals, not "about 25".
- **Severity is inflated,** more than in the behaviour audit:
  - Of the 7 Highs, **only UX4-1 stays High**. A widget test measured it as worse than reported. The other six become Medium.
  - Of the 23 Medium and Low items, 9 are rated one step too high.
  - **No re-rating went up.**
  - The usual reasons:
    - the item is cosmetic or a wording inconsistency, with no data at risk;
    - the path is opt-in (Free-text entry, Device Sync, the custom-figure library);
    - a way out exists elsewhere on the screen;
    - part of the behaviour was decided earlier and the audit didn't say so.
- **Several items need a product decision the audit presented as obvious.** Examples: which button is primary in "Discard changes?", what the seed dance is, whether non-blocking warnings are tertiary or error-coloured, US vs UK spelling, and the Save, New and header conventions. The audit's own style guide does not settle any of them. `docs/user/style-guide.md` governs the user guide, and says nothing about sentence case, ICU plurals, spelling or quote style in app strings.

## Verdict counts

| Verdict | Count | Items |
| --- | --- | --- |
| Confirmed (severity stands) | 15 | UX2-2, UX2-3, UX2-5, UX3-7, UX4-1, UX4-3, UX4-4, UX4-5, UX4-6, UX5-3, UX6-1, UX6-3, UX7-1, UX7-4, UX7-5 |
| Confirmed, re-rated | 15 | High→Medium: UX2-1, UX3-1, UX3-2, UX3-3, UX4-2, UX5-1. Medium→Low: UX2-4, UX3-4, UX3-5, UX3-6, UX5-2, UX5-4, UX6-2, UX7-2, UX7-3 |
| Partly fixed | 0 | |
| Fixed | 0 | |
| Deliberate (whole item) | 0 | Parts of UX5-1, UX5-4, UX6-2, UX7-3 and UX7-4 are deliberate; see the entries |
| Not reproduced (whole item) | 0 | Sub-claims UX4-3e and UX6-2b's "✓" are not reproduced |
| Unverifiable here | 0 | Device-only parts are listed under "Unverifiable here" |

## Error and severity-calibration rate

| Measure | Rate |
| --- | --- |
| Items whose mechanism is wrong | 0 / 30 |
| Items with at least one wrong or overstated sub-claim | 11 / 30 (37%): UX2-1d, UX2-4, UX3-3, UX3-6, UX4-3, UX4-4, UX5-1, UX5-3, UX6-2, UX7-3, UX7-5 |
| Items with a deliberate or decided component the audit didn't mention | 6 / 30 (20%): UX2-2 (#1919 made Discard red), UX5-1 (#336 seed), UX5-4 (ux.md's "confirm where undo is impossible"), UX6-2 (#143 FABs), UX7-3/7-4 (shape-coded stars; #463/#498 Undo snackbar) |
| Severity too high: all items | 15 / 30 (50%) |
| Severity too high: Highs | 6 / 7 (86%) |
| Severity too high: Medium and Low | 9 / 23 (39%) |
| Severity too low | 0 / 30 |

**Rule of thumb for this audit:** trust the mechanism. Discount Highs by a step unless the caller's data or a core screen is at stake, and check sub-claims and counts before quoting them. The behaviour intake found about a third of its severities too high; this audit's Highs are worse calibrated, and its Medium and Low ratings slightly worse.

## Verdicts, item by item

"Layer" says what was actually checked. All file paths are under `app/lib/src/` unless shown otherwise; ARB lines are `app/lib/l10n/app_en.arb`.

### Batch 2: protect unsaved work

| ID | Item | Audit | Verdict | Now | Evidence and reasoning | Layer |
| --- | --- | --- | --- | --- | --- | --- |
| UX2-1 | Five editors lose input on Back, swipe-down or a tap outside | High | **Confirmed, re-rated** | Medium | **Still present:** none of the five has a `PopScope` or discard prompt. Most were last changed at the history root (#1902); #1983, #1996 and #2003 touch none of them. **(a)** Shorthand mapping editor (plain `Navigator.pop`, `shorthand_mapping_editor_screen.dart:109`) and **(b)** compound shorthand editor (`:227`, `:272`) are reachable only with Free-text entry on, which is off by default. **(c)** Theme editor: reachable by default from Appearance; what is lost is colour choices. **(d)** Venue sheet: **21 text fields, not "about 8"** (controllers `venue_editor_sheet.dart:53-75`). It is a default `showModalBottomSheet` with a drag handle. **(e)** Custom-field sheet (`custom_fields_screen.dart:133-141`). **Framework detail:** a barrier tap goes through `maybePop`, so `PopScope` blocks it, but **swipe-down and the drag handle call `Navigator.pop` directly** (`bottom_sheet.dart:769-772`). The sheets also need `enableDrag: false` (precedent: `program_editor_screen.dart:3604-3605`). **No shared guard exists:** dance, program, compound and dialect each define their own dialog. **Severity:** these editors hold settings and reference data, not dances or programs, and two of them are opt-in. The behaviour intake kept PLAT-11, the same finding for c–e, at Medium. | Read code and framework source; git log |
| UX2-2 | "Discard" is the filled primary in unsaved-changes dialogs | Medium | **Confirmed**; the colour was a batch-1 change | Medium | Discard is a `FilledButton` with `destructiveFilledButtonStyle` in the dance (`dance_editor_screen.dart:640-645`), program (`program_editor_screen.dart:2979-2983`) and compound (`glossary/compound_editor_screen.dart:956-962`) dialogs. The dialect editor has Cancel · Exit without saving · **Save and exit** (`dialect_editor_screen.dart:796-810`). **#1919 (bbec420) made Discard red**, under its "every confirm that deletes, discards, resets or replaces data looks dangerous" fix. That was the same audit's batch 1, merged from the maintainer's account; I could not confirm the maintainer chose the colour, rather than an agent applying the rule. The audit's batch 2 now asks to demote that same button, so this is a decision, not a mechanical fix. "Save and exit" must not pop when the save fails validation. | git show bbec420; read code |
| UX2-3 | Typed text in small dialogs is lost on a stray tap outside | Medium | **Confirmed** (all 5) | Medium | None sets `barrierDismissible`:<br>• Add difficulty level: `settings/defaults_section.dart:1301`.<br>• Snippet edit: `walkthrough_snippets_screen.dart:88`, `:182`.<br>• Glossary notes: `glossary_screen.dart:737`. Its `PopScope(canPop: !_saving)` at `:870` guards only during the save.<br>• Choreographer details: `choreographer_details_dialog.dart:30`.<br>• Matrix column rename: `settings/matrix_column_editor.dart:186`, `:661`.<br>A dirty-aware `PopScope` covers the barrier, Esc and Back. That is better than `barrierDismissible: false`, which can't change once the dialog is open. | Read code; grep |
| UX2-4 | Shorthand editors show errors at the top of a scrolled page | Medium | **Confirmed, re-rated**; the comparison is not reproduced | Low | **The errors sit at the top:** the error `Text` is the first item of the `ListView` (`shorthand_mapping_editor_screen.dart:186-193`; compound `:322-326`). Some errors are about the figure list further down.<br>**The comparison is wrong:** the dance and venue forms do use inline `errorText`, but **neither scrolls to it**. Flutter's `FormState.validate` has no `ensureVisible` (`form.dart:360-384`).<br>**Comment drift:** the dance editor's comment "Ensure the user sees the first error even if it is above the fold" (`dance_editor_screen.dart:394-399`) describes behaviour that doesn't exist.<br>**Severity:** gated by Free-text entry, so Low. | Read code and framework source |
| UX2-5 | Deleting a difficulty level has no confirm and no undo | Low | **Confirmed** | Low | `defaults_section.dart:1378-1397` refuses deletion while the level is in use. Otherwise it deletes silently. `DifficultyLevelRepository.restore()` exists (`difficulty_level_repository.dart:224`), but no app code calls it. What is lost is a label and its position. It **does not depend on** the blocked LIFE-9/LIFE-4/GIG-17 trash policy: Undo fits either answer. | Read code; grep |

### Batch 3: plain language and consistent terms

`docs/user/style-guide.md` binds the user guide. For app strings it gives only "non-technical; avoid jargon from the codebase" and a short term list (Perform mode, backup/restore, dance, figure/move). It does **not** set sentence vs Title Case, plurals, US vs UK spelling, quote style, or a word for the trash, share files, or author vs choreographer. Its own text mixes "color" and "coloured". Every "standardize on X" below is a choice for whoever fixes it, not an existing rule. Unless noted, these strings predate #1902, so their origin can't be traced in this clone.

| ID | Item | Audit | Verdict | Now | Evidence and reasoning | Layer |
| --- | --- | --- | --- | --- | --- | --- |
| UX3-1 | Wrong or misleading words | High | **Confirmed, re-rated** | Medium | **(a)** `danceReimportJson` "Callers Compendium JSON" (en:12480; da, de, ja and nl keep the English; fr has "JSON de Callers Compendium"). Used at `dance_reimport_flow.dart:46`. Medium.<br>**(b)** `onlineImportVariationDialogBody` (en:7848) and `importReviewVariationBody` (en:9443) say "title and caller match", but the code matches title + author (`online_search.dart:143`). Medium: it misleads on a default import path.<br>**(c)** `settingsSyncQuotaExcludeImports` "Stop syncing imported dances" (en:871) turns on the setting titled "Skip unused imported dances" (en:703). It appears only under Experimental › Device Sync at 80% or more of quota. Low.<br>**(d)** After `BackUpReady`, the confirm still says `migrationBelowFloorBackUpAndReset` (`main.dart:2028`). #1970 added a separate developer reset and #1977 touched no ARB, so neither changed this. It is reached only by a database below the migration floor. Low.<br>No item loses data, so none is High. | Grep all six ARBs; read call sites |
| UX3-2 | "Custom figure" means two things | High | **Confirmed, re-rated** | Medium | **The two meanings:** 18 strings say "custom figure(s)":<br>• unparsed text: `importGap*`, `danceEditorFiguresHelp`, `reparse*` ×6 and others;<br>• the user's own library: the `Custom Figures` setting, `customFiguresTitle`, and two "…while Custom Figures is on" strings.<br>**More names for the user's own figures:** "your own figure(s)" ×12, "your figures" ×6 and "your combinations" ×1.<br>**Partial precedent:** "Unrecognized figure" is already used twice (`importGapDialogTitle` and `importGapSemanticLabel`), right beside "kept verbatim as a custom figure".<br>**Docs:** the user docs split the same way (authoring.md vs settings.md), and glossary.md defines neither meaning.<br>**Decided?** No decision found. #1962 (docs only) reinforces "Custom Figures" as the setting's name.<br>**Severity:** confusing, but nothing is lost. The library meaning sits behind the Experimental switch. Medium. | Parsed app_en.arb; grepped docs/user |
| UX3-3 | Developer terms reach callers | High | **Confirmed, re-rated**; one word refuted | Medium (sync part Low) | **Sync review (Experimental):** about 10 strings, for example "Peer record: {identity}" / "Local record: {id}" (en:3824, 3834), which show raw ids, "peer change" ×3, and "sync pass or a supported review flow" (en:3872). **"Tombstone" appears in no displayed string**, only in a key name. The conflict sheet is already plain (en:1215+).<br>**Import notes (default path):** 6–8 strings, including "metadata-only stub", "taxonomy default", "Couldn't parse" and "re-parse". #1979, #1999 and #2001 left them unchanged.<br>**Custom fields (not gated):** "Stable machine key…" and "Boolean", plus the visible "Key *" concept (about 6 strings).<br>**Updates:** "sha256 integrity" and "(sha256)". #1987 added failure labels but kept these two.<br>**Startup error:** shows `Error: {errorType}` from `runtimeType` (`widgets/app_bootstrap.dart:174`, `:395`). The type name is shown on purpose instead of the message, for privacy, but it is still jargon.<br>**Severity:** jargon that confuses but loses nothing is Medium. | Parsed ARB; read call sites; diffed #1987/#1999 |
| UX3-4 | Hard-coded English | Medium | **Confirmed, re-rated** | Low | **Hard-coded strings:**<br>• `'Enter a number'` at `custom_field_editor.dart:91`. A localized key, `collectionBatchCustomFieldNumberInvalid`, already exists.<br>• `'Yes' : 'No'` at `dance_detail_data.dart:294`. `commonYes`/`commonNo` exist, but the code runs in the data layer, so l10n has to be threaded in.<br>• Six file-dialog labels: `backup_io.dart:87`, `import_io.dart:241,253`, `crash_log_io.dart:26`, `artifact_destination.dart:29`, `share_file.dart:57`.<br>**Refuted:** the custom-theme role labels *are* mapped through l10n.<br>**Severity:** short labels, and English-only users see no difference. Low. | Grep Dart |
| UX3-5 | One thing, several names | Medium | **Confirmed, re-rated** | Low | **Counts in en:**<br>• Trash: "Recently Deleted" 1, "Recently deleted" 1, "trash" 4, "Trash" 1, "Deleted items" 3.<br>• Files: "share file" 2 (one added by #1999), "dance file" 2, "JSON file" 9, "Caller's Compendium file" 1. "Compendium archive" is not in the ARB.<br>• People: "author" 24, "choreographer" 6, and both in one string, `danceEditorChoreographerCreateDuplicate`.<br>• "Add note / waltz" opens "Add note or break".<br>• "performance view" ×3, one of them **added by #1986**, against the style guide's term "Perform mode".<br>**Severity:** each name is understandable on its own. Low. | Parsed ARB |
| UX3-6 | Title Case, "(s)" plurals, "colour", quotes | Medium | **Confirmed, re-rated**; counts corrected | Low | **Title Case:** 8 strings, including "Developer Options", new in #1970, and "More Details". "Soft Dark" is **not** a proper name: it is translated in all five locales, unlike Catppuccin and Nord, and its siblings use sentence case.<br>**"(s)" in both plural forms:** exactly 3 (`importReviewProgramNotes`, `importReviewRecordsFailed`, `importReviewBatchErrors`).<br>**"Colour":** 20 strings and 25 uses, not "about 30", against "color" in 2. There are also 11 other British spellings, while the app says "neighbor".<br>**Quotes: "65 vs 238" is not reproduced.** Straight `"` appears in 70 strings, curly in 78; straight `'` in 254, curly in 54.<br>**Severity:** polish. Low. | JSON parse of app_en.arb |
| UX3-7 | Small copy fixes | Low | **Confirmed** | Low | All present:<br>• "Move names dotted·underline" (en:10808).<br>• "Switch to the app's" (en:516). It reads as half of a pair next to "Rename mine", which works on screen but is vague read aloud; Experimental.<br>• "Cute af" (en:2627; the translations already soften it).<br>• "Save *" (en:6006; `program_editor_screen.dart:3120`; default path).<br>• "WiFi" ×5 (Device Sync).<br>• "default params" (en:9540). | Grep ARB |

### Batch 4: phone layout

| ID | Item | Audit | Verdict | Now | Evidence and reasoning | Layer |
| --- | --- | --- | --- | --- | --- | --- |
| UX4-1 | Program slot rows leave about 16px for the dance title | High | **Confirmed, worse than reported** | **High** | **Measured at 360px with real fonts:** a primary slot's title box is **8px** wide. An alternate's is **0px**, and its row throws "RenderFlex overflowed by 24 pixels". The result is the same at text scale 1.0 and 2.0.<br>**Cause:** `widgets/program_slot_list_editor.dart:498-704` has five fixed controls: view, up, down and cut (40px each) and ⋮ (48px). View is always wired on phones (`program_editor_screen.dart:3567`).<br>**History:** the file is unchanged since #1902.<br>**Severity:** this is the program builder, a core screen, at default settings on a common phone, and it hides every slot's title. It meets the High bar.<br>**Constraint on the fix:** the code comment at `:627-628` keeps the scissors icon and "Cut …" tooltip "by maintainer decision (issue #1270)". #1270 was filed by a beta tester and closed by @ibanner56 via #1385; the verifier did not read the maintainer's wording in the issue. | **Ran widget test**; read code |
| UX4-2 | Perform's beats label squeezes the figure | High | **Confirmed, re-rated** | Medium | **Measured with auto-size off** at 1.8 (`kPerformDefaultScale`): the figure column is 160px, which holds **5–7 characters per line**. With system text at 1.3 it holds 4.5.<br>**With auto-size on, the default** (`settings_keys.dart:42`): a 7-figure dance fits at about 17px with one line per figure.<br>**When it bites:** once the caller taps A−/A+, which turns auto-size off. That is common, but cramped is not unreadable.<br>**Code:** `screens/perform_card.dart:1166-1210`. The file is unchanged by #1990. | **Ran widget test**; read code |
| UX4-3 | Overflows at large text or in German | Medium | **Confirmed**, with corrections | Medium | **(a)** Settings rows with buttons: **measured as a squeeze, not an overflow.** The German title is 35px wide at 2× (`settings/general_section.dart:766-841`).<br>**(b)** Advanced-query group header: a `Row` with an unflexed `Text` (`widgets/advanced_query_builder.dart:93-130`, `:588-620`). Confirmed.<br>**(c)** Compact matrix chip: an unflexed title in `Row(min)` (`widgets/program_matrix_table.dart:1384-1420`). Confirmed.<br>**(d)** Tap-tempo sheet: about 390px of non-scrolling content in a sheet capped at about 200px in landscape. It **overflows even at default text** (`widgets/tap_tempo_metronome.dart:182-236`). Confirmed.<br>**(e)** Fixed-width dropdowns: **not reproduced.** They use `isExpanded`, so they ellipsize. | **Ran synthetic test** (a); read code (b–e) |
| UX4-4 | Toolbars crowd out titles | Medium | **Confirmed**, one correction | Medium | **Program editor:** with all 5 actions shown, the title box is **32px** (measured; 80px with 4). Five actions is the default for any saved program with a dance (`program_editor_screen.dart:3025-3099`). **Correction:** that title is the static "Build program", not the program's name, so nothing the caller typed is hidden.<br>**Summary:** the program's name `Expanded` beside 4 icons leaves about 120px, and the name wraps at `headlineSmall` (`program_summary_screen.dart:709-745`, read).<br>**Precedent:** `dance_detail_screen.dart:184` (`compactActionsBreakpoint = 600`). | **Ran synthetic test** (editor); read code (summary) |
| UX4-5 | "Add a dance" picker draws buttons over long titles | Medium | **Confirmed** | Medium | `widgets/collection_picker.dart:1004-1095`: a `Stack` paints add, view and the in-program marker, each `Positioned`, over a `DanceListTile` built without trailing. Up to about 130px of the first line sits under them at default text. The online rows have the same layout (`:1159-1215`). #2002 edits this file, but only the filter wiring. | Read code |
| UX4-6 | Small targets and missing roles | Low | **Confirmed** | Low | **(a)** The import-gap badge's tap target is the bare icon: **16px** at 1× (`widgets/import_gap_badge.dart:33-56`). It already has a button role and a label.<br>**(b)** The rail's Search and Guide tiles are bare `InkWell`s with no `Semantics(button: true)` (`screens/app_shell.dart:427-470`, `:483-530`). #1919 changed only the rail's scrolling. The rail appears only on wide layouts, so this half is not a phone issue. | Read code |

### Batch 5: empty, loading and error states

| ID | Item | Audit | Verdict | Now | Evidence and reasoning | Layer |
| --- | --- | --- | --- | --- | --- | --- |
| UX5-1 | A new user is never shown how to bring dances in | High | **Confirmed, re-rated**; the seed is deliberate | Medium | **(a) The seed:** `data/seed_service.dart:52-69` adds "The Baby Rose" once, behind a latch, with no setting. It came from **#336, authored and merged by @ibanner56**, whose description says "on a fresh install the collection is now never empty". The seed is also cited in the store-review notes (`docs/dev/store-submission/listing-copy.md:238`, `app-store.md:149`). The code comment cites a ROADMAP line that is not in `docs/ROADMAP.md`. So the seed hiding the empty state is a **consequence of a decided feature**, not an oversight.<br>**(b) The empty state:** it has no buttons (`dance_list_screen.dart:2545-2565`). But **New dance (FAB) and Import dances (app bar) are on screen**, so "never shown how" overstates it. "As Programs already does" is half right: Programs offers New program but no Import.<br>**(c) New: a false claim in the guide.** `docs/user/getting-started.md:61` says "Your collection starts empty". D2's INTAKE-11 bullet covers only `:213-228`.<br>**Severity:** onboarding friction; nothing is lost and the entry points exist. **Overlaps:** INTAKE-11 (D2) and INTAKE-12 ("what the seed dance is", under "Needs design" in batch-plan.md). `docs/design/ux.md:188` already says "Empty states teach: first-run Collection offers … 'import your data'"; I could not trace who wrote that line. | Read code; read #336 |
| UX5-2 | Two empty-state styles; no Clear filters | Medium | **Confirmed, re-rated** | Low | **More than two styles,** with no shared widget:<br>• Programs: icon, title, body and button.<br>• Collection: the brand mark and text.<br>• About 9 screens show one line of text.<br>• Diagnostics uses a `ListTile`.<br>• Two private `_EmptyState`s exist (reparse, matrix).<br>**"No dances match your search"** has no button (`dance_list_screen.dart:2858-2864`), but the search field's clear-all ✕ shows whenever any query or filter is active (`:2422-2428`, `:1304-1308`).<br>**Severity:** cosmetic, and the way out exists. Low. | Read code |
| UX5-3 | Errors without a way forward | Medium | **Confirmed**, one part re-rated, one part refuted | Medium | **(a)** No Retry on tag colours (`tag_colors_screen.dart:135-141`), collection search (`dance_list_screen.dart:2850-2856`) or dance editor load (`dance_editor_screen.dart:967-971`). Not in the audit: the **program editor load** (`program_editor_screen.dart:3134-3145`) has none either.<br>**(b)** Dance detail shows **"Dance not found." when the load fails** (`dance_detail_screen.dart:396-406`, `:963`). The code says the two cases "already looked alike" (#963, logging only). This tells the caller their dance is gone when it isn't, so it keeps this item at Medium. The program editor already separates the two cases.<br>**(c)** A failed sync conflict count hides the entry (`settings/device_sync_section.dart:675-679`). This is Device Sync, so Low.<br>**(d) "Many errors don't say what to do":** partly wrong. The collection, programs, custom fields, venues, Recently deleted and sync review all have Retry. Only the copy gives no further step. | Read code |
| UX5-4 | Silent deletes and a vanishing instruction | Medium | **Confirmed, re-rated**; the confirm-only design is stated | Low | **(a) Deletes:** dialect, theme, shorthand, snippet, custom field and custom figure each **confirm first**, then delete with no snackbar. The row then vanishes from a visible list. That matches `docs/design/ux.md:186-187` ("destructive confirms only where undo is impossible"), since the trash covers only dances and programs. The custom-field delete catches only `CustomFieldInUseException` (`custom_fields_screen.dart:235-270`), so other failures are silent. That is a small real bug.<br>**(b) The instruction:** the `wipedButStillAttached` instruction is a 10s snackbar with no action (`settings/sync_devices_screen.dart:51-58`). It needs Device Sync plus a rare partial failure, and Disconnect stays on screen. Low. | Read code |

### Batch 6: wide-screen readability

| ID | Item | Audit | Verdict | Now | Evidence and reasoning | Layer |
| --- | --- | --- | --- | --- | --- | --- |
| UX6-1 | Content stretches edge to edge on desktop | Medium | **Confirmed** (structure; pixel figures not re-measured) | Medium | **No content max-width helper exists.** The caps that do exist:<br>• #1919's dialog cap of 560 (`theme/app_shapes.dart:33-36`);<br>• a few ad-hoc caps (command palette, sync conflict sheet, matrix column editor);<br>• user-guide **images only**, at 720 (`user_guide/user_guide_doc_view.dart:233`). The guide's text is unconstrained.<br>**The stretched screens:**<br>• dance detail: a plain `ListView` with `Expanded` figure text, so the beats sit at the far edge (`widgets/figure_table.dart:201-247`);<br>• Settings: an `Expanded` content column with about 30 `SwitchListTile`s;<br>• the dance editor form: `CrossAxisAlignment.stretch` (`dance_editor/dance_editor_form.dart:280`).<br>**Arithmetic:** at 1280px, Settings content is about 1,019px wide, which fits "about 1,000". The 900 and 1,250 figures were not reproduced.<br>**Where 760 comes from:** only the wireframes (`docs/design/wireframes/2-dance-detail.svg`). No doc states a width rule. | Read code; arithmetic |
| UX6-2 | Sibling screens arrange the same things differently | Medium | **Confirmed, re-rated**; "✓" refuted; part deliberate | Low | **(a) Headers:** dance detail titles its app bar "Dance" and shows the name in a card. Program summary shows the name in a header row with 5 icon buttons (`program_summary_screen.dart:707-747`).<br>**(b) Save:** a FAB in 2 editors (dance, program) and the toolbar in 5 (theme, compound, compound shorthand, shorthand mapping, dialect). **Refuted:** the toolbar Save is `AppBarTextAction`, which shows the word **"Save"** on desktop and falls back to ✓ only on narrow screens or at large text.<br>**(c) "New…":** an extended FAB on 4 screens, a toolbar "+" on 2, an `OutlinedButton` on 4.<br>**Decided?** The dance and program Save FABs and the detail Edit FAB came from **#143** ("UI consistency pass: align dance & program screens with the builder"), merged by @ibanner56 and co-authored by Copilot. Its aim was alignment with the builder, before most toolbar-Save editors existed.<br>**Drift:** the code comments citing `docs/design/ux.md` §2/§3 for the FAB placement are false (`dance_editor_screen.dart:940-944`, `dance_detail_screen.dart:966-968`). Neither section mentions a FAB.<br>**Severity:** every action is labelled and reachable. Low. | Read code; read #143 |
| UX6-3 | Mixed field labels in the dance editor | Low | **Confirmed**, with a nuance | Low | **Floating labels:** Title, Formation detail, Progression, Phrase structure, notes, Hook and Walkthrough.<br>**Headings above the field (`FieldLabel`):** Authors, Type, Formation, Tags, Tunes, Links, Sources, Related and Custom fields.<br>**A third style:** Rating has a `bodySmall` caption.<br>**Nuance:** Authors, Tags and the rest are chip pickers, which can't take a floating label. Only **Type and Formation** are dropdowns that could.<br>**Decided?** No convention is stated (`ux-modernization.md` §5.3 sketches but sets no rule). | Read code |

### Batch 7: visual system cleanup

Tokens on main:

- **Spacing:** `theme/app_spacing.dart`, 4/8/12/16/24/32/48.
- **Radii:** `theme/app_shapes.dart`, 8/12/16, and 28 for dialogs.
- **Shared widgets:** `SectionHeader`, `WarningsCard` (extracted by #1990), `CollapsibleSection` and `showUndoSnackBar`.
- **No `snackBarTheme`** exists anywhere.

| ID | Item | Audit | Verdict | Now | Evidence and reasoning | Layer |
| --- | --- | --- | --- | --- | --- | --- |
| UX7-1 | Warning boxes have six or more looks | Medium | **Confirmed** | Medium | **Nine boxed notices,** with 5 fills, 3 radii (8/10/12), 2 paddings, and `Card` and `Container` mixed:<br>• `WarningsCard`: tertiary at 12%, radius 8.<br>• `_ProgramWarningsCard`: a `tertiaryContainer` Card, radius 12 (`program_editor_screen.dart:4244-4248`).<br>• Five in `import_review_screen.dart`, including **`errorContainer`** for non-blocking warnings.<br>• `theme_editor_screen.dart:163-167` (radius 10).<br>• The venue sheet hint.<br>**The editors' two cards differ** in fill, radius, elevation and icon colour.<br>**Medium stands** because warning severity reads differently from screen to screen: tertiary in the editors, error in import. | Read code; grep |
| UX7-2 | Hand-built section headers; two force UPPERCASE | Medium | **Confirmed, re-rated** | Low | **The two:** `widgets/collapsible_section.dart:35` (`title.toUpperCase()`, used by Experimental, Developer options, Device Sync and 5× in the dialect editor) and `_EditorHeader` (`dialect_editor_screen.dart:957-975`, a copy of `SectionHeader` plus uppercase).<br>**Hand-built primary headers:** 10 more.<br>**Not in the audit:** `SectionHeader` itself has no `Semantics(header: true)`.<br>**Decided?** Nothing prescribes uppercase.<br>**Severity:** for the six shipped locales the result is ugly, not wrong. Low. | Read code; grep |
| UX7-3 | Icon drift | Medium | **Confirmed, re-rated**; the star is partly deliberate | Low | **(a) Remove-from-list:** `remove_circle_outline` ×7, `close` ×11, `delete_outline` ×9.<br>**(b) Warnings:** triangle, octagon and `error_outline` families. "Three families" holds.<br>**(c) Filled glyphs:** the filled copy icon (`widgets/figure_list_editor.dart:2298`) is confirmed. The **stars are deliberate shape-coding** (`program_matrix_table.dart:865`: "distinct SHAPE (star) + text, not colour alone"); rating state also uses them.<br>**(d) Matrix toggles:** state shows only in the tooltip (`program_editor_screen.dart:3331-3352`). Confirmed.<br>**#1919** changed only the status and Edit icons.<br>**Severity:** cosmetic. Low. | Grep counts; read code |
| UX7-4 | Snackbars behave two ways | Low | **Confirmed**; the Undo behaviour is decided | Low | **127 `showSnackBar` calls:**<br>• 18 go through `showUndoSnackBar`: floating, 6s, persistent under assistive navigation.<br>• 123 are bare: fixed, 4s, queued.<br>• 3 are bespoke.<br>**Decided?** The Undo behaviour came from **#463, filed by @ibanner56** ("not transient… obscures other UX elements"), and #498, merged by @ibanner56 and authored by the `isaacbanner` account (I could not confirm that account is the maintainer). #498 explicitly left plain snackbars alone, so the split is a scoping choice, not a ruling. The 6s duration is the implementer's choice.<br>**Limit on the fix:** `SnackBarThemeData` has no duration, so a theme can unify the behaviour but not the timing.<br>**Collision:** #1993 rewrites `undo_snack_bar.dart` and all 18 call sites. | Grep; read #463, #498; diffed #1993 |
| UX7-5 | Off-scale radii, padding and font sizes | Low | **Confirmed**, counts corrected | Low | **Radii:** **39** `Radius.circular` literals outside `theme/`, not about 25. 21 are on the scale and 18 off it. The 999 pill in `skeleton.dart` is deliberate. `AppShapes` is referenced only twice outside `theme/`.<br>**20px header gaps:** 2.<br>**Font sizes:** 43 `fontSize:` literals, but 38 are PDF export or pre-theme crash code, which is legitimate. **4** are in-app UI.<br>**Dropdowns:** 9 bare `DropdownButton`s sit beside boxed fields. The 9 `SettingsDropdownRow` uses are a documented pattern (`settings_dropdown_row.dart:1-12`). | Scripted counts; read code |

## Overlaps with the behaviour audit

| UX item | Behaviour-audit item | Status there | What to do |
| --- | --- | --- | --- |
| UX2-1 (c–e) | PLAT-11 (intake: "= UX batch 2, item 1") | Not placed in a branch; batch-plan.md folds it here | Fixed by **U1**. Mention PLAT-11 in that PR. |
| UX5-1 | INTAKE-11 | D2, getting-started.md `:213-228` | Add `getting-started.md:61` ("starts empty") to **D2**. |
| UX5-1 | INTAKE-12 | Needs design: what the seed dance is | **One decision** for both (D-5 below). |
| UX2-5, UX5-4a | LIFE-9, LIFE-4, GIG-17 | Blocked: does the trash protect referenced records? | UX2-5's Undo doesn't depend on that decision. UX5-4a's "undo instead of confirm" option does. |
| UX7-4 | F14 / #1993 (in flight) | Rewrites `showUndoSnackBar` with a required `undoFailedMessage` | **U11** lands after #1993. Any new Undo snackbar in U2 or U9 uses #1993's signature. |
| UX6-2 | D2 edits `ux.md` §2, §5 and ux-modernization UX-5 | Planned | Write the Save/New rule into ux.md **after D2**. |
| UX4-1, UX4-4, UX7-3d | F5b (summary rows), F10 (slot resolution), F11 (stale state) | Planned, not started | See "Sequencing". |

None of the four in-flight PRs fixes or changes any of the 30 items. They do edit all six ARB files, plus `program_editor_screen.dart` (#1993 +2, #1994 +12), `dance_detail_screen.dart` (#1993, #2002), `collection_picker.dart` (#2002) and `defaults_section.dart` (#2003, 3 lines).

## Fix branches

### How to read this

- **Size** counts changed lines, tests included: S < 150, M 150–400, L 400+.
- **Strings:** every branch that adds or changes UI text changes `app_en.arb` and all five locale ARBs (`da`, `de`, `fr`, `ja`, `nl`), following `docs/dev/localization.md`. Place keys next to related keys, never at the end of the file. User-visible branches add a `changelog.d/<id>.json` fragment.
- **Model:** Sonnet 5.5 for contained work; Opus 5.5 for stateful or cross-cutting work.
- **Item counts:** a few branches carry 2 items. Each of those items bundles 3–6 sub-claims, so each branch's real scope is still 5–12 fixes.
- **"My call"** marks a choice I made, with the alternative I rejected. None of these is a maintainer decision.
- **Guard tests:** every guard test must be shown to fail first (AGENTS.md).

### Overview

| # | Branch | Items | Size | Model | Wave | Needs |
| --- | --- | --- | --- | --- | --- | --- |
| U1 | `fix/unsaved-editor-guards` | UX2-1 (a–e), UX2-2 | M (~350) | Opus | UW2 | D-1 for UX2-2's buttons |
| U2 | `fix/small-dialog-input` | UX2-3, UX2-4, UX2-5, the UX2-4 comment drift | M (~250) | Sonnet | UW1 | — |
| U3 | `fix/copy-plain-language` | UX3-1 (a–d), UX3-3, UX3-4, UX3-6 (the three "(s)" plurals only), UX3-7 | M (~350 incl. 6 ARBs) | Sonnet | UW2 | — |
| U4 | `fix/copy-one-name-each` | UX3-2, UX3-5 | M (~400 incl. docs) | Sonnet | UW3 | D-3 |
| U5 | `fix/copy-style-sweep` | UX3-6 (case, spelling, quotes) | M–L | Sonnet | UW3 | D-4 (style-guide rule first) |
| U6 | `fix/phone-layout-widgets` | UX4-2, UX4-3 (a–d), UX4-5, UX4-6 | M (~300) | Sonnet | UW1 | D-7 (small) for UX4-2 |
| U7 | `fix/program-screens-on-phones` | UX4-1, UX4-4 | M (~300) | Opus | UW2 | D-2 |
| U8 | `fix/errors-with-a-way-forward` | UX5-3 (a–c), UX5-4b, the custom-field delete catch | M (~200) | Sonnet | UW2 | — |
| U9 | `fix/empty-states` | UX5-1b, UX5-2 (+ UX5-1a if D-5 changes the seed) | M (~300) | Sonnet | UW3 | D-5, D-6 |
| U10 | `fix/readable-width` | UX6-1 (non-program screens), UX6-3 | S (~120) | Sonnet | UW1 | D-8 (the width number; minor) |
| U11 | `fix/visual-tokens` | UX7-2, UX7-4 (theme only), UX7-5 (outside hot files), `SectionHeader` semantics | M (~250) | Sonnet | UW2 | — |
| U12 | `fix/notices-and-icons` | UX7-1, UX7-3 (a–c) | M (~300) | Sonnet | UW3 | D-9, D-10 |
| (F10) | folded | UX7-3d (matrix toggles show their state) | +~10 | — | F10's wave | — |
| (later) | `fix/sibling-screen-conventions` | UX6-2 | M | Sonnet | after F11 and D2 | D-11 |

**Totals:** 12 fix branches, plus one item folded into F10 and one branch (UX6-2) that waits on a decision and on F11. Decision-free now: U2, U3, U6, U8, U10 (with a default width) and U11. Every UX item placed: see "Check list".

### U1 `fix/unsaved-editor-guards`: every editor asks before throwing work away

- **Items:**
  - **UX2-1 (a–e).** Extract one shared `confirmDiscardChanges` helper (e.g. `utils/confirm_discard.dart`). Use it in the five unguarded editors. Re-point the dance, program, compound and dialect editors at it.
    - The shorthand mapping and compound shorthand editors get a dirty-aware `PopScope`.
    - The theme editor's dirty check is `_theme != initial` or a changed name.
    - The **venue and custom-field sheets** need `PopScope` **plus** `enableDrag: false` and no drag handle, because swipe-down bypasses `PopScope`.
  - **UX2-2**, per D-1. With option (a), the dialect pattern becomes the helper's layout: Cancel · Exit without saving · **Save and exit**.
    - "Save and exit" stays on the page when validation fails.
    - Update `docs/user/authoring.md:600-604` ("Keep editing / Discard").
- **Main files:** the five editor files; `dance_editor_screen.dart:621-645`; `program_editor_screen.dart:2963-2983` (a dialog-only hunk); `glossary/compound_editor_screen.dart:941-962`; `dialect_editor_screen.dart:784-810`; a new helper; ARB (2–3 generic keys, because the `dialectEditor*` keys are scoped to the dialect editor); `docs/user/authoring.md`; tests.
- **Size:** M (~350). **Model:** Opus, because of the dirty-state definitions in five editors, the sheet-dismissal semantics, and save-failure handling inside the dialog.
- **Depends on:** #1993 and #1994 merging (both touch `program_editor_screen.dart`; trivial), and D-1. If D-1 is still open, ship the guards with today's two buttons and leave UX2-2 for a follow-up. That is my call; the rejected alternative, holding the guards for the decision, leaves the only Medium data-loss item in this audit open.
- **Severity:** UX2-1 M, UX2-2 M.
- **Overlap:** PLAT-11 (behaviour audit). Say so in the PR body.

### U2 `fix/small-dialog-input`: small dialogs keep what was typed

- **Items:**
  - **UX2-3:** the five dialogs (add level, snippet, glossary notes, choreographer details, matrix rename) get a dirty-aware `PopScope`. A tap outside does nothing once text has changed.
    - *My call:* do nothing on a tap outside, rather than prompt. A prompt on a small dialog is heavier than the risk.
  - **UX2-4:** shorthand token errors become `errorText` on the token field. The figure-list error sits by the list and is brought into view with `Scrollable.ensureVisible`, following the pattern at `figure_list_editor.dart:447-453`. Same for the compound shorthand editor.
    - Fix or delete the false "ensure the user sees the first error" comment in `dance_editor_screen.dart:394-399`.
  - **UX2-5:** deleting a difficulty level offers Undo through `showUndoSnackBar`, calling the existing `restore(id)`.
    - *My call:* Undo, not a confirm. This follows `ux.md:186-187`'s "undo everywhere".
- **Main files:** `settings/defaults_section.dart` (`:1301`, `:1378-1397`), `walkthrough_snippets_screen.dart`, `glossary_screen.dart`, `choreographer_details_dialog.dart`, `settings/matrix_column_editor.dart`, `shorthand_mapping_editor_screen.dart`, `compound_shorthand_editor_screen.dart`, `dance_editor_screen.dart` (one comment), ARB (1–2 keys for the level Undo).
- **Size:** M (~250). **Model:** Sonnet.
- **Depends on:**
  - **#2003:** it changes 3 lines of `defaults_section.dart`, so this branch rebases trivially after it.
  - **#1993:** UX2-5's Undo must use #1993's `undoFailedMessage` signature. Land this after #1993, or write against its branch.
  - **U1:** both edit the two shorthand editors, but in different hunks (U1 the pop path, U2 the error display). Land U2 first or second; whichever is second rebases.
- **Severity:** UX2-3 M, UX2-4 L, UX2-5 L.

### U3 `fix/copy-plain-language`: wrong words and jargon (no naming decision needed)

- **Items:**
  - **UX3-1:**
    - (a) "Caller's Compendium JSON";
    - (b) "title and author match", in both strings;
    - (c) the quota button reuses the setting's own name ("Skip unused imported dances");
    - (d) a plain "Reset" label after the backup is saved (`main.dart:2028`).
  - **UX3-3:** plain-language rewrites, following the conflict sheet's style.
    - Import notes: "metadata-only stub", "taxonomy default", "parse".
    - Update checksum lines.
    - The custom-field "Stable machine key" helper, and "Boolean" → "Yes/No".
    - Sync review: "peer record", "sync pass".
    - The startup error drops `Error: {errorType}` from the screen and keeps the type in Copy details (`widgets/app_bootstrap.dart:174`, `:395`).
    - *My call:* keep the visible "Key" field for custom fields and only rewrite its helper. Hiding the key and deriving it from the label is a product change, and is listed under D-3's notes.
  - **UX3-4:**
    - `'Enter a number'` → the existing `collectionBatchCustomFieldNumberInvalid`;
    - Yes/No → `commonYes`/`commonNo`, with l10n threaded into `dance_detail_data.dart`;
    - 6 file-dialog labels as new keys.
  - **UX3-6, the three "(s)" plurals only:** make them ICU plurals. This needs no style ruling.
  - **UX3-7:** all six fixes. "Save *" becomes an accessible "Save (unsaved changes)", or "Save" plus a semantic hint; the wording follows the style guide's "non-technical" rule.
- **Main files:** ARB ×6 (about 40–50 keys changed or added), `main.dart` (one line), `widgets/app_bootstrap.dart`, `dance_editor/custom_field_editor.dart:91`, `dance_detail/dance_detail_data.dart:294`, `backup_io.dart`, `import_io.dart`, `crash_log_io.dart`, `artifact_destination.dart`, `share_file.dart`, plus tests that assert the old English.
- **Size:** M (~350 including all six ARBs). **Model:** Sonnet.
- **Depends on:** all four in-flight PRs merging. They don't touch these keys, but they all edit the six ARBs.
- **Severity:** UX3-1 M, UX3-3 M, UX3-4 L, UX3-6 L, UX3-7 L.

### U4 `fix/copy-one-name-each`: one meaning per term (after D-3)

- **Items:**
  - **UX3-2:** the two meanings of "custom figure", per D-3. The audit proposes "unrecognized figure" and "your own figures"; there is a precedent in `importGapDialogTitle`.
  - **UX3-5:** one name each for:
    - the trash;
    - share files;
    - author vs choreographer;
    - "Add note or break";
    - "Perform mode" in place of "performance view" (the style guide already names Perform mode, so that one needs no decision).
- **Main files:** ARB ×6 (about 25–45 keys), `docs/user/authoring.md`, `settings.md`, `glossary.md` (the bundled copy re-synced with `tools/ci/sync_user_docs.py`), and test expectations.
- **Size:** M (~400 including docs). **Model:** Sonnet.
- **Depends on:** D-3, U3 (same ARB neighbourhoods), and **D2**, because both edit `settings.md`.
- **Severity:** UX3-2 M, UX3-5 L.

### U5 `fix/copy-style-sweep`: case, spelling and quotes (after D-4)

- **Items:** UX3-6:
  - 8 Title Case strings;
  - 20 "colour" strings plus 11 other British spellings;
  - the quote style (about 300 strings, if normalized).
- **First:** write the ruling into `docs/user/style-guide.md`, and say there that it covers app strings, so the next audit has a rule to check against.
- **Size:** M without quote normalization; L with it. Consider leaving quotes for last, or only normalizing new strings. **Model:** Sonnet.
- **Depends on:** D-4 and U4. It touches many ARB lines, so it goes last among the copy branches.
- **Severity:** L.

### U6 `fix/phone-layout-widgets`: shared widgets that overflow or hide text on phones

- **Items:**
  - **UX4-2:** per D-7. My default is to cap the beats label's text scale at about 1.3 with `MediaQuery.withClampedTextScaling`, keeping the beats column aligned. The rejected alternative, stacking the label under the figure, changes how a caller scans the card on stage.
  - **UX4-3:**
    - (a) Settings rows put a trailing button under the subtitle when it would take more than about 40% of the row (a shared helper);
    - (b) a `Flexible`/`Wrap` advanced-query header;
    - (c) an ellipsized, width-capped matrix chip;
    - (d) a scrollable tap-tempo sheet, fixed **inside** `tap_tempo_metronome.dart`, so the F11 file `perform_program_screen.dart` is not touched;
    - (e) is not reproduced and is dropped.
  - **UX4-5:** the picker's add, view and marker buttons go into the tile's trailing slot (or a reserved right inset) instead of `Positioned` over the title. The online rows get the same fix.
  - **UX4-6:** the import-gap badge gets a minimum 24px target, and the rail's Search and Guide tiles get `Semantics(button: true)`.
- **Main files:** `screens/perform_card.dart`, `settings/general_section.dart`, `widgets/advanced_query_builder.dart`, `widgets/program_matrix_table.dart` (the chip only), `widgets/tap_tempo_metronome.dart`, `widgets/collection_picker.dart`, `widgets/import_gap_badge.dart`, `screens/app_shell.dart`. Widget tests at 360px and at 2× text. No strings.
- **Size:** M (~300). **Model:** Sonnet.
- **Depends on:** #2002, because of `collection_picker.dart` (a textual rebase only).
- **Severity:** UX4-2 M, UX4-3 M, UX4-5 M, UX4-6 L.

### U7 `fix/program-screens-on-phones`: the builder and summary fit a phone (after D-2)

- **Items:**
  - **UX4-1:** below 600px (matching `compactActionsBreakpoint`), each slot row keeps its drag handle and ⋮. The controls D-2 chooses move into ⋮.
    - Up and down must stay reachable without dragging (`ux.md:136`).
    - Respect the #1270/#1385 cut wording.
    - Update `docs/user/programs.md:216-219`, which describes the row buttons.
  - **UX4-4:** below 600px, the builder's and the summary's toolbars keep Perform and Export. Mark all performed, Duplicate and Delete move to ⋮, as dance detail already does.
- **Main files:** `widgets/program_slot_list_editor.dart` (rows `:498-704`), `program_editor_screen.dart` (app bar `:3025-3099`), `program_summary_screen.dart` (header `:709-745`), ARB (Move up, Move down and Cut as menu labels, about 3–5 keys), `docs/user/programs.md`, widget tests at 360px that **fail today with the measured overflow**.
- **Size:** M (~300). **Model:** Opus. It touches the 4,337-line builder, and the menu must keep the cut, paste and alternate-group behaviour.
- **Depends on:** D-2, and #1993/#1994 merging (both edit `program_editor_screen.dart`). See "Sequencing" for F5b, F10 and F11.
- **Severity:** UX4-1 **High**, UX4-4 M. This is the one High in the audit; schedule it as soon as D-2 is answered.

### U8 `fix/errors-with-a-way-forward`: an error says what happened and offers Retry

- **Items:**
  - **UX5-3:**
    - (a) Retry on tag colours, collection search, dance editor load and program editor load;
    - (b) dance detail separates "couldn't load" from "not found", following the program editor's `_ProgramLoadError.missing`;
    - (c) a failed sync conflict count shows "Couldn't check for conflicts" with Retry, instead of hiding the row.
  - **UX5-4b:** the `wipedButStillAttached` instruction becomes a dialog, or a persistent notice in the Device Sync section while the condition holds.
    - *My call:* a dialog, because the condition is rare and must be acted on.
  - **Found by the verifier:** the custom-field delete catches and reports failures other than `CustomFieldInUseException`.
  - **Optional:** a copy pass on the load-error strings, adding a next step. Only if the branch stays under budget.
- **Main files:** `tag_colors_screen.dart`, `dance_list_screen.dart` (`:2850-2856`), `dance_editor_screen.dart` (`:967-971`), `program_editor_screen.dart` (`:3134-3145`, an isolated hunk), `dance_detail_screen.dart` (`:396-406`, `:963`), `settings/device_sync_section.dart`, `settings/sync_devices_screen.dart`, `custom_fields_screen.dart`, ARB (about 3–4 keys).
- **Size:** M (~200). **Model:** Sonnet.
- **Depends on:**
  - #1993 and #2002 (`dance_detail_screen.dart`);
  - #1994 (`program_editor_screen.dart`);
  - U1, which also edits `custom_fields_screen.dart` (different hunks).
- **Severity:** UX5-3 M, UX5-4 L.

### U9 `fix/empty-states`: one empty-state pattern (after D-5 and D-6)

- **Items:**
  - **UX5-2:** a shared `widgets/empty_state.dart` (icon, title, body, optional action), applied per D-6.
    - "No dances match your search" gets a Clear search button, reusing `collectionClearSearchTooltip`'s wording.
  - **UX5-1b:** the empty Collection offers Import dances and New dance, and optionally Browse published collections, reusing the existing labels.
  - **UX5-1a**, only if D-5 changes the seed (mark it as a sample, or drop it):
    - update `seed_service.dart`;
    - update the store-review notes;
    - update `getting-started.md:61`, unless D2 already fixed it.
- **Main files:** a new widget; about 10 list screens (see the UX5-2 table in the verifier notes: venues, custom fields, custom figures, shorthands, snippets, tag colours, Recently deleted, custom themes and Collection); ARB (about 9 titles if D-6 picks the full pattern).
- **Size:** M (~300). **Model:** Sonnet. If D-5 picks "mark the seed as a sample", that part needs a provenance or tag on the seed. Make it a separate small PR, possibly Opus, because it touches stored data and could need a privacy-registry check if it adds a settings key.
- **Depends on:** D-5, D-6 and U8 (both edit `dance_list_screen.dart`, in different hunks).
- **Severity:** UX5-1 M, UX5-2 L.

### U10 `fix/readable-width`: reading width on desktop

- **Items:**
  - **UX6-1:** a new `widgets/readable_width.dart` with one constant (D-8; default 760, the wireframes' width). Apply it to dance detail, the dance editor form, the Settings content pane and the user guide's text.
    - *My call:* apply it as symmetric padding computed in a `LayoutBuilder`, rather than `Center` + `ConstrainedBox`, so the scrollbar and the scroll area stay at the window edge.
    - The program screens are left out until F11 lands.
  - **UX6-3:** Type and Formation take floating labels, and the chip pickers keep their headings. Add one line to `docs/design/ux.md` stating the rule.
    - *My call:* option (A) under D-12, floating labels for inputs and headings for chip groups. If the maintainer prefers headings everywhere, it is the same size.
- **Main files:** the new helper, `dance_detail_screen.dart` (`_buildBody`), `dance_editor/dance_editor_form.dart` (`:253`, `:314-330`), `settings_screen.dart` (`:205`), `user_guide/user_guide_doc_view.dart` (`:147`), `docs/design/ux.md`, one width test.
- **Size:** S (~120). **Model:** Sonnet.
- **Depends on:** #1993, #2002 and #2003 touch dance detail and the form, but not these lines. Expect a trivial rebase.
- **Severity:** UX6-1 M, UX6-3 L.

### U11 `fix/visual-tokens`: headers, snackbar theme, token literals

- **Items:**
  - **UX7-2:** drop both `toUpperCase` calls, and replace `_EditorHeader` with `SectionHeader`.
    - Update the uppercase assertions in `settings_screen_test.dart` and `dialect_editor_screen_test.dart`.
    - Add `Semantics(header: true)` to `SectionHeader` (a verifier finding).
    - Optionally migrate the 10 hand-built headers.
  - **UX7-4, theme only:** add a `snackBarTheme` with `behavior: floating` in `theme/component_themes.dart`. Leave durations alone: the theme can't set them, and a 123-site helper sweep is not worth it for a Low item.
  - **UX7-5:**
    - the 21 on-scale radius literals → `AppShapes`;
    - the 4 in-app font sizes and 2 header gaps → tokens;
    - the 9 form dropdowns → `DropdownButtonFormField`.
    - **Skip** the hot files (`program_editor_screen.dart`, `import_review_screen.dart`, `figure_list_editor.dart`) and the 18 off-scale values. Rounding those needs a visual call, so leave them for U12 or a later pass.
- **Main files:** `widgets/collapsible_section.dart`, `widgets/section_header.dart`, `dialect_editor_screen.dart`, `theme/component_themes.dart`, `settings/appearance_section.dart`, `theme_editor_screen.dart`, `custom_fields_screen.dart`, `venue_editor_sheet.dart`, `widgets/advanced_query_builder.dart`, `app_shell.dart`, `skeleton.dart` (leave the pill).
- **Size:** M (~250). **Model:** Sonnet.
- **Depends on:** **#1993**, which rewrites `undo_snack_bar.dart` (so its explicit `behavior` becomes redundant after this lands), and U1 (`venue_editor_sheet.dart`, `custom_fields_screen.dart`, `theme_editor_screen.dart`; different hunks).
- **Severity:** all L.

### U12 `fix/notices-and-icons` (after D-9 and D-10)

- **Items:**
  - **UX7-1:** a shared `NoticeCard(kind: info | warning | error, icon?, title?, child)`.
    - Migrate the nine boxed notices, keeping their `ValueKey`s.
    - Non-blocking warnings use the D-9 palette.
  - **UX7-3:**
    - (a) remove-from-list icons per D-10;
    - (b) one warning glyph family;
    - (c) the outlined copy icon. Leave the shape-coded stars.
    - (d) is folded into F10.
- **Main files:** a new widget, `widgets/warnings_card.dart`, `program_editor_screen.dart:4244` (only `_ProgramWarningsCard`), `import_review_screen.dart` (5 sites), `theme_editor_screen.dart`, `venue_editor_sheet.dart`, and about 10 files for icons (including `figure_list_editor.dart`, `defaults_section.dart` and `main.dart` ×4).
- **Size:** M (~300). **Model:** Sonnet.
- **Depends on:** D-9, D-10, all four in-flight PRs (they touch `import_review_screen.dart`, `main.dart`, `figure_list_editor.dart` and `defaults_section.dart`), U11 (shared theme files), and F10 if it is in flight when this lands (one card in `program_editor_screen.dart`).
- **Severity:** UX7-1 M, UX7-3 L.

### Folded into F10: UX7-3d

The matrix's "alternates" and "phrases" toggles show their state only in the tooltip (`program_editor_screen.dart:3331-3352`). F10 already edits the matrix rows (`:3167-3181`) and header (`:3385`) of the same table. Add `isSelected` and `selectedIcon` to the two `IconButton`s there: about 10 lines and one test. *My call:* folding this into F10 avoids a third branch editing the matrix code between F10 and F11.

### Not yet a branch: UX6-2 (after D-11, F11 and D2)

UX6-2 needs three convention decisions (D-11). Once they are made, the work is:

- put the Save, New and header rule into `docs/design/ux.md`;
- correct the false §2/§3 citations in `dance_editor_screen.dart:940-944` and `dance_detail_screen.dart:966-968`. Correct these even if the conventions stay as they are;
- adjust the screens that break the rule.

It touches `program_editor_screen.dart` and `program_summary_screen.dart`, so it goes after F11, and it edits ux.md, so it goes after D2. Sonnet, M.

## Needs a decision

Each decision is listed with its options. None has been made, and the plan assumes none. Where I state a preference, it is mine.

| # | Decision | Items | Options |
| --- | --- | --- | --- |
| D-1 | Which button is primary in "Discard changes?" | UX2-2 (U1) | (a) The dialect pattern everywhere: Cancel · Exit without saving · **Save and exit** (the audit's proposal). (b) Two buttons, with **Keep editing** primary and Discard as a red text button. (c) Keep today's red filled Discard, which #1919 introduced. |
| D-2 | Which slot-row controls stay visible below 600px | UX4-1 (U7) | (a) Only drag and ⋮; view, up, down and cut move into ⋮. This frees about 170px. (b) Keep cut visible (the #1270 scissors) and move view, up and down; the title gets about 48px, still cramped. (c) Keep view visible and move up, down and cut. Long-press preview already covers view. I lean to (a), with up and down first in the menu. |
| D-3 | One name per meaning | UX3-2, UX3-5 (U4) | **Custom figure:** (i) "unrecognized figure" plus "your own figures", the setting renamed (the audit's proposal); (ii) rename only the unparsed meaning and keep the "Custom Figures" setting; (iii) only merge the four variant names of the user's own figures. **Trash:** "Recently deleted" (the screen name) or "trash". **Share files:** "share file" or "Compendium file". **People:** "author" (24 uses) or "choreographer" (6). Also, optional: whether a custom field's machine key stays visible or is derived from the label. |
| D-4 | US or UK spelling, case and quote style in app strings | UX3-6 (U5) | Spelling: US (the app already says "neighbor") or UK (20 "colour" strings). Case: sentence case for titles and settings (the de facto majority) or keep Title Case for screen titles. Quotes: curly everywhere, straight everywhere, or new strings only. Whichever is chosen, write it into the style guide. |
| D-5 | What the first-run seed dance is (with INTAKE-12) | UX5-1 (U9) | (a) Keep the seed and show a "bring your dances in" card while only the seed is present. (b) Keep it but mark it as a sample, with a "remove sample" action; this also answers INTAKE-12. (c) Drop the seed and let the improved empty state show; update the store-review notes. (d) Seed only if nothing is imported in the first session; the most complex. #336 (merged by @ibanner56) chose "never empty", so (c) reverses it. |
| D-6 | One empty-state design | UX5-2 (U9) | (a) Icon, title, body and action on every list. (b) The full pattern for primary lists (Collection, Programs, Venues, Custom figures, Recently deleted), and one line inside Settings sub-lists. (c) Leave it as it is. The verifier leans to (b). |
| D-7 | Perform beats label on narrow screens | UX4-2 (U6) | (a) Cap the label's text scale at about 1.3 (my default). (b) Stack the label under the figure below about 400px. |
| D-8 | Reading width | UX6-1 (U10) | 760 (the wireframes; my default), 720 (the guide's images), or about 840 (keeps Progression and Rating side by side). |
| D-9 | Notice palette and shape | UX7-1 (U12) | Non-blocking warnings in **tertiary**, like the editors, or **error**, like import. A flat container, or an elevated `Card`. |
| D-10 | Remove-from-list icon | UX7-3a (U12) | (a) `remove_circle_outline` for "remove from this list", `delete_outline` for deleting a record, and `close` only on chips. (b) `close` everywhere a row is removed. The verifier leans to (a). |
| D-11 | Sibling-screen conventions | UX6-2 | **Save:** (A) always an extended FAB; (B) always the app-bar "Save" (already 5 of 7 editors); (C) a FAB for the two long editors and the app bar elsewhere, written down as the rule. **New:** (A) a FAB on top-level lists, a button inside Settings sections, "+" only where a FAB would cover content; (B) a FAB everywhere. **Header:** (A) the record's name in the app bar on both detail and summary; (B) keep both bodies and move the summary's actions into its app bar. |
| D-12 | Editor field labels | UX6-3 (U10) | (A) Floating labels for inputs, headings for chip groups (my default). (B) Headings everywhere. |
| — | Outside this audit, from the trash-policy question already blocked in batch-plan.md | UX5-4a | Keep confirm-only (the stated `ux.md` rule); confirm plus a "Deleted" snackbar; or Undo instead of confirm, which needs soft delete for settings-backed items and the LIFE-4/LIFE-9 answer. No branch until that is decided. |

## Sequencing against F10, F11, D2 and the in-flight PRs

**State on 2026-10-29:**

- **In flight:** #1993 (F14), #1994 (F16), #2002 (F6) and #2003 (F3).
- **Planned, not started:** F5b, F10, F11 and D2. The batch plan's waves are W3 (F5b), W4 (F10) and W5 (F11, D2).

**Hot files:**

| File | Behaviour-audit work | UX branches, in landing order |
| --- | --- | --- |
| `program_slot_list_editor.dart` | F5b may extract a helper (`:291-310`); F10 edits `_slotTitle` (`:146-149`) | U7 (rows `:498-704`) |
| `program_editor_screen.dart` (4,337 lines) | #1993 (+2), #1994 (+12) → F10 (lookup, `_removeSlot`, matrix) → F11 (`:1943`, `:2796`) | U1 (discard dialog) and U8 (load error), small hunks after #1993 and #1994; U7 (app bar) before F5b and F10; UX7-3d inside F10; U12 (one card) after F10; UX6-2 after F11 |
| `program_summary_screen.dart` | #1993 (+2) → F5b (rows around `:733`, mark-all) → F10 → F11 (`:609-647`) | U7 (header `:709-745`) before F5b; UX6-2 after F11 |
| `perform_program_screen.dart`, `add_to_program_sheet.dart`, `programs_shell.dart` | F10, F11 | none: U6 fixes the tap-tempo sheet inside its own widget |
| `docs/design/ux.md`, `docs/user/settings.md`, `getting-started.md` | D2 | D2 also takes `getting-started.md:61`; U10's one ux.md line can go before D2 (a different section); U4 and UX6-2 after D2 |
| `docs/user/programs.md` | F5, F6 and F10 edit it; D2 does not | U7 (`:216-219`) |
| ARB files (6) | every in-flight PR | every UX branch except U10; put each key beside its related keys |
| `undo_snack_bar.dart` | #1993 rewrites it | U11 after #1993; U2's Undo uses #1993's signature |

**Decisions on F10, F11 and D2:**

- **F10: fold UX7-3d in** (about 10 lines in the matrix header F10 already edits). **Sequence U7 ahead of F5b and F10.** U7 carries this audit's only High, F5b and F10 haven't started, and U7's hunks (row controls, app bars, summary header) don't overlap their logic. F5b and F10 rebase onto U7, rather than U7 waiting behind three program branches.
  - The rejected alternative, folding UX4-1 and UX4-4 into F10, would take F10 from about 380 to about 680 lines and mix layout with slot-resolution logic.
  - **Coordinate with F5b:** its per-row performed toggle adds a control to summary rows (not to the builder's slot rows). U7 should leave room for it in the summary layout, and F5b should check its row at 360px.
- **F11: nothing folded.** No UX item is about stale state. U6 keeps its tap-tempo fix inside `tap_tempo_metronome.dart`, so it doesn't touch `perform_program_screen.dart`. U10 leaves the program screens out until F11 lands. UX6-2 waits for F11.
- **D2: fold one line in.** `getting-started.md:61` ("Your collection starts empty") sits beside the INTAKE-11 lines D2 already rewrites. If D-5 changes the seed before D2 starts, write the sentence to match. U4 and UX6-2 land after D2.

**UX waves:**

1. **UW1, start now (3):** U6, U10 and U2. U6 and U10 add no strings, and rebase trivially on #2002 and #2003. U2 adds 1–2 strings and an Undo, so write it against #1993's `showUndoSnackBar` signature, or start it just after #1993 merges.
2. **UW2, after the four in-flight PRs merge (5):** U1, U3, U7 (once D-2 is answered; ahead of F5b and F10), U8 and U11.
3. **UW3, after the decisions (4):** U4 (after D-3 and D2), U9 (after D-5 and D-6), U12 (after D-9 and D-10), and U5 last (after D-4 and U4).
4. **After F11 and D2:** the UX6-2 conventions branch, and U10's extension to the program screens.

Each subagent verifies its own edits with `tools/preflight.py --fast` or `--only`. The session that owns each PR runs the full preflight once, on the final tree. A full run takes a machine-wide lock, so stagger dispatch.

## Side findings (not in the audit)

- **German "Takte":** `danceFigureBeats` is "{beats} Takte" (`app_de.arb:4423`). "Takt" usually means bar or measure, not beat. This looks like a mistranslation. It needs a fluent reviewer, not an agent; list it in the next translation pass.
- **Framework detail for every future sheet with input:** `PopScope` does not stop swipe-down or a tap on the drag handle (`bottom_sheet.dart:769-772`).
- **`SectionHeader` has no header semantics:** handled in U11.
- **Two code comments cite `ux.md` §2/§3 for rules those sections don't contain:** handled with UX6-2.
- **A comment promises an error scroll that doesn't exist:** handled in U2.

## Unverifiable here

- **The audit's "Seen" items on screen** (UX5-1, UX6-1, UX6-2, UX6-3). They were re-checked in code, and by arithmetic for the widths; no app build was run. The 900px and 1,250px width figures were not reproduced.
- **Device behaviour:** sheet dismissal by swipe (UX2-1d/e) was read from the Flutter source, not run on a device. UX4-6's target sizes were read, not checked with a semantics test.
- **Authorship:** whether the maintainer personally chose:
  - the red Discard (#1919);
  - the seed (#336);
  - the Save FABs (#143, co-authored by Copilot);
  - the Undo snackbar design (#498, authored by the `isaacbanner` account);
  - the #1270 cut wording.

  Each was merged from the maintainer's account; none was confirmed as the maintainer's own wording.
- **History before #1902:** it is squashed in this clone, so who wrote most of the older strings and design-doc lines (including `ux.md:186-189`) could not be traced.

## Check list: all 30 items, each placed once

| Item | Verdict | Now | Placement |
| --- | --- | --- | --- |
| UX2-1 | Confirmed, re-rated | M | U1 |
| UX2-2 | Confirmed | M | U1 (D-1) |
| UX2-3 | Confirmed | M | U2 |
| UX2-4 | Confirmed, re-rated | L | U2 |
| UX2-5 | Confirmed | L | U2 |
| UX3-1 | Confirmed, re-rated | M | U3 |
| UX3-2 | Confirmed, re-rated | M | U4 (D-3) |
| UX3-3 | Confirmed, re-rated | M | U3 |
| UX3-4 | Confirmed, re-rated | L | U3 |
| UX3-5 | Confirmed, re-rated | L | U4 (D-3) |
| UX3-6 | Confirmed, re-rated | L | U3 (plurals), U5 (rest; D-4) |
| UX3-7 | Confirmed | L | U3 |
| UX4-1 | Confirmed | **H** | U7 (D-2) |
| UX4-2 | Confirmed, re-rated | M | U6 (D-7) |
| UX4-3 | Confirmed (e not reproduced) | M | U6 |
| UX4-4 | Confirmed | M | U7 |
| UX4-5 | Confirmed | M | U6 |
| UX4-6 | Confirmed | L | U6 |
| UX5-1 | Confirmed, re-rated | M | U9 (D-5); `:61` docs line → D2 |
| UX5-2 | Confirmed, re-rated | L | U9 (D-6) |
| UX5-3 | Confirmed | M | U8 |
| UX5-4 | Confirmed, re-rated | L | U8 (4b); 4a waits on the trash-policy decision |
| UX6-1 | Confirmed | M | U10 (D-8); program screens after F11 |
| UX6-2 | Confirmed, re-rated | L | Conventions branch after D-11, F11 and D2 |
| UX6-3 | Confirmed | L | U10 (D-12) |
| UX7-1 | Confirmed | M | U12 (D-9) |
| UX7-2 | Confirmed, re-rated | L | U11 |
| UX7-3 | Confirmed, re-rated | L | U12 (a–c; D-10), F10 (d) |
| UX7-4 | Confirmed | L | U11 |
| UX7-5 | Confirmed | L | U11 (on-scale and outside hot files); off-scale values with U12 |

**Totals:** 30 items. 15 confirmed as rated, 15 re-rated (all down), 0 fixed or partly fixed by a later PR, 0 not reproduced. One High remains (UX4-1). 12 fix branches, one item folded into F10, one conventions branch after F11 and D2, and 12 decisions (D-1 to D-12).
