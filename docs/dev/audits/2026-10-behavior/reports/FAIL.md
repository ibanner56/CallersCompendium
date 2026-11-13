# FAIL — When things go wrong: failure handling as a product behaviour

Auditor key: `FAIL`. Read-only audit; no builds, no tests run. All paths are relative to
`/home/user/CallersCompendium`.

## Scope & method

User story: *"I'm in a church basement with no Wi-Fi, my laptop is nearly out of disk, I'm on
an old version, and the app was force-quit last week mid-save. I need it to start, tell me
plainly what's wrong, never pretend something succeeded, and give me a way forward."*

Docs read: `docs/user/faq.md`, `settings.md` (Updates, Diagnostics), `backup-portability.md`
(export, reminders), `imports.md` (title-list import), `programs.md` (title list, ContraDB
program import), `authoring.md` (drafts), `docs/adr/002-distribution-and-update-channels.md` §5,
`docs/dev/releasing.md` (key rotation).

Code traced, by failure class:

- **No network / timeouts / HTTP errors:** `data/import_io.dart` (`_sendGuarded`,
  `fetchImportUrl`, `UrlFetchFailureReason`), `online_title_lookup.dart`,
  `program_import_online_resolver.dart`, `contradb_program_import.dart`,
  `title_list_import.dart`, `screens/plaintext_program_import_screen.dart`,
  `screens/contradb_program_import_screen.dart`, `screens/dance_list_screen.dart` (online
  search and preview), `published_collections/*` and `screens/published_collection_catalog_screen.dart`,
  `update/update_service.dart`, `update_controller.dart`, `artifact_downloader.dart`,
  `update_failure_labels.dart`, `widgets/sync_now_action.dart`,
  `screens/settings/sync_failure_labels.dart` and `sync_support_codes.dart`.
- **Disk full / permission denied / file locked / picker cancelled:** `data/backup_io.dart`,
  `backup_service.dart` (`exportBackupNow`), `screens/settings/general_section.dart`
  (export, restore and its picker), `sync_pairing_screen.dart` (backup offer),
  `import_review_screen.dart` (`_chooseFile`), `widgets/export_guard.dart`,
  `export/share_file.dart`.
- **Startup, bootstrap, killed mid-operation, second instance:** `main.dart`
  (`main`, `_startupSequence`, `_closeForShutdown`, `_backUpAndReset`),
  `widgets/app_bootstrap.dart`, `data/migration_guard.dart`, `migration_error_labels.dart`,
  `single_instance_guard.dart`, `window_service.dart`, `application_shutdown_controller.dart`,
  `editor_draft_shutdown_scope.dart`, `screens/dance_editor/dance_editor_controller.dart`
  (autosave).
- **Crash and diagnostics:** `diagnostics/crash_reporter.dart`, `crash_fallback.dart`,
  `error_log.dart`, `crash_log_store.dart`,
  `packages/compendium_core/lib/src/diagnostics/crash_log_record.dart`,
  `screens/settings/diagnostics_section.dart`.
- **Undo after a failure:** `utils/undo_snack_bar.dart` and every `onUndo: () async` site.

I traced each feature along a failure-class × feature matrix (summary at the end of
Cross-cutting patterns). "Traced" means I followed the call path in code. "Inferred" means I
did not confirm runtime platform behaviour, and each such finding says what I did not verify.

---

## Findings

### FAIL-1 (High) — On a phone, the backup reports "Backup exported." and resets the reminder even when the share sheet was dismissed

**Scenario.** A caller on Android or iOS sees the overdue-backup bar and taps **Export backup**.
The share sheet opens. They are interrupted, or they don't see a sensible destination, and
swipe the sheet away.

**What happens.** `saveBackupToFile` writes the JSON to a temp file, calls
`SharePlus.instance.share(...)`, ignores its `ShareResult`, and returns `true` unconditionally
(`app/lib/src/data/backup_io.dart:247-262`; the doc comment at :228-232 says it returns true
"once the sheet has been invoked"). `exportBackupNow` treats `true` as delivered and stamps
`last_backup_at` (`app/lib/src/data/backup_service.dart:818-829`). Settings then shows
**Backup exported.** and "Last backup: today" (`screens/settings/general_section.dart:222-230`).
The overdue reminder (`backup_reminder.dart:84-90`) stops firing until the next interval.

