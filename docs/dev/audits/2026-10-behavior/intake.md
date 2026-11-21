# Defensive intake of the October 2026 behavior audit

This is a second opinion on `README.md` (the synthesis) and the nine reports in `reports/`, written for the maintainer before anyone acts on them. Everything was checked against main at a6665db.

**How this was done.** Eight verifier agents each took one cluster of findings. Each re-read the cited code, looked for guards on the path, checked settings defaults, searched tests, ADRs, design and user docs, changelog and git history, and read GitHub issues and PRs (read-only). Where it settled a question, they ran targeted tests or probes in scratch copies outside the tree: dart tests in copies of `compendium_core` and flutter widget or controller tests in a copy of `app/`. I re-checked the reversals and the load-bearing defaults myself:

- **PLAT-1:** read `pubspec.lock` and the share_plus 13.3.1 iOS source in the pub cache.
- **AUTH-1:** checked the Free-text entry default in `dance_editor_screen.dart:350-358`.
- **LIFE-1:** re-read `recently_deleted_screen.dart:339-345` and `purgeDeleted` in `dance_repository.dart:1932-1937`.
- **UX leftovers:** checked the claim myself.

Nothing was run on a device. Some agents hit GitHub search rate limits, so "no tracking issue found" means no match in open issues and in title and keyword searches; it does not mean "proven untracked". Where a verdict says a decision was made, the entry says who made it and where, and flags when the author of an issue comment could not be confirmed as the maintainer.

## Overall assessment

- **The mechanisms are reliable.** Of 110 findings checked, 1 was not reproduced outright (PRES-8) and 1 high was refuted in its harmful part (PLAT-1). Every other finding describes code that behaves as stated, at least in part. Several were confirmed by running tests: LIFE-1, OUT-1, OUT-2, GIG-2, GIG-3, AUTH-1, AUTH-2, AUTH-4, PLAT-2, INTAKE-9, FIND-2, FIND-4, FIND-5 and FIND-16.
- **Severity is inflated, systematically.**
  - Of the 22 highs, **3 stay High**: LIFE-1, INTAKE-1, and OUT-1 for related-dance links. 18 become Medium, and PLAT-1 becomes Low.
  - Among medium and low findings, about a third are rated too high.
  - The usual reasons:
    - the path needs an opt-in or experimental setting (Free-text entry, Auto-save, Device Sync, venue records);
    - the harm is display-only and the stored data is intact;
    - part of the behaviour was decided earlier and the auditor didn't find where.
