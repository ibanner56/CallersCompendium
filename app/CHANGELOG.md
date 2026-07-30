# Changelog

All notable changes to Caller's Compendium (the app) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings use the semantic `major.minor.patch` version. Flutter's build
number — the `+build` segment of `version` in `app/pubspec.yaml` — is noted with
each release so store builds and tags can be traced back to an entry.

## [Unreleased]

### Fixed

- **ContraDB import: figures with a `balance &` prefix now recognize instead of
  falling through to a plain custom figure.** ContraDB renders a balanced move as
  `balance & <move>` (e.g. `balance & Rory O'More right`), and the `&` was being
  left behind, demoting otherwise-matchable Rory O'More, petronella, pull by, box
  circulate, and square-through figures to custom. A trailing parenthetical note
  (e.g. `(in long waves)`) is preserved verbatim on the recognized figure. Notes
  that interrupt a figure mid-phrase still stay custom, and malformed/unbalanced
  parentheses are handled safely. (#578)
- **ContraDB import: more real-world figures recognize instead of falling
  through to custom.** Extended the ContraDB figure recognizers to cover renders
  that were dropping to custom over a single unconsumed qualifier: `star` now
  reads the grip clause (`star left - wrist grip - 4 places`,
  `star right - hands across - 3 places`); `box the gnat` reads a leading
  `<hand> hand balance &` prefix (`neighbors right hand balance & box the gnat`);
  a bare `pass through` recognizes and keeps its trailing qualifier as a note
  (`pass through by the left`, `to next neighbors`); `chain` reads a leading
  `left|right diagonal` and keeps `to shadow` as a note; and the `prev neighbors`
  subject (ContraDB's rendered form) now recognizes. Any leftover text is
  preserved verbatim as the figure's note; unrecognized figures still import as
  editable custom. (#585)

## [0.1.0] - 2026-07-29

Flutter build: `0.1.0+1`.

This section covers the `0.1.0` line. **`v0.1.0-beta.5`** (this pre-release) builds
on **`v0.1.0-beta.4`** with a round of caller-authoring and polish work: a dedicated
**Walkthrough** field for teaching notes, a reusable **walkthrough snippet library**
that pre-fills it from your own step text, **grouping your Collection by category**
(a dance's "vibe"), an explicit **end facing for swings**, and **exported documents
that now follow your language** — alongside the switch to plain, **integrity-checked
backups**. The changes **since beta.4** are grouped first; the standing feature
overview and install notes follow.

### Added

- **A dedicated Walkthrough field for every dance.** Each dance now has its own
  free-text **Walkthrough** — a home for the step-by-step teaching notes you say
  while walking a dance through, kept separate from the shorter Calling notes. It
  appears in the dance detail view and travels with the dance.
- **A walkthrough snippet library.** Build up a personal, per-figure library of your
  own walkthrough wording. The first time you walk a figure the app learns your text,
  and from then on it pre-fills the Walkthrough for any dance that uses that figure.
  Editing a snippet asks whether to change it **everywhere** or **just for this
  dance**, and you can manage the whole library from **Settings ▸ Defaults**.
- **Group your Collection by category (a dance's "vibe").** Pick a tag and the
  Collection splits into that category and everything else, so you can jump to a
  "drawer" of bouncy, flowy, or glossy dances mid-evening. Reusable **choice** fields
  — your band adjectives, say — can be built up on the spot with a **＋** while you
  edit. It reuses the tags and custom fields you already have, so there is no new
  data to set up.
- **Swings can record their end facing.** A swing can be marked as ending facing **up
  or down the hall** or **out of the set**. The usual "in"/across ending renders
  exactly as before; the marker appears — on dance cards, in Perform, and in exports —
  only when a swing ends somewhere other than the default.
- **Backups now carry an integrity check.** Every exported backup wraps your data with
  a **SHA-256 checksum**, so a corrupted backup is caught and refused at
  restore — before any of your current data is touched — instead of importing
  something damaged. The export stays a single, human-readable `.json` file; the
  checksum guards against accidental corruption, not encryption, and — because it
  travels inside the file — is not a defense against deliberate tampering.

### Changed

- **Exported documents now follow your language.** Printed and shared dance cards, set
  lists, and the programming matrix (both plain-text and PDF exports) now render their
  field labels — Formation, Level, Band, Caller, Venue, the matrix legend, and the
  rest — in the app's current language, matching the six languages the interface
  already speaks, instead of always printing in English. The diagnostics log export
  stays English by design as a maintainer support artifact.
- **More of the app's status messages are translated.** Core validation, warning, and
  import-issue messages that previously always rendered in English now appear in your
  language. (These translations are machine-assisted and anchored to the app's
  existing terminology; a native-speaker review pass is planned.)
- **Imports recognise more figures.** The Caller's Box and ContraDB importers now cover
  more figure phrasings and rendered figures, so fewer moves fall through to
  unstructured custom text.
- **Caller's Companion imports read more date formats.** Composed and revised dates
  written in non-ISO or localized forms are now parsed instead of being dropped.

### Removed

- **Passphrase-encrypted backups (`.ccbackup`) have been dropped.** The short-lived
  encrypted-backup option introduced in beta.4 is gone; backups are now always a
  plain, human-readable `.json` file protected by an integrity checksum (see Added). A
  backup holds your own library and settings — no passwords, accounts, or third-party
  personal data — and it never leaves your device unless you export it, so the
  encryption option added real complexity for little practical benefit. Treat an
  exported backup like any personal document and store it somewhere you trust.
  **Breaking:** the app can no longer open existing `.ccbackup` files. If you have one,
  restore it with the beta.4 build and export a fresh `.json` backup.

### Fixed

- **The Perform card fits the screen again.** Auto-size now scales the card to fit
  windows smaller than full-screen, so the B1 section no longer clips on macOS.
- **Settings section titles are translated.** The navigation titles on Settings
  sub-screens now follow your chosen language instead of staying in English.

### Data / Migrations

- **Schema advances from version 14 to 15 — automatically and losslessly.** A single
  additive step runs on first launch: a new `walkthrough` text column on dances, empty
  for every existing dance. Nothing is back-filled or rewritten, and upgrading is a
  normal in-place install with no reinstall and no manual data steps. (Upgrading
  *directly from beta.1* still runs the one-time ocean-wave migration described in the
  beta.2 notes, and needs the Android reinstall below.)

### Known issues

- **Coming from beta.1? A one-time Android reinstall is still required.** beta.2
  unified the Android application identifier with Apple
  (`org.callerscompendium.compendiumApp`), so a beta.1 sideload cannot upgrade in
  place. **Export a backup (Settings ▸ General ▸ Export a backup), uninstall the old
  app, install this build, then restore.**
- **Have an older `.ccbackup` file?** The encrypted-backup format from beta.4 can no
  longer be opened. Restore it with the beta.4 build and export a fresh `.json` backup.
- **In-app update checks remain opt-in.** Automatic checks and the beta channel are off
  by default and enabled in Settings; when on, updates are signature-verified. Either
  way, you can always watch the GitHub Releases page for new betas.
- **Windows and Linux desktop builds are still unsigned** (see Platforms & install).

### What you can do today

- **Build your Collection.** Create, edit, and tag dances, organize them your way, and
  soft-delete/restore anything (with a 30-day Recently Deleted safety net). Group the
  list by category to hot-swap dances of a given "vibe" mid-evening.
- **Plan Programs.** Assemble a set with event date, a reusable venue, ordered slots,
  and alternates; track program status; duplicate a program to reuse a good set.
- **Perform.** Open a program — or a single dance — in a large-print, auto-sizing
  Perform view built for reading across a dim hall, mark dances as you call them, and
  tap out the tempo on a built-in visual metronome.
- **Author the way you teach.** Build figures with the structured editor, or turn on
  free-text entry to type them (with your own shorthands); record a step-by-step
  **Walkthrough** for each dance and let your **snippet library** pre-fill it from
  wording you have used before.
- **Import your existing library.** Bring dances in from a JSON backup, The Caller's
  Box, ContraDB, and Caller's Companion (`.USR`); import **programs** from Caller's
  Companion (`.USR`) and from **ContraDB** as well. Every import is reviewable and
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
version (`0.1.0-beta.5`), and the steps you took. For import problems, a small
sanitized sample of the file you were importing helps enormously.

### License

Caller's Compendium is free software under the **AGPL-3.0**, with an
[additional permission](../LICENSE-EXCEPTION.md)
that allows distribution through managed application marketplaces (Apple's App
Store, Google Play, and comparable stores) under those stores' required terms —
while the source stays fully AGPL-3.0 and every user keeps their rights to it. The
source is always available at <https://github.com/ibanner56/CallersCompendium>.
