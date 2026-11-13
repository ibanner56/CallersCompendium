# GIG audit — the gig lifecycle: plan, call, remember

## Scope & method

User story traced end to end: build a program (with alternates, breaks, notes), check the matrix, export or email it, call it in Perform (including on-the-fly adjustments), then record and recall history (dance detail, "Called ×N", Last-called sort, venue repeats, half stats).

**Docs read:** docs/user/programs.md, perform.md, settings.md (Program › Venues/Programs/Performance/Calling history, Date format), collection.md (sort), glossary.md (Calling history), sharing.md (program bundle), imports.md (shared program); docs/design/ux.md §1, §2, §4, §5; domain-model.md (calling history, program table).

**Code read (main paths):**
- core: `model/program.dart` (grouping, `plannedDanceCount`, `duplicate`, `stampDanceSlotsPerformed`), `storage/repositories/program_repository.dart` (`_upsert`, the derived-history queries, venue counts, half stats), `storage/calling_history_scope.dart`, `analysis/half_calling_stats.dart`, `analysis/program_matrix.dart` (adjacency), `export/program_text.dart`, `storage/repositories/dance_repository.dart` (`_sortByLastCalled`), `storage/repositories/venue_repository.dart` (`delete`), `imports/compendium_archive_import.dart` (program intake).
- app: `screens/perform_program_screen.dart`, `perform_adjust_sheet.dart`, `perform_dance_screen.dart` (exit), `program_editor_screen.dart` (save, auto-commit, Perform launch/persist, mark-all, matrix build, status field), `program_summary_screen.dart` (load, Perform launch/persist, mark-all, set list), `programs_shell.dart`, `widgets/add_to_program_sheet.dart`, `program_list_tile.dart`, `program_slot_list_editor.dart` (mark performed), `dance_detail/calling_history_section.dart`, `data/calling_history_caller_filter.dart`, `widgets/dance_list_tile.dart` (badge), `sync/sync_controller.dart` (automatic triggers).

I did not build or run anything. Every finding was traced through code unless it is marked **Inferred**.

---

## Findings (most severe first)

### GIG-1 — High — Uncalled alternates are recorded as called, and every bulk "performed" path does it
**Scenario.** Saturday's program has 10 dances, 3 of them with an alternate. The caller uses none of the alternates. Afterwards they tap **Mark all performed**, or set **Status → Performed**, which is the obvious "this gig happened" control. They have turned on **Require "mark performed"** so that history is accurate.
**What happens.** All three uncalled alternates are stamped performed. Each one now shows the gig in its dance-detail history, gets +1 on "Called ×N", counts toward the repeated-venue line and the half stats, and moves up under Last-called sort. Next time at that venue, the caller is warned off dances they never called.
**Expected.** "Mark all performed" and the Performed status should skip alternates, or at least make it clear that alternates are included. The guide says it marks "every unperformed dance slot", which reads as the evening's dances.
**Evidence (Traced).**
- Editor mark-all: `app/lib/src/screens/program_editor_screen.dart:2298-2301`. The only test is `s.danceId != null && s.performedAt == null`, so `isAlt` is never checked.
- Summary mark-all: `app/lib/src/screens/program_summary_screen.dart:862-866`. Same test.
- Status transition: `packages/compendium_core/lib/src/model/program.dart:613-616` (`stampDanceSlotsPerformed`, no `isAlt` check), called from `program_repository.dart:506-512`.
- Default mode with no marks at all: the history, count and last-called queries have no `is_alt` filter (`program_repository.dart:980-993`, `1095-1109`), so an alternate is "called" just by being listed.
- The only correct path is to mark each slot by hand in Perform or the builder.
**Decision:** should alternates ever count by default? Options: (a) the bulk paths skip `isAlt` slots and history excludes unperformed alternates; (b) bulk paths keep marking alternates but say so, and the default mode excludes alternates.