- **The synthesis counts duplicates and decided behaviour as defects.** "144 findings" is about 130 distinct issues. Several of its "decisions for the maintainer" were already made: swipe-to-delete, "any program counts" as called, settings sync, exact-phrase search, and no per-dance prompt on program import.
- **The suggested order is right to start with small fixes, but its first list is wrong in places.** It includes a refuted item (PLAT-1), omits the second-worst confirmed bug (INTAKE-1), and understates the size of OUT-1, GIG-3 and AUTH-1/2. Its step 3, "unify intake", is unnecessary: six targeted fixes remove every high in that theme, and a full unification would reverse maintainer rulings (#797, #811, #1627).

## Verdicts on the 22 high findings

Counts:

| Verdict | Count |
| --- | --- |
| Confirmed, stays High | 2 |
| Confirmed with narrower scope, stays High for that scope | 1 |
| Confirmed, re-rated Medium | 14 |
| Partly confirmed, re-rated Medium | 4 |
| Not reproduced, now Low | 1 |

"Layer" says what was actually checked.

| ID | Verdict | New sev. | Key evidence and reasoning | Layer |
| --- | --- | --- | --- | --- |
| LIFE-1 | **Confirmed** | High | `permanentlyDelete` soft-deletes the item at 1970, then calls `purgeDeleted` with the default 30-day retention (`recently_deleted_screen.dart:339-345`, 368-373), which removes every row deleted more than 30 days ago (`dance_repository.dart:1932-1950`; programs the same). A scratch test with trash {A 5d, B 60d, C 10d}: deleting A also removed B. It only bites users who chose Never or 90 days, which are exactly the users who asked to keep things. Silent, irreversible data loss. | Ran a test in scratch; re-read the code myself |
| INTAKE-1 | **Confirmed** | High | Re-importing a dance the caller already has defaults to skip (`import_review_screen.dart:1169-1181`, #446). Skipped rows are left out of the commit (`:1335-1372`). The id maps used to link program slots contain only records that succeeded (`callers_companion_usr_import.dart:928-939`, `compendium_archive_import.dart:1058-1080`), so existing slots are rewritten to "Dance not imported (…)" placeholders. No test covers this. It is silent damage to program data on a normal re-import. | Re-read code; traced UI to core |
| OUT-1 | **Confirmed, narrower scope** | High (related-dance links); Low (URL links) | The probe was re-run and all three failures reproduce. A **related-dance** link always fails the import (FK error, 0 dances; a program slot becomes "Dance not imported"), even when the target dance is in the same file. Related links are common: Import as a variation adds one, the editor adds reciprocal ones, and every CC `Dance_Related` pair becomes one. A **URL** link imports the first time and fails only on a round trip (UNIQUE on `dance_links.id`). "Any link" overstates it. | Ran probe in scratch; re-read codec, remap and repository |
| AUTH-1 | Confirmed, re-rated | Medium | Widget test: a typed line that hasn't been entered is dropped on Save, and Back closes without a discard prompt. The composer exists only with **Free-text entry on, which is off by default** (`dance_editor_screen.dart:350-358`, which I checked). The guide line "nothing you type is ever thrown away" refers to unparsed text, not to un-entered text, so the report over-quotes it. | Ran widget test in scratch; re-read code |
| AUTH-2 | Confirmed, re-rated | Medium | A controller test with 4 rows built 1 figure. Model tests pin `toFigure()` returning null, but nothing pins a silent drop at Save. The meanwhile two-sides rule is documented (authoring.md:393-395). The beat Total counting groups that won't be saved, and a move-less row losing its note, are not documented. | Ran controller test; re-read code |
| AUTH-3 | Confirmed, re-rated | Medium | The renderer never reads notes on meanwhile sides or modifier children. A probe renders "allemande right 1 1/2" as "once". The data is kept, and the shape is rare in contra. Shares a root with AUTH-4. | Re-ran probe; re-read renderer and consumers |
| AUTH-4 | Confirmed, design partly deliberate | Medium | Every probe row reproduces, plus two the auditor didn't script. "Keep the structured reading and put the rest in a note" is designed and pinned (`neighbors swing slowly` test). The narrow leftover rule was scoped in #1612; it was filed under the owner account, but the verifier could not confirm the maintainer wrote it. The failing cases are what #1612 meant to stop, and no test pins them. The note stays visible; wrong beat counts shift sections. | Ran probe in scratch; read classifier, tests, #1612 |
| GIG-1 | Confirmed, re-rated | Medium | No bulk path checks `isAlt` (`program.dart:613-616`), and a scratch test gave the alternate a history row. In default mode alternates count anyway, as programs.md documents. The stamp matters only with "Require mark performed" on, and in the Last-called sort. Nothing decides the alternates question: #356 and PR #390 settled "dance-linked slots" only. | Ran core test in scratch; grepped every history consumer |
| GIG-2 | Confirmed, re-rated | Medium | A scratch test under `TZ=America/New_York` shows the stamp `2026-10-24T00:00Z` as 23 Oct; the same test passes under UTC. Default settings reach it, and it affects every North American caller who uses Status → Performed. Only the displayed date is wrong; the stored value is the event date. Using the event date as the stamp was approved by the maintainer in #356, so the display fix needs no decision. | Ran test in two time zones; re-read the display function |
| GIG-3 | Confirmed, **wider** than reported, re-rated | Medium | A scratch test replaying the editor's writes turns stamps `(24 Oct, 24 Oct)` into `(null, null)`. Auto-save is off by default (`main.dart:598-603`), **but** the same loss is reachable with auto-save off through GIG-4: set Performed, open Perform from the builder, then make two adjustments. Losing stamps changes what's shown only with "Require mark performed" on. | Ran core test in scratch; checked the default |
| FIND-1 | Partly confirmed, re-rated | Medium | It is a real gap, but a **missing feature**, not a defect. #1084 (a beta user) asked only for Called / Not called, which shipped. #1238 (owner) added venue repeats to the detail page. No open issue asks for a venue or recency filter. | Re-read code; read issues |
| FIND-2 | Confirmed, re-rated | Medium | `_sortByLastCalled` (`dance_repository.dart:2996-3047`) uses performed slots only and has no caller scope. That breaks the owner-filed #583 requirement that history honour the caller filter "in lockstep". A probe sorted another caller's program first. No data loss. GIG-5 is the same finding. | Ran probe; read #583 |
| OUT-2 | Confirmed, re-rated | Medium | A probe imported the sender's rating, Performed status, pay and dialect, and the dances counted with default settings. **New:** importing a Performed program also stamps slots the sender never marked. sharing.md:149 documents pay travelling, but that text came from docs PR #1893 and no maintainer ruling was found. See also the privacy-registry gap under "Missing". | Ran probe; re-read code |
| INTAKE-2 | Confirmed, partly deliberate | Medium | `_sameField` also compares showInList, searchable, shareable and label (`share_metadata_import.dart:404-414`). The refusal itself is documented (sharing.md:76-78), and a test pins it **for a type mismatch only**. Nothing justifies treating display flags as conflicts. **New trigger:** Caller's Companion labels "Card" and "card" make the same key with different labels, so the import is refused. | Re-read code, tests, docs |
| INTAKE-3 | Confirmed; "no prompt" decided | Medium | "No per-dance prompt on program import" is the maintainer's ruling (#797), pinned by `contradb_program_import_test.dart:410-443`. Creating a duplicate rather than linking an identical existing dance was the implementing agent's choice (PR #812), and the title-list path does the opposite (#685). | Re-read code, test, #797 |
| INTAKE-4 | Partly confirmed | Medium | Backing out and Undo both leave the imported dances, contrary to programs.md:118. The default-tags bullet is deliberate (tester request #1476, settings.md:396-400). | Re-read code and docs; read #1476 |
| FIND-3 | Confirmed as a missing feature | Medium | `tag_colors_screen.dart:23-26` defers tag rename and delete as separate work; that comment came from docs PR #1893, not a recorded maintainer decision. No roadmap item or open issue covers it, so the gap is real and untracked. It is not a defect. | Re-read code; roadmap and issue search |
| FAIL-1 | Confirmed, re-rated | Medium | `backup_io.dart:254-261` discards the `ShareResult` and returns true. share_plus 13.3.1 **does** report a dismissed sheet on both iOS and Android, so the comment that completion "isn't reliably observable" is half wrong. No data is lost, but the false "Backup exported." also resets the overdue reminder, which is the app's only backup nudge. Kept near the top of the priority list for that reason. | Read the plugin's native source for the pinned version; traced the call to the snackbar |
| FAIL-2 | Confirmed, re-rated | Medium | Offline is reported as "No confident online matches". There is no Cancel, and leaving the screen does not stop the work. The sibling title-list import *does* stop on `connectionFailed`. The test pins only "does not throw". It is a false "nothing found", not data loss. | Re-read code; traced to the snackbar |
| FAIL-3 | Partly confirmed | Medium | The current wording is documented in settings.md:458-461. ADR-002 §5 (status: Proposed) forbids an error **dialog** but does not require a failure to read as "No update found". "Stranded by a key rotation" is a **future** risk: no rotation has happened and the next-key slot is empty. A future manifest-schema bump would strand old installs with no mitigation. | Re-read code, ADR, runbook, user doc |
| LIFE-2 | Partly confirmed | Medium | **Keeping the deletion record is deliberate:** sync-spec.md §3.1-3.2 (a published record is never hard-deleted; `published_records` is monotonic) and storage.md ("retained as tombstones indefinitely"). ADR-004 was accepted with @ibanner56 as decider, but no separate ruling on retention was found. **The UI part is a real bug:** the snackbar says "permanently deleted" unconditionally, and the item stays in the trash ("Kept until you delete it" under Never retention). Device Sync is behind Settings › Experimental. | Read spec, ADR, storage.md; ran test in scratch |
| PLAT-1 | **Not reproduced** (the harmful part) | Low | `pubspec.lock` pins share_plus **13.3.1**. Its 13.3.0 changelog says "Avoid exceptions on iPads with no sharePositionOrigin (#3769)", and `FPPSharePlusPlugin.m` falls back to a 2×2 pt anchor at the centre of the view. The sheet opens, just anchored mid-screen. The missing origin is real; "very likely to fail" is not. | I read the lockfile, the changelog and the native source in the pub cache myself. Not run on a device |

## Medium and low findings: sample and error rate

I checked all 71 non-high findings that the synthesis cites in its themes or decisions, plus a systematic sample of 17 of the remaining 51. The sample took every third finding in report order, chosen without regard to plausibility: AUTH-5, -11, -14, -17, FAIL-12, -15, FIND-7, -12, -16, GIG-14, INTAKE-9, -15, OUT-5, -9, PLAT-16, PRES-8 and PRES-13.

| Outcome | Cited set (71) | Random sample (17) | All 88 |
| --- | --- | --- | --- |
| Confirmed as rated | 31 | 11 | 42 (48%) |
| Confirmed, severity lowered | 23 | 4 | 27 (31%) |
| Partly confirmed (part wrong, deliberate or overstated) | 13 | 1 | 14 (16%) |
| Deliberate (the behaviour was decided or documented) | 4 | 0 | 4 (5%) |
| Not reproduced | 0 | 1 | 1 (1%) |

**Error rates to calibrate the unchecked 34:**

- **Plainly wrong:** about 1–6% (1/88 overall; 1/17 in the random sample). The code described is real.
- **Wrong about whether it's a defect:** a further ~5% are deliberate, and about 16% have a deliberate, documented or overstated component.
- **Severity too high:** about 30% (27/88; 4/17 in the random sample). No re-rating went up. LIFE-3 is a half-step ("Low–Medium").
- **Rule of thumb:** trust the mechanism, discount the severity by one step about a third of the time, and look for a prior decision before calling something a bug.

**The deliberate and not-reproduced ones:**

- **PRES-8, not reproduced:** `renderFreeText` maps only internal role tokens. A probe shows "larks" stays "larks" with the switch on or off.
- **PRES-5, deliberate:** see "Decisions already made". Two help pages are stale.
- **GIG-16, deliberate:** host caller only for v1, per a triage comment on #583 under the owner account. The verifier could not confirm the maintainer wrote it.
- **INTAKE-10, deliberate:** a "Do not fix" code comment and #687. It is also only reachable with venue records on, which is off by default.
- **LIFE-11, documented** (dialects.md:339-342). The text came from docs PR #1893; no maintainer decision was found.

**Notable partial verdicts:**

- **FAIL-6:** the "no undo-failed string anywhere" claim is wrong (one exists, and two screens use it). Scenario B duplicates INTAKE-4.
- **PRES-1:** ADR-004 (Accepted, decider @ibanner56) says settings sync. What's missing is disclosure.
- **PRES-2:** the synthesis's "first connection silently overwrites" is false for custom themes. They are a whole-collection key, so a conflict is queued for the caller (`sync-spec.md:2781-2789`).
- **PLAT-3:** imports.md and sharing.md already scope file-open to Apple platforms; only faq.md over-promises.
- **INTAKE-5:** the fuzzy-title example is now caught by the #1907 possible-match prompt.
- **GIG-12:** stamping only on the status transition is the maintainer-merged design (#390, fixing #356).

The full per-finding tables, with file:line evidence, are summarised in the appendix at the end of this file.

## Critique of the synthesis

### Themes

| Theme | Assessment |
| --- | --- |
| "Called" means something different on each screen | **About half real.** The badge, Called / Not called filter, detail history, half stats and venue counts already share one caller clause and the performed setting, and they agree. The real divergences are the Last-called sort (FIND-2/GIG-5), the lack of a rule for which date a call carries (GIG-2), and alternates (GIG-1, GIG-9). "Called ×4 counts every program" is the **documented default** (programs.md, settings.md, ROADMAP G.2, #583). OUT-2, LIFE-6, LIFE-7, GIG-7, PRES-4, GIG-12, GIG-16 and FIND-1 have separate causes that "one shared query" would not fix. GIG-13 restates OUT-2 + LIFE-7, and GIG-5 restates FIND-2, so the 15-ID list counts about 4 findings twice. |
| Each way in is a separate import feature | **Real in the wrappers, not in the core.** There are about 9 intake routes (~13k lines; the review screen alone is 4,001), but they all commit through the same pipeline. The highs come from four specific bugs (INTAKE-1, -3, -4, OUT-1), not from the lack of a single review step. Routing program and single-dance imports through review would reverse #797, #811 and #1627. |
| The app reports success when nothing happened | **Grouped by symptom, not by cause.** At least four mechanisms sit under it: an ignored return value (FAIL-1); a typed failure collapsed into one message (FAIL-2, -3, -5, -9; the only group with a truly shared cause); async callbacks with no catch (FAIL-4, -15, FIND-11, FAIL-6); and unrelated bugs (LIFE-2 is a data-model issue, OUT-1 an import bug, OUT-10 an export filter). Device Sync's failure types are specific to sync's HTTP server and have no disk or permission classes, so they carry over as a **pattern** for network features only, not as code. |
| Typed input disappears without a warning | **Real, and the best of the seven.** It has a plausible shared fix: Save keeps what's on screen or says what it leaves out. GIG-3, GIG-4 and GIG-6 are a different cause (stale snapshots written back) and should be split out as "stale copies overwrite newer data". That pattern also covers GIG-19 and LIFE-14. |
| Delete and trash follow different rules | **Real, but mixes a bug, a missing feature and a design question.** LIFE-1 and LIFE-3 are bugs; FIND-3, LIFE-5 and FIND-9 are missing features; LIFE-2 rests on a deliberate sync design. GIG-11, LIFE-8 and OUT-7 are one finding (how a trashed dance renders) counted three times. |
| Settings stop short of some screens | **Mixes three things.** (a) Settings not reaching screens (PRES-3/OUT-3/GIG-18, PRES-7, PRES-10, PRES-4): the "one live source, one renderer" direction fits. (b) Sync classification and disclosure (PRES-1, -2): this needs a decision, and the renderer direction does nothing for it. (c) Already-decided behaviour with stale docs (PRES-5, -6). FIND-15 and PLAT-15 are one finding. The "first connection silently overwrites custom themes" sentence is false (see PRES-2). |
| Desktop and mobile conventions | **Direction right, two sentences wrong.** "On iPad, the backup export's share sheet is very likely to fail" is false (PLAT-1). The Windows/Linux sentence needs a qualifier: the docs already scope file-open to Apple platforms. The update-banner sentence applies only after the user turns automatic checks on (installation.md already tells Play users they don't need it). What stands: the template menu and the "All rights reserved" text, keyboard-map drift (PLAT-7, against PR #59's claim), Perform not entering OS full screen, PLAT-2's false "empty file" message, and year-less dates (PLAT-12). |

**Inflation from double counting.** These findings appear under several numbers: FIND-2/GIG-5; GIG-13 ≈ OUT-2 + LIFE-7; FIND-3 ≈ LIFE-5 (tags half); GIG-11/LIFE-8/OUT-7; PRES-3/OUT-3/GIG-18; FIND-15/PLAT-15 (PRES-9 overlaps); FIND-7 ⊃ PRES-15; FAIL-6B/INTAKE-4; PLAT-11 = UX audit batch 2, item 1. The synthesis says it counts duplicates, but its themes and its "22 high" headline read as if the overlaps were independent confirmations.

### Severity calibration

The audit's scale treats any wrong output as High. For a beta app with a niche audience, High should mean silent loss of the caller's own data, or a core feature failing while reporting success, on a path default settings reach. By that bar, three findings qualify:

- **LIFE-1:** irreversible.
- **INTAKE-1:** damages programs on a routine re-import.
- **OUT-1, related links:** sharing, a core feature, fails while saying "Imported".

FAIL-1 is the closest Medium, because it silences the only backup reminder. Display-only errors (GIG-2, AUTH-3), opt-in paths (AUTH-1, GIG-3, LIFE-2) and missing features (FIND-1, FIND-3) are Medium at most.

### "Fix without a decision"

| Item | Really decision-free? | Really small? |
| --- | --- | --- |
| LIFE-1 | Yes | Yes. Call the existing `hardDelete([id])` in both screen configs, or add an id filter to `purgeDeleted`. A ~30–40 line test; low risk. Side benefit: no more 1970 timestamps. |
| AUTH-1 | **Partly.** "A non-empty composer counts as unsaved; submit or warn on Save and Back" is decision-free. Whether on-screen Done commits or cancels, and whether the Move box commits on blur, are maintainer calls. | ~40–80 lines across `figure_list_editor.dart` and `dance_editor_screen.dart`, plus tests; low-to-moderate risk. |
| AUTH-2 | **Mixed.** Excluding unsaveable groups from the Total (~5 lines) and keeping a move-less row with a note as a custom figure (~10 lines, as #679 does for sides) are decision-free. A "N rows won't be saved" prompt is a new dialog with strings in 5 locales (~100 lines), and it changes a documented meanwhile rule. | Split it. |
| OUT-1 | Mostly. One small call: a related link whose target isn't in the file gets dropped with an import note, following existing practice. | **Not small:** ~80–150 lines plus 3–4 tests (give links fresh ids in both import routes; re-add related links after commit through the existing id map; show failures in the share result). Moderate risk around Undo ordering. |
| FAIL-1 | Yes, if a dismissed sheet means "not exported" and every other result means "exported". | Yes. ~10 lines in `backup_io.dart` and `crash_log_io.dart`, a corrected comment and user doc, a changelog fragment, and a test with a fake share platform. |
| GIG-3 | Yes, but **only if fixed with GIG-4**. Re-stamping in the repository instead would reverse PR #390's rule that a slot cleared by hand is not re-stamped. | **Not a one-liner:** three stale copies (the auto-save result, the builder's save from Perform, Perform's own snapshot). ~30–60 lines in two screens plus 2–3 widget tests; moderate risk around bulk-Undo bookkeeping. |
| LIFE-3 | Yes for reading the setting for programs (~3 lines). Renaming the setting from "dances" to "items" is a minor wording choice touching 5 locales and settings.md. | Yes |
| FAIL-7 | Yes | ~10 lines (catch and log, as the seed step does), but it is Low, and most of the work is a test that makes the startup purge fail. |
| PLAT-1 | **Remove from the list.** The harmful part is not reproduced. Passing the anchor for consistency is optional (~20 lines). | — |

**Missing from the list, and just as decision-free:**

- INTAKE-1 (link slots to the dance a skipped row already points at, ~50 lines).
- INTAKE-4 (track dances created during program resolve and remove them on Undo or back-out, ~70 lines; programs.md:118 already promises this).
- The GIG-2 display (render a stamp copied from `eventDate` as a date, not via `toLocal()`).
- AUTH-6 (~5 lines).
- GIG-9 (~1 line).
- FIND-2's caller-scope half (~10 lines; #583 already requires it).
- PLAT-8's "All rights reserved" strings.
- PLAT-2's misleading "no dances" message for a backup opened via Open with.

### Suggested order

- **Step 1** is the right idea with the wrong contents: drop PLAT-1, add INTAKE-1, INTAKE-4 and GIG-2, and be honest that OUT-1 and GIG-3 are 100-line changes with tests, not one-liners.
- **Step 2** (settle the calling-history model) is right to come early, but the decision is smaller than framed. Most surfaces already agree. The open questions are (a) do alternates count, (b) which date a call carries, and (c) whether duplicated and received programs count. The rest is the FIND-2 sort, which #583 already decides.
- **Step 3** (unify intake) should be dropped as a step. Replace it with the targeted fixes in my list. A unification refactor of ~13k lines with a 4,001-line review screen has a high regression risk and would reverse maintainer rulings on programs and single-dance import.
- **Step 4** (one failure model) should be narrowed to the network features (FAIL-2, -3, -5, -9) plus an async-button error guard (FAIL-4, -15, FIND-11). It is a pattern, not a port of Device Sync code.
- **Step 5** is fine as a batch.

### Decisions the synthesis lists that are already made, fully or partly

| Synthesis "decision" | What is already decided, by whom, where |
| --- | --- |
| Confirm before delete vs swipe (PRES-5) | **Decided by the owner** on #352 ("Design decision (product owner)", 2026-07-20): swiping reveals Delete, and "the second tap *is* the confirmation". PR #392, written and merged by the maintainer, scopes the setting to the ⋮ menu, and `confirm_before_delete_test.dart` pins "no dialog on the swipe path". The owner did not address the accessibility angle explicitly. What remains is **doc drift**: `settings.md:67-68`, `accessibility.md:164-166` and two ⋮ code comments. This is a docs fix unless the maintainer wants to revisit. The UX audit artifact also records "Swipe-to-delete: keep it". |
| What counts as "called" | "Any program counts" by default is documented (programs.md, settings.md, ROADMAP G.2) and set by the owner-filed #583. The event date as the stamp was maintainer-approved in #356. Stamping on the status transition only was maintainer-merged in #390. **Still open:** alternates, and duplicated or received programs. |
| Which settings sync (PRES-1/-2) | ADR-004 (Accepted, decider @ibanner56): "Everything classified shareable, settings included — a paired device should feel like the same app". **Still open:** whether theme, locale and reduce-motion are exceptions (never discussed), and disclosure. The false "saved on this device" string is a bug either way. |
| How search matches (FIND-5) | The owner set exact-substring matching for 3+ characters in #1005. **Still open:** only the cross-field consequence, and the guide's "Type any words". |
| Re-import treatment (INTAKE-1/-7) | INTAKE-7 is known and deferred as "Q-I1 (b) later" in #1480. That decision record is not in the repo, and no open issue tracks it. INTAKE-1's slot linking is a bug fix, not a decision. |
| Program import duplicates (INTAKE-3, under "unify intake") | No per-dance prompt: maintainer ruling #797. Linking an identical existing dance instead of duplicating it would follow the existing #685 rule. |
| Manual update check (FAIL-3) | Correctly listed as open. ADR-002 doesn't settle it, and the current wording is documented in settings.md. |
| Back-to-back across breaks (GIG-8) | Matches #582's spec ("row order in the matrix"), which didn't consider breaks. Still a fair question, but a design question, not a bug. |
| Perform dialect switch (PRES-6) | Both persistence models are intended (owner issue #1554, dialects.md:359-363). Only perform.md's "quick look" wording misleads. |

### What the synthesis misses

- **Unused alternates raise "Called ×N" by default,** because the default count covers every slot. It is the most visible effect of the alternates question and isn't in any report.
- **Privacy registry and OUT-2.** The registry note on program pay justifies sharing it only to the caller's *own* devices, but share files carry it to other people. Whichever way OUT-2 is decided, that classification note is wrong today. AGENTS.md treats the registry as the privacy boundary, so this should be fixed promptly.
- **Comments that contradict other sources:**
  - `update_signature.dart:4-5` says key rotation "never strands an install"; `releasing.md` says some installs are stranded.
  - `venue_repository.dart:239-243` says a deleted venue can be restored with its program; no code does that.
  - ADR-004 gives per-device text scale as its `deviceScoped` example, but the registry classifies `perform_text_scale` as `deviceLocal`.
  - backup-portability.md says the progress indicator closes "as soon as the share sheet opens", but the share call returns only when the sheet closes.
- **Feature gating.** The synthesis never weighs which paths need an opt-in or experimental setting: Device Sync is behind Settings › Experimental; Free-text entry, Auto-save and venue records are off by default. That is the main reason the highs are overstated.
- **A future-risk item:** a manifest-schema bump would strand every older install on the update check, with no mitigation (FAIL-3 adjacent).
- **OUT-5's fix is not free.** Bumping the archive version would make 0.7.0 and older refuse share files, the same trade-off as open issue #1885. Bumping the backup envelope version instead avoids it.
- **INTAKE-2's case-collision trigger** ("Card" / "card" from Caller's Companion).
- **Shared roots worth fixing together:** AUTH-3 + AUTH-4; GIG-3 + GIG-4; FAIL-1 + PLAT-1 (same function); PLAT-5 + PLAT-6 (the updater doesn't know how the app was installed).
- **Overlap with the October UX audit:** PLAT-11 is UX batch 2, item 1; INTAKE-11/-12 overlap UX batch 5 (the seed dance hides the empty state).
- The probes README omits two AUTH-4 inputs that the verifier added and ran.

### UX leftovers claim (batches 2–7 of the October UX audit)

**Confirmed for tracking; confirmed in the code for the items I sampled.**

- PR #1919 delivered batch 1 only. #1921 and #1922 carried out the maintainer's four decisions, which the UX artifact records as the maintainer's.
- The repo has 6 open issues (#1935, #1885, #1423, #1031, #770, #491), and none covers a UX follow-up batch.
- None of the 39 PRs opened since 2026-10-25 touches batches 2–7 by title.
- Batch 2: the five editors it names (shorthand mapping, compound shorthand, theme, venue sheet, custom fields) still have no `PopScope` or discard guard.
- Batch 3: "Callers Compendium JSON" is still in all six ARB files (`danceReimportJson`), and "Cute af", "Save *", "WiFi" and "dotted·underline" are still in `app_en.arb`.
- **Not checked:** the batch 4–7 items in code. They are untracked, but whether each still reproduces is unverified.

## Re-ranked priority list

| # | Fix | Why here |
| --- | --- | --- |
| 1 | **LIFE-1**: purge only the item asked for | Silent, irreversible loss of trash the caller chose to keep; a one-call change with a test. |
| 2 | **INTAKE-1**: link slots of skipped re-import rows to the existing dance | Routine re-import silently damages program data; ~50 lines, no decision. |
| 3 | **OUT-1**: fresh link ids and post-commit related-link remap; list failures in the share result | Sharing, a core feature, fails while saying "Imported" for common dances; ~100 lines, mostly decision-free. |
| 4 | **FAIL-1** (with the optional PLAT-1 anchor in the same function) | A false backup confirmation silences the only backup reminder; ~10 lines. |
| 5 | **GIG-3 + GIG-4** together: stop writing stale program copies | Erases performed marks and commits unsaved edits, reachable with default settings through Perform; ~30–60 lines. |
| 6 | **AUTH-1/-2 decision-free parts + AUTH-6**: Save commits or flags a pending line; the Total excludes dropped groups; noted rows kept; the Undo window fixed | Typed work lost without warning; small and local. The Done-button semantics wait for a decision. |
| 7 | **INTAKE-4**: remove dances created by program resolve on Undo or back-out | Contradicts programs.md:118; leaves surprise dances; ~70 lines. Fixes FAIL-6B too. |
| 8 | **GIG-2 display**, plus **GIG-9** and **FIND-2 caller scope** | Wrong dates for every North American caller by default, a wrong closer, and a broken #583 requirement; each is small. |
| 9 | **Privacy-registry note for program pay, and the stale comments** listed under "Missing" | The registry is the privacy boundary; doc drift is this repo's top defect class. Docs-only. |
| 10 | **Calling-history decisions** (alternates, the date, duplicated or received programs), then LIFE-7, OUT-2 and the badge | One short decision session unlocks several Medium fixes; LIFE-7 is ~1 line once decided. |
| 11 | **LIFE-2 UI honesty**: don't say "permanently deleted" for a kept tombstone | Reaches only experimental Device Sync users, but it is a false success message; the wording is a small decision. |
| 12 | **INTAKE-2 / INTAKE-3**: loosen the field match; reuse the #685 linking rule on ContraDB program import | Each ~20–25 lines once the maintainer agrees. |
| 13 | **FAIL-2 / FAIL-3**: classify offline separately for the online features | A false "nothing found"; FAIL-3 still needs the wording decision. |
| 14 | **Date format and year in exports and history** (PRES-3/OUT-3/GIG-18, PLAT-12) | Printed set lists go to the band; one formatter change; Medium. |
| 15 | **Docs batch**: PRES-5 pages, search.md (FIND-4/-5), faq.md (PLAT-3), perform.md (PRES-6), the "saved on this device" string (PRES-2), ux-modernization.md (PLAT-7) | Cheap, and closes several "decisions" that are really drift. |
| 16 | **File issues for UX batches 2–7**, and fold PLAT-11 into batch 2 | Untracked work from a merged audit; tracking costs nothing. |
| 17 | Features: FIND-1 venue/recency filter, FIND-3/LIFE-5 tag and people management, FIND-9 duplicates | Real gaps but not defects; need product design. |
| 18 | Platform polish: PLAT-5/-6 together, PLAT-7, PLAT-8 menu, PLAT-9, PLAT-13 | Low individually; batch them. |

## Unverifiable here

- **PLAT-1 on a real iPad.** The source says the sheet opens, anchored at the centre of the screen. A device run would confirm it.
- **FAIL-1 on devices.** Whether "Save to Files" and similar targets report success, or report dismissed on cancel, consistently across iOS and Android versions.
- **PLAT-4.** Which MIME type Android apps assign to a saved `.ccshare`, and so whether the picker can see it.
- **OUT-4 on Letter paper.** Whether A4 output shrinks or clips.
- **GIG-14 in the app.** The mechanism was tested in a minimal Flutter test, not in the app.
- **FAIL-7.** A startup purge failure was traced to the recovery screen but not induced.
- **PLAT-6.** Where portable Windows builds keep their data, so whether two copies share a library.
- **Authorship of #1612 and the GIG-16 triage comment on #583.** Both are under the owner account; whether the maintainer wrote them decides whether they count as maintainer decisions.
- **Closed issues and PRs.** Search was rate-limited for some verifiers (FAIL-OUT could list open issues only). A fix or tracking issue among closed items could have been missed.
- **AUTH-1 keyboard Done.** Whether the IME action behaves the same across mobile keyboards.
- **UX batches 4–7.** Whether each item still reproduces; only batches 2–3 were sampled.

## Appendix: verdicts for every checked medium and low finding

Re-rated severities are shown as "was → now". "Dup" marks a finding that restates another.

- **AUTH:**
  - Confirmed: AUTH-6 M, AUTH-10 M, AUTH-11 M, AUTH-14 L, AUTH-17 L (rare path).
  - Re-rated: AUTH-5 M→L.
  - Partly confirmed: AUTH-9 M→L (replacing the row is decided, #1177 D2; the lost mark and note are not documented).
- **GIG** (program editing):
  - Confirmed: GIG-4 M, GIG-17 L, GIG-18 L, GIG-19 L.
  - Re-rated: GIG-6 M→L (last-writer-wins is in sync-spec; Device Sync is opt-in), GIG-11 M→L.
  - Partly confirmed: GIG-14 M→L.
- **Calling history:**
  - Confirmed: GIG-5 M (dup of FIND-2), LIFE-7 M.
  - Re-rated: GIG-7 M→L, GIG-8 M→L (per #582), GIG-9 M→L, LIFE-6 M→L, PRES-4 M→L.
  - Partly confirmed: GIG-12 M→L, GIG-13 M (mostly a dup).
  - Deliberate: GIG-16 L.
- **INTAKE:**
  - Confirmed: INTAKE-6 M, INTAKE-7 M (deferred in #1480), INTAKE-9 M (reproduced), INTAKE-13 L, INTAKE-14 L, INTAKE-15 L, INTAKE-16 L.
  - Re-rated: INTAKE-8 M→L.
  - Partly confirmed: INTAKE-5 M, FAIL-6 M→L (B is a dup of INTAKE-4).
  - Deliberate: INTAKE-10 M→L.
- **LIFE:**
  - Confirmed: LIFE-3 M→L/M, LIFE-5 M (decision), LIFE-8 M, LIFE-14 L, FIND-9 M (feature), OUT-7 L (the export label is "Untitled dance").
  - Re-rated: LIFE-4 M→L, LIFE-9 M→L, LIFE-10 M→L, FAIL-7 M→L.
  - Deliberate (documented): LIFE-11 L.
- **FAIL / OUT:**
  - Confirmed: FAIL-15 L, FIND-11 L, OUT-3 M, OUT-4 M, OUT-9 L.
  - Re-rated: FAIL-5 M→L, FAIL-8 M→L, FAIL-9 M→L, FAIL-12 M→L, OUT-5 M→L.
  - Partly confirmed: FAIL-4 M→L, OUT-10 L (the whole-program skip is documented).
- **PLAT:**
  - Confirmed: PLAT-2 M (probe), PLAT-7 M, PLAT-12 M, PLAT-15 L, PLAT-16 L, PLAT-19 L.
  - Re-rated: PLAT-5 M→L, PLAT-6 M→L, PLAT-8 M→L, PLAT-10 M→L, PLAT-13 M→L.
  - Partly confirmed: PLAT-3 M→L, PLAT-4 M→L, PLAT-9 M→L.
- **PRES / FIND:**
  - Confirmed: PRES-3 M, PRES-9 L, PRES-10 L, PRES-13 L, FIND-12 L, FIND-15 L, FIND-16 L (probe).
  - Re-rated: PRES-2 M→L, PRES-7 M→L, FIND-4 M→L (probe), FIND-7 M→L.
  - Partly confirmed: PRES-1 M→L, PRES-6 M→L, FIND-5 M→L/M.
  - Deliberate: PRES-5 M→L (docs drift remains).
  - Not reproduced: PRES-8 L.
