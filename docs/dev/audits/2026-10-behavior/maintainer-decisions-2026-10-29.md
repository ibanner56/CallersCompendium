# Maintainer decisions, 2026-10-29

The maintainer (ibanner56) recorded these answers on the decision page https://claude.ai/artifact/MRVAeqpyG34SKbv48Xomdy on 2026-10-29. This file was exported from the page's store, and the notes are quoted verbatim. Each row gives the option the maintainer picked and whether it matched the recommendation on the page. Recommendations came from the planning session; only the picks are maintainer decisions.

Option wording and evidence for each question are in the page's source data. The audit reports and `batch-plan.md` / `ux-followups-intake.md` give the background.

## UX audit decisions

### D-2 (UX4-1, UX4-4)
**Question:** On a phone, which buttons stay on each program slot row in the builder?

**Decision:** (a) Drag handle and ⋮ only. View, Up, Down and Cut move into ⋮, with Up and Down first. The title gains about 170px. About 300 lines in U7. *(matches the recommendation)*

### D-1 (UX2-2)
**Question:** In the "Discard changes?" dialog, which button should be the main one?

**Decision:** (b) Keep editing filled, Discard red text. Two buttons. The safe choice is the filled one and Discard stays red. A few lines per dialog. *(matches the recommendation)*

### D-5 (UX5-1, INTAKE-12, INTAKE-11)
**Question:** What should the first-run sample dance, "The Baby Rose", be?

**Decision:** (a) Keep it, add an import card. A "bring your dances in" card shows while the sample is the only dance. No stored-data change. Part of U9. *(matches the recommendation)*

### D-3 (UX3-2, UX3-5)
**Question:** Which single name should each of these things have: custom figure, the trash, share files, and author?

**Decision:** (a) Rename only the unread-text meaning. "Unrecognized figure" for unread text (already used twice). Keep the Custom Figures setting. Trash is "Recently deleted", files are "share file", people are "author". *(matches the recommendation)*

### D-7 (UX4-2)
**Question:** In Perform on a narrow phone, how should the beats label make room for the figure?

**Decision:** (a) Cap the beats label's text size. Limit the label to about 1.3× text scale, keeping the beats column aligned. Small; part of U6. *(matches the recommendation)*

### D-9 (UX7-1)
**Question:** What colour and shape should a warning that doesn't block anything use?

**Decision:** (a) Tertiary, flat container. Error colour is kept for things that block. Matches the editors' WarningsCard. *(matches the recommendation)*

### D-8 (UX6-1)
**Question:** How wide should reading text be allowed to grow on a desktop window?

**Decision:** (a) 760px. Matches the wireframes. U10 is about 120 lines. *(matches the recommendation)*

### D-6 (UX5-2)
**Question:** Should every list use one empty-state design?

**Decision:** (b) Full pattern on main lists only. Collection, Programs, Venues, Custom figures and Recently deleted; one line inside Settings sub-lists. *(matches the recommendation)*

### D-4 (UX3-6)
**Question:** For app text, which spelling, capitalisation and quote style is the rule?

**Decision:** (c) Same as (a), but normalise all quotes. About 300 more strings; L size. *(differs from the recommendation (a: US spelling, sentence case, quotes as-is))*

### D-10 (UX7-3)
**Question:** Which icon should mean "remove from this list"?

**Decision:** (a) Minus-circle removes, bin deletes, cross on chips. One meaning per icon; part of U12. *(matches the recommendation)*

### D-11 (UX6-2)
**Question:** Where should Save, New and the record's name sit on sibling screens?

**Decision:** not yet decided.

**Maintainer's note:** "I’d like to see a rendering of each to decide"

### D-12 (UX6-3)
**Question:** In the dance editor, should fields use floating labels or headings above them?

**Decision:** (a) Floating labels for inputs, headings for chips. Type and Formation change. One rule line in ux.md. Part of U10. *(matches the recommendation)*

### UX5-4a (UX5-4)
**Question:** When you delete a dialect, theme, shorthand, snippet, custom field or custom figure, should it stay confirm-only?

**Decision:** (b) Confirm, then a "Deleted" snackbar. Small; makes the result visible. *(differs from the recommendation (a: Keep confirm-only))*

## Behaviour audit decisions

### sharing-custom-fields (INTAKE-2)
**Question:** When a received file has a custom field with your key but different display settings, should the import still work?

**Decision:** (a) Match on key, type and choices. Use your own field and your display settings; show any real conflict during review. About 20 to 25 lines. *(matches the recommendation)*

### contradb-program-dupes (INTAKE-3)
**Question:** When you import a ContraDB program, should a dance you already have be reused instead of duplicated?

