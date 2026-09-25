<!-- release-managed-by: tools/release/compile_changelog_fragments.py -->
# Changelog

All notable changes to Caller's Compendium (the app) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings use the semantic `major.minor.patch` version. New releases use
the exact `app/pubspec.yaml` version and select their channel from the tag:
`vX.Y.Z-beta` for beta or `vX.Y.Z` for stable. Store build codes are derived
from that tag, so new entries need no visible or manually maintained suffix.

### Platforms & install

- **Android** — a signed universal `.apk` for direct install (sideload); you may
  need to allow "install unknown apps" for your browser or file manager. The app
  is also in a **Google Play closed test**, which installs and updates through the
  Play Store — ask about joining if you'd prefer that. The Play build and the
  `.apk` are signed with **different keys**, so you can't upgrade between them in
  place; pick one and stick with it (back up before switching).
- **iOS** — delivered through **TestFlight** to invited testers; by design there is
  no `.ipa` on this Releases page.
- **macOS** (universal) — **signed with an Apple Developer ID and notarized**, you
  may see a confirmation on first launch.
- **Linux** (x64) — desktop artifacts are **unsigned**, but Linux generally has no
  signing prompt:
  - The **`.tar.gz`** is the no-setup path — extract and run. The `.AppImage`
    needs the **FUSE 2** runtime (`libfuse.so.2`) — package `libfuse2` on
    Debian/Ubuntu, `fuse-libs` on Fedora — which some recent distros don't
    preinstall; install it, or launch with
    `./CallersCompendium-*.AppImage --appimage-extract-and-run`.
- **Windows** (x64) — release artifacts are signed via Azure Trusted Signing but
  may show a **SmartScreen** warning; choose **More info → Run anyway** on the
  blue **Windows protected your PC** prompt.

## [Unreleased]

_Nothing yet._

## [0.5.0] - 2026-09-24

### Added

- A dance whose saved figures or tunes cannot be read now says so, on the dance itself and as a marker in your collection, instead of appearing to have none. Nothing has been deleted: what was saved is kept exactly as it is, and editing anything else about the dance will not replace it.
- Device Sync now tells you when a dance is being held back because its saved figures or tunes can't be read, instead of leaving it quietly missing from your other devices. The notice says nothing has been deleted and points at the only thing that fixes it: entering those figures or tunes again.
- Connecting a device to Device Sync now says plainly that anyone holding the sync phrase can read everything you sync, change or delete it on every connected device, and delete the whole store from the server. It appears on both the create and connect paths.
- Typing your own sync phrase instead of keeping the generated one now warns you to keep personal information out of it. Like the strength warning beside it, it never stops you using the phrase you chose.
- The Device Sync section now shows the server it is syncing with as a full address, whether that is the Caller's Compendium server or your own. A server that isn't the default one is still flagged.
- Device Sync settings now list the other devices connected to your store and let you remove one you no longer use, so it stops taking up one of the store's 32 places. A removed device can connect again with the sync phrase.
- Device Sync settings can now disconnect every device and delete the store from the server. This cannot be undone, and it is the only way to immediately remove what a leaked sync phrase still opens.
- Settings ▸ About ▸ View licenses now includes the license of fmptools, the open-source project the Caller's Companion importer is based on.
- Experimental settings now include Device Sync, which is off until you turn it on. It shows sync status, waits for WiFi by default, and reminds you that sync is not a backup.
- Device Sync now has a Connect flow: create a new store or connect to an existing one by phrase, with an optional one-time backup offer and clear disclosures about sharing and the phrase's no-recovery guarantee. If a previously connected store has gone missing, you're asked before it's replaced.
- Device Sync gains a 'Skip unused imported dances' setting to trim what a device with a large imported collection uploads (a dance used in a program or linked from another dance is always included), and a note on a venue whose address and contact details didn't come across when it synced from another device.
- You can review saved sync decisions in Settings and either merge a supported peer deletion or keep both records with a distinct local name; invalid or stale decisions remain safely retained.
- You can disconnect a device from its Device Sync store with Disconnect this device. It forgets the phrase and the server it was using and stops syncing on that device only, without changing your library, the store, or your other devices. Turning Device Sync off and on still keeps you connected.
- When you connect Device Sync, a Server field shows which sync server you're using. It's pre-filled with the Caller's Compendium server, and you can change it if you run your own. The app warns you before you use a different server and keeps showing it on the sync status.
- The Device Sync status now starts with the sync phrase this device is connected with, so you can add another device later without having written the phrase down when you first connected. It stays hidden until you tap Show, and Copy works without revealing it.

### Changed

