# October 2026 behavior audit — synthesis

Nine read-only audits, each following one caller user story end to end. Full reports are in `reports/`; probe sources in `probes/`. Published summary page: https://claude.ai/artifact/Tm6fL9hgeC8fUVVJ1N488u

This directory exists so a reviewer can do a defensive intake of the findings. It is not meant to be merged as-is.

Totals: 144 findings — 22 high, 72 medium, 50 low (LIFE-11 "Low/Medium" counted as low). Overlapping findings from different audits keep their own numbers, so the count includes duplicates.

## Areas

- **AUTH** — Entering a dance: I learned a dance at a weekend and want it in my collection quickly, in my own shorthand, exactly as I'll call it.
- **GIG** — Running a gig: Build a program with alternates, check the matrix, print it for the band, call it from a phone on stage, then keep an accurate record.
- **INTAKE** — Bringing dances in: First launch, then 300 dances from The Caller's Box, ContraDB, Caller's Companion, text lists and friends' share files.
- **OUT** — Sending dances out: Print, email, share, export and back up, then import into another copy of the app with nothing lost.
- **PRES** — Display settings everywhere: Dialect, date format, decimal turns and colors: does every screen and export honor them, and which follow you to other devices?
- **FIND** — Finding and organizing: Find an easy dance not yet called at this venue in 30 seconds; tidy tags, ratings and custom fields on a quiet Sunday.
- **LIFE** — Rename, duplicate, delete: What deleting, renaming, duplicating and restoring each kind of record really does to related data.
- **FAIL** — When things go wrong: No Wi-Fi, a full disk, an old version, a force-quit mid-save: does the app say plainly what happened and offer a way forward?
- **PLAT** — Each platform: Keyboard and menus on desktop, back gestures and share sheets on mobile, opening a file someone sent, and the same features everywhere.

## Cross-cutting themes (the synthesizer's grouping)

### “Called” means something different on each screen

Calling history is worked out from which programs a dance is in and from per-slot “performed” stamps, and each screen combines them its own way. The “Called ×4” badge counts every program by default. The Last-called sort counts only stamped slots and ignores the caller filter, so with default settings it falls back to title order. Marking a program performed also stamps the alternates nobody called. Setting the status to Performed records the gig a day early anywhere west of UTC. Duplicated programs, drafts of future gigs and programs received from another caller all count as yours. Deleting a program erases its history. And a caller cannot ask for the one thing the history exists for: “not called at this venue lately”.

*Direction:* Decide once what “called” means and which date it carries, then answer every surface from one shared query.

*Findings:* GIG-1, GIG-2, GIG-3, GIG-5, GIG-7, GIG-9, GIG-12, GIG-13, GIG-16, FIND-1, FIND-2, OUT-2, LIFE-6, LIFE-7, PRES-4

### Each way in is a separate import feature

Whether default tags apply, whether duplicates are caught, whether there is a review step and an Undo, and how failures are reported all depend on which route a dance took into the app. Re-importing a Caller's Companion file, or receiving a program a second time, turns existing slots into “Dance not imported (…)”. A ContraDB program import duplicates dances the caller already has. Program imports write dances before Import is pressed and leave them behind on Undo. The same share file goes through one of two importers depending on how it arrived.

*Direction:* Route every intake path through the import review and its single commit-and-undo step.

*Findings:* INTAKE-1, INTAKE-3, INTAKE-4, INTAKE-5, INTAKE-6, INTAKE-7, INTAKE-8, INTAKE-10, INTAKE-13, INTAKE-14, INTAKE-16, OUT-1, FAIL-6

### The app reports success when nothing happened

These are the findings most likely to cost a caller trust. A dismissed share sheet counts as a backup and silences the overdue reminder. “Permanently delete” says done, and the item comes back. A friend's shared dance fails to import and the message says “Imported”. An offline update check says “No update found”. Offline program lookup says “No confident matches”. Only Device Sync tells offline, temporary and permanent failures apart and gives advice with a copyable code. Every other feature has its own failure types, and three of them turn a known failure into a reassuring message.

*Direction:* Adopt Device Sync's failure model (offline, temporary, permanent, each with a plain next step) across the app.

*Findings:* FAIL-1, LIFE-2, OUT-1, FAIL-3, FAIL-2, FAIL-4, FAIL-5, FAIL-8, FAIL-9, INTAKE-2, FIND-11, OUT-10

### Typed input disappears without a warning

In the dance editor, a figure line typed but not entered, a row with its move cleared, or a half-filled meanwhile is dropped on Save, and the running beat total still counted it. Notes on a meanwhile side are stored but never displayed. In programs, auto-save writes back a stale copy that erases performed stamps, and an adjustment in Perform commits every unsaved builder edit.

*Direction:* Save should either keep what's on screen or say what it is leaving out.

*Findings:* AUTH-1, AUTH-2, AUTH-3, AUTH-6, AUTH-9, AUTH-10, GIG-3, GIG-4, GIG-6, GIG-19, INTAKE-7, LIFE-10, LIFE-14, PLAT-19

### Delete and trash follow different rules for each record type