### GIG-2 — High — Setting Status → Performed records the gig one day early for callers west of UTC (all of North America)
**Scenario.** A caller in Boston sets the event date to Sat 24 Oct, then after the gig sets **Status → Performed** and saves.
**What happens.** Every slot gets `performedAt = eventDate`, and eventDate is stored as UTC midnight (`DateTime.utc(y,m,d)`, `program_editor_screen.dart:4102`). The history row converts `performedAt` to local time (`calling_history_section.dart:390-399`): 2026-10-24T00:00Z becomes 23 Oct 20:00 EDT, so the row reads **23 Oct 2026**. The program itself still shows 24 Oct.
**Evidence (Traced).**
- `program.dart:606-610`: `nextStoredTimestamp(now: eventDate ?? fallback)`.
- `calling_history_section.dart:390-394`: `performedAt` wins over `eventDate` and gets `toLocal()`.
- The test at `app/test/screens/calling_history_section_test.dart:569-600` covers a 02:30Z instant only, not a stamp at eventDate midnight.

**Related date inconsistencies (same root cause: performedAt mixes "calendar day of the gig" with "the instant someone tapped"):**
- **Mark all performed** (editor and summary) and per-slot **Mark performed** (builder `program_slot_list_editor.dart:295`, Perform `perform_adjust_sheet.dart:166-177`) stamp *now*. Marking everything on Monday morning records Monday, not Saturday's gig. A dance marked at 00:30 during a late gig records the next day. The status path records the event date instead, so two ways of recording the same gig give two different dates.
- Re-dating a program after it was stamped (`performedAt` wins, `program_repository.dart:1107-1108`) leaves history on the old date. So does marking a program Performed before an event date was entered (stamp = save time). Nothing moves the stamps.

**Decision:** should the history date be the program's event date when there is one, with `performedAt` treated only as a "called" flag? Or should stamps be day-precision local dates?

### GIG-3 — High (only with **Auto-save program changes** on) — Status → Performed stamps are wiped by the next auto-save in the same session
**Scenario.** Auto-save is on. The caller sets Status → Performed, which auto-commits and stamps the slots in the database. They then type a program note ("great crowd").
**What happens.** The repository stamps slots only on the *transition* to Performed (`program_repository.dart:506-513`). The editor keeps its own unstamped slot list after the commit: `setState(... _existing = persisted; _slots = persisted.slots)` at `program_editor_screen.dart:1242-1246`, where `persisted` is the pre-write object built in `_persistDraft` (`:2637-2666`), not a read-back. The next auto-commit writes those unstamped slots. `_upsert` deletes and reinserts every slot (`:572-600`), and because the stored status is already Performed it does not stamp again. Every performed mark is erased with no warning. The editor never showed the marks in the first place, because the editor does not watch the program.
**Evidence (Traced):** the lines above. The same pattern exists in the editor's Perform persist path (`:1976-1980` sets `_existing = persisted`, not the `stored` read-back), so a status change followed by two Perform adjustments from the builder hits the same erase.
**Expected.** After saving, the editor should adopt the stored program (`updateAndReadBack`, already used at `:1950`), or stamping should not depend on the transition alone.

### GIG-4 — Medium — An adjustment in Perform launched from the builder silently saves all unsaved builder edits
**Scenario.** Auto-save is off (the default). The caller opens a saved program in the builder, tries a different order, changes the title or status, and does not save. They tap **Perform this program**, then in Perform tap **Adjust → mark current slot performed**.
**What happens.** Perform received the builder's unsaved draft (`_programToPerform` uses `_draftProgram`, `program_editor_screen.dart:1849-1852`). The persist callback writes `(_draftProgram ?? existing).copyWith(slots: …)` to the database (`:1939-1951`), then clears dirty (`:1976-1980`). The experimental reorder and the metadata edits are committed, and the "Discard changes?" option is gone. If the unsaved status was Performed, GIG-1/GIG-3 stamping also fires.
**Evidence (Traced).** The comment at `:1936-1938` assumes the only pending edits are "queued for auto-commit". With auto-save off, `_draftProgram` is every unsaved edit. perform.md says only that "changes to a saved program are saved with it".
**Decision:** persist only the slots Perform changed on top of the *stored* program, or block Perform-from-builder while there are unsaved edits ("Save first?").