- Inbound dance and program sync now uses the trusted sync envelope timestamps instead of conflicting metadata embedded in the record body.
- In the program builder, the scissors button on a slot now removes that slot from the program, and the redundant Remove slot entry has left the slot's ... menu. Removing a slot never deletes the dance from your collection.
- The screen shown when connecting finishes now says what actually happened to the first sync — that it has finished, that it didn't finish and will retry, or that it is waiting for WiFi or for a connection. It used to say the first sync was running now, which was never true by the time you could read it.
- That screen also repeats that sync is not a backup, which it previously left out.
- Duplicate dances merged when a device first attaches to a store are now reported on the Device Sync status surface, not only in the dialog shown after pairing. Reconnecting a store that went missing, rejoining a store that was replaced, and a first sync that had to wait for WiFi all report their merges now.
- The sync phrase disclosure no longer says that moving every device to a new phrase is the only fix for a leaked one: it leaves the old store readable by whoever has the leaked phrase, and deleting the store is the only thing that removes that at once.
- The "Skip unused imported dances" setting now says that turning it off uploads the skipped dances again, alongside what it already said about turning it on.
- Device Sync now converges steady-state edits through one guarded pass, queues at most one follow-up, protects newer local edits and records created during a pass from stale inbound snapshots, negotiates only final-manifest blobs after apply, rejects inbound non-shareable custom-field data, skips malformed relation records and dependent cascades when an inbound parent cannot be persisted, settles pending work before shutdown, stops before publication until local attach state exists, reuses unchanged peer manifests and verified blobs across isolated passes, and pauses for confirmation instead of silently recreating a missing collection. Malformed persisted Device Sync configuration no longer prevents the rest of the app from starting.
- Your synced deletions remain safe while cited records stay in use, and conflicting shared names now reconcile without silently losing references.
- Device Sync now fresh-attaches by unioning both sides before applying deterministic dance deduplication, rewiring references and preserving actionable review candidates for same-title dances with different choreography. Those ambiguities can be merged or kept distinct from the Sync decisions screen. Attaching to an empty store publishes through one guarded continuation, while stale manifest conflicts retry fresh attach on the next trigger and create conflicts stop without silently joining an existing store.
- Device Sync now quarantines records with implausible future timestamps, repairs timestamps only from permitted peer evidence, and keeps unsafe quarantined values and their enforced dependents out of publication until an agreed fallback is available.
- Backup restore and shared archive import now invalidate stale sync conclusions and rerun shareable-text normalization over restored data.
- In Settings > Experimental, Device Sync is now a section you can open and close. It starts closed while sync is off and open while it's on.
- Restoring a backup now pauses Device Sync until the restore finishes, preventing an in-flight sync pass from overwriting restored data.
- When you create a Device Sync store you can now type your own sync phrase instead of using the generated one. It still has to be four words separated by hyphens, and if the phrase you pick looks easy to guess the screen warns you without stopping you.
- Inbound Device Sync changes now refresh the open screens that depend on the updated records without requiring navigation or an unrelated edit.

### Fixed