Storage soft-deletes eleven kinds of record, but only dances and programs have a trash. Permanently deleting one item purges everything trashed more than 30 days ago, whatever the retention setting says. Anything ever synced can never leave the trash. A trashed dance shows up five different ways across the program screens, and as “Untitled dance” on the band's printout. Tags, choreographers and sources can be created but never renamed, merged or deleted.

*Direction:* One trash model for every record type, one way to render a trashed dance, and rename and merge for tags and people.

*Findings:* LIFE-1, LIFE-2, LIFE-3, LIFE-4, LIFE-5, LIFE-8, LIFE-9, LIFE-11, GIG-11, GIG-17, OUT-7, FIND-3

### Settings stop short of some screens

The date format setting is ignored by PDFs, the emailed set list and calling history, and the default “System” format drops the year. Decimal turns never reach exports. Some screens use a shorter figure renderer that drops “balance &”. Settings that the app says stay on this device, such as custom themes, actually sync, and the first connection silently overwrites them. Sorting ignores the app's language, and every PDF is A4.

*Direction:* Read display settings from one live source, and render dance text through one renderer that takes them.

*Findings:* PRES-1, PRES-2, PRES-3, PRES-5, PRES-6, PRES-7, PRES-9, PRES-10, GIG-18, OUT-3, OUT-4, PLAT-12, FIND-15, PLAT-15

### Desktop and mobile conventions are only partly there

On Windows and Linux, a share file can't be opened by double-clicking it. On a phone, the update banner sends TestFlight and Play users to downloads they can't use. The macOS menu bar is Flutter's unchanged template, and its About box says “All rights reserved” on an AGPL app. The promised full keyboard map is four shortcuts. Perform never goes full screen. On iPad, the backup export's share sheet is very likely to fail.

*Direction:* Treat each platform's file-open, menu and update hand-offs as part of the feature, not as packaging.

*Findings:* PLAT-1, PLAT-2, PLAT-3, PLAT-4, PLAT-5, PLAT-6, PLAT-7, PLAT-8, PLAT-9, PLAT-10, PLAT-13

## High-severity findings and how far each was verified

