# PLAT — Platform citizenship and cross-platform parity

Auditor key: `PLAT`. Read-only audit of the tree as checked out on 2026-10-27.

## Scope & method

User story: "I prepare on a Windows laptop or Mac and call from an Android phone or an
iPad. The app should work the way my device works, and the same features should be on
each, or there should be a clear reason why not."

**Read (user docs):** `docs/user/installation.md`, `accessibility.md`, `faq.md`,
`settings.md` (Formats, Language, Updates), `sharing.md` (dance/program file sections),
`imports.md` ("Open a shared program someone sent you"), `authoring.md` (reorder, undo),
`perform.md` (enter, move through a program), `collection.md` (bulk select).
**Read (design):** `docs/design/ux.md` §shell and §5 Perform, `docs/design/ux-modernization.md` UX-5.

**Traced (code):**
- OS intake: `app/lib/src/data/incoming_file_channel.dart`, `main.dart` (`main()`,
  `_handleIncomingFile`), `archive_intake_service.dart`, `archive_codec.dart`
  (`decodeArchive` and `_decodeList`), `backup_document.dart` (container shape),
  `AndroidManifest.xml`, `MainActivity.kt`, iOS and macOS `Info.plist`, the iOS
  ShareExtension `Info.plist`, `IncomingFilesPlugin.swift`/`IncomingFilesBridge.swift`
  (security-scoped access), the Windows `main.cpp`, the Linux `my_application.cc`,
  `packaging/linux/*.desktop`, `AppRun` and `packaging/windows/CallersCompendium.iss`.
- Single instance and window: `single_instance_guard.dart`, `window_service.dart`,
  `window_frame.dart`, the macOS `AppDelegate.swift`/`MainFlutterWindow.swift`/`MainMenu.xib`
  and `AppInfo.xcconfig`, and the Windows `Runner.rc`.
- Shortcuts: every `Shortcuts`/`CallbackShortcuts`/`SingleActivator`/`LogicalKeyboardKey`
  in `app/lib` (4 files), `command_palette.dart`, and the shell `openSearch`.
- Back handling: every `PopScope` in `app/lib`, plus the editors that have none.
- Share sheet: `share_file.dart`, `backup_io.dart`, `crash_log_io.dart`, and the tests that
  assert `sharePositionOrigin`.
- Updater: `current_platform.dart`, `update_service.dart`, `update_controller.dart`,
  `artifact_handoff.dart`, and `tools/release/gen_release_metadata.py` (primary artifact choice).
- Lifecycle: `perform_wakelock.dart`, `editor_draft_shutdown_scope.dart`, autosave debounce.
- Locale: every ARB file (key diff script), `regional_formats.dart`, `locale_scope.dart`,
  `title_sort_key.dart`, `filter_compiler.dart` sort SQL, and Dart-side `compareTo` sorts.
- Every platform gate (`Platform.isX`, `defaultTargetPlatform`, `kIsWeb`).

I did not build or run the app. A throwaway Dart script to confirm PLAT-2 could not
run: no `package_config.json` exists, and running `pub get` would have written into the
repo. PLAT-2 was traced by reading the code instead.

---

## Findings

### PLAT-1 — High — iPad: backup export (and diagnostics-log export) open the share sheet with no anchor

**Scenario:** On an iPad, a caller opens **Settings › General › Export a backup**. The
guides tell them to do this "before installing a new version" (installation.md), when
switching between the Play and APK builds, and when moving to a new device (faq.md).

**What happens:** The mobile branch of `saveBackupToFile` calls
`SharePlus.instance.share(ShareParams(files: …, subject: …))` with **no
`sharePositionOrigin`** (`app/lib/src/data/backup_io.dart:255-261`). The diagnostics-log
export does the same (`app/lib/src/diagnostics/crash_log_io.dart:66-72`). On iPad,
`share_plus` presents the activity view as a popover, and it rejects a null or zero
origin with a PlatformException ("sharePositionOrigin: argument must be set…").

