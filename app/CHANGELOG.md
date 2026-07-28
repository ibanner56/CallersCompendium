# Changelog

All notable changes to Caller's Compendium (the app) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings use the semantic `major.minor.patch` version. Flutter's build
number — the `+build` segment of `version` in `app/pubspec.yaml` — is noted with
each release so store builds and tags can be traced back to an entry.

## [Unreleased]

## [0.1.0] - 2026-07-22

Flutter build: `0.1.0+1`.

This section covers the `0.1.0` line. **`v0.1.0-beta.4`** (this pre-release) builds
on **`v0.1.0-beta.3`** with the project's biggest round of hardening yet — a broad
data-safety and update-integrity pass — alongside genuinely new capabilities:
**venues as a first-class entity**, **free-text figure entry** with your own
shorthands, **portable backups with a built-in integrity check**, **crash
diagnostics**, and a **newly multilingual
interface** — the app now speaks German, French, Japanese, Danish, and Dutch alongside
English. The changes **since beta.3** are grouped first; the standing feature overview
and install notes follow.

### Added

- **Venues are now a first-class entity.** Create a reusable venue once — hall or
  grange name, address, contact, schedule, and notes — and attach it to any program
  from the program editor's venue picker, or manage the whole list from a dedicated
  Venues screen. A program's linked venue fills in its printed and exported set list.
  When you **share a program or export it to PDF**, the venue travels with it — but the
  organizer's **contact details (contact names, phones, emails) are left out by
  default**, with an opt-in prompt to include them when the venue has contact details
  on file. Importing a shared program **reuses a matching venue you already have instead
  of creating a duplicate** — venues are matched by name and location (address/city), so
  re-importing the same event won't clutter your venue list. The feature is **opt-in** behind a Settings toggle; with it off, programs
  keep their existing free-text venue label exactly as before.
- **Free-text figure entry (opt-in).** With the new Settings toggle on, you can type a
  figure as plain text (including `;`-separated compounds) and Caller's Compendium
  parses it into a structured, editable figure on the spot. Anything it can't map is
  kept as a clearly flagged custom that you can re-check later — nothing is dropped.
- **Your own figure shorthands.** Define personal shorthands (e.g. `pt` → *pass
  through*) that expand — one shorthand can even stand in for several figures — as you
  use free-text entry, so common phrases go in fast.
- **Backups now carry an integrity check.** Every exported backup wraps your data in a
  built-in **SHA-256 checksum**, so a corrupted or altered file is caught and refused at
  restore — before any of your current data is touched — instead of importing something
  damaged. The export stays a single, human-readable `.json` file.
- **Crash diagnostics.** Unexpected errors are now caught and written to a local,
  rotating crash log you can view, export, and clear from **Settings ▸ Diagnostics**.
  Exports scrub your dance content, file paths, and contact details by default; there
  is nothing sent anywhere and no telemetry.
- **Parser-gap customs are flagged, and re-checkable.** Figures that came in as custom
  only because an importer couldn't yet recognise them are now marked distinctly from
  the customs you wrote yourself, and a Settings action can re-parse them against the
  current recognisers as coverage improves.
- **More batch editing in multi-select.** Collection multi-select now sets or clears a
  dance **level**, and batch-edits **rating**, **tunes**, and **custom fields** across
  the selection.
- **Tap a tag to filter.** Tapping a tag chip on a dance jumps to the Collection
  filtered to that tag.
- **Signed, integrity-checked updates.** When you opt in to update checks, the app now
  verifies a cryptographically **signed update manifest** (Ed25519, with the public key
  pinned in the app), only accepts artifacts from an **allowlist of GitHub-owned
  hosts**, and gates launch on that verification.
- **The app is now available in six languages.** Caller's Compendium's interface is
  now translated into **German, French, Japanese, Danish, and Dutch**, in addition to
  **English**. Pick your language under **Settings ▸ Language & region**, or leave it on
  **System default** to follow your device. Your dance content — figure and call
  terminology — is unaffected: that is governed by your chosen **dialect**, independent
  of the interface language. A couple of surfaces intentionally stay in English for now:
  a small set of core status messages and the text inside **exported PDF/text
  documents** (so a shared program reads the same for everyone); these are tracked for a
  future release.

### Changed

- **Received shares go through the review screen.** Files and program bundles that
  arrive via a share intent now open the same import review/consent screen that shared
  links already used, so nothing is committed without your say-so.