The same saver is used by the "back up first?" step of Device Sync pairing
(`screens/settings/sync_pairing_screen.dart:110-119`). That step also sets
`_backupOffered = true` whether the export was delivered, cancelled or failed (:143-147),
so pairing continues as if a safety copy existed.

**Expected.** "Exported" only when a destination accepted the file. A dismissed sheet should
leave both the reminder and the last-backup date unchanged. `backup-portability.md:43-45`
promises the confirmation appears "when it's done".

**Why it matters.** This is the one failure a local-first app must not hide. The caller now
believes they have a safety copy they do not have, and the app stops reminding them.

**Confidence.** Traced for the code path. Inferred for platform behaviour: `share_plus ^13.3.1`
(`app/pubspec.yaml:51`) returns `ShareResultStatus.success/dismissed/unavailable`, and I did
not confirm on device how reliable that status is on each OS. Even if it is only reliable on
some platforms, the code ignores it everywhere.

**Decision.** If the share status is too unreliable to trust, the options are:

- (a) Trust `success` and treat `dismissed` as "not delivered".
- (b) Don't stamp the date on mobile, and ask "Did you save it somewhere?".
- (c) Word the snackbar as "Backup handed to the share sheet" and don't reset the reminder.

---

### FAIL-2 (High) — "Resolve unmatched online" for a program title list reports being offline as "No confident online matches found"

**Scenario.** In the church basement, a caller pastes a 15-line set list into **From title
list**, sees 9 unmatched lines, and taps **Resolve unmatched online**.

**What happens.**

- `_attemptSource` folds every lookup miss into `_SourceMiss`, including
  `OnlineTitleLookupFailure.unreachable` (offline, DNS failure, timeout, 5xx)
  (`app/lib/src/data/program_import_online_resolver.dart:211-217`). Its import step also
  swallows every `Exception` into `_SourceMiss` (:299-302).
  `lookupUniqueExactTitle` has already turned the network exception into a miss
  (`online_title_lookup.dart:162-169`).
- So `resolveUnmatchedOnline` never throws for a network problem. The screen's error snackbar
  (`importPlaintextSearchError`, `screens/plaintext_program_import_screen.dart:189-210`) is
  effectively unreachable.
- The caller sees **"No confident online matches found — 9 titles kept as notes."**
  (`app_en.arb:8111`, shown at :250-256). That is a factual claim about the archives that was
  never tested.

There are three more problems on this path:

- **It never stops early.** Every title is tried against Caller's Box and then ContraDB, one
  after another (:52-64, :101-109). `isConnectionFailure` exists precisely so that "a batch
  caller may stop asking" (`online_title_lookup.dart:48-52`), but this caller ignores it. On a
  slow link that is up to 2 × 30 s per title (`importFetchTimeout`, `import_io.dart:396`),
  with no progress and no Cancel (`_resolving` only disables the button, :490-499).
- **Leaving doesn't stop it.** The screen has no `PopScope`. Backing out mid-resolve doesn't
  stop the loop, which keeps importing dances into the collection with no program and no
  message (`if (!mounted) return` comes only after the whole await, :186-214).
- **The ContraDB program import has the same shape.** `resolveContraDbProgram` swallows each
  activity's fetch or import failure into a note (`contradb_program_import.dart:166-170`)
  during **Import**. A connection that drops between **Fetch program** and **Import** yields
  "Imported "X" — 12 slots (0 linked, 12 notes)" (`app_en.arb:7896`;
  `contradb_program_import_screen.dart:366-463`).

**Sibling inconsistency.** The Collection title-list import does this correctly. It maps
`unreachable` to `connectionFailed`, stops after the first connection failure, shows
"Stopped looking up titles after a connection failure…", and offers progress and Cancel
(`title_list_import.dart:600-651`, `app_en.arb:8374-8378`, `imports.md:197-218`). Two
features doing the same thing give opposite answers offline.

