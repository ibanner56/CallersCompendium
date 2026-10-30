# Maintainer decisions, round 2 and design notes (2026-10-29 / 2026-10-30)

The maintainer (ibanner56) recorded these answers on the decision page https://claude.ai/artifact/MRVAeqpyG34SKbv48Xomdy between 2026-10-29 22:33 UTC and 2026-10-30 00:47 UTC. Each entry quotes the chosen option's label and text as the page showed it, and the maintainer's own note verbatim where they left one. Entries marked *(differs from the recommendation)* are where the maintainer chose another option than the page recommended.

Further decisions were made in conversation with the orchestrating session on 2026-10-29/30 and relayed to the branch sessions; they are recorded at the end.


## Round 2 (follow-ups to the 2026-10-29 decisions)

### R2-check-again (FAIL-11)

**Question:** "Check again" would always fail on two startup screens but can succeed on the other two. Add it to those two?

**Decision:** (b) No Check again anywhere. As you picked. Those two screens need a restart after the fix. *(differs from the recommendation, (a))*

**Unblocks:** B25

### R2-d2-scope (FIND-4, FIND-5, PLAT-3, PLAT-7)

**Question:** The queued user-guide PR (D2) would document four behaviours you just chose to change. Move those four bullets to the branches that change them?

**Decision:** (a) Move them to B11, B21 and B29. Each branch documents its own change. The rest of D2 stands.

**Unblocks:** D2

### R2-d4-quotes (UX3-6)

**Question:** You chose to normalise all quotes (D-4 c). Which style, and do apostrophes count?

**Decision:** (c) Straight everywhere. "like this" and don't. The easiest to type, and translators get it right. *(differs from the recommendation, (a))*

**Unblocks:** U5b

### R2-g1-review

**Question:** The German "beats" sweep needs a fluent reviewer. How should G1 land?

**Decision:** (a) Merge the sweep now; review later. The PR is marked "needs fluent review", and you arrange a reviewer.

**Unblocks:** G1

### R2-intake2-clash (INTAKE-2)

**Question:** When a share file brings a custom field whose key matches yours but whose type or choices differ, what happens?

**Decision:** (a) Import into a new field "<key>_2", with a review note. Follows the .USR import's existing rule. Nothing is lost.

**Unblocks:** B17

### R2-intake7-native (INTAKE-7)

**Question:** Batch re-import will replace only the choreography. Should that also apply to native Compendium archives and share files?

**Decision:** (a) Every source, archives included. Your own ratings, tags and notes are never overwritten by a re-import.

**Unblocks:** B18

### R2-life2-retire (LIFE-2)

**Question:** Your LIFE-2 note asked to clear a deletion record once every device has synced past it. That can't be done safely. Which do you want?

**Decision:** (a) Hide it and blank its content (no retirement). Permanently delete hides the item and overwrites its content with a fresh stamp. Only a few bytes remain, with no names or text. Meets the privacy goal.

**Unblocks:** B7, then B8 and B9

### R2-out2-export (OUT-2)

**Question:** Your OUT-2 note says pay, rating and dialect "should still travel in sync and export". By "export", do you mean Backup?

**Decision:** (a) Yes: sync and Backup keep them; share files drop them. B19 removes pay, rating and Perform dialect from share files only.

**Unblocks:** B19

### R2-pres12-mixer (PRES-12)

**Question:** In set lists, does your own formation colour override the mixer accent?

**Decision:** (a) Mixer accent always wins. Your formation colour applies to every other dance.

**Unblocks:** B22

### R2-tag-tap (FIND-14)

**Question:** Tapping a tag chip adds it to the filters. The Tags filter matches "any" tag, so adding one can show more dances, not fewer. What should a tap do?

**Decision:** (b) Require all selected tags (AND). Changes the Tags facet's rule everywhere. *(differs from the recommendation, (c))*

**Maintainer's note:** "None of the above, really - every beta user sampled said they want to be able to toggle between and/or, with and being the default when you add a second tag. Any tags added beyond the second should honor the currently selected and/or mode."

**Unblocks:** B15

### R2-trash-docs (LIFE-9, GIG-17)

**Question:** "Trash doesn't protect" contradicts three design documents. Amend them, or switch to "trash protects"?

**Decision:** (a) Keep (b) and amend the three docs. B8 makes every guard ignore trashed records and adds errata. B9 makes restore cope with missing venues and fields.

**Unblocks:** B8, B9


## N1: history filters (docs/design/history-filters.md)

### N1-1 (FIND-1)

