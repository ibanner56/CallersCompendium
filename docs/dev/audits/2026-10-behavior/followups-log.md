# Follow-up log (orchestrator notes, 2026-10-29 to 2026-10-31)

Raw notes kept by the orchestrating session while the audit branches landed. Each line was reported by a fix session or a reviewer; none has been re-verified against current main. Maintainer decisions recorded here are also in the maintainer-decisions files, which are authoritative.

- B23 (#2035): compound editor, shorthand editor and Settings default figures should settle the Move box on their own Save (~5 lines each).
- B23 (#2035): diagnostic_labels_test "every mapped code is non-generic" can't fail in debug builds (pre-existing).
- B26 (#2034): a failed manual re-check clears a previously found update (pre-existing).
- U7 (#2033): alternate slot title is ~77dp at 360dp (design call).
- U9 (#2027): 8 machine-translated keys need fluent review; plus German "Takte" sweep (G1).
- B1 (#2032): undated unperformed program slots dated by updated_at (N1 Decision 3).
- F10 (#2022): Perform jump-sheet numbering; author of trashed dance with trashed author missing from exports; LIFE-8 Restore button.
- U2 (#2011): _ParameterizedColumnDialog stray dismissal; dance editor _save doesn't scroll to first invalid field.
- U6 (#2015): advanced-query leaf section dropdown and online result-count overflow at 360/2x.
- U11 (#2014): 12 on-scale radii in hot files + 17 off-scale values; 8 dropdowns not converted.
- U12 (#2028): unboxed notice rows (sync pairing disclosure, device sync tiles).
- U9 (#2027): Browse published collections button on the import card.
- B20 (#2038): needs a real-device Android check before merge.
- B16 (#2036): "Imported X" wording after "Same dance"; Caller's Box fallback in ContraDB program import still declines identical dances instead of linking; ContraDB confident match with differing figures imports a duplicate rather than a variation (#686).
- B12 (#2037): tombstone adopted under a recreated custom field leaves a trashed dance's search entry stale (pre-existing); whole-number custom values may index as "3.0".
- B20 (#2038): reword importFileNotText to say "not a share file" for binary picks (all six ARBs).

## Maintainer decision 2026-10-29 ~23:22 UTC (B30, via question dialog)
- Withdrawn screen-bound keys from older peers: "(a) Drop withdrawn keys (Recommended)". Inbound values are dropped, not kept or passed on, and no keptNewerFields notice appears. A dated sync-spec §6.7 amendment goes in the B30 PR. Relayed to session_016XEZ6Fot2zFTDC71cdb66u.
- B11 (#2039 merged): FIND-4 Advanced/By-phrase type-aheads deferred by maintainer — follow-up.
- B6 (#2042): stamp-bump guard not shown to fail (mutation didn't apply) — nudged.
- B31 (#2044): other DateFormat.yMMMd(appLocale) sites (sync conflicts, device sync, editor) still follow app language; PLAT-13 glossary not built.
- B6 (#2042 merged): stamp-bump guard merged without being shown to fail; editor-open-keeps-old-name; deleted-dialect-name reuse. Remote branch re-created post-merge (deletable).

## Maintainer decision 2026-10-30 ~00:01 UTC (B27 #2045, via question dialog)
- Store builds and end-of-support notices: "Notice only, in #2045 (Recommended)". Store builds read the release info for end-of-support only, show no update offer, and 'Get update' opens the store listing. Relayed to session_016XEZ6G2GQksStwfT5Fstgy.
- B27 store link (2026-10-30 ~00:05): "TestFlight + Play URL (Recommended)". iOS goes to the TestFlight public link and Android to the Play details URL. Relayed.
- B30 (#2046): conflict queued before the upgrade on a withdrawn key clears only after first complete pass; old-build device detaching after all peers upgraded skips cleanup. data-classification.md regen conflicts with B19, B4 — sequence.
- B30 re-decision (2026-10-30 ~00:12): "(c) Drop + document (Recommended)". Keep the drop. Document that old-build devices show a false 'isn't taking N changes' notice until they upgrade. Relayed.
- B31 en_DK (2026-10-30 ~00:31): "Merge, follow-up PR (Recommended)". The B31 session does the region-fallback follow-up on claude/fix-region-date-fallback after #2044 merges.

## Approvals 2026-10-30 ~00:52 UTC
- Wave 2: "Start wave 2 (Recommended)". Same rules and approvals.
- Design-note implementation: "Plan and start building". One planning session, then build as slots free up, same rules and approvals.
- B30 (#2046 merged): (1) a conflict queued before the upgrade on a withdrawn key may fail with candidateChanged until the first full pass; small fix: refreshConflictReviews drops such rows. Ask the maintainer about a follow-up. (2) An old-build device detaching after all peers upgraded skips cleanup; accept. (3) The next data-classification.md regen (B19, B4) must regenerate, not hand-resolve.
- Design planner ambiguities (2026-10-30 ~01:15): "Accept all 8 (Recommended)". Plan at fea55f7; docs PR #2049. D1 queue: N5-S1, N1-H1, N2-T1, N2-T4 (after B7). W2 remaining: G1, B21, B18, B19, B3, B10, B15.

## 2026-10-30 ~02:10 UTC
- B7 retention: "Blank on retention too (Recommended)". The B7 session does the follow-up claude/fix-retention-blanks-synced after #2053 merges.
- Wave 3: "Hold wave 3". Do NOT start B4/B5/B22/B24/B28/B29 even after F11 merges.
- B7 (#2053) follow-ups: race where a citation shows a dash (maybe folded into the retention PR); older builds can restore a blank '—' record; review_queue blobs keep content until resolved.
- F11 (#2040 merged): a change made elsewhere to a program's details is overwritten on Save while the builder holds unsaved detail edits; suspected false 'changed elsewhere' notice after a bulk-mark Undo; the first draft by key is offered rather than the most recent.

## 2026-10-30 ~02:20 UTC Windows CompanyName blocker
- #1986 changed CompanyName, which moves every Windows data folder; v0.8.1-beta used org.callerscompendium. Maintainer: "Revert CompanyName (Recommended)". Fix session session_016XEZ6FXMMjS6AocGFaPykQ on claude/fix-windows-company-name. It must merge before #2054. Over the 4-slot limit by one because it's a blocker.
- #2045 (B27) merged; archive session_016XEZ6G2GQksStwfT5Fstgy. #2051 (B14) merged too.
- B7 #2053 merged 04:30; retention follow-up started by same session. B8, N2-T4 unblocked (queued).
- G1 (#2058): Danish has the same bar/beat slip in 3 strings ('takt'/'takter'). Follow-up.
- N5-S1 (#2056): manual NVDA/VoiceOver + highlight contrast check not done; link rows, tunes, custom fields, citations, header lines, chips, warnings, A1 labels, history copy without line breaks.
- #2061 (B7 retention follow-up) also fixes #2053's startup sweep, which restamped citers on stale devices and could overwrite other devices' edits. Main carries that bug until #2061 merges, so prioritise it. Follow-up 1 (citations of blank tombstones) is not done.
- B8 (#2062): until B9 lands, deleting a level that only a trashed dance uses means restoring that dance makes its next save fail. B9 must land before the next release. Follow-ups: sync-borne type mismatches; a stale comment in existence.dart.
- B18 (#2064, merge alone): published-collection corrections no longer reach existing dances; the review screen's 'overwritten' strings; share metadata revives deleted tags that are unused; the .USR Import-and-edit related-link gap.
- B25 (#2054 merged): no startup export button (follows the FAIL-10 decision); the SyncFailure allow-list entry is inert. B21 (#2060 merged): the real Windows/Linux desktop check is still unconfirmed; the Windows parent-dir symlink walk is a follow-up.
- B7 (#2061 merged): another device can add a dance to a program before it receives the blank, so that slot shows a dash; review_queue blobs can hold blanked content. #2063 (B15) merged.
- B18 (#2064 merged): 1) review strings still say 'overwritten'; 2) ShareMetadataImporter revives deleted tags/fields/sources; 3) .USR Import-and-edit gets Dance_Related links; 4) .USR unresolved-endpoint warnings fire for re-imported pairs; 5) published collection title/credit corrections no longer reach imported dances (needs maintainer).
- B9 (pushed, waiting on #2062): restore leaves a venueId that names no venue at all as-is; duplicate drops a dead venue link. One 'suspected' item is a follow-up. N2-T4 opened #2067. #2062 hit the coverage-collector flake again; re-run once.
- N4-S1 (#2069): Add tags on 5,000 selected took about 21 s in the harness; bulk writes need work before S3/S4. B10 (#2068): missing dialect/theme delete widget tests; the commonDeletedSnack ARB description still says 'dance'. N2-T4 (#2067): the changelog says managers ship 'in a later release'; edit if T2 lands first. B19 (#2065): replacing from a share clears the receiver's rating (open question).
- B8 (#2062 merged): B9 must note that a trashed dance restored from a backup or share comes back with no level. Follow-ups: sync-borne custom-field type mismatches; a stale comment in existence.dart. #2065 and #2067 merged at 14:05 too.
- N4-S4 (#2074): the level, rating, tunes and custom-field batch handlers have the same per-dance getById loop; batching them is a follow-up. setStatusForMany went from ~6 s to ~3.3 s for 5,000 in the harness.

- 2026-10-30 14:47 B6 stamp proof: renameDialect test 'a newer stored stamp still advances' (program_repository_test.dart) goes red under both mutations (reuse stamp; passed-in stamp without bump). Guard holds, no PR. Session archived.
- 2026-10-30 15:50 B3 #2079 review N1 (offer to link venues races an open program editor whose stale save clears venueId). My call (not maintainer): fix in PR via (c) editor writes venueId only if user changed it; rejected (b) open-editor registry, (a) document only. Fallback to (b) only after asking me.
- 2026-10-30 15:51 Flaky: app/test .../dance_editor_reference_data_watch_test.dart "coalescing window reduces re-reads" failed once on #2074 (windowed=2 unwindowed=2), passed on re-run. Timing-based. Watch for repeats; candidate for a robustness fix.
- N4-S4 follow-up (re-confirmed): level/rating/tunes/custom-field batch handlers still per-dance getById for priors; getByIds would roughly halve them.
- 2026-10-30 16:22 B9 #2076 green. Open maintainer question (non-blocking, sync-spec §6.8): a revival under a held peer tombstone stays advertised as a tombstone until the hold resolves; propagate anyway? Follow-ups: Recently-deleted snackbar when a peer blanks an item mid-list; CC re-import keeps a dead venue link.
- 2026-10-30 16:43 N2-T1 (#2073) follow-ups: stale step-1 "renamed onto a name this device already uses" rows never cleared (bug); the note's two small choices to confirm in T2; documented limits: three-way merges, citations after alias retirement.
- N3-A2 (#2080) merged 16:42. Build's call: at 200% text with keyboard up, pinned New row can scroll away inside 45% header cap (departs from N3-5 "always visible" in that case; design §4.5). Option if maintainer wants: drop the title when the keyboard is up. Last full preflight did not complete on final head (CI green). Stray recreated branch deleted after verifying no unique content.
- 2026-10-30 21:41 B28 #2086 follow-ups: Windows maximized window may keep title bar in full screen (window_manager 0.5.2 limit; needs device check); device checks for immersive mode on Android/iOS. B29 API: TogglePerformFullScreenIntent / ExitPerformFullScreenIntent; Esc always consumed in Perform.
- B22 #2085 own calls: user colour honoured under high contrast; colour-coding off shows no accent.
- B4 own calls: status set even when nothing left to mark; un-marking never changes status (per plan).
- 2026-10-31 09:36 B29 #2096: native mac menu not verified on a real Mac (mocked channel only). Follow-ups: N4 Ctrl-A binding; import-under-review has no back guard (pre-existing); native titles of system menu items. Own calls: Esc via DismissIntent probe; app commands leave pages through each page's back guard.
- B5 #2093: maintainer question — should Undo snackbar repeat N?
- D2 follow-up (low): collection.md juxtaposes "All fields finds each word exactly as typed" with "figures matched by meaning".
- 2026-10-31 09:53 U4 #2097 open. Refreshed 38 stale keys per non-English locale using each locale's existing terms; listed for native review. New guard app/test/l10n/one_name_each_test.dart. Checked: B29's new menu strings use no retired terms.
- Note for U5a: B29's macOS menu strings are Title Case on purpose ("New Dance", "Import Dances…"), per macOS convention; U5a's sentence-case rule needs a menu exception.
- 2026-10-31 15:47 B5 #2093, B29 #2096, U4 #2097 merged. Wave 3 complete.
  - B29: one-minute Mac check (Settings…, New Dance, Close from menu; no Edit menu). Follow-ups: N4 Ctrl/Cmd-A in Collection; import-under-review back guard; native macOS system-menu titles not localized (PLAT-16); B28 single-dance Perform scroll keys.
  - U4: native review of da/de/fr/ja/nl for changed keys (PR body); design-doc prose still says "custom figure" (ux.md, dialect.md, figure-taxonomy.md, imports.md).