**Confidence.** Traced.

---

### FAIL-3 (High, Decision) — A manual "Check for updates" says "No update found" when it could not check, and permanently so for stranded old installs

**Scenario.** A caller on an old version taps **Settings › Updates › Check for updates**,
offline or online.

**What happens.**

- `checkManifest` returns `null` for every failure: offline, 404, timeout, a missing or
  invalid signature, an unsupported `manifestSchemaVersion`, or a parse error
  (`app/lib/src/update/update_service.dart:115-153`).
- `checkNow` maps `null` to `UpdateCheckStatus.noUpdate` (`update_controller.dart:827-833`;
  the enum doc at :48-51 says this is "indistinguishable from up to date by design").
- Settings renders **"No update found. You're on version {v}."**
  (`screens/settings/updates_section.dart:243-244`, `app_en.arb:2233`).

**The old-version case.** `docs/dev/releasing.md:866-869` and :880-882 acknowledge that
installs which predate a key rotation "will stop seeing updates… (fail closed, silently 'no
update')". A future `manifestSchemaVersion` bump (`update_manifest.dart:14-17`, hard-refused
at :290) strands them the same way. The installs most in need of an update are told,
indefinitely, that there isn't one. The end-of-life banner can't rescue them either: it
parses the same manifest.

**Why it reads as a defect.** ADR-002 §5 (`docs/adr/002-…md:261-262`) requires that the check
"fails silently offline — a missing network is a no-op, never an error dialog". That fits the
*automatic* check. A *user-initiated* check that ends in an inline status line is not an error
dialog, and Device Sync already shows the calm alternative: **"No connection right now…"**
(`app_en.arb:1791`, `sync_now_action.dart:150`). `settings.md:460-462` documents the current
behaviour, so this is a product decision, not a doc bug.

**Options.**

- (a) For a manual check only, add a `couldNotCheck` status: "Couldn't check for updates right
  now — you're on version X." It sends nothing extra, so privacy is unchanged.
- (b) Keep the current behaviour and add "(or the update service couldn't be reached)" to the
  sentence.
- (c) Treat an authenticated-but-unsupported schema as "A newer version is available — get it
  from the Releases page".

**Confidence.** Traced.

---

### FAIL-4 (Medium) — Import › Choose file: an unreadable or non-UTF-8 file makes the button do nothing

**Scenario.** A caller chooses **Settings › General › Import…**, then **Choose file**, and
picks:

- a `.json` saved in Windows-1252 by another tool,
- a file OneDrive or antivirus holds locked, or
- a file on a disconnected network drive.

**What happens.** `pickImportFile` decodes with strict `utf8.decode`
(`app/lib/src/data/import_io.dart:182-188`, :208-212). That throws `FormatException`, or
`FileSystemException`/`PathAccessException` for a locked or unreachable file.
`ImportReviewScreen._chooseFile` catches only `ImportFileTooLargeException`
(`screens/import_review_screen.dart:632-659`). Everything else escapes the async `onPressed`
to the zone handler and lands in the crash log. The spinner stops (`finally`), and nothing
on screen changes. `_chooseUsrFile` (:665-693) is the same.

**Sibling inconsistency.**

- The backup-restore picker in the same Settings page catches `BackupFileTooLargeException`,
  `FormatException` ("not a valid backup") and `Object` ("Couldn't open that file")
  (`screens/settings/general_section.dart:989-1019`).
- `guardExport` exists precisely because "a tap that visibly did nothing" was fixed for
  exports in #1395 (`widgets/export_guard.dart:12-16`).

The same picker also backs the Collection import, app-shell re-import and program
re-import entry points (`collection_shell.dart:249`, `app_shell.dart:101`,
`program_editor_screen.dart:665`). I did not trace each caller's own catch.

**Confidence.** Traced for `import_review_screen`. Inferred for the other entry points.

---

### FAIL-5 (Medium) — Update download: a full disk, an HTTP 404/5xx or a file collision all say "Check your connection"

**Scenario.** On a laptop that is nearly out of disk, the caller chooses **Download & install
update**. The write fails part-way.