- **LIFE-1** — Permanently deleting one item purges every other item trashed more than 30 days ago, even with retention set to Never or 90 days. *[Re-checked — the synthesizer re-read the cited code]*
- **LIFE-2** — An item that was ever synced can't leave the trash. “Permanently delete” says it's gone, then the item comes back marked “Scheduled for deletion”. *[Re-checked — the synthesizer re-read the cited code]*
- **OUT-1** — A shared dance that has any link fails to import, a program's slot becomes “Dance not imported”, and the message says “Imported N items”. *[Reproduced — the auditor ran the real code in a scratch copy]*
- **AUTH-1** — A figure line typed but not entered is dropped on Save, with no Discard prompt. The on-screen Done clears it; the keyboard's Done adds it. *[Re-checked — the synthesizer re-read the cited code]*
- **AUTH-2** — Rows with a cleared move, a half-filled meanwhile or an empty group vanish on Save, but the beat total still counted them. *[Traced — auditor's reading only; not re-checked]*
- **AUTH-3** — Notes on a meanwhile side or modifier appear nowhere outside the open editor, so “allemande 1½” displays as “once”. *[Traced — auditor's reading only; not re-checked]*
- **AUTH-4** — The free-text parser keeps a wrong reading and moves the rest of the line into a note: “circle left 3/4 and pass through” becomes “circle left 4 places”. *[Reproduced — the auditor ran the real code in a scratch copy]*
- **GIG-1** — Mark all performed and Status → Performed stamp alternates nobody called, which skews history, counts and venue repeats. *[Re-checked — the synthesizer re-read the cited code]*
- **GIG-2** — Status → Performed records the gig a day early anywhere west of UTC, while Mark all performed records the day you tapped it. *[Re-checked — the synthesizer re-read the cited code]*
- **GIG-3** — With auto-save on, the next edit after Status → Performed writes back the editor's unstamped copy and erases every mark. *[Traced — auditor's reading only; not re-checked]*
- **OUT-2** — A program received from another caller counts as your calling history and brings their pay and star ratings with it. GIG-13 found the same independently. *[Traced — auditor's reading only; not re-checked]*
- **INTAKE-1** — Re-importing a .USR, or receiving a program again, replaces links to dances you already have with “Dance not imported (…)” notes. *[Traced — auditor's reading only; not re-checked]*
- **INTAKE-2** — A share file is refused at the last step if the receiver's custom field with the same key differs even in Show in list or Include in sharing. *[Re-checked — the synthesizer re-read the cited code]*
- **INTAKE-3** — Programs → From ContraDB adds a second copy of every dance you already have, without asking. *[Traced — auditor's reading only; not re-checked]*
- **INTAKE-4** — Program imports write dances before Import is pressed, keep them if you back out, and leave them behind on Undo. *[Traced — auditor's reading only; not re-checked]*
- **FIND-1** — Nothing filters for “not called at this venue” or “not called recently”, and the program picker shows no calling history at all. *[Traced — auditor's reading only; not re-checked]*
- **FIND-2** — The Last-called sort uses a different meaning of “called” from the badge, the detail page and the guide. GIG-5 found the same. *[Traced — auditor's reading only; not re-checked]*
- **FIND-3** — Tags can't be renamed, merged or deleted anywhere. LIFE-5 found the same for choreographers and sources. *[Traced — auditor's reading only; not re-checked]*
- **FAIL-1** — On a phone, dismissing the share sheet still shows “Backup exported.” and resets the overdue-backup reminder. *[Re-checked — the synthesizer re-read the cited code]*
- **FAIL-2** — Resolving titles online while offline reports “No confident matches”, can't be cancelled, and keeps importing after you leave. *[Traced — auditor's reading only; not re-checked]*
- **FAIL-3** — A manual Check for updates says “No update found” whenever it couldn't check, and permanently so for installs stranded by a key rotation. *[Traced — auditor's reading only; not re-checked]*
- **PLAT-1** — On iPad, backup and diagnostics export open the share sheet without the anchor iPad requires. Every other share passes one. *[Needs a device — read from code only]*

## Decisions the synthesis says the maintainer must make

- **What counts as “called”, and on which date?** Options the audits raise: only slots marked performed, or any program with a past event date; record the program's event date, not the moment someone tapped; leave alternates out of bulk marks. (GIG-1, GIG-2, GIG-5, GIG-12, FIND-2)
- **Should duplicated or received programs ever count as your history?** Options: clear the event date on Duplicate, import received programs as Draft with marks cleared, or rename the default badge to “In N programs”. (GIG-13, OUT-2, LIFE-6, LIFE-7)
- **What should “Permanently delete” do to a record that was synced?** Options: hide the record and blank its content while keeping the deletion marker, say plainly it is kept as a deletion record, or retire the marker once every device has it. (LIFE-2)
- **Should tags, choreographers and sources get rename, merge and delete?** Today they can only be created. The trash purge removes them silently, taking tag colors and private choreographer notes with them. (FIND-3, LIFE-5, FIND-9)
- **How should re-import treat dances you already have?** A skipped dance could still link its program slots. Batch re-import could refresh figures only, the way Re-import choreography does, instead of wiping rating, tags and links. (INTAKE-1, INTAKE-7)
- **How strict should custom-field matching be on shared files?** Compare only key, type and choices, map onto the receiver's field, and show any conflict during review rather than after it. (INTAKE-2)
- **Should a manual update check say it couldn't check?** Automatic checks would stay silent, as ADR-002 requires. Only the button the caller pressed would get a “Couldn't check right now” line. (FAIL-3)
- **Which settings should sync?** Theme, language, Reduce motion and the Perform stage theme sync today, while Perform text size deliberately doesn't. Nothing in the app says which is which. (PRES-1, PRES-2)
- **Should the “Confirm before delete” accessibility setting also cover swipe-to-delete?** You decided to keep swipe-to-delete as it is. This asks only whether a caller who turned that setting on should get a prompt there too, as the docs promise. (PRES-5)
- **Are dances on either side of a break or waltz back-to-back?** Options: a break separates them, any free-text slot separates them, or keep the current behavior and document it. (GIG-8)
- **Platform hand-offs** Register .ccshare on Windows and Linux, point phone update banners at the right store, and replace the template macOS menu. Should Perform go full screen? (PLAT-3, PLAT-5, PLAT-8, PLAT-9)
- **How should search match?** Multi-word searches of three or more characters only match the exact phrase. Search doesn't know a dialect's own move names, though the editor and Glossary do. (FIND-4, FIND-5)

## Suggested order (the prioritization under review)

1. **Fix without a decision** — Small, contained fixes for data loss or false reports. LIFE-1 (pass the retention to the purge), AUTH-1 and AUTH-2 (commit or warn on Save), OUT-1 (remap link ids on import), FAIL-1 (respect a dismissed share sheet), GIG-3 (adopt the read-back after commit), LIFE-3, FAIL-7, and PLAT-1 once confirmed on a device.
2. **Settle the calling-history model** — One decision unlocks most of the first theme. Then one shared query for the badge, sort, filter, venue repeats and half stats, plus the venue filter callers would expect (FIND-1).
3. **Unify intake** — The largest piece of work, and the one that most affects first impressions. Every path through review, one duplicate check, one Undo, one result summary that names failures.
4. **One failure model** — Builds on what Device Sync already does well. Shared offline, temporary and permanent classes, each with a plain next step, written to the diagnostics log.
5. **Settings reach and platform polish** — Mostly medium and low items, good for batching. Date format and decimal turns in exports, one figure renderer, the sync list for settings, file associations, menus, keyboard shortcuts.

## Also claimed

- Batches 2–7 of the October UX audit (https://claude.ai/artifact/R8DAGdsagzTaVw6SGCA3m1, PR #1919) have no tracking issues and remain in the code (e.g. theme/venue editors lack an unsaved-changes guard; "Callers Compendium JSON" still in app_en.arb).
- Method: auditors were read-only, did not build or run the app, and ran nothing on devices. Probes ran outside the repo against a copy of packages/compendium_core at a6665db.