**Question:** How should the venue filter decide that two programs were at the same venue?

**Decision:** (a) Venue key, like the repeated-venues list. The filter always agrees with the dance page's repeated venues, but a typed "Grange" and a saved "Grange" stay separate until old programs are linked.

**Unblocks:** H1, H2

### N1-2 (FIND-1)

**Question:** How should a caller choose the time window for "not called recently"?

**Decision:** (a) Presets plus a chosen date. One tap for 4 weeks, 3 months, 6 months or 1 year, plus "Since a date"; it costs two controls in one section.

**Maintainer's note:** "Also an option for dances which haven't been called. I think you can just say 1mo, 3mo, 6mo, or since a date on top of that, 1 year is a long while."

**Unblocks:** H2 (H1 adds the scope underneath)

### N1-3 (FIND-1)

**Question:** If a program has no event date and was never marked performed, should its dances count as called recently?

**Decision:** (a) Leave them out of recency windows. They still count as called and in "called ×N" but never as recent; the Last-called sort can then place a dance differently from its chip.

**Unblocks:** H1 (and B1's shared date helper)

### N1-4 (FIND-1)

**Question:** In the dance picker, should "within 3 months" count back from the program's date or from today?

**Decision:** (b) Always from today. Simpler, but wrong for a program planned weeks ahead. *(differs from the recommendation, (a))*

**Unblocks:** H3

### N1-5 (FIND-1)

**Question:** When you add dances to a program at a venue, should the picker hide dances already called there?

**Decision:** (a) Flag them, with an off-by-default chip. Rows called here show a "here" marker, and a Not called here chip hides them in one tap per program.

**Unblocks:** H3

### N1-6 (FIND-1)

**Question:** In the picker, should dances you have just added to this program stop counting as called?

**Decision:** (c) Leave out the whole program. Also hides a dance performed an hour ago, and Perform has no in-program marker to make up for it. *(differs from the recommendation, (a))*

**Unblocks:** H1, H3

### N1-7 (FIND-1)

**Question:** Should dance rows show when a dance was last called, and whether it was called at this venue?

**Decision:** (a) Short "last called" chip plus "here". Rows show "3 mo ago", and picker rows add a "here" marker; one more chip on a busy row, which card fields can hide.

**Unblocks:** H3 (L ~500 lines, or M ~300 if c)

### N1-8 (FIND-1)

**Question:** Should people who have customised their card fields see the new Last called chip without turning it on?

**Decision:** (a) No, they turn it on themselves. No new setting or migration; the changelog says where to turn it on, and an older synced device can drop it again.

**Unblocks:** H3

### N1-9 (FIND-1)

**Question:** Should a program dated in the future count as a call in "within 3 months"?

**Decision:** (a) Yes, count future programs. "Not called within 3 months" hides a dance already planned for next month, matching "called ×N".

**Unblocks:** H1


## N2: tags, authors and sources (docs/design/tags-and-people.md)

### N2-1 (FIND-3, LIFE-5)

**Question:** Should Device Sync's rules change so that a merge you make by hand reaches your other devices safely?

**Decision:** (a) Yes, amend sync-spec §6.6. Merges record an alias, so a device that tagged dances offline lands on the merged entry; T1 must still choose the fix for one open risk.

**Unblocks:** T1

### N2-2 (LIFE-5)

**Question:** When you merge two authors, what happens to the details on the one that goes away?

**Decision:** (b) Fill the blanks, list what's dropped. Empty fields take the other author's values, and the dialog lists conflicting values it will drop; a longer dialog on conflict.

**Unblocks:** T3

### N2-3 (FIND-3, LIFE-5)

**Question:** Where should the new Tags, Authors and Sources managers live?

**Decision:** (a) Settings, General, Library. Three new Library entries, and Tag colours in Appearance opens the Tags manager; nothing added to Collection.

**Unblocks:** T2 (T3 builds on T2's screen)

### N2-4 (LIFE-5)

**Question:** Can you delete an author or source that dances still credit?

**Decision:** (a) No, offer Merge into instead. Delete appears only for unused entries; an entry in use offers a merge, so no dance loses its credit.

**Unblocks:** T3

### N2-5 (FIND-3)

**Question:** How long can you undo deleting a tag?

**Decision:** (a) Only from the Undo snackbar. Undo lasts as long as the snackbar, and nothing new is stored.

**Unblocks:** T2

### N2-6 (LIFE-5)

**Question:** When old dances are purged from the trash, should tags, authors and sources with details you entered be kept?

**Decision:** (b) Keep entries that hold details. Bare entries go; ones with a colour, website, notes or email stay as Not used, keeping third-party contact data.

**Unblocks:** T4

### N2-7 (FIND-3)

**Question:** When you delete a tag, should it come off every dance for good?

**Decision:** (a) Remove it from every dance. Each dance loses the tag and is updated, so all devices agree; bringing the tag back does not re-tag old dances.

**Unblocks:** T1


## N3: add-to-program sheet (docs/design/add-to-program-sheet.md)

### N3-1 (FIND-17)

**Question:** In the Add to program sheet, how should performed programs appear?

**Decision:** (c) Group them, collapsed below. Open programs first, then a collapsed Performed (N) row; everything stays two taps away, at the cost of one row.

**Unblocks:** N3-2 (feat/add-to-program-order-and-search)

### N3-2 (FIND-17)

**Question:** Among programs still being planned, which should come first in the sheet?

**Decision:** (a) Soonest event first, then by edit. Programs dated today or later come first, soonest at the top; the rest follow by last edit, as today.

**Unblocks:** N3-2 (feat/add-to-program-order-and-search)

### N3-3 (FIND-17)

**Question:** Should the Add to program sheet have a search field, and should it match venue names?

**Decision:** (c) Above about 8, titles and venues. Small lists stay compact, and "the Tuesday night at X" finds its program; one extra read on open.

**Unblocks:** N3-2 (feat/add-to-program-order-and-search)

### N3-4 (FIND-17)

**Question:** If a program already holds the dance, what happens when you tap it?

**Decision:** (b) Ask first. Safer for a mis-tap, but breaks the rule to confirm only where Undo is impossible and slows a deliberate repeat. *(differs from the recommendation, (a))*

**Unblocks:** N3-1 (feat/add-to-program-contains-and-new)

### N3-5 (FIND-17)

**Question:** Where should New program with this dance sit in the sheet?

**Decision:** (a) Pinned first row. Always visible, even with the keyboard up and a long list; it costs one row.

**Unblocks:** N3-1 (feat/add-to-program-contains-and-new)

### N3-6 (FIND-17)

**Question:** Should a dance that is only an alternate in a program show the In this program marker?

**Decision:** (a) Yes, alternates count. The marker answers "will I add this twice?" and matches the picker's count.

**Unblocks:** N3-1 (feat/add-to-program-contains-and-new)


## N4: bulk selection (docs/design/bulk-selection.md)

### N4-1 (FIND-8)

**Question:** When a new search hides dances you selected, should they stay selected?

**Decision:** (b) Keep them and show the count. The count line says 14 selected (9 not shown), with Deselect those not shown; a longer result line.

**Unblocks:** S1 (feat/collection-select-all)

### N4-2 (FIND-8)

**Question:** Should Select all pick only the dances in the current results, or the whole collection?

**Decision:** (a) Current results only. Selects exactly the list on screen; to select everything, clear the filters first.

**Unblocks:** S1 (feat/collection-select-all)

### N4-3 (FIND-8)

**Question:** Should Group by category stay on while you select dances?

**Decision:** (a) Keep groups, add section checkboxes. Sections stay put, and each header gets a checkbox that selects or clears its rows.

**Unblocks:** S2 (feat/selection-keeps-groups)

### N4-4 (FIND-8)

**Question:** Should deleting many dances at once ask you to confirm?

**Decision:** (a) Follow Confirm before delete. One rule for every delete; with the setting off a 200-dance delete is one tap, recoverable from Recently deleted.

**Unblocks:** S3 (feat/batch-delete)

### N4-5 (FIND-8)

**Question:** Which new batch actions should be built first?

**Decision:** (b) All six together. Everything at once, but Add to program and Add source would pre-empt open decisions in those two notes. *(differs from the recommendation, (a))*

**Maintainer's note:** "but not mixer or mixed level"

**Unblocks:** S3, S4 now; S5 after N3 is decided; S6 after N2 is decided

### N4-6 (FIND-8)

**Question:** How should the selection bar fit up to fourteen actions on a phone?

**Decision:** (a) Grouped ⋮ menu, Select all icon. Keeps three icons, plus Select all where it fits; the rest go in a grouped menu with Delete last, in the error colour.

**Unblocks:** S4 (feat/batch-details); S1 for the Select all icon


## N5: selectable text (docs/design/selectable-text.md)

### N5-1 (PLAT-17)

**Question:** Should you be able to select dance text on phones too, or only on desktop?

**Decision:** (a) Desktop only. Phones stay exactly as now and keep only Copy dance; turning it on everywhere later is a one-line change.

**Unblocks:** S1 (feat/selectable-detail-text)

### N5-2 (PLAT-17)

**Question:** On the program summary, should the dance titles in the set list be selectable?

**Decision:** (a) No, header text only. Title, details and notes select; set-list rows keep their taps, and the export menu copies the titles.

**Unblocks:** S2 (feat/selectable-summary-text)

### N5-3 (PLAT-17)

**Question:** When you copy selected text, should you get exactly what is on screen?

**Decision:** (a) What you see. Copies the wording as shown, including verbose text and capitals; it differs from Copy dance on those two settings.

**Unblocks:** S1 (feat/selectable-detail-text)

### N5-4 (PLAT-17)

**Question:** When you right-click, which menu should appear?

**Decision:** (a) Copy menu in text, ⋮ on rows. Right-click on dance or summary text shows Copy and Select all; on a list row it opens the ⋮ menu.

**Unblocks:** S3 (test/selectable-right-click-rule), B29

### N5-5 (PLAT-17)

**Question:** Should Perform let you select text?

**Decision:** (a) No, leave Perform out. Nothing on stage changes from a stray drag; callers copy from the dance page or the summary.

**Unblocks:** S1 (feat/selectable-detail-text)


## Decisions made in conversation (relayed by the orchestrating session)

These were asked through a question dialog and answered by the maintainer directly. The option text is quoted as shown.

### B30 / PRES-1: withdrawn screen-bound keys from older peers (2026-10-29 ~23:22 UTC)
**Decision:** "(a) Drop withdrawn keys". Inbound values for the four withdrawn keys are dropped: not kept, not passed on, no "kept for a newer version" notice. Needs a dated amendment to sync-spec §6.7.

**Re-decided 2026-10-30 ~00:12 UTC** after review found that an old-build device then shows a false "isn't taking N changes … may need an app update" notice about an upgraded peer: "(c) Drop + document". Keep the drop; document the old-device notice in the §6.7 amendment and the user guide. Rejected: (b) keep and republish whole, because every upgraded device would keep sending values classified deviceLocal.

### B27 / PLAT-5, PLAT-6: store builds and end-of-support notices (2026-10-30 ~00:01 UTC)
**Decision:** "Notice only, in #2045". Store builds still read the release info, but only for end-of-support; they never show an update offer, and the banner's "Get update" opens the store listing.

**Store link (2026-10-30 ~00:05 UTC):** "TestFlight + Play URL". iOS opens the TestFlight public link and Android the Play details URL, each one constant.

### B31 / PLAT-12: English-language phones with a non-English region (2026-10-30 ~00:31 UTC)
**Decision:** "Merge, follow-up PR". #2044 merges with the limit documented; a follow-up adds a region fallback (for en_DK, the numeric order of a locale for that region).

### Design plan / N1–N5: the eight readings in `design-work-plan.md` (2026-10-30, relayed ~01:19 UTC)
**Question:** the eight ambiguities `design-work-plan.md` lists ("Ambiguities the answers leave open"), each with the planner's recommended reading, as the planning session gave them.

**Decision:** "Accept all 8 (Recommended)". The option read: "Builders follow these readings, labelled as the planner's reading that you accepted."

The design notes label each one "planner's reading, accepted by the maintainer 2026-10-30". The readings themselves are in `design-work-plan.md`; this entry records only that the maintainer accepted them.

### B7 / LIFE-2: retention auto-purge and items that have synced (2026-10-30 ~02:10 UTC)
**Question:** B7 (#2053) makes Permanently delete blank a published (synced) dance or program. The Recently deleted retention auto-purge still skips published items, so they stay in the trash for ever. Should retention blank them too, given that one device's retention would then clear the item from every device's trash?

**Decision:** "Blank on retention too". The option read: "Follow-up branch: retention treats an expired synced item like Permanently delete. The settings text says it applies to all your devices." The "(Recommended)" tag and its reason were the orchestrating session's. Rejected: "Keep skipping synced items" and "Shortest setting wins" (which needs the setting synced).

Built in the B7 follow-up branch `claude/fix-retention-blanks-synced`.

### Wave 3 (2026-10-30 ~02:10 UTC)
**Question:** when #2040 (F11) merges, start wave 3 (B4 → B5, B22, B24, B28 → B29)?

**Decision:** "Hold wave 3". Do not start wave 3 until the maintainer says so.

### Windows CompanyName: release blocker from #1986 (2026-10-30 ~02:20 UTC)
**Question:** #1986 (F17, after v0.8.1-beta) changed `app/windows/runner/Runner.rc` CompanyName from "org.callerscompendium" to "Caller's Compendium contributors". On Windows, path_provider builds the cache and support folders from CompanyName\ProductName, so the next release would open an empty library for existing Windows users. How should it be fixed?

**Decision:** "Revert CompanyName". The option read: "One-line fix: CompanyName goes back to \"org.callerscompendium\"; the new LegalCopyright text stays. Every folder stays where v0.8.1 put it. Add a test pinning CompanyName with a comment on why, and fix the storage.md and FAQ paths. Opened under your standing approval as a fix PR." Rejected: keeping the new name and migrating the old folders.

Built in #2057.

### B18 follow-up / INTAKE-7: published-collection corrections on re-import (2026-10-30 ~06:50 UTC)
**Question:** B18 (#2064) made re-import replace only a dance's choreography. A published collection's corrected title or credit therefore no longer reaches an imported dance, while its provenance records the new version. Is that intended?

**Decision:** "Ask per import". The option read: "The review screen offers \"Also update title and credit\" as a checkbox on re-import rows." Rejected: "Yes, by design" (document only) and the orchestrating session's recommendation, "Also take title/credit" when not edited since the last import.

### B18 follow-up: four import leftovers (2026-10-30 ~06:50 UTC)
**Question:** fold B18's four listed leftovers (review screen still says "overwritten"; share metadata revives deleted tags, fields and sources; .USR Import-and-edit adds related links; spurious .USR warnings for re-imported pairs) into one follow-up branch?

**Decision:** "One follow-up branch". The option read: "One branch fixes all four, plus the title/credit answer above, under the same rules and approvals. It needs all six ARBs for the wording."

### B19 follow-up / OUT-2: "Same dance – replace" and an absent rating (2026-10-30 ~14:10 UTC)
**Question:** share files no longer carry a dance's rating (OUT-2, #2065). So "Same dance – replace" from a share file clears the receiver's existing rating, because the file has none; `callersbox_online_test` pins "replace overwrites rating". Should replace keep the existing rating when the incoming file has none?

**Decision:** "Keep my rating". The option read: "Replace leaves your existing rating alone whenever the incoming file carries none. It's a small follow-up PR covering the import pipeline, that test and imports.md." The "(Recommended)" tag and its reason were the orchestrating session's. Rejected: "Clear it, as now".

### D-11 / UX6-2: Save, New and the record's name on sibling screens (2026-10-30 ~14:20 UTC)
**Question:** where should Save, New and the record's name sit on sibling screens? Answered in three parts after viewing the renders at https://claude.ai/artifact/GJJMBFTrPuCp46DWMPtsjo.

**Decision:**
- **Save:** "(a) Keep today's split". The two long editors (dance, program) keep a floating Save; the other five keep Save in the top bar. Write the rule into `ux.md` and fix the two code comments that cite `ux.md` for the floating Save.
- **New:** "Keep today's mix". Floating New on top-level lists; "+" in the top bar where a floating button would cover entries (Glossary).
- **Record name:** "(B) Actions to top bar". The top bar keeps "Program" and takes the four action icons; the full name keeps its own line in the body. Dance detail is unchanged.

All three match the recommendations. Builds as the UX6-2 branch, after D2.

### B30 follow-up / PRES-1: stale conflict rows for withdrawn keys (2026-10-30 ~14:25 UTC)
**Question:** a sync conflict on one of B30's four withdrawn keys queued before the upgrade can fail to resolve until the first full pass. Fix by having `refreshConflictReviews` drop such rows?

**Decision:** "Yes, small fix PR". The option read: "A Sonnet branch drops stale conflict rows for the four withdrawn keys, with a guard test. No behaviour changes for anything else."

### B6 follow-up: prove the rename stamp test can fail (2026-10-30 ~14:25 UTC)
**Question:** #2042's test that a renamed program's stamp moves strictly forward was never shown to fail. Prove it now?

**Decision:** "Yes, prove it". The option read: "A small session mutates renameDialect to reuse the old stamp and checks the test goes red. If it doesn't, the session strengthens the test in a small PR. A test-only change."

### Wave 3 release condition (2026-10-30 ~14:30 UTC)
**Decision (maintainer's words):** "Release wave 3 when everything remaining from wave 2 is all-green and ready to merge."

At that time the only wave-2 branch not yet merged or open was B3 (`fix/link-typed-venues`), so wave 3 (B4 → B5, B22, B24, B28 → B29) starts once B3's PR is green and ready to merge.

## Still open

- Nothing on the decision page.