**What happens.** `downloadArtifact` returns `DownloadOutcome.networkError(...)` for every one
of these:

- a non-2xx HTTP status (`app/lib/src/update/artifact_downloader.dart:232-233`)
- something already at the destination (:259-262)
- failing to create the file (:280-284)
- a write or flush failure, which is where a full disk lands (:380-389, :508-509)

`_downloadFailureFor` maps `networkError` to `UpdateDownloadFailure.unreachable`
(`update_controller.dart:611-622`). The banner and Settings then say **"The update could not be
downloaded. Check your connection and try again…"** (`app_en.arb:10820`). The advice is wrong
for the disk-full case: retrying refills the disk and fails the same way.

The controller also never logs the outcome's `message` (`update_controller.dart:406-411` calls
only `_failDownload`). A failed download leaves nothing in Settings › Diagnostics.

**Note.** A disk-full classifier already exists for migration snapshots
(`classifySnapshotFailure`, `data/migration_guard.dart:328-353`) but is not reused here.

**Confidence.** Traced.

---

### FAIL-6 (Medium) — Undo fails silently, and the Undo after a program import doesn't undo the dances it imported

**Scenario A — Undo fails.** On a nearly full disk, a caller deletes a program and taps
**Undo**.

- `showUndoSnackBar` takes `onUndo` as a `VoidCallback` (`app/lib/src/utils/undo_snack_bar.dart:45, 62`).
- Every site passes an `async` closure: `programs_list_screen.dart:447`,
  `program_summary_screen.dart:561`, `program_editor_screen.dart:2818`,
  `dance_list_screen.dart:2266`, `dance_detail_screen.dart:579`,
  `add_to_program_sheet.dart:233`, `import_review_screen.dart:2096`, and both program-import
  screens.
- A failed `restore` / `hardDelete` / `update` becomes an uncaught async error. It goes to
  the zone log only. The snackbar has already closed, and nothing says the undo didn't happen.
- There is no "undo failed" string anywhere in `app_en.arb`.

**Scenario B — program import Undo.** A caller runs **From ContraDB** or **Resolve unmatched
online**, which auto-imports dances from the network, then taps **Undo**. Undo only
hard-deletes the program (`plaintext_program_import_screen.dart:368-370`,
`contradb_program_import_screen.dart:466-468`). Every dance imported during resolve stays in
the collection. `programs.md:118` promises "the same **Undo** safety net as every other
import", but the dance import's undo removes the dances it added (`imports.md:470-472`).

**Confidence.** Traced for both.

**Decision (B).** Either make Undo remove the auto-imported dances (they are known: lines
carrying `importedOnline` / `isLinked`), or change the docs and the snackbar to say "the
program was removed; N imported dances were kept".

---

### FAIL-7 (Medium) — A failed startup clean-up of old deleted items stops the whole app from opening

**Scenario.** On a laptop that is nearly out of disk, the caller has a dance deleted more than
30 days ago, and opens the app.

**What happens.** `_startupSequence` handles each step differently:

- The seed failure is non-fatal (`main.dart:1533-1546`).
- A failed retention-setting read is non-fatal and carefully reasoned (:1555-1566).
- The deferred integrity probe is advisory (:1601-1609).
- `dances.purgeDeleted` / `programs.purgeDeleted` are awaited **unguarded** (:1567-1581).
  Each runs a write transaction (`dance_repository.dart:1938`, `program_repository.dart:1434`).

If the purge throws (`SQLITE_FULL`, or `SQLITE_BUSY` from a sync tool holding the file), the
whole bootstrap fails. The caller gets the generic **"Could not prepare the collection."**
screen and can't open a library that is readable. Retry fails the same way until they free
space.

**Expected.** Housekeeping should never block opening. Log the failure and skip, as the seed
step does.

**Confidence.** Traced for the unguarded call. Inferred that a full disk makes this
transaction fail: I did not reproduce it, but SQLite needs journal or WAL space for any write.

---

### FAIL-8 (Medium, Decision) — Editor autosave failures are invisible and unlogged