**Decision:** (a) Reuse an identical dance (#685 rule). Still no per-dance prompt (#797). About 20 to 25 lines. *(matches the recommendation)*

### online-single-import (INTAKE-5)
**Question:** When you import one dance from online search and you typed the same dance yourself, should the app ask first, and offer Undo?

**Decision:** (a) Ask on a hand-entered match, add Undo. Neutral wording in the existing dialog; Undo on the snackbar. *(matches the recommendation)*

### batch-reimport (INTAKE-7)
**Question:** Should batch "Re-import onto…" keep your rating, tags, links and notes?

**Decision:** (a) Use the choreography-only update. Batch re-import replaces only figures, formation and progression, like the detail-page version. *(matches the recommendation)*

### update-check-wording (FAIL-3)
**Question:** When you tap Check for updates and the check fails, what should it say?

**Decision:** (c) (a), plus a newer-format notice. An authentic but unsupported manifest says "A newer version is available from the Releases page". *(matches the recommendation)*

### LIFE-2-wording (LIFE-2)
**Question:** When you permanently delete something that was ever synced, what should happen in Recently deleted?

**Decision:** (a) Hide it and blank its content. Keep only the deletion record; the trash and backups no longer show its content. *(matches the recommendation)*

**Maintainer's note:** "Also clear the deletion record if every device has a more recent sync than the timestamp on the delete"

### diagnostics-reach (FAIL-10)
**Question:** Should a scrubbed diagnostics export keep safe error messages, and be reachable when the app can't start?

**Decision:** (d) (a) and (c). Small code change plus a FAQ fix. *(matches the recommendation)*

### startup-dead-ends (FAIL-11)
**Question:** Should the four dead-end startup screens offer a way forward?

**Decision:** (b) Copy details and Releases link only. No re-run; keeps them strictly terminal. *(differs from the recommendation (a: Check again, Releases link, Copy details))*

**Maintainer's note:** "I don’t think check again would ever succeed, so it’s a button that always fails, right?"

### search-index (FIND-6, FIND-13)
**Question:** What should the search bar look in, and should "Searchable" off hide a custom field from it?

**Decision:** (a) Honour Searchable, fix yes/no values. Keep today's field list; filters still reach tags and formation. *(matches the recommendation)*

### trash-policy (LIFE-9, LIFE-4, GIG-17)
**Question:** Should a record in Recently deleted still protect the venues, custom fields and levels it uses?

**Decision:** (b) Trash doesn't protect. Every guard ignores trashed records; restore must then cope with missing venues and fields. *(differs from the recommendation (a: Trash protects))*

### program-delete-history (LIFE-6)
**Question:** When you delete a program, should the app warn that its dances lose that calling history?

**Decision:** (a) Warn in the confirm and guide. "N dances will lose this from their calling history". *(matches the recommendation)*

### perform-full-screen (PLAT-9)
**Question:** Should Perform really go full screen, or should the guide stop saying so?

**Decision:** (a) Go full screen. Immersive mode on phones; a full-screen toggle on desktop using window_manager, already a dependency. Restore on exit. *(matches the recommendation)*

### autosave-failures (FAIL-8)
**Question:** If the editor can't save its draft (for example on a full disk), should anyone know?

**Decision:** (c) Both. About 40 lines. *(matches the recommendation)*

### settings-sync-scope (PRES-1)
**Question:** With Device Sync on, should language, motion and Perform screen settings stay on each device?

**Decision:** (a) Make screen-bound settings per-device. Language, Reduce motion, stage theme and auto-size become deviceLocal; theme keeps syncing. *(matches the recommendation)*

### program-status (GIG-12)
**Question:** What should a program's status (Draft, Finalized, Performed) mean?

**Decision:** (a) Keep separate, say so. Helper text under the dropdown and a line in programs.md. Small. *(matches the recommendation)*

**Maintainer's note:** "But add a setting with the others related to performance tracking to set program status to performed when someone hits the mark all as performed button and leave it enabled by default - option 2, essentially, with a settings switch to go back to option 1."

### perform-keys (PLAT-10)
**Question:** In Perform, should Down and Page Down scroll a long card before moving to the next dance?

**Decision:** (a) Scroll first, then advance. Down and Page Down scroll to the end, then move on. Pedals keep working. *(matches the recommendation)*

### updater-install-kind (PLAT-5, PLAT-6)
**Question:** Should the updater know how the app was installed?

**Decision:** (a) Detect store and portable installs. Store builds don't check; portable builds say "download the new zip from the release". *(matches the recommendation)*

### guide-language (PLAT-13)
**Question:** For callers using the app in another language, what should the Guide do?

**Decision:** (a) A one-line notice. "The Guide is in English" for non-English locales. One string. *(matches the recommendation)*

### venue-history-merge (GIG-7)
**Question:** Should calling history treat a typed venue and a venue record with the same name as one hall?

**Decision:** (b) Offer to link old programs. When venue records are turned on. *(differs from the recommendation (a: Merge by the displayed name))*

### back-to-back-breaks (GIG-8)
**Question:** In the matrix, are two dances on either side of a break still "back-to-back"?

**Decision:** (a) A break separates. Use the program's sections, which the matrix already receives. *(matches the recommendation)*

### picker-parity (FIND-7, PRES-15)
**Question:** Should the program's "add a dance" picker match Collection's search tools?

**Decision:** (b) Full parity. Search in, sort, online scopes and card fields. *(differs from the recommendation (a: Add card fields and Search in))*

### decimals-in-exports (PRES-10)
**Question:** Should "Show turns as decimals" also apply to printed and exported cards?

**Decision:** (a) Document the exclusion. One line, like Capitalize. *(matches the recommendation)*

### locale-sorting (FIND-15, PLAT-15)
**Question:** Should sorting handle accented letters and non-English articles?

**Decision:** (a) Fold accents in the sort key. É sorts with E; no new dependency. *(matches the recommendation)*

### android-ccshare (PLAT-4)
**Question:** Should Android accept a .ccshare file that arrives as a generic file type?

**Decision:** (a) Accept generic files, validate in the app. Add application/octet-stream to the picker and the Open-with filter. *(matches the recommendation)*

### dance-card-fields (OUT-6)
**Question:** Should a printed or emailed dance card be able to show its source and hook?

**Decision:** (a) Add sources and hook to the picker. Two more options. *(matches the recommendation)*

### tag-chip-tap (FIND-14)
**Question:** When you tap a tag chip on a dance, should it add that tag to your current search instead of replacing it?

**Decision:** (a) Add the tag to the current filters. Nothing is lost. *(matches the recommendation)*

### program-dialect-rename (PRES-11, LIFE-11)
**Question:** When you rename a dialect, should programs that use it follow the new name?

**Decision:** (a) Carry renames to programs. Rename updates every program that names it. *(matches the recommendation)*

### formation-colours-set-lists (PRES-12)
**Question:** In set lists, should your own formation colours override the built-in formation-family tints?

**Decision:** (a) Your colour wins where set. Family tint stays for uncoloured formations. *(matches the recommendation)*

### bare-hey (AUTH-13)
**Question:** When you type just "hey", should the pass and shoulder the app fills in be marked as assumed?

**Decision:** (c) Accept as documented. No change. *(matches the recommendation)*

## Residual decisions inside planned findings

### OUT-2-share-fields (OUT-2)
**Question:** Should your pay, star ratings and Perform dialect travel in files you share with other callers?

**Decision:** (a) Leave out pay, rating and dialect. Share mode only; backup and sync unchanged. *(matches the recommendation)*

**Maintainer's note:** "These fields should still travel in sync and export"

### GIG-2-call-date (GIG-2)
**Question:** Which date should a dance's calling history show: the program's event date, or when you tapped Mark performed?

**Decision:** (a) The event date when there is one. The stamp becomes a "called" flag; tap time is used only for undated programs. Re-dating moves history. *(matches the recommendation)*

### AUTH-2-incomplete-rows (AUTH-2)
**Question:** When Save will drop an unfinished group (a meanwhile with one side filled), should the app say so first?

**Decision:** (b) Warn on the row and in Warnings. No dialog; reuses the Warnings card. *(matches the recommendation)*

### AUTH-1-move-blur (AUTH-1)
**Question:** If you type a move name in a row's Move box and click away without pressing Enter, should the app take it?

**Decision:** (a) Take an exact match on blur. An exact move name or shorthand is applied, using #2003's rule; anything else reverts. *(matches the recommendation)*

### PLAT-12-system-date (PLAT-12)
**Question:** Should the "System default" date format follow the app's language or the device's region?

**Decision:** (b) Follow the device region. Read the platform locale for dates. *(differs from the recommendation (a: Keep app language, document it))*

### PLAT-7-shortcuts (PLAT-7)
**Question:** Which desktop keyboard shortcuts should the app have?

**Decision:** (b) (a) plus right-click and mouse Back. Right-click opens the ⋮ menu. *(differs from the recommendation (a: A minimal map))*

### FIND-4-dialect-search (FIND-4)
**Question:** Should search understand your dialect's own move names, as the editor does?

**Decision:** (a) Search bar uses the dialect's names. Reuse the reverse map Advanced's figure rows already use; type-aheads later. *(matches the recommendation)*

### FIND-5-multiword (FIND-5)
**Question:** Should a search of several words find dances with those words in different fields?

**Decision:** (b) Split into words and AND them. Reverses part of #1005. *(differs from the recommendation (a: Keep the phrase, fix the guide (D2)))*

### PLAT-8-mac-menu (PLAT-8)
**Question:** On the Mac, should the menu bar do something useful?

**Decision:** (b) A small app menu bar. Settings, New dance, Import, Guide, plus standard items. *(differs from the recommendation (a: Wire Cmd-, and Help only))*

### PLAT-3-desktop-open (PLAT-3)
**Question:** On Windows and Linux, should double-clicking a .ccshare file open it in the app?

**Decision:** (a) Register the file type. Installer and .desktop changes; pass the path to a running app. *(differs from the recommendation (b: Fix faq.md and sharing.md (D2)))*

## Calls made by fix sessions

### ratify-F5b
**Question:** Do you accept that the F5b toggles skip rows whose dance no longer exists?

**Decision:** (a) Accept. No work. *(matches the recommendation)*

### ratify-F8 (OUT-8)
**Question:** Shared file names are cut to 64 characters and lose leading dots (#2004, open). Do you accept that?

**Decision:** (a) Ratify. No work. *(matches the recommendation)*

### ratify-F6 (GIG-13, LIFE-7, OUT-2)
**Question:** Do you accept three calls the F6 session made in #2002 (merged)?

**Decision:** (a) Ratify all three. No work. *(matches the recommendation)*

### ratify-german-beats
**Question:** German uses "Takte" (bars) for beats. Who fixes it, and with which word?

**Decision:** (a) Agent sweep to "Schläge", fluent review. Add a glossary entry, change all beat strings in one PR, ask a German-speaking caller to review it. *(matches the recommendation)*

### ratify-F3 (AUTH-9)
**Question:** Retyping a figure row now keeps its walkthrough step as well as its note and mark (#2003, merged). Do you accept that?

**Decision:** (a) Ratify. No work. *(matches the recommendation)*

### ratify-F16-ecd (INTAKE-15)
**Question:** Should the "Convert ECD dances?" question stay at launch, or move to just after an import?

**Decision:** (a) Keep it at launch. No work; it now has Undo and docs. *(matches the recommendation)*

## Features that need a design note

### design-history-filters (FIND-1)
**Question:** Should we write a design note for venue and recency filters in Collection and the program picker, and how soon?

**Decision:** (a) Design note now. Write it before the next planning round. *(matches the recommendation)*

### design-tags-people (FIND-3, LIFE-5)
**Question:** Should we write a design note for renaming, merging and deleting tags, choreographers and sources, and how soon?

**Decision:** (a) Design note now. Write it before the next planning round. *(matches the recommendation)*

### design-duplicates (FIND-9)
**Question:** Should we write a design note for a duplicate-dance finder and merge, and how soon?

**Decision:** (c) Drop it. Not planned. *(differs from the recommendation (b: Later: open a backlog issue))*

### design-bulk-select (FIND-8)
**Question:** Should we write a design note for bulk selection (Select all, and which batch actions), and how soon?

**Decision:** (a) Design note now. Write it before the next planning round. *(differs from the recommendation (b: Later: open a backlog issue))*

### design-tidy-filters (FIND-10)
**Question:** Should we write a design note for tidy-up filters (no level, unrated, level ranges, rating sort), and how soon?

**Decision:** (c) Drop it. Not planned. *(differs from the recommendation (b: Later: open a backlog issue))*

### design-settings-ia (PRES-13)
**Question:** Should we write a design note for the Settings layout, and how soon?

**Decision:** (c) Drop it. Not planned. *(differs from the recommendation (b: Later: open a backlog issue))*

### design-provenance (INTAKE-8)
**Question:** Should we write a design note for multi-valued provenance and keeping the original source on received dances, and how soon?

**Decision:** (c) Drop it. Not planned. *(matches the recommendation)*

### design-add-to-program (FIND-17)
**Question:** Should we write a design note for the Add-to-program sheet (search, hiding past programs, "already contains"), and how soon?

**Decision:** (a) Design note now. Write it before the next planning round. *(differs from the recommendation (b: Later: open a backlog issue))*

### design-selectable-text (PLAT-17)
**Question:** Should we write a design note for selectable dance and program text on desktop, and how soon?

**Decision:** (a) Design note now. Write it before the next planning round. *(differs from the recommendation (b: Later: open a backlog issue))*

### design-seed (INTAKE-12)
**Question:** Should we write a design note for what the seed dance is, and how soon?

**Decision:** (c) Drop it. Not planned. *(matches the recommendation)*

### design-second-instance (PLAT-18)
**Question:** Should we write a design note for what a second app launch shows when it can't reach the first, and how soon?

**Decision:** (c) Drop it. Not planned. *(matches the recommendation)*