### GIG-5 — Medium — "Last called" sort ignores both history settings and is usually title order in default mode
**Scenario.** The caller uses the default (any program counts) and never marks slots performed. Their collection tiles say "Called ×4". They sort by **Last called** to see what they called most recently.
**What happens.** The sort uses `MAX(performed_at)` over performed slots only (`dance_repository.dart:3009-3025`), so every dance is "never called" and the list falls back to title order. The sort also has no caller clause, so with **Track calling history for all callers** off it still counts other callers' programs. The badge, the facet and the detail history all honour both settings (`dance_list_tile.dart:114-116`, `program_repository.dart:980-993`).
**Expected.** collection.md:52 says "the dances you have *programmed* most recently, first", and settings.md says counts follow the two settings.
**Evidence (Traced).** `CollectionData.lastCalled` comes from the same performed-only aggregate (`program_repository.dart:998-1002`).
**Decision:** make last-called follow the history mode, using `COALESCE(performed_at, event_date, updated_at)` like `effectiveDate` when performed-only is off, and apply the caller filter.

### GIG-6 — Medium — Perform runs on a snapshot taken at launch. Synced changes are not shown, and the next adjustment overwrites them
**Scenario.** The caller fixed the running order on their laptop. On stage the tablet opens Perform before the resume/app-start sync has landed, or a debounced sync lands mid-set (Perform's own adjustment writes trigger one: `sync_controller.dart:689-720`; resume trigger `:659-670`).
**What happens.** `PerformProgramScreen` keeps `late Program _program = widget.program` (`perform_program_screen.dart:213`) and a fixed `CollectionData` snapshot, so it never re-reads. The caller reads the stale order. The next adjustment calls `updateAndReadBack(updated)` with that stale base and no comparison (`program_summary_screen.dart:622-625`; editor `program_editor_screen.dart:1943-1951`). The synced edit is overwritten locally, and because the overwrite has a newer `updatedAt` it will also win on the other device.
**Evidence.** The app side is Traced. **Inferred:** I did not trace the sync engine's program apply, and assumed last-writer-wins by `updatedAt`.
**Expected.** At minimum, write adjustments as a compare-and-set against the program Perform started from (the post-exit Undo already uses `replaceIfUnchanged`), and tell the caller when the program changed underneath them.

### GIG-7 — Medium — The repeated-venues summary splits one hall in two and can hide a real repeat
**Scenario.** The caller recorded old programs with free-text venue "Grange Hall", then turned on **Use reusable venue records** and links new programs to the "Grange Hall" record. A dance was called once under each.
**What happens.** Counts are keyed `text:grange hall` and `id:<uuid>` separately (`program_repository.dart:1133-1147`). Each count is 1, and `_visibleVenueCounts` drops counts ≤1 (`calling_history_section.dart:463`), so no "called 2× at Grange Hall" line appears. This is the warning the feature exists for. With larger counts the same hall shows on two lines.
**Evidence (Traced).** The guide calls switching modes "lossless", which is true of the data, but the history treats the two as different venues.
**Decision:** merge by resolved display label in the app layer, or offer "link existing free-text programs to this venue" when the mode is switched on.

### GIG-8 — Medium — The matrix's "back-to-back" alert fires across breaks and waltzes
**Scenario.** Dance 6 ends the first half, then a **Break** and a waltz note, then dance 7 opens the second half. Both have a balance and swing on the same beats.
**What happens.** The builder drops free-text slots before building matrix rows (`program_editor_screen.dart:3167-3173`). Adjacency is pure row index plus alternate grouping (`program_matrix.dart:577-605`), and `sections` is passed but not used for collisions. Dances 6 and 7 are flagged as "Shares beats with an adjacent dance". The same happens across a waltz in the middle of a half.
**Expected.** programs.md: "two dances that run back-to-back in the program".
**Decision:** are dances separated by a break, or by a waltz or another non-contra slot, adjacent? Options: break-only separation (section boundary), separation by any free-text slot, or keep the current behaviour and document it.

### GIG-9 — Medium — The half stats name an alternate as the "evening's closer"
**Scenario.** The last group of the second half is "Chorus Jig" with alternate "Hull's Victory".
**What happens.** The closer is "the LAST dance slot of the second half", taken over all slots with a `danceId`, alternates included (`half_calling_stats.dart:112-121`). Hull's Victory, the alternate that sits after its primary, gets `closedSecondHalfCount++` and Chorus Jig does not. In default mode this needs no performed mark at all. In performed-only mode a mark-all also credits the alternate (GIG-1).
**Evidence (Traced).** The opener is unaffected, because the primary comes first.

### GIG-10 — Medium — One program, five different sizes
For a program with 6 dances, 2 alternates, 1 break and 1 waltz note (10 slots):
| Surface | Shows | Source |
|---|---|---|
| Programs list tile | "7 slots" (`plannedDanceCount`, which counts the waltz) | `program_list_tile.dart:44` |
| Builder header | "10" | `program_editor_screen.dart:3385` |
| Summary | "Set list (10)", even with **Hide alternates in set list** on and 8 rows rendered | `program_summary_screen.dart:691-693` vs `:951` |
| Add-to-program sheet | "10 dances" (`collectionDanceCount(slots.length)`) | `add_to_program_sheet.dart:107,116` |
| Perform | "Slot N of 8" (groups, including the break and waltz) | `perform_program_screen.dart:641-648` |
| Emailed set list / PDF | numbered 1–8, so the band sees "5. Break" | `program_text.dart:88-116` |

programs.md says the count is "the number of dances the evening is planned for, so alternates and breaks are not counted." Only the list tile follows that, and its unit is "slots". (Traced.)

### GIG-11 — Medium — A dance in Recently deleted is rendered five ways, and the band gets "Untitled dance"
**Scenario.** The caller deletes a dance that is still in Saturday's program, without noticing it is used there, then prints the set list for the band.
| Surface | Rendering | Evidence |
|---|---|---|
| Perform | "Petronella (deleted dance)", with figures | `perform_program_screen.dart:1623-1636`, `:687-689` |
| Builder | "(deleted dance)" | `program_slot_list_editor.dart:149` |
| Matrix | row "(deleted dance)" with **no figures**, so its moves vanish from the variety check and collisions with neighbours are missed | `program_editor_screen.dart:3174-3181` |
| Summary | "Dance unavailable" | `program_summary_screen.dart:474` (`getById` without `includeDeleted`), `:1033-1060` |
| Set-list text / PDF | "Untitled dance" (`labels.unknownDance`) | `program_text.dart:221-222`, `app_en.arb:7545` |

perform.md documents only the Perform behaviour. (Traced.) Every surface should resolve soft-deleted dances the way Perform does (`resolveDeletedSlotDances`).

### GIG-12 — Medium — Program status is decorative and only partly connected to history
- **Finalized** has no behavioural effect anywhere. Grepping `ProgramStatus.` in app/lib finds only labels and chip colours.
- **Mark all performed** does not set the status to Performed. Setting the status to Performed stamps every dance slot (GIG-1/2/3). Clearing marks leaves the status alone, and moving the status back to Draft never removes stamps (`program_repository.dart:497-505`). A fully marked gig stays "Draft" on the Programs list.
- Neither the status dropdown (`program_editor_screen.dart:3918-3950`, no helper text) nor programs.md ("a **Status** … shown on the Programs list") says that choosing Performed writes calling history. Choosing it by mistake and saving is not undoable: there is no Undo, and reverting does not unstamp.
**Decision:** what does each status mean? Options: make status derived from the per-slot marks; make Performed and mark-all one action with Undo; or keep them separate but say so in the UI and docs.

### GIG-13 — Medium — Default history counts things that were not called: plans, duplicates, and other callers' gigs
In the default mode (any program counts), with the badge text "Called ×N":
- **Duplicate** copies the event date and venue (`program.dart:556-558`). Duplicating last month's program for next month immediately gives every dance +1, a second history row **on last month's date at the same venue**, and a repeated-venue line, before anything has been called.
- A future or cancelled gig counts as soon as it is drafted, and keeps counting unless it is deleted.
- **A program another caller sent you** (Share program + dances) is imported with its `status`, `performedAt` and `caller` intact (`compendium_archive_import.dart:151,166`). The `status` field passes `_upsert`'s create path, where `priorRow == null`, so it is stamped too (`program_repository.dart:506-512`). With no default caller set (the default), their gig appears in *your* history, even in performed-only mode. With a default caller set, it is excluded only if they filled in their name.
**Evidence (Traced).** **Decision:** clear the event date on duplicate (or ask); import received programs as Draft with marks cleared; consider renaming the default-mode badge ("In N programs").

### GIG-14 — Medium (Inferred) — Rotating a tablet mid-gig loses the "resume where you left off" state
**Scenario.** On a tablet in landscape (≥900 px), the caller opens a program in the wide summary pane, taps Perform, and calls half the evening. The tablet gets bumped into portrait (<900 px), or rotated and back.
**What happens.** `ProgramsShell` swaps its split pane for the narrow list on any breakpoint crossing (`programs_shell.dart:71-86`). The `ProgramSummaryPane` that launched Perform (`:106-117`) is disposed, and `_performResume` lives in that pane's State (`program_summary_screen.dart:609-616`). Perform itself survives, because it is on the root navigator and there are no nested navigators. Adjustments still persist, because `_repos` is a field. But after **Exit** the caller lands on the list, not the program, and **Perform this program** restarts at slot 1 with the clock at 0. The exit dialog had just promised "Your place and the running clock are kept".
**Not verified:** I did not run a rotation, and inferred the route-below rebuild from Flutter's `maintainState`. The fix is to hold the resume state in the shell keyed by program id, or to give the pane a GlobalKey as was done for the list (#895).

### GIG-15 — Low — Single-dance Perform's exit dialog promises a resume that does not exist
`perform_dance_screen.dart:285-286` reuses `performExitBody` ("Your place and the running clock are kept, so you can resume where you left off", `app_en.arb:6791`). `PerformDanceScreen` has no resume state, and perform.md says single-dance Perform "starts the next session fresh". (Traced.)

### GIG-16 — Low / Decision — The caller filter ignores guest-caller slots
With **Track calling history for all callers** off, a dance a *guest* called at your program counts as yours. Dances *you* called as a guest at someone else's program (`program.caller` = host, `slot.guestCaller` = you) are excluded. The filter only looks at `programs.caller` (`calling_history_scope.dart`). The `guestCaller` field exists on every slot (`program_repository.dart:590-594`). Options: also match `slot.guest_caller`, or document that only the host counts.

### GIG-17 — Low — A program restored from Recently deleted can come back without its venue
The venue delete guard counts only *live* programs (`venue_repository.dart:259-270`, deliberately). Sequence: delete the program, delete the venue (allowed), restore the program. The program's `venueId` now dangles. A program created in venue-record mode has no free-text fallback, so the summary, exports, history row and venue counts all lose "where". settings.md:119-121 says the guard exists "to keep you from stranding a program". (Guard Traced, UI fallback Inferred.)

### GIG-18 — Low — The Date format setting is not applied to history or exports
settings.md:298-300 says the choice "controls how program event dates appear". Calling-history rows use `formatMediumDate` (`calling_history_section.dart:426`), as do the set-list text/PDF (`program_export_menu.dart:134,541`) and the matrix PDF (`program_editor_screen.dart:3330`). The list, summary, editor and add-to-program sheet use `formatEventDate`. A caller with a custom or D/M/Y format sees two formats, and the band gets the locale format. (Traced.)

### GIG-19 — Low — Add-to-program Undo overwrites any edit made in between
`add_to_program_sheet.dart:233-241` restores `previousSlots` onto the current program unconditionally. Perform's post-exit Undo uses `replaceIfUnchanged`. Example: add a dance, reorder in the builder, then tap Undo on the still-visible snackbar (it can stay up indefinitely with accessible navigation). The reorder is lost. (Traced.)

### GIG-20 — Low — Design-doc drift
- ux.md §5 lists "swipe" navigation in Perform. There is no horizontal drag or PageView in `perform_program_screen.dart` or `perform_card.dart`, and perform.md correctly omits swipe.
- ux.md §2 says calling history comes "from performed programs", but the default is any program (domain-model.md and settings.md are correct).

---

## Cross-cutting patterns

1. **"Called" has no single definition.** Calling history, "Called ×N", the facet, venue repeats and half stats follow the two settings. Last-called sort follows neither (GIG-5). None of them distinguish alternates (GIG-1, GIG-9). The bulk "performed" writers stamp alternates (GIG-1). The status field is a hidden third writer (GIG-12). The fix is one shared predicate covering performed, primary-vs-alternate and caller, used by every consumer, plus one rule for which date a gig is recorded under (GIG-2).
2. **performedAt is used both as a flag and as a date.** Each writer picks its own time (now, event date, save time), and display converts it as an instant (GIG-2). The status path's stamps are invisible to the editor, which keeps writing its own copy (GIG-3).
3. **Surfaces that hold their own copy of a program write it back without comparing.** This covers the builder after auto-commit (GIG-3), Perform's snapshot (GIG-4, GIG-6) and the add-to-program Undo (GIG-19). The repo already has the right primitive (`updateAndReadBack` / `replaceIfUnchanged`), but only Perform's post-exit Undo uses it.
4. **Per-surface resolution of the same slot.** Counts (GIG-10), deleted dances (GIG-11) and date formatting (GIG-18) are each re-derived per surface instead of sharing one helper, so they drift.

## Checked and fine
- Perform back, predictive-back and close are guarded by `PopScope(canPop:false)` plus a confirm dialog, with a re-entrancy guard (`perform_program_screen.dart:530-579`).
- Timers survive backgrounding and sleep: elapsed is measured, not ticked, and refreshed on resume (`:330-398`).
- Perform's **mark performed** targets the *shown* member, including a swapped-in alternate (`currentSlotId: _currentSlot.id`, `:921`, `:761-764`).
- An adjustment keeps the reading view on the same slot id (`_applyProgram`, `:774-798`). The post-exit Undo is compare-and-replace (`program_summary_screen.dart:639-647`).
- Soft-deleting a program removes it from every history query (`deleted_at IS NULL` everywhere), and Undo/restore brings it back.
- Duplicate clears `performedAt` and resets the status to Draft (`program.dart:568-581`).
- A venue rename reaches history rows and the summary (#944 handling in `calling_history_section.dart`).
- Event dates are stored as UTC midnight and shown without conversion in the list and summary, so the right calendar day is shown.
- `hideAlternates` is applied consistently to the summary, text and PDF via `outputGrouped`. Perform intentionally shows every slot, as documented.
- Matrix alternates are compared against neighbouring groups and not against each other, as documented.
- Perform is reachable from the builder, the summary (wide and narrow) and dance detail. It is not on collection rows or search results, which matches ux.md.

## Out of scope but noticed
- Privacy/sharing: a program bundle carries the program's **Pay** (documented in sharing.md:149). Worth a second look by the privacy auditor, since the recipient's import keeps it as their own program's pay.
- Storage/i18n: caller matching uses SQLite `LOWER(TRIM(...))` (`calling_history_scope.dart`), which folds ASCII only, so "Ólafur" and "ólafur" do not match.