**Scenario.** On a full disk, a caller edits a dance for twenty minutes, then the laptop dies.

**What happens.** `_writeDraft` swallows every draft-write failure: "diagnostics: silent —
must never stall editing" (`app/lib/src/screens/dance_editor/dance_editor_controller.dart:970-985`).
It doesn't even call `logCaughtError`. Only the shutdown flush rethrows (`surfaceErrors`),
and `flushAll` then logs only the error's type (`data/editor_draft_shutdown_scope.dart:51-60`).
`authoring.md:526-529` promises "Your work is kept while you type… If the app closes before
you save… the app offers you the draft back". On a full disk nothing was kept, and neither the
caller nor the log knows.

Not blocking editing is right. Saying nothing at all is not. The program editor uses the same
pattern (`program_editor_screen.dart:1101`); I did not read its catch.

**Confidence.** Traced for the dance editor. Inferred for the program editor.

**Options.**

- (a) A quiet "Draft not saved" marker in the editor bar after N consecutive failures.
- (b) Log the first failure per session to Diagnostics.
- (c) Both.

---

### FAIL-9 (Medium) — Published collections: every failure reads "temporarily unavailable", there's no Retry, and nothing is logged

**Scenario.** A caller opens the published-collections catalog offline. Or a newer catalog
format has shipped and they are on an old version.

**What happens.**

- `PublishedCollectionFetchFailure` has nine typed causes: `unavailable`, `redirectRefused`,
  `responseTooLarge`, `malformed`, `unsupported`, `missingSignature`, `invalidSignature`,
  `digestMismatch`, `byteCountMismatch`
  (`app/lib/src/published_collections/published_collection_service.dart:26-36`).
- A manifest whose major or minor schema is newer than the reader becomes `malformed`
  (:70-85; `published_collection_manifest.dart:137-147`).
- The screen collapses all of them into **"Published collections are temporarily
  unavailable."** for both the catalog (`screens/published_collection_catalog_screen.dart:141-148`)
  and an archive (:242-247; `app_en.arb:12339`).
- So an old app facing a newer catalog is told "temporarily" forever. Per-entry "needs a
  newer app version" exists (:235-241), but the whole-catalog case doesn't use it.
- The catalog future is `late final` (:89-90), so there is no Retry short of leaving and
  re-entering the screen.
- Neither failure is logged: `// diagnostics: silent` at :112, and the catalog
  `FutureBuilder` logs nothing.

Compare the import screens, which map ~40 typed reasons to specific, source-named messages
(`data/import_error_labels.dart`).

**Confidence.** Traced.

---

### FAIL-10 (Medium) — Diagnostics can't capture what the maintainer needs, and aren't reachable when startup fails

**Scenario.** A non-technical caller hits one of the failures above and follows
`settings.md:551-553`: "A scrubbed log attached to a GitHub issue is the most useful thing you
can send."

**Problem 1 — many failures never reach the log.** `settings.md:512-514` promises the log
captures "errors you see reported on screen (like a failed import)". Not logged at all:

- update-download outcomes (FAIL-5)
- published-collection failures (FAIL-9)
- the program resolver's per-title failures (`program_import_online_resolver.dart:299-301`)
- autosave failures (FAIL-8)
- update-check failures (by design)

**Problem 2 — the scrubbed export withholds even safe, typed messages.**
`CrashLogRecord.scrubbed` replaces *every* non-empty message with
`[message withheld from scrubbed export]`
(`packages/compendium_core/lib/src/diagnostics/crash_log_record.dart:134-148`). That includes
`UrlFetchException(callersBoxTimeout, timeoutSeconds: 30)`, which is path-free and prose-free
by construction (`import_io.dart:387-392`). The recommended export therefore can't tell a
timeout from a 404 from a blocked redirect. Only the Device Sync section keeps its causes,
through its own support codes (`screens/settings/sync_support_codes.dart`).

**Problem 3 — startup failure.** When startup fails, Settings › Diagnostics is unreachable. The
bootstrap screen offers Copy details (type plus stack) and a hint that the log is "in the app's
support folder" (`app_en.arb:109`). `faq.md:165-168` gives that path for Linux only. A Windows
or macOS caller (sandbox container) has no way to find `crash.log`.