Every other share path in the app passes an origin: `share_file.dart:167-174`,
`dance_export_actions.dart:190` and `program_export_menu.dart:393`. The project already
pins that requirement in tests (`app/test/program_export_test.dart:515` "share receives a
non-null sharePositionOrigin", `dance_export_test.dart:560`, `dance_detail_screen_test.dart:934`).
The backup and diagnostics-log paths are the two that were missed.

**Expected:** The share popover opens, anchored to the button, as it does for a dance or
a program.

**Confidence:** **Inferred.** I traced that the origin is missing in both call sites and
present everywhere else. I did not run the plugin on an iPad. The claim that iPad rejects
a null origin comes from `share_plus` behaviour that I know of but did not check in this
tree, because there is no pub cache. Verify on an iPad, or in the simulator with the iPad
idiom. If it is confirmed, this blocks the backup habit that the guides rely on, on one
of the two stage devices named in the user story.

### PLAT-2 — Medium — Opening a full backup through "Open with" / tap says "That file didn't contain any dances or programs"

**Scenario:** On a new Android phone, the caller taps
`callers-compendium-backup-2026-07-15.json` in Files, Drive or an email attachment. On a
Mac, they choose Open With › Caller's Compendium. Moving a backup across is what
faq.md "How do I move everything to a new phone or computer?" tells them to do.

**What happens:**
- The app is offered for the file. Android registers `VIEW`/`SEND` for `application/json`
  (`AndroidManifest.xml:36-47`). macOS and iOS register `public.json` as Alternate
  (`app/macos/Runner/Info.plist:24-35`, and the same in the iOS `Info.plist`).
- Backups are written as `.json` (`backup_service.dart:808`).
- The file goes to `ArchiveIntakeService.validateFromPath` (`main.dart:1157-1163`).
- A backup's root is the checksum container `{backupContainer, checksum, payload}`
  (`backup_document.dart:312-318`). `archiveFromJson` treats the absent `dances` and
  `programs` keys as empty lists (`archive_codec.dart:519`: `if (raw == null) return const []`).
- Intake therefore rejects the file as `noContent` (`archive_intake_service.dart:226-230`).
- The snackbar says **"That file didn't contain any dances or programs."** (`app_en.arb:8434`),
  even though the backup may hold the caller's whole library.

**Expected:** The app recognises the file as a backup and says so. For example: "This is a
backup. To replace this device's library with it, use Settings › General › Restore."
It could also offer the restore flow directly.

**Confidence:** Traced. The script I wanted to run to confirm it could not run (see Method).

**Decision:** Either (a) recognise a `backupContainer` root during intake and route the
caller to Restore with an explanation, or (b) only change the message. (b) is the minimum,
because the current text is false.

### PLAT-3 — Medium — Windows and Linux: "open the file I was sent" does nothing, silently

**Scenario:** A Windows caller receives `Contra Night.ccshare`. They double-click it, or
choose Open with › compendium_app.exe, or run `./CallersCompendium.AppImage file.ccshare`.

**What happens:**
- **No association is registered.**
  - The Inno script has no `[Registry]` or `ChangesAssociations` entry
    (`packaging/windows/CallersCompendium.iss`).
  - The Linux `.desktop` file has no `MimeType=`, and `Exec=compendium_app` takes no
    `%f`/`%U` (`packaging/linux/org.callerscompendium.compendiumApp.desktop`).
  - So `.ccshare` shows as an unknown file type even with the app installed.
- **Arguments are dropped.** Both runners pass argv to Dart: `app/windows/runner/main.cpp:22-25`
  and `app/linux/runner/my_application.cc:124` (AppRun forwards `"$@"`). But
  `Future<void> main() async` takes no arguments (`app/lib/main.dart:136`), and there is no
  native `getInitialFile` on these platforms, so the channel returns null
  (`incoming_file_channel.dart:78-90`).
- **On a cold start** the app opens normally and ignores the file.
- **If the app is already running,** the second launch only sends the literal line
  `raise` (`single_instance_guard.dart:300`, `handleSecondLaunch` at `:495-524`). The
  existing window comes forward and the file is lost.
- **Dragging the file onto the window** also does nothing on any desktop: there is no
  drop target plugin in `generated_plugin_registrant.*`.

**Expected / docs:**
- imports.md:256-261 says Windows and Linux users must use **Settings › General ›
  Import…**, so the gap is documented there.
- faq.md:125 tells every recipient they "can **open that file directly** (AirDrop, 'Open
  with', or a share intent)".
- sharing.md:200 calls `.ccshare` "Caller's Compendium's own file type", which is only
  true on Apple devices.
- Neither installation.md nor faq.md says the desktop builds behave differently.

**Confidence:** Traced.

**Decision:**
- (a) Add the `.ccshare` association to Inno and to the `.desktop` file. Read argv in
  `main`, and forward the path over the existing loopback raise channel, for example a
  `open <path>` line next to `raise`.
- (b) Or keep the gap and fix faq.md and sharing.md so they say which platforms support it.

### PLAT-4 — Medium — Android: a `.ccshare` file at rest may not be openable or pickable

**Scenario:** A Mac or iPad caller uses the default **Share (program + dances)**, which
produces a `.ccshare` file, and sends it by email or chat to an Android caller. The
recipient taps the attachment, or saves it and uses **Settings › General › Import…**.

**What happens:**
- **Open with:** the only file filters are `VIEW`/`SEND` on `application/json`
  (`AndroidManifest.xml:36-47`). Android does not know the `.ccshare` extension, so
  providers usually label such a file `application/octet-stream`. In that case the app is
  not offered for it.
- **Import…:** the picker passes `mimeTypes: ['application/json']` alongside
  `extensions: ['ccshare','json']` (`import_io.dart:240-248`). On Android, `file_selector`
  filters by MIME type, so an octet-stream `.ccshare` is likely greyed out.

imports.md:258 tells Android users only about `.json` bundles. sharing.md:200-202 promises
that "on any device the recipient can bring it in with **Settings › General › Import…**".

Sharing directly from Android to Android through the share sheet probably works:
`share_file.dart:85` tags the file `application/json`, and `IncomingFileStagerTest.kt:114`
covers a `.ccshare` name.

**Confidence:** **Inferred.** I did not verify which MIME type real providers (Gmail,
Drive, the Files app) assign to `.ccshare`, or `file_selector_android`'s filter logic
(no pub cache). Test by pushing a `.ccshare` to Downloads and trying both entry points.

**Decision:** Accept `application/octet-stream` in the picker and in the VIEW filter (and
validate in Dart as now), or default mobile senders to `.json`.

### PLAT-5 — Medium — Phone/tablet update banner sends TestFlight and Play users to a GitHub release they cannot use

**Scenario:** An iPad (TestFlight) or Google Play caller turns on **Beta channel** and
**Check automatically**, as installation.md recommends.

**What happens:**
- `UpdateService` reports an update whenever the manifest version is newer, whatever the
  platform (`update_service.dart:156-165`).
- The manifest has no iOS artifact. `gen_release_metadata.py:51-54` lists only linux,
  macos, windows and android, so `artifact` is null on iOS. The banner still shows "A
  newer version … is available" with **View release**, which goes to the GitHub release.
- An iOS user finds nothing to install there, and TestFlight may not yet carry the build.
- A Play user finds the sideload APK. installation.md ("Pick one lane") says it is signed
  with a different key and will not install over the Play build.
- Nothing in `app/lib/src/update/` detects TestFlight or the Play installer (grep for
  `installerPackage` and `play` found nothing).
- installation.md:243 says the banner "links you to the release so you can download it
  the usual way for your device". That is not true for either of these channels.

**Confidence:** Traced (no store-channel detection; the manifest has no iOS artifact).
The user-facing consequence is inferred.

**Decision:**
- (a) Suppress the banner, or change its text to "Update from TestFlight / Play", when
  there is no artifact for this platform or the installer is a store.
- (b) Or hide **Check automatically** on store builds.

### PLAT-6 — Medium — Desktop updater installs a different format from the one the caller chose

**Scenario:** A caller runs the **portable Windows .zip**, or the **Linux tar.gz** with
the optional `.desktop` entry. They click **Download & install update**.

**What happens:** The manifest's primary artifact is always the installer form: exe over
zip, AppImage over tar.gz, dmg over zip (`tools/release/test_gen_release_metadata.py:110-115`).
- **Windows:** `handoffArtifactToOs` starts the `.exe` installer
  (`artifact_handoff.dart:117-122`). It installs a second copy into Program Files, and the
  portable copy in the caller's folder stays old. settings.md:493 says the installer
  "handles closing and replacing the existing installation", but there is no installation
  to replace.
- **Linux:** a tar.gz user is handed an AppImage in a temporary folder that is cleaned up
  after a week (settings.md:497-501), and their menu entry still points to the old tree.
- Nothing detects a portable or tar.gz install (grep for `portable` found nothing in
  `app/lib/src/update/`).

**Confidence:** Traced (artifact choice and handoff). The user-visible outcome is inferred.

**Decision:** Detect a portable install (for example, the absence of the Inno uninstaller
or registry key, or `APPIMAGE` unset on Linux). Then either offer the matching archive, or
say "you're running a portable copy — download the new zip from the release".

### PLAT-7 — Medium — The desktop "full keyboard map" is four bindings; desktop conventions (save, find, close, right-click, mouse-back) are missing

**Scenario:** A caller preparing on a laptop presses Ctrl/Cmd-S in the dance editor,
Ctrl/Cmd-F in the Collection, Cmd-, for settings, Cmd-W or Esc to leave a pushed screen,
Ctrl-Z in the program editor, right-clicks a dance row, or uses the mouse's Back button.

**What happens:** None of these do anything. The complete list of app shortcuts is:
- Ctrl/Cmd-K global search (`command_palette.dart:43-44`)
- undo/redo in the **dance** editor only (`dance_editor_screen.dart:818-835`)
- Alt+↑/↓ and Ctrl/Cmd+Enter in the figure list (`figure_list_editor.dart:1779-1823`)
- arrow/Page keys in Perform (`perform_program_screen.dart:1168-1205`)

There is no `onSecondaryTap` anywhere in `app/lib` (0 hits), and no handling of
`kBackMouseButton`. The program editor has no undo/redo stack at all, unlike its sibling
the dance editor.

The design commits to more. `docs/design/ux.md:24` lists "full keyboard map" for desktop,
and `ux-modernization.md` UX-5's acceptance criterion is "complete desktop keyboard map".
accessibility.md says "full keyboard control" (which Tab traversal arguably gives), but a
desktop user expects the conventional accelerators.

**Confidence:** Traced (grep was exhaustive over `app/lib`).

**Decision:** Pick a minimal desktop map and say which layer owns it:
- Ctrl/Cmd-S save, Ctrl/Cmd-N new dance, Ctrl/Cmd-F focus search, Cmd-, Settings,
  Esc/Cmd-W back
- a right-click → the same ⋮ menu
- mouse Back → `maybePop`

Then document it in accessibility.md. The alternative is to drop "full keyboard map"
from the design docs.

### PLAT-8 — Medium — The macOS menu bar is the unmodified Flutter template, and the About box says "All rights reserved"

**Scenario:** A Mac user explores the menu bar, presses Cmd-, for settings or Cmd-W to
close, opens Help, or opens Caller's Compendium › About.

**What happens:**
- `MainMenu.xib` is the stock template. **Preferences… (Cmd-,)** has no action
  (`MainMenu.xib:36`), so it is permanently disabled. The label is also the pre-Ventura
  "Preferences…" rather than "Settings…".
- There is no File menu and no **Close** item, so Cmd-W does nothing.
- **Help** is an empty `systemMenu="help"` (`:326-329`) and does not open the bundled
  Guide.
- There is no `PlatformMenuBar` in `app/lib`, so no app command (New Dance, Import,
  Perform, Guide) appears in the menu bar. Mac users look there to discover features.
- **About** shows `NSHumanReadableCopyright = "Copyright © 2026 org.callerscompendium.
  All rights reserved."` (`app/macos/Runner/Configs/AppInfo.xcconfig:14`). That
  contradicts the AGPL-3.0 licence stated in faq.md, and the publisher is shown as a
  reverse-DNS id.
- Windows has the same issue: `app/windows/runner/Runner.rc:92,96` sets
  CompanyName `org.callerscompendium` and "All rights reserved", while the Inno script
  says "Caller's Compendium contributors".
- Menu titles never localise (see PLAT-16).

**Confidence:** Traced.

**Decision:** Either install a small `PlatformMenuBar` (Settings, New dance, Import…,
Guide), or at least wire Cmd-, and the Help item. Fix the copyright strings either way;
that fix needs no decision.

### PLAT-9 — Medium — Perform does not go full screen on any platform, although the guide says it "fills the whole screen"

**Scenario:** A caller starts **Perform this program** on a laptop on stage, or on an
Android phone.

**What happens:**
- There is no `SystemChrome.setEnabledSystemUIMode` (immersive) and no
  `windowManager.setFullScreen` anywhere in `app/lib` (grep: 0 hits).
- On Android and iOS the status and navigation bars stay visible over the dark stage
  card, with notifications and the clock.
- On desktop, Perform is an ordinary route inside a 1024×768 window, with the OS title
  bar and the taskbar or Dock visible.
- `docs/user/perform.md:20` says "It fills the whole screen", and `docs/design/ux.md:162`
  says "Full-screen card".

**Confidence:** Traced (absence).

**Decision:** Either (a) enter immersive mode on mobile and offer a full-screen toggle on
desktop (F11 / Ctrl-Cmd-F), restoring both on exit, or (b) reword the guide to "fills the
app window".

### PLAT-10 — Medium — In Perform, an overflowing card cannot be scrolled from a keyboard or page-turner pedal

**Scenario:** A caller has auto-size off (for example, after pressing A+ once, which
turns it off; accessibility.md) on a long dance. They drive Perform with a keyboard or a
Bluetooth page-turner, which sends arrow or Page keys.

**What happens:**
- The card body is a `SingleChildScrollView` (`perform_card.dart:167,235`).
- Every vertical key is bound to slot navigation: ↓/PageDown → `_goNext`, ↑/PageUp →
  `_goPrev` (`perform_program_screen.dart:1194-1205`). The scroll view has no focusable
  controller, so the keyboard cannot reach the bottom of the card.
- Pressing ↓ to read on jumps to the **next dance**. perform.md:118 documents only "arrow
  keys or Page Up / Page Down" for moving between slots.
- When the walkthrough overlay is open, the same keys already scroll it, so the pattern
  exists in the code.

**Confidence:** Traced (bindings). That cards overflow in practice is inferred, since
auto-size usually prevents it.

**Decision:** Either ↓/PageDown scroll first and advance only at the bottom, or ←/→ keep
slot navigation and ↑/↓ scroll the card.

### PLAT-11 — Medium — Back gesture, scrim tap or swipe-down silently discards some editors; sibling editors ask first

**Scenario:** A caller edits a custom theme (up to 15 colour roles), types a venue with
address and contacts in the venue sheet, or builds a choice custom field. Then they make
the Android back gesture, swipe from the iOS edge, swipe the sheet down, tap outside it,
or press Esc.

**What happens:**
- `ThemeEditorScreen` is a plain `Scaffold` with a Save action and no `PopScope`
  (`theme_editor_screen.dart:66-98`).
- `VenueEditorSheet.show` uses `showModalBottomSheet` with the default `isDismissible`
  and `enableDrag` (`venue_editor_sheet.dart:40-46`).
- The custom-field form is opened the same way (`custom_fields_screen.dart:133-141`).
- In all three, the work is gone without a prompt.
- By contrast, the dance editor (`dance_editor_screen.dart:802-816`), program editor
  (`program_editor_screen.dart:2887-2895`), dialect editor and glossary compound editor
  all confirm before discarding, and the dance and program editors also keep drafts.

**Confidence:** Traced.

### PLAT-12 — Medium — With the default "System" date format, program dates carry no year

**Scenario:** A caller with programs from 2025 and 2026 scans the Programs list, a
summary, or the add-to-program sheet.

**What happens:**
- `formatEventDate` falls back to `MaterialLocalizations.formatMediumDate`
  (`regional_formats.dart:201`). That is the `MMMEd` pattern ("Wed, Jul 15"), which has
  no year.
- It is used in `program_list_tile.dart:44-51`, `program_summary_screen.dart:694`,
  `program_editor_screen.dart:3770`, `add_to_program_sheet.dart:110` and the ContraDB
  import screen.
- Last year's July 15 program and this year's look identical. The list has no year
  section headers.
- "System default" also follows the **app language**, not the device's regional format.
  An English-UI caller in the UK or in Denmark gets US ordering.

**Confidence:** Traced. The year omission rests on Flutter's documented `formatMediumDate`
contract ("Wed, Sep 27").

**Decision:** Use `formatFullDate` or `yMMMd` for the system default, or add the year
only when it differs from the current year.

### PLAT-13 — Medium — The in-app Guide is English only in all six locales, with no notice

**Scenario:** A German or Japanese caller opens **Guide**.

**What happens:**
- `app/assets/docs/user/` holds one English set (`pubspec.yaml:146-147`).
- The UI is fully translated: all 2,543 keys are present in da, de, fr, ja and nl.
- The Guide therefore names screens in bold English (**Settings › General**) that do not
  match the German UI (Einstellungen).
- No string says the Guide is English-only (only `userGuideMissing`, `userGuideLoadError`
  and `userGuideOpenOnline` exist).

**Confidence:** Traced.

**Decision:** Either (a) translate the guide, or (b) show a one-line notice on the Guide
for non-English locales, and set up a glossary of UI labels. (b) is cheap.

### PLAT-14 — Low — Shortcut hints are hard-coded, not derived from the platform

- The undo/redo tooltips read **"Undo (Ctrl+Z)"** and **"Redo (Ctrl+Shift+Z)"** on macOS
  and iPad too (`app_en.arb:10045,10049`; `dance_editor_screen.dart:861,872`).
  authoring.md:520-523 documents Cmd-Z on macOS.
- The Collection and Programs search tooltip is **"Search (Ctrl/Cmd-K)"** on Android
  phones as well (`dance_list_screen.dart:1915`, `programs_list_screen.dart:489`).
- The rail button already builds the correct per-platform hint (`app_shell.dart:437-440`).
- Alt+↑/↓ (move figure) and Ctrl/Cmd+Enter (commit and next) work
  (`figure_list_editor.dart:1779-1823`) but are documented nowhere in `docs/user`.
- Program slots have no equivalent of Alt+↑/↓.

Traced.

### PLAT-15 — Low — Sorting is not locale-aware

- Title sort is `title COLLATE NOCASE` (`filter_compiler.dart:170`), or, with the default
  "ignore leading articles", a Dart `compareTo` on `toLowerCase()`
  (`dance_repository.dart:2938-2943`, `title_sort_key.dart:23-34`).
- Many other lists also use `toLowerCase().compareTo` (glossary, tags, themes, compound
  shorthands).
- Both orders compare code units, so a title starting with É, Ä, Ü or Æ sorts **after Z**.
- "Ignore leading articles" strips only English the/a/an, while the UI ships French,
  German, Dutch and Danish.

Traced. This is rare in contra titles, so Low, but it is visible to a Danish or German
caller.

### PLAT-16 — Low — OS-provided chrome does not follow the app's languages on every platform

- iOS declares `CFBundleLocalizations` (en, da, de, fr, ja, nl). The macOS `Info.plist`
  does not, and ships only `Base.lproj`. AppKit-provided UI (the menu bar, Save/Open
  panels, the print panel, the About box) is therefore likely to stay English for a
  German Mac user. **Inferred.**
- The Windows installer declares only `english` (`CallersCompendium.iss` `[Languages]`).
- Android has no `localeConfig`, so the Android 13+ per-app language setting is absent.
  iOS offers the equivalent setting.

### PLAT-17 — Low — Dance content cannot be selected or copied piecemeal

`SelectionArea` and `SelectableText` appear only in the Guide
(`user_guide_doc_view.dart`). A desktop caller cannot select one figure line, the calling
notes, or a program summary to paste into an email. The only option is the whole-card
**Copy dance**. Traced.

### PLAT-18 — Low — A second desktop launch that cannot reach the first instance appears to do nothing

When the raise fails, for example a stale port or Wayland focus rules, `handleSecondLaunch`
writes an explanation only to **stderr** and exits (`single_instance_guard.dart:516-524`).
A caller who double-clicked the icon sees nothing happen. Traced.

### PLAT-19 — Low — Mobile editors do not flush their draft when the app is backgrounded

`EditorDraftShutdownController.flushAll` runs only on desktop window close and macOS
terminate (`main.dart:187-191`). On Android and iOS, the only lifecycle observers are
Perform's (wakelock and clock). Edits made in the last 500 ms before backgrounding
(`dance_editor_controller.dart:40,924`; `program_editor_screen.dart:1071`) rely on the
debounce timer firing before the OS suspends or kills the process. **Inferred**,
small window.

---

## Cross-cutting patterns

1. **OS integration was built for Apple and Android first; Windows and Linux get the
   generic path** (PLAT-3, PLAT-4, PLAT-8, PLAT-16). Intake, share extension, UTI and
   locale declarations are polished on iOS. Desktop Windows and Linux have none of them,
   and macOS has the intake but a template menu bar. The user docs describe the Apple
   behaviour as the norm (faq.md:125, sharing.md:200).
2. **The updater does not know how the app was installed** (PLAT-5, PLAT-6). It knows
   the OS but not the distribution channel: TestFlight, Play, sideloaded APK, portable
   zip, tar.gz or AppImage.
3. **Keyboard hints are written as literals instead of read from the bindings**
   (PLAT-7, PLAT-14). The binding table, the tooltips, the docs and the design's
   "full keyboard map" have drifted apart. A single shortcut registry that produces both
   the `Shortcuts` map and the tooltip text would stop this.
4. **Discard protection is opt-in per screen** (PLAT-11). The flagship editors have it,
   and the smaller editors and sheets were built without it.
5. **Incoming files are classified by file extension, not content** (PLAT-2). A backup
   and a share bundle are both `.json`, but only one is accepted. A rejected file gets a
   message that describes the wrong case.

## Checked and fine

- **ARB completeness:** 0 missing and 0 extra keys in da, de, fr, ja and nl against en
  (2,543 keys). Strings identical to English are placeholders or brand names.
- **Window frame persistence:** clamped to the display that contains the saved origin,
  maximize handled with the restored size kept, 640×480 minimum enforced
  (`window_service.dart`, `window_frame.dart`).
- **Desktop close / Cmd-Q:** editor drafts and the database close before the window
  goes. macOS uses `terminateLater`, and closing the last window quits, as expected for a
  single-window app.
- **Single-instance guard:** fails open on unexpected lock errors, raises the existing
  window on Linux and Windows, and relies on LaunchServices on macOS.
- **Wakelock:** released on pause and re-acquired on resume, serialised
  (`perform_wakelock.dart`).
- **Perform exit:** the back gesture, predictive back and the close control all go
  through one confirmation (`perform_program_screen.dart:565-579`).
- **Guide back stack:** intercepts back only while it is the active destination.
- **Swipe actions:** every swipe action has a ⋮ equivalent. Collection multi-select is
  reachable from **More actions › Select dances** without a long-press (collection.md:378).
- **Drag-only settings lists** (matrix columns, levels, choices) are honestly documented
  in accessibility.md.
- **iOS and macOS incoming files:** security-scoped access is used correctly.
- **Linux identity:** `.desktop` `StartupWMClass` matches `APPLICATION_ID`.
- **Linux share sheet:** the file-share fallback to Save As is documented in sharing.md.
- **macOS install-location banner:** gated to macOS and documented in installation.md.
- **iPad multitasking:** Split View and Stage Manager are allowed (no
  `UIRequiresFullScreen`). Single-scene is intentional.
- **Share origins:** dance and program shares pass `sharePositionOrigin`, and tests pin it.
- **Perform keys:** auto-focused, and the walkthrough overlay correctly captures them.
- **Platform gates:** every gate found is intentional, and each user-visible one is
  documented: Linux share→Save As, macOS install banner, update handoff per OS, pdfium
  licence, Android/iOS announcement timing.

## Out of scope but noticed

- settings.md:461-463: an update check that cannot reach the server "reports that no
  update was found". That is a silent wrong result, for the update auditor.
- `packaging/windows/CallersCompendium.iss:3-4` says the installer is unsigned, but
  `release.yml:316` signs it with Azure Trusted Signing. The comment is stale.
- `regional_formats.dart:3` says "Ahead of full app i18n (which we do NOT ship here)",
  but six locales ship. The comment is stale.
- The program editor has no undo/redo, while the dance editor does. That parity question
  is for the programs auditor.