- **Bulk re-import defaults to keep-local.** Re-importing a set that overlaps your
  collection now defaults to keeping your local copies and shows an overwrite count
  before you commit, so a re-import can't silently clobber your edits.
- **The program editor autosaves.** Your set list is saved as a draft while you build
  it, so an app or OS interruption mid-edit no longer loses your work.
- **Perform mode is steadier and safer to leave.** Leaving Perform now confirms before
  it drops your place and clock (and restores them on re-entry), the top bar collapses
  its extra actions into an overflow on narrow phones, and per-second rebuild churn,
  auto-size flashes, and a dropped wake-lock on resume are fixed.
- **Undo snackbars are transient and out of the way.** Undo prompts now auto-dismiss on
  a sensible timer and float above the bottom controls instead of covering them.
  (Screen-reader users still get the persistent, dismissible behavior the OS expects.)
- **Reduce Motion follows your OS setting.** The app now honors the system Reduce
  Motion preference by default; the in-app toggle still overrides it.
- **Exports keep your on-screen figure detail.** Printed and shared dance cards now use
  the same fuller rendering you see on screen, so balances, enders, hey length, and
  hall direction are no longer dropped from exports.

### Removed

- **Passphrase-encrypted backups (`.ccbackup`) have been dropped.** A short-lived
  earlier beta offered an optional encrypted backup; backups are now always a plain,
  human-readable `.json` file protected by an integrity checksum (see Added). A backup
  holds your own library and settings — no passwords, accounts, or third-party personal
  data — and it never leaves your device unless you export it, so the encryption option
  added real complexity for little practical benefit. Treat an exported backup like any
  personal document and store it somewhere you trust.
  **Breaking:** the app can no longer open existing `.ccbackup` files. If you have one,
  restore it with the older build and export a fresh `.json` backup.

### Fixed

- **Deleting a dance, venue, or related-dance link can no longer corrupt your data.** A
  cluster of purge-time bugs — where permanently removing the target of a link or a
  dance-only program slot could later make the whole Programs or Collection list fail
  to load — has been fixed and locked down with integrity tests and fuzz coverage.
- **iOS "Share via browser" imports now work.** Sharing a link into the app from
  Safari now reliably wakes the app and drains the shared item on foreground, instead
  of flashing a sheet and doing nothing.
- **Trashed dances no longer appear in search.** Soft-deleted dances are now excluded
  from full-text search results, matching the filtered browse list.
- **Assumed figure subjects are marked, not invented.** When an import omits who does a
  figure, the app now attaches a non-authoritative "assumed" marker instead of silently
  presenting a guessed subject as fact.
- **Orphaned records are cleaned up.** Purging a dance now garbage-collects the
  choreographer and source rows it leaves behind.
- **The tag input clears after you add a tag** in the dance editor.

### Security & data safety

This release puts a deliberate pass over the ways your data could be lost, corrupted,
or tampered with:

- **Fail-closed migration snapshot.** If the automatic pre-upgrade backup can't be
  written, the app now stops and asks before proceeding, rather than silently upgrading
  without a safety net.
- **Atomic backups and all-or-nothing restore.** Backups are written to a temporary
  file and swapped into place, so an interrupted write can't corrupt your last good
  backup; a replace-mode restore now fully succeeds or leaves your data untouched.
- **Tamper-evident backups.** Every backup carries a SHA-256 integrity checksum; a
  corrupted or altered file fails the check and is refused at restore, before any of
  your current data is touched. (This is a corruption/tamper check, not encryption —
  backups stay plain, human-readable JSON.)
- **Single-instance desktop guard.** Running a second copy on desktop no longer risks a
  database-lock race.
- **Hardened imports.** Imported text is sanitized against control, bidirectional, and
  look-alike character spoofing; import files are size-capped and `.USR` structure is
  bounded; and titles are sanitized before they become PDF print-job names.
- **Safer release builds.** Android release builds now fail loudly if the signing key
  is missing (instead of quietly debug-signing), and the Windows installer's toolchain
  is pinned and checksum-verified.

### Accessibility

- **Perform accessibility preferences persist** across sessions.
- **Dialect substitution fields have programmatic labels** for screen readers.
- **The theme editor's low-contrast warning is announced** as a live region.

### Performance

- **Faster large collections.** Collection hydration is batched to remove an
  N+1 query pattern, author and last-called sorts are scoped to the current result set,
  and the derived-index rebuild runs in batches with progress instead of appearing to
  hang.

### Data / Migrations