**Confidence.** Traced.

**Decision.** Options:

- (a) Allow-list typed exception messages (`UrlFetchException`, `SyncFailure`,
  `UpdateDownloadFailure`, `PublishedCollectionFetchException`) to survive scrubbing.
- (b) Add an "Export diagnostics" button to the bootstrap error screen. It needs no database,
  only the crash log, so the export would have to be the full one or one scrubbed by paths
  only.
- (c) List the support folder path for every OS in the FAQ.

---

### FAIL-11 (Medium) — The four terminal startup screens give no way forward, unlike the generic one

**Scenario.** A caller on an old build opens a library a newer build (or a restored device)
already upgraded. Or their disk is full when a migration is due.

**What happens.** The generic `_BootstrapErrorScreen` has Retry, Copy details and a log hint
(`app/lib/src/widgets/app_bootstrap.dart:332-420`). The other four screens are bare:

- **Downgrade** (:80-98): a sentence, "please update the app" (`app_en.arb:113`). No version
  numbers, no link to Releases, no way to check for updates, no Copy details.
- **Snapshot-aborted** (:112-131) and **Relocation-blocked** (:137-172): told to "reopen the
  app" (`app_en.arb:125, 168`). There's no Retry, though the preflight re-runs fine on Retry
  (`_startBootstrap`, `main.dart:1088-1099`). On iOS and Android, "reopen" means force-quitting
  from the app switcher, which many callers don't know how to do.
- None of the four offers Copy details or the diagnostics-log hint, though they are exactly
  the cases a maintainer would want reported.

(This is distinct from the already-covered "exception class name" issue, which is about what
the generic screen shows.)

**Confidence.** Traced.

**Decision.** The ADR keeps these screens terminal and without Retry to stop a pointless retry
loop. A "Check again" button is a different thing: for snapshot-aborted it re-runs the
preflight after the caller frees space, and for downgrade a Releases link costs nothing.

---

### FAIL-12 (Medium) — Closing the window waits, with no feedback or timeout, for any sync pass in progress

**Scenario.** On flaky church Wi-Fi, a sync pass is running. The caller clicks the window's
close button.

**What happens.**

- `WindowService.onWindowClose` → `WindowCloseCoordinator.handle` → `closeApp`
  (`app/lib/src/data/window_service.dart:44-66`, :321-324) → `_closeForShutdown`
  (`main.dart:1033-1046`).
- `_closeForShutdown` awaits the in-flight writer, then `coordinator.dispose()`, which
  awaits the in-flight pass (`sync/sync_coordinator.dart:1650-1675`). Only *then* does it
  flush editor drafts and close the database.
- `setPreventClose(true)` keeps the window open. Further clicks share the same future and do
  nothing. Each sync request is bounded at 30 s (`sync_http_client.dart:63`), but a pass makes
  several requests, and nothing tells the caller the app is closing.
- A caller who gives up and kills the process from Task Manager or Force Quit loses the final
  draft flush. That flush is ordered last, though autosave limits the loss to about the last
  500 ms of typing.

**Confidence.** Traced for the order and the missing timeout. Inferred for how long a pass can
take on a bad link: I didn't measure it, and the engine itself was out of scope.

---

### FAIL-13 (Low) — Tapping an online result shows a 30-second loader that can't be cancelled

`_pushOnlinePreview` shows a `barrierDismissible: false` spinner while the dance is fetched
(`app/lib/src/screens/dance_list_screen.dart:1057-1065`). The fetch is bounded only by
`importFetchTimeout` (30 s). On a captive-portal or "one bar" connection, the caller is stuck
on a modal spinner with no Cancel and no Back. Errors that follow are well worded (:1069-1092).
**Traced.**

### FAIL-14 (Low) — The crash fallback says "recovered" but offers no way out, and its Copy details differs from the bootstrap screen's