- Device Sync now tells you to update the sending device instead of silently rewriting noncanonical inbound record content under the peer's timestamp.
- Startup no longer re-checks your whole collection on every launch once a single name has been left for later. Renaming a tag, choreographer or custom field to a name another one already holds is enough to trigger it, and the check then repeated forever; it now re-tries just the affected entries and stops once they are resolved.
- Searching by author or by a cited source now finds dances whose choreographer, source or custom-field text was repaired by the one-time text clean-up. The search index was left holding the old text, so those dances could not be found by it.
- Settings, Re-check custom figures now opens normally when a dance's stored figures cannot be read. Previously a single such dance made the screen show its error message, and Try again failed the same way every time. The unreadable dance is left out of the list, and nothing about it is rewritten.
- A dance whose stored figures cannot be read no longer stops the app from opening. The dance still appears in your collection, and its stored transcription is kept exactly as it is rather than being replaced with an empty one.
- A dance whose stored tune list cannot be read no longer stops the app from opening. The dance still appears in your collection, and its stored tune list is kept exactly as it is rather than being replaced with an empty one.
- Renaming a choreographer or a custom field to a name that is already taken now says so, instead of appearing to work and reverting the next time the screen is opened.
- Re-importing an archive no longer fails on a difficulty level whose label differs from another level only in how the accents are stored.
- Saving a setting whose entries differ only in how their accents are stored no longer fails; both entries are kept.
- Creating a custom field whose key another field already uses now tells you so and leaves the existing field alone. It used to fail without a message, so the new field simply never appeared.
- Reconnecting a Device Sync store that is no longer there now follows Sync only on WiFi: on mobile data with that setting on, nothing is sent and the app points you at the setting, with the question still waiting for you. A reconnection that doesn't go through now says so on the question instead of quietly reappearing, and a store that another of your devices has already recreated is joined rather than asked about again and again.
- Connecting a new device to a sync store no longer fails outright when one record from another device cannot be downloaded or is refused. That record is skipped and retried on a later sync, and the rest of the library arrives, so a single missing record or a device on an older app version no longer blocks the new device from syncing. Connecting still stops without saving anything when another device's record list cannot be read at all.
- Device Sync no longer skips a record because one other device sent a copy with an implausible clock. The offending copy is still refused and reported, and the record now arrives from any device that sent a sound one, along with the dances and programs citing it.
- A record held back on this device for an implausible clock no longer stops the dances and programs that cite it from receiving other devices' edits and deletions. Only the held-back record itself sits out, so an edit made on another device now arrives instead of waiting for this device's clock to be corrected.
- The choreographer details kept only on your own device — email, location, and the deceased marker — are no longer deleted when two of your devices rename two different people to the same name and both renames arrive in one sync. Both records are kept as they were, and the clash is recorded for review instead of the two people being merged into one record.
- When another of your devices renames a choreographer, tag, custom field, or difficulty level onto a name a different record on this device already uses, Settings → Sync decisions now offers Merge and Keep both for it. Until now the clash was listed with no action available, and the other device's change was skipped on every sync, so that record quietly stopped syncing with nothing telling you why. Merging two choreographers warns you first, because the email address, location, and deceased marker on the record that is not kept are stored only on this device and cannot be recovered.
- A custom field you marked private no longer causes the same field to be renamed on your other devices. Previously, receiving a shared field whose key matched a private field of your own renamed the shared one everywhere, on account of a field only this device had; now the private field is the one renamed, and it never leaves this device.
- Editing a record that another device has deleted, but that this device still uses, now keeps your edit and cancels the pending deletion. Previously the edit was discarded and the record was deleted once nothing referenced it any more.
- Undoing an import no longer erases a venue that a deleted program still points at, so restoring that program from Recently Deleted brings back its venue too.
- Undoing an import no longer destroys a deleted dance's author, tag, citation or custom field value. The association is kept, and the author, tag, source or field is kept as a deleted record rather than being erased, so restoring both the dance and that record brings the association back. Restoring the dance on its own does not, because a deleted author, tag, source or field stays hidden until it is restored too.
- Undoing an import can no longer silently strip a tag from a dance you still have. Removing a tag as part of an import rollback now stops rather than taking the tag off every dance that carries it.
- Search no longer finds a dance by the value of a custom field you have deleted. Previously, deleting a dance, then deleting a custom field that no remaining dance used, then restoring the dance from Recently deleted left the dance matching the deleted field's value in the search box, even though the dance's own page no longer showed that field. Restoring the field and then editing the dance makes its value searchable again.
- Deleting a Device Sync store no longer reports that nothing was changed when the store was in fact deleted. If the store is removed from the server but this device cannot disconnect from it, the app now says so and tells you how to finish, instead of inviting you to retry a deletion that already succeeded.
- The Device Sync device list no longer says that removing another device stops it syncing. Removing a device frees the place it used in the store, but a device that is still running publishes again the next time it syncs; the confirmation and the user guide now say so.
- The Filters heading now counts Level, Mixed level, Mixer and Minimum rating filters, so a collapsed panel no longer reads as if nothing is filtered — in the Collection and in the dance picker.
- If exporting or sharing a program hits an unexpected internal error, you now see an error message instead of nothing happening.
- The startup warning about a failed database integrity check, and its Dismiss button, now appear in your chosen language instead of always in English.
- Update download errors (no place to download to, incomplete or refused downloads, a failed security check, a failed install) now appear in your chosen language instead of always in English.
- The Device Sync status now tells you when a sync had something to report — records that differ on two devices and could not be resolved, a local creation kept from a peer's deletion, something on this device whose date the app can't trust, records from another device skipped as unusable, a suspect clock, an update deferred by your own edit, or changes that haven't reached your other devices. These notices block nothing and need no dismissal, and they clear by themselves once a sync stops finding the condition — at the latest the next time you open the app.
- Declining to replace a store that no longer exists now says sync is paused, and how to reconsider, instead of continuing to show the date of the last successful sync with the store that has gone.
- Undoing an import no longer leaves behind a choreographer the import created. When the imported dance had already been shared to another device it is kept as a deletion record, and those records no longer count as crediting the choreographer.
- Undoing a shared archive import no longer removes a venue that a retained program still points at.
- Device Sync now protects records before publishing their blobs, so undoing an import during synchronization preserves deletion evidence instead of losing the record permanently.
- Large device sync updates no longer fail when a dance or program has many relationships.
- Sync review decisions now stay safely pending when the affected local record was edited after the review was queued.
- If Device Sync cannot finish applying an incoming dance or program, it now leaves that record exactly as it was instead of keeping half of the incoming version. A half-applied record could otherwise stay different from your other devices indefinitely.
- Connecting Device Sync no longer fails with "Device Sync isn't available right now" on builds that were never given a sync server address.
- An incoming tag, author or custom field whose name is already taken by a different record is now reported instead of being quietly stored under the wrong name or merged into the record you had deleted.
- Device Sync no longer runs a pointless extra sync pass after every pass that applied changes.
- Restoring a backup or a shared archive right after turning Device Sync on no longer risks a sync pass starting while the restore is still writing.
- An unexpected database error while applying one incoming record no longer stops the whole sync pass, and no longer repeats on every later pass.
- Device Sync keeps what it learned from a pass that failed partway, so the warning about records no other device has picked up is no longer reset by an unreliable connection.
- Screens now refresh after a sync pass that only repaired timestamps, or that renamed a shared tag, author, source or level.
- A record you deleted that is still in use somewhere no longer takes edits back from a device that has not learned about the deletion yet.
- A synced program whose linked venue was deleted (or hadn't arrived yet on this device) no longer gets stuck reporting the same sync conflict forever. The program keeps its venue link as received from the other device instead of having it silently cleared.
- Device Sync no longer asks you to resolve a naming conflict it can settle itself. A peer's older deletion of a record you still have no longer raises a review you could only clear by renaming.
- A record you kept because something still uses it now receives edits from your other devices instead of reporting, on every sync, that it changed locally when it did not.
- Device Sync no longer forgets which records it has already merged when no other device is currently attached, so a device returning later no longer re-creates duplicates that were already resolved.
- Merging a saved sync decision about a difficulty level that was already merged away once now resolves onto the surviving level instead of failing and leaving the decision stuck.
- A clock-implausible peer record is now reported as quarantined rather than malformed, so it reads as a clock problem instead of a corrupt record.
- A saved sync decision no longer becomes permanently unresolvable after you edit the record it is about: the decision is re-queued against the current version instead of keeping the one captured when it was first raised.
- When another device brings back a record whose deletion this device was still holding — because something here was using it — the record now stays. It could previously disappear again on its own once the last thing using it was removed.
- The Device Sync status line no longer keeps showing a stale "Last synced" time after a sync attempt fails, finds the store has changed, or finds a previously connected store can no longer be reached; each is now named on the status line, with the last successful time still shown separately when there is one.
- A sync pass that hits an internal error is now recorded as a failed pass instead of surfacing as an unhandled error.
- Turning Device Sync off and back on no longer risks swallowing the next settings-only change instead of syncing it.
- The user guide's Sync decisions section now explains both kinds of conflict Device Sync can ask you to resolve, in plain language, instead of describing only one and naming an internal engineering work unit.
- Synced deletions are no longer applied on the strength of a companion deletion that the same pass then declines to apply, and a renamed difficulty level that was already merged away once is reconciled onto the surviving level instead of being reported as a conflict.
- Device Sync no longer stops applying changes after a peer deletes a dance that used a difficulty level this device had already deleted. The incoming deletion used to fail every pass and roll back the whole batch with it, so no further record could sync.
- Device Sync no longer re-derives the slow, salted sync-identity check on every step of a sync pass. Once a pass has confirmed prior use, later steps reuse that answer instead of repeating several seconds of CPU work per configured identity, including inside a held write lock.
- Saving while Device Sync is applying changes in the background no longer fails with a database error: both connections now use write-ahead logging and wait for each other.

### Removed

- Cut and paste reordering of program slots is gone; drag a slot by its handle, or use its move up and move down buttons, to reorder. Cut and paste for figures in the dance editor is unchanged.

### Data / Migrations

- Collections that already completed the one-time text clean-up rebuild their search index once on first launch, with the usual progress indicator, to repair entries left stale by it.
- Schema 35 -> 36: add the nullable queue-time local wire hash to Device Sync review rows so resolving a review can detect edits made after it was queued; existing review rows retain null hashes.

## [0.4.1] - 2026-09-19

### Added

- You can search Caller's Box and ContraDB online by figure text from Collection; ContraDB uses complete canonical move names.

### Changed

- The About page and GitHub Pages landing page now show the 0.4.0 release codename, “Allemande Left,” alongside the app version.
- You can more easily distinguish the Program defaults and Dance-authoring defaults sections in the Defaults pane.

### Fixed

- When you import or restore an archive with malformed content, the problem is reported as an archive error instead of an uncaught failure.
- Importing shared metadata no longer fails when an incoming tag or custom field matches one you already have but is written in a different Unicode form; the existing entry is reused instead.
- Private copies of files you share into the app are now removed after validation or dismissal.
- Saving a backup on Windows or Linux now writes to a temporary file and swaps it into place, so an interrupted save can no longer destroy your previous backup.
- Restoring a backup now resets settings missing from that backup to their defaults immediately.
- You no longer lose your newest dance or program editor changes when the app closes before autosave finishes.

## [0.4.0] - 2026-09-11

### Added

- You can track elapsed time and pause or resume while performing a single dance, with an opt-out under Program > Performance.
- You can search your Collection and online dance archives by author, including Caller's Box and ContraDB author searches.
- You can add an editable meanwhile container from the dance editor's Add menu and configure the side figures used to seed it in Settings.
- You can author ordered modifier containers, use bounded meanwhile/modifier containers in shorthand mappings, preserve them through backups and exports, and configure the figures seeded by Add modifier in Settings.
- You can now define, rename, reorder, and remove your own ordered dance difficulty levels from Settings > Defaults; existing dance assignments stay attached when a level is renamed, and levels in use cannot be removed.
- You can configure a default starting program template for manually created programs.
- You can now plan walkthrough and dance minutes separately for each program slot, with Perform showing each timing phase.
- You can show per-slot caller notes above dance titles while performing a program; the new Program > Performance setting is on by default.
- Program matrix rows now show numbered sections such as 1st, 2nd, and 3rd when breaks divide an evening into multiple sections.
- You can temporarily hide alternate rows in the program matrix without changing the saved program or its exports.
- Calling history can show the venues where a dance was called repeatedly, with a configurable number of results.
- You can show the phrases where each comparable move starts directly in the program matrix.

### Changed

- Align figure parameter names and pull-by variants across imports, rendering, and editing.
- Imported formations now keep recognized shape and source detail separate, so formation names are not duplicated in dance details.
- You can select, search, color, and export Reverse progression improper formations.
- You can show supported discouraged dance terms as canonical wording in dance details, notes, Perform mode, and exports. This display setting is on by default and never changes saved text.
- Releases now carry a memorable codename that can continue across versions or change with a new release.

### Fixed

- Dismissing the mobile figure picker now leaves an existing stand still figure unchanged and no longer reopens the picker after you enter a new one.
- You can undo marking all dances performed from a program without clearing earlier performed history or later edits.
- CallersBox imports now preserve the crossing dancers and explicit loop direction in Circulate figures.
- You now see “backing up” instead of “who” for the facing star dancer parameter in figure entry, search, defaults, and matrix controls.
- You now get the non-rolling role and relationship assigned correctly when you import a CallersBox roll-away annotation.
- When you import a mad robin from Callers Box, the app no longer invents which pair steps in front when the source does not say.
- You can import ContraDB hey ricochets with their structured timing and dancer-position flags.
- You no longer see tags in the dance or Collection pickers after removing their last live-dance association; newly created tags are saved together with the dance that uses them and survive an autosave restore.
- You can now sort the Program editor and Perform dance pickers by the first meaningful word when "Ignore leading articles when sorting" is enabled, including while a picker is open.
- You can read the complete move-substitution guidance on narrow screens.
- When you preview a dance in the Program editor, only one close control is shown.
- When you make an alternate primary, you now swap it with the nearest preceding primary while keeping the remaining alternates grouped.
- Related-dance links to temporarily deleted dances are hidden until the target is restored, instead of appearing as missing dances.
- ContraDB dances now preserve hall enders as structured figure details when you import them.
- The program editor now labels the note option “Add note / waltz”.

### Data / Migrations

- Upgrade existing v34 figure data and saved snippet signatures to the v35 taxonomy while preserving nested figures and snippet conflicts.
- When you first launch after this update, your legacy assumed mad robin subjects are corrected only when their source figure omitted an explicit subject, and your canonical and search indexes are rebuilt.
- The schema 32 to 33 migration adds a nullable purge-caption marker for program slots; existing rows keep their legacy ambiguity and are preserved losslessly.
- Existing program-slot planned times are retained as dance minutes.
- Schema 32 -> 35: add the purge-caption marker and configurable difficulty vocabulary with sync tombstones, then split program-slot planned minutes into nullable walkthrough and dance minutes while preserving existing planned values as dance minutes.
- Taxonomy 33 -> 35: normalize legacy mad-robin subjects only when the source omitted one, rename persisted parameter keys, consolidate pull-by aliases recursively through nested figures, and rebuild derived figure and search rows.

## [0.3.1] - 2026-09-03

### Added

- **JSON export delivery choices** — choose to save, copy the raw JSON, share
  through the OS, or cancel when exporting a dance or program as JSON.
- **Dialect dance-detail settings** — manage canonical figure text availability,
  dance-detail opening terms, free-text entry, figure shorthands, and walkthrough
  snippets together under Dialect. Canonical figure text is off by default.

- **Dance choreography re-import** — refresh figures, formation, and progression
  from every saved dance detail view, including read-only Program Editor previews,
  without replacing your saved metadata.

### Fixed

- **Program editor dance previews** — closing a wide preview no longer exits the
  editor.

- **CallersBox imports** — recognize 16-beat heys without an explicit duration
  and preserve supported bracketed balance-wave annotations.
- **Dance figures** — correct shared rendering, taxonomy defaults, and
  CallersBox/ContraDB imports reported in issue #1160.
- **Program dance picker** — remove the misleading detail chevron from rows
  whose tap action adds or replaces a dance.

### Data / Migrations

- **Schema 31 → 32** — add local Device Sync state tables for baselines, aliases,
  pending tombstones, review candidates, and publication history; existing user
  data is unchanged by these additive tables.
- **Taxonomy 32 → 33** — correct figure defaults and canonical figure-eight
  wording, rebuilding derived canonical and full-text rows once without changing
  stored figure JSON or the SQLite schema. This taxonomy marker is documentary;
  it does not trigger a database migration.

## [0.3.0] - 2026-09-01

### Changed

- **Privacy policy** — disclose that credited choreographers, authors, callers,
  and bands can be personal data about third parties, while documenting the
  configured sync service and local-only contact fields.

### Fixed

- **Windows Settings navigation** — use an update icon that renders correctly
  for the Updates section.
  
- **Shareable text normalization** — sanitize before NFC composition and
  re-repair existing values that were left decomposed by the previous order.
  
- **Related dance links** — manually saved relationships now stay synchronized
  in both directions, including retargeting and removal.
- **Transitive related-dance groups** — optionally keep a related-dance group
  synchronized across all of its members, with group-wide removal that
  preserves unrelated ordinary links.

### Data / Migrations

- **Schema 29 → 30** — remove redundant normalization collision snapshots;
  existing skip identities are retained automatically and no user content or
  timestamps are changed.
- **Schema 30 → 31** — add an optional transitive marker to related-dance links;
  existing links remain ordinary by default.

## [0.2.0] - 2026-08-31

### Added

- **Program dance previews** — inspect saved or online dance details from the
  program builder without adding or importing them. Hold a result or dance slot
  for a temporary wide-screen preview, or use **View details** for a
  keyboard-accessible read-only preview.

- **Dance statuses** — Draft and Variation are now available in the dance
  editor, status filters, and status presentations.
  
### Changed

- **Privacy policy** — the published policy now discloses optional Device Sync,
  the content its operator can access, venue fields that remain local, the
  freeform-note limitation, and break-glass access-log retention.
  
- **Import review** — review rows now show author, formation, and source
  attribution; pasted title lists with multiple exact matches now offer a
  grouped choice instead of discarding the candidates.
  
- **Dance file exports** — the dance **Export** menu now offers privacy-safe
  `.ccshare` and `.json` files containing the dance and its referenced,
  shareable metadata. Recipients review the import before committing it and can
  undo a successful import.
  
- **Desktop in-app updates** — verified Windows installers now start directly
  after **Download & install**. On macOS, choose whether to update immediately;
  the disk image opens before the app closes so you can replace it in
  **Applications**, or defer with **Update and restart**.

### Fixed

- **Text input sanitization** — Normalize and sanitize shareable text on local 
  writes, including existing collections repaired safely on database open.

- **Meanwhile groups in the dance editor** — beat totals and section labels now
  update immediately when you group figures, before saving the dance.

- **macOS shutdown** — quitting from the Dock, menu, or Command-Q now waits for
  the local database to close before macOS tears down the app.

- **Windows shutdown** — closing the app now completes Flutter's native window
  teardown before the runner releases COM resources, preventing a crash on exit.

### Data / Migrations

- **Schema 28 → 29** — add the `normalisation_skips` table so collisions found
  during shareable-text normalization are recorded safely for later retry
  without losing existing data.

## [0.1.3] - 2026-08-26

### Changed

- **Collection and Programs picker** — filter dances by whether they have been
  called in the active caller and performed-history scope.
  
### Fixed
  
- **macOS app name** — Finder and release bundles now use a branded name instead
  of the internal `compendium_app` build name.
  
- **Caller's Box bracket annotations now preserve stated dancer context.**
  Supported square-bracket dancer sets populate an otherwise unstated figure
  subject; supported context is retained as a dialect-aware note when the
  subject is already explicit or the move has no subject slot. Non-duple and
  unrecognised dancer descriptions remain custom figures rather than being
  silently dropped.

- **Caller's Box imports** — selected fall-back and formation clauses now import
  as existing figures instead of making the whole source line custom.

## [0.1.2] - 2026-08-25

### Changed

- **Collection import** — browse signed Published collections from the Import
  dances source picker, and open custom fields or recently deleted dances in
  the desktop detail pane.

- **Program editor** — keep Event date visible while grouping the remaining
  event metadata under **More details**; mobile import actions now state what
  each source imports.

- **Navigation icons** — align Program, Experimental, and Collection actions
  with their destinations.
  
### Fixed

- **macOS in-app updates** — choosing **Download & install** now opens a Save
  As dialog before downloading the disk image, so macOS records user-approved
  download provenance and can launch the installed notarized app.

- **Dialect move wording templates** — long-wave and promenade branches now
  appear only after choosing those moves, while a single circle template keeps
  the automatic **single file** prefix.

## [0.1.1] - 2026-08-24

### Changed

- **Dialect editor** — organize dialect settings into collapsible sections,
  keep the preview visible, and confirm before discarding edits or resetting
  wording templates and discouraged terms.

### Fixed

- **Figure alias editor previews** — changing a shoulder or hand parameter now
  immediately updates the inverse-pair move name in the editor.
  
- **Compact do-si-do and see-saw names** — canonical figure text now uses
  `dosido` and `seesaw`, while imports and full-text search continue accepting
  the legacy spaced and hyphenated spellings. (issue #1056)
  
- **AirDrop `.ccshare` files** — iOS and macOS now identify shared program
  bundles as Caller's Compendium files instead of generic JSON/text.

- **Parameter-aware dialect move wording** — global wording now has separate,
  complete templates for parameter branches of long waves, promenades, and
  circles, preventing single-file and in/out choreography from being lost.

- **Gate previews** no longer show the internal `unspecified` label when you
  add a gate without filling in its subject. (issue #1038)

- **Dialect wording templates** — the dialect editor now blocks malformed or
  oversized move wording templates instead of saving settings the renderer will
  ignore. (issue #1043)

- **Imported walkthroughs** — preserve dance walkthrough text when committing
  published collections and generic archive/JSON imports. (issue #1040)

- **Program auto-commit** — edits made while an auto-commit clears its recovery
  draft are no longer overwritten by the older committed snapshot.
- **Programming Matrix PDF privacy** — linked venue postal addresses are now
  removed from the exported matrix header while the public venue name remains.

- **User-guide navigation** — Settings and import instructions now match the
  current section layout, and the guide now covers signed published collections.

- **Database reset recovery** — resetting an unsupported database now reloads
  the app in-process with a fresh runtime instead of leaving the recovery dialog
  visible until the application is reopened.

- **Complete backups** — backups now preserve custom fields and their values even
  when **Include in sharing** is turned off; that setting still keeps them out of
  files you share with other people.

- **macOS shutdown stability** — the database now closes before the native
  window is destroyed, preventing an intermittent crash during application exit.

### Added

- **iOS browser sharing** — share supported Caller's Box and ContraDB dance
  links, or ContraDB program links, to queue them for review in Caller's
  Compendium. The share extension confirms the queueing result in the app's
  selected language; open the app to review and import the link.

- **Experimental settings** — a new section provides a home for features that
  are still in development.

- **Program picker online search** — search The Caller's Box or ContraDB from
  the program builder, then import and add a result directly. Non-break note
  slots can also be replaced with a selected dance from their edit dialog.

### Data / Migrations

- **Taxonomy 31 -> 32** — canonical figure names for do-si-do and see-saw are
  now `dosido` and `seesaw`; legacy spellings remain accepted and normalized at
  the full-text query boundary. Existing stored figure JSON and SQLite schema
  are unchanged; derived FTS rows rebuild once.

## [0.1.0] - 2026-08-21

Flutter build: `0.1.0+1`.

This section covers the `0.1.0` line. **`v0.1.0-beta.9`** (this pre-release) builds
on **`v0.1.0-beta.8`** and covers the latest improvements since that release.
The changes since beta.8 are grouped first; the standing feature overview and
install notes follow.

### Added

- **Signed published collections** — discover and import immutable dance
  collections from the trusted Compendium Analect catalog after detached
  signature and archive digest verification, with collection-level consent and
  provenance tracking. (issue #862)

- **Re-import choreography from a dance detail** — choose Caller's Box,
  ContraDB, or a single-dance Caller's Compendium JSON file, review the parsed
  dance, then update only its figures, formation, and progression. Your notes,
  ratings, tags, links, authors, citations, and other collection metadata stay
  intact. (issue #990)

- **Directed promenades** now import their stated rotation sense into the
  existing `promenade.turn` parameter. TCB `clockwise`/`counterclockwise`
  qualifiers no longer force the whole line to custom, and ContraDB's
  `on the left`/`on the right` wording is promoted from a note to
  `clockwise`/`counterclockwise` respectively. Unrelated source tails remain
  notes. (issue #771)

- **Parameterized program-matrix columns** — define taxonomy-move columns with
  optional exact parameter constraints, with most-specific matching and unified
  reorder, rename, hide, and delete controls. Matching figures replace their
  ordinary built-in column, and unmatched parameterized columns stay out of the
  matrix. (issue #935)

- **Compound program-matrix columns** — define named, per-dance columns for
  strictly-adjacent sequences of at least two exact taxonomy moves. Matching is
  additive, so figures retain their built-in or parameterized memberships;
  compounds appear only when their contiguous sequence is present and never
  participate in adjacent-dance collision warnings. (issue #935)

- **Edit the program-matrix columns** — a new **Settings → Program → Matrix
  columns** editor lets you reorder, rename, and remove the matrix's built-in
  columns app-wide. Changes apply live on screen and in the PDF export. Removed
  columns stay listed so you can restore them, and two reset controls bring back
  removed columns (keeping your renames) or restore the shipped defaults behind
  a confirm. (issue #935)

- **Configurable program-matrix columns (foundation)** — the program matrix can
  now honour an app-wide column configuration: built-in columns can be hidden,
  reordered, and renamed, applied live wherever the matrix is shown (on-screen
  and in the PDF export). The configuration is stored as a preference that
  travels in local backups and is validated on restore, so a malformed blob is
  dropped rather than applied. No editor UI is exposed yet — this PR lands the
  model, persistence, and wiring only. (issue #935)

- **`promenade.destination`** — single-file promenade figures can now carry a
  structured destination param (e.g. "to next neighbors", "to neighbors"). The
  ContraDB importer recognises `to new neighbors`, `to the same neighbors`, and
  `to {dancer-set}` tails; these are stored as `destination` instead of the
  figure note. The param uses the existing dancer-set vocabulary
  (`nextNeighbors`, `neighbors`, `partners`, …) and defaults to `unspecified`
  (= "not stated"), so existing figures are unaffected. Destinations appear in
  display, search, and filter. (taxonomy v29, issue #921)

- **`promenade.turn`** — promenades can now record a rotation sense
  (`clockwise`/`counterclockwise`), the slot the ContraDB/TCB parser
  extensions in issue #771 are blocked on. Editable in the dance editor;
  hidden and automatically reset to "not stated" whenever `dir` is
  `in`/`out`/`up`/`down`, where a rotation sense doesn't apply. (taxonomy v30,
  issue #989)

### Changed

- **Numeric custom fields** — reject `NaN`, infinity, and overflowed numeric
  input instead of allowing values that cannot be encoded in JSON.

- **Dialect move wording templates** — optionally customize the display sentence
  for each taxonomy move in Settings → Dialect. Templates support computed move
  slots, warn about omitted slots, and require confirmation before saving
  incomplete templates. They are bounded and sanitized on import; canonical
  text, search, and deduplication remain unchanged.

- **Dance editor figure wording** — add an optional per-dance wording override
  for structured figures. The override is previewed with the active dialect and
  affects display only; canonical search and deduplication remain unchanged.

- **Collection search** — search can now be scoped to **All fields**, **Title**,
  or **Figure**. Short prefixes and longer literal substrings, including
  punctuation-spanning title text, use derived local indexes; online search
  remains title-only.

- **Program editor auto-save** — enable **Settings → Program → Auto-save program
  changes** to commit valid edits as you work and avoid the discard warning when
  leaving the editor. It is off by default, so explicit Save remains unchanged
  until you opt in.

- **Windows release artifacts are now signed via Azure Trusted Signing** when the
  release workflow's repository variables are configured: the portable bundle
  binaries and generated installer are signed through the WUS2 endpoint.
  Releases retain an unsigned fallback when that configuration is absent.

- **Settings → Program** — a new **Program** settings section now holds the
  program-facing preferences that previously lived under **General**: the reusable
  **Venues** toggle and venue manager, the programming-matrix **Flag exact beat
  overlap only** toggle, the **Auto-size Perform cards** toggle, and the two
  **Calling history** toggles. Nothing about what these settings do changed —
  only where they live. (issue #935)

- **Single-file circle wording** now matches the rest of the app: `turn` is
  shown as `left`/`right` (was previously shown as
  `clockwise`/`counterclockwise`) in both the dance view and search text.
  (taxonomy v30, issue #989)

- **`promenade.destination` now appears on any promenade whose direction is
  stated as something other than the default** (previously it only appeared
  on single-file promenades). A single-file promenade with an unstated (i.e.
  default `across`) direction that already had a destination set will no
  longer show that destination in the rendered text — the stored value is
  kept, not deleted, in case direction support is added for it later.
  (taxonomy v30, issue #989)

- One-time startup migration: existing promenade and single-file-circle
  figures are re-indexed for search once, to pick up the wording and
  rendering changes above. This is automatic and does not require any user
  action. (taxonomy v30, issue #989)

### Fixed

- Import dedupe now treats canonically equivalent NFC/NFD title and author
  spellings as the same comparison key, preventing duplicate dances and
  choreographer rows. (issue #1021)

- Archive re-imports no longer link programs to soft-deleted venues; an exact
  provenance match restores the venue before the program is persisted. (issue
  #1016)

### Data / Migrations

- **Schema 25 → 28** — schema v26 adds venue provenance for reliable shared-bundle
  deduplication, v27 records published-collection import history, and v28 adds
  scoped Collection prefix and substring indexes. Existing derived indexes are
  rebuilt automatically; existing user data is preserved.

- **Taxonomy 28 → 31** — versions v29–v31 add structured promenade destinations
  and rotation senses, revise promenade and single-file-circle wording, and add
  standalone turn figures. This is a documentary marker: it is not read at
  runtime and does not itself rewrite the database.

### Compacting beta.N changelogs

Previous releases under the 0.1.0-beta.N tagging scheme made in-place edits to
this changelog. The changelogs for each checkpoint can be found in the published
changelog for each previous beta tag:
- [v0.1.0-beta.8 (2026-08-14::7f5ca12)](https://github.com/ibanner56/CallersCompendium/blob/7f5ca1214766757eabc2f2f2d2c9cb9698af3215/app/CHANGELOG.md)
- [v0.1.0-beta.7 (2026-08-12::0e2d664)](https://github.com/ibanner56/CallersCompendium/blob/0e2d664c7dbd2ffcdcfff8c8587b35ccd68f7d63/app/CHANGELOG.md)
- [v0.1.0-beta.6 (2026-08-01::3d6a476)](https://github.com/ibanner56/CallersCompendium/blob/3d6a476bbf5f82511980ed017fe2ac6e3cc5278d/app/CHANGELOG.md)
- [v0.1.0-beta.5 (2026-07-29::8e3ca47)](https://github.com/ibanner56/CallersCompendium/blob/8e3ca4758aef24975f5ad11bd2b7150b95eabcc6/app/CHANGELOG.md)
- [v0.1.0-beta.4 (2026-07-22::208c54b)](https://github.com/ibanner56/CallersCompendium/blob/208c54b76791a8f4bd2f83d54c57dfa5928cd248/app/CHANGELOG.md)
- [v0.1.0-beta.3 (2026-07-20::a23dd01)](https://github.com/ibanner56/CallersCompendium/blob/ee25bdf359884d1278f018cc896fec6e781bcc1c/app/CHANGELOG.md)
- [v0.1.0-beta.2 (2026-07-19::dcda0c9)](https://github.com/ibanner56/CallersCompendium/blob/dcda0c935d8d7a097ba31e2f6b9c6155bae684ee/app/CHANGELOG.md)
- [v0.1.0-beta.1 (2026-07-17::276e14a)](https://github.com/ibanner56/CallersCompendium/blob/d2871a031e6998f685dfb65cf862aacacfc6082e/app/CHANGELOG.md)
- [000 CHANGELOG (2026-07-15::fe4376b)](https://github.com/ibanner56/CallersCompendium/blob/fe4376b7fb57ff926ac490cf74def6b178aeb89f/app/CHANGELOG.md)