- **Schema advances from version 12 to 14 — automatically and losslessly.** Two
  additive steps run on first launch: a performance-only index (no data touched), and
  the new **venues** table plus a nullable `venue_id` link on programs. Existing
  programs keep their free-text venue label untouched, nothing is back-filled, and no
  content is rewritten. **Upgrading from beta.2 or beta.3 is a normal in-place
  install** — no reinstall and no manual data steps. (Upgrading *directly from beta.1*
  still runs the one-time ocean-wave migration described in the beta.2 notes, and needs
  the Android reinstall below.)

### Known issues

- **Coming from beta.1? A one-time Android reinstall is still required.** beta.2
  unified the Android application identifier with Apple
  (`org.callerscompendium.compendiumApp`), so a beta.1 sideload cannot upgrade in
  place. **Export a backup (Settings ▸ General ▸ Export a backup), uninstall the old
  app, install this build, then restore.**
- **In-app update checks remain opt-in.** Automatic checks and the beta channel are off
  by default and enabled in Settings; when on, updates are now signature-verified (see
  Security & data safety). Either way, you can always watch the GitHub Releases page for
  new betas.
- **Windows and Linux desktop builds are still unsigned** (see Platforms & install).

### What you can do today

- **Build your Collection.** Create, edit, and tag dances, organize them your way,
  and soft-delete/restore anything (with a 30-day Recently Deleted safety net).
- **Plan Programs.** Assemble a set with event date, a reusable venue, ordered slots,
  and alternates; track program status; duplicate a program to reuse a good set.
- **Perform.** Open a program — or a single dance — in a large-print, auto-sizing
  Perform view built for reading across a dim hall, mark dances as you call them, and
  tap out the tempo on a built-in visual metronome.
- **Enter figures your way.** Build figures with the structured editor, or turn on
  free-text entry to type them (with your own shorthands) and have them parsed into
  structured, editable figures.
- **Import your existing library.** Bring dances in from a JSON backup, The Caller's
  Box, ContraDB, and Caller's Companion (`.USR`); import **programs** from Caller's
  Companion (`.USR`) and now from **ContraDB** as well. Every import is reviewable and
  undoable with one tap.
- **Share between devices.** Send a program and its dances to another device, or open
  one that was shared with you.
- **Search the way you talk.** Dialect-aware search and filtering understands the
  terminology you use, whichever tradition you call in.
- **Keep your data yours.** Export a full backup to a single human-readable JSON file
  (with a built-in integrity check) and restore it on another machine — no account, no
  cloud, no telemetry.

### Platforms & install

- **Android** — a signed universal `.apk`. Install it directly (sideload); you may
  need to allow "install unknown apps" for your browser or file manager. It is **not**
  on the Play Store yet. (If you ran beta.1, see the reinstall note under Known
  issues.)
- **iOS** — delivered through **TestFlight** to invited testers; by design there is
  no `.ipa` on this Releases page.
- **macOS** (universal) — **signed with an Apple Developer ID and notarized**, so it
  opens normally (you may see a single first-launch confirmation).
- **Linux** (x64) and **Windows** (x64) — desktop builds, **still unsigned** for this
  beta, so your OS will warn you before it runs:
  - Windows: **More info → Run anyway** on the SmartScreen prompt.
  - Linux: the **`.tar.gz`** is the no-setup path — extract and run. The `.AppImage`
    needs the **FUSE 2** runtime (`libfuse.so.2`) — package `libfuse2` on
    Debian/Ubuntu, `fuse-libs` on Fedora — which some recent distros don't
    preinstall; install it, or launch with
    `./CallersCompendium-*.AppImage --appimage-extract-and-run`.

### Your data & safety

Everything lives locally on your device. There is no telemetry and nothing is sent
anywhere. Imports are previewed before they commit and are undoable, so trying a new
source is safe. Before a large import — or any upgrade — you can export a backup from
**Settings ▸ General ▸ Export a backup** for extra peace of mind.

### Feedback

Please tell us what breaks or feels wrong:
<https://github.com/ibanner56/CallersCompendium/issues>. Include your platform, the
version (`0.1.0-beta.4`), and the steps you took. For import problems, a small
sanitized sample of the file you were importing helps enormously.

### License

Caller's Compendium is free software under the **AGPL-3.0**, with an
[additional permission](../LICENSE-EXCEPTION.md)
that allows distribution through managed application marketplaces (Apple's App
Store, Google Play, and comparable stores) under those stores' required terms —
while the source stays fully AGPL-3.0 and every user keeps their rights to it. The
source is always available at <https://github.com/ibanner56/CallersCompendium>.