- `crashFallbackBody` says "This part of the app hit an unexpected error and **recovered**"
  (`app_en.arb:4234`). The widget only replaces the failed subtree and offers just Copy details
  (`app/lib/src/diagnostics/crash_fallback.dart`). There is no Back, Reload or Go home. If it
  replaces a whole route body, nothing has recovered.
- The two "Copy details" buttons copy different things. CrashFallback scrubs the stack through
  `CrashRedactor` (`_detailsText`). The bootstrap screen copies the raw stack
  (`app_bootstrap.dart:359-361`), which is why the FAQ has to warn about file paths.

**Traced.**

### FAIL-15 (Low) — A failed Clear log in Diagnostics says nothing

`_clear` has `try/finally` and no `catch` (`app/lib/src/screens/settings/diagnostics_section.dart:222-230`).
A delete failure, such as a file another program holds on Windows, escapes to the zone log.
No snackbar appears, and the list reloads still showing the entries. Compare `_export` just
above, which catches and shows `diagnosticsExportFailed`. **Traced.**

### FAIL-16 (Low) — On macOS, replacing a backup on a full disk can destroy the old one

On macOS, `writeDesktopBackup` writes in place (`app/lib/src/data/backup_io.dart:287-310`)
because the sandbox forbids a sibling temp file. That is documented in code, but not for users.
A caller who saves over last week's backup on a full disk gets "Couldn't export a backup." and
a truncated old file. `backup-portability.md` doesn't mention it. **Traced** for the code.
**Inferred** that a full disk truncates the file.

---

## Cross-cutting patterns

1. **Failures collapse into a reassuring outcome.** The same root shape appears four times: a
   typed failure exists in the data layer, and the presentation turns it into a statement of
   success or absence.
   - "No update found" (FAIL-3)
   - "No confident online matches found" (FAIL-2)
   - "Backup exported." (FAIL-1)
   - "Temporarily unavailable" (FAIL-9)

   Device Sync is the counter-example. It keeps offline (`suppressedOffline`), transient and
   permanent outcomes distinct, and it has its own advice and copyable support code.

2. **No shared classification layer. Each feature rolls its own, at very different levels of
   care:**

   | Taxonomy | Size | What the user gets |
   | --- | --- | --- |
   | `UrlFetchFailureReason` (imports) | ~40 | Rich, source-named messages |
   | `SyncFailureCause` | 11 | Cause, advice, support code, transient tier |
   | `UpdateDownloadFailure` | 8 | 4 of the downloader's kinds collapsed into `unreachable` |
   | `PublishedCollectionFetchFailure` | 9 | All shown as one string |
   | `SnapshotFailureCause` | 3 | Classifies disk-full / permission from OS error codes |

   Disk-full and permission classification exists **only** for the migration snapshot. Backup
   export, update download, autosave, the startup purge and the generic bootstrap screen all
   describe a full disk generically or wrongly. A shared
   `classifyIoFailure(Object) → {diskFull, permissionDenied, locked, unknown}`, plus one shared
   sentence set, would fix FAIL-5, FAIL-7, FAIL-8 and FAIL-16 together. It would also make the
   FAQ's "free some disk space" advice something the app could actually say.

3. **Async callbacks passed where a `VoidCallback` is expected.** `onUndo`, `onPressed` and
   `onTap` closures that `await` and throw end up only in the zone log (FAIL-4, FAIL-6,
   FAIL-15). `guardExport` is the right pattern but covers only exports. A `guardAction`
   counterpart, or an `AsyncCallback`-typed `showUndoSnackBar` that shows a "Couldn't undo"
   snackbar itself, would close the class.

4. **"diagnostics: silent" is overused on user-visible failures.** The annotation was meant for
   best-effort internals, but it also appears on catch sites whose failure the user experiences
   (FAIL-2, FAIL-8, FAIL-9). Those sites then leave nothing for a bug report (FAIL-10).

**Failure-class × feature matrix** (✓ = clear, recoverable; ~ = partial; ✗ = silent or wrong):

| Feature | Offline | Slow / timeout | 4xx / 5xx / malformed | Disk full / permission | Version mismatch |
| --- | --- | --- | --- | --- | --- |
| URL import / online search | ✓ | ✓ | ✓ | n/a | n/a |
| Collection title-list import | ✓ (stops) | ✓ | ✓ | n/a | n/a |
| Program title-list resolve | ✗ FAIL-2 | ✗ (no stop or cancel) | ✗ | n/a | n/a |
| ContraDB program import | ✓ fetch / ✗ commit | ~ | ✓ fetch / ✗ commit | n/a | n/a |
| Published collections | ~ (one string) | ~ | ✗ | n/a | ✗ FAIL-9 |
| Update check (manual) | ✗ FAIL-3 | ✗ | ✗ | n/a | ✗ (stranded) |
| Update download | ✓ | ✓ (idle timeout, cancel, retry) | ~ (says "connection") | ✗ FAIL-5 | n/a |
| Device Sync now | ✓ | ✓ | ✓ | n/a | ✓ (refused / custom-server advice) |
| Backup export | n/a | n/a | n/a | ~ (generic) | n/a |
| Backup restore | n/a | n/a | ✓ | ✓ | ✓ |
| Import file pick | n/a | n/a | ✗ FAIL-4 | ✗ FAIL-4 | n/a |
| Startup | n/a | n/a | n/a | ~ snapshot ✓ / purge ✗ FAIL-7 | ✓ guard / ~ no way forward FAIL-11 |

---

## Checked and fine

- **Import fetch layer.** SSRF guard, per-hop redirect allowlist, 8 MiB cap, a 30 s timeout
  covering the whole send, and typed reasons with source-named wording
  (`import_io.dart:611-717`).
- **Collection online search and preview.** Errors are typed, shown inline or as a snackbar,
  and logged (`dance_list_screen.dart:1007-1036`).
- **Exports (PDF / text / bundle).** All go through `guardExport`, which catches `Object`
  (#1395). A cancelled Save As is silent, as it should be.
- **Backup restore.** The picker catches TooLarge, Format and Object errors. Restore
  distinguishes integrity, newer-schema, incomplete and missing-app-section failures, and
  retrying settings after a partial failure is offered (`general_section.dart:300-420, 960-1019`).
- **Device Sync "Sync now".** Offline and metered gates have their own messages,
  transient-vs-permanent wording, conflict re-check, and advice per cause, with custom-server
  variants.
- **Single-instance guard.** Fails open on an unexpected I/O error. The OS advisory lock
  releases on crash, so a crashed instance can't brick relaunch. The second launch exits
  before opening the database.
- **Migration preflight.** Downgrade and below-floor checks fail closed. A failed snapshot asks
  the caller (with a classified cause) instead of migrating silently. Back Up + Reset never
  wipes if the snapshot fails.
- **Update auto-check and temp sweep.** Fire-and-forget (`unawaited`), never block startup;
  the sweep is fully guarded.
- **Update download.** Idle and write-stall watchdogs, Cancel, and Retry in both the banner and
  Settings; a sha256 failure deletes the file.
- **Retirement notice.** Cached and shown offline. A failed check doesn't clear it.
- **Startup seed and retention-read failures.** Non-fatal and logged. The integrity probe is
  advisory.
- **Crash log.** Rotation is bounded (1 MiB × 4) and appends are serialized and
  exception-proof. Reading it in Settings handles failure explicitly and doesn't show "No
  errors" on a read error.

## Out of scope but noticed

- **Leftover temp backup on mobile.** `saveBackupToFile` writes the full-library JSON to the
  temp directory and never deletes it (`backup_io.dart:247-254`). That is a privacy and storage
  question for the privacy or platform auditor.
- **Background downloads after a published-collection timeout.** `.timeout()` on the published
  collection fetch doesn't cancel the underlying `http.Client` stream. The `finally` close runs
  only when the inner future completes, so a timed-out download keeps running in the background
  (`published_collection_service.dart:133-150`, :167-218).
- **ContraDB program commit after leaving the screen.** `_commit` creates the program even if
  the screen was popped during resolve, because there is no `mounted` check before
  `programs.create` (`contradb_program_import_screen.dart:397-424`). The caller then gets no
  Undo snackbar for it.
