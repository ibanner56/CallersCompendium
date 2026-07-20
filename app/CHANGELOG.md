# Changelog

All notable changes to Caller's Compendium (the app) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings use the semantic `major.minor.patch` version. Flutter's build
number — the `+build` segment of `version` in `app/pubspec.yaml` — is noted with
each release so store builds and tags can be traced back to an entry.

## [Unreleased]

## [0.1.0] - 2026-07-19

Flutter build: `0.1.0+1`.

This section covers the `0.1.0` line. **`v0.1.0-beta.2`** (this pre-release) builds
on **`v0.1.0-beta.1`** with wider import support, program sharing between devices,
signed macOS and iOS (TestFlight) builds, and a large round of figure-text display
refinements. The changes **since beta.1** are grouped first; the standing feature
overview and install notes follow.

### Added

- **Import a whole program from ContraDB.** Paste a `contradb.com/programs/N` link —
  or **search ContraDB programs by name** right in the app — to import the program
  and the dances it references, previewed and undoable like every other import.
- **Share a program together with its dances.** A new share action bundles a program
  and every dance it references into one self-contained file and hands it to your OS
  share sheet (AirDrop on macOS/iOS, the share intent elsewhere).
- **Open a shared program directly.** Caller's Compendium is now a share target:
  opening a shared bundle (AirDrop / "Open with" / share intent) launches the app,
  imports the program and its dances, and opens the program automatically.
- **A starter dance on first launch.** A fresh install now seeds a single dance —
  *The Baby Rose* by David Kaynor — so the collection is never empty to begin with.
  You can delete it; it is never re-added, and it is never seeded over existing data.
- **iOS builds are now available** to TestFlight testers (see Platforms & install);
  beta.1 had no iOS build.

### Changed

- **Figure text reads more naturally.** A large parity pass brought the on-screen
  wording of many figures in line with ContraDB's phrasing — silencing redundant
  defaults, dropping implied subjects, singularizing where appropriate, and adopting
  fuller wording for moves such as zig zag, slice, mad robin, revolving door, box
  circulate, hey, poussette, square through, the long-wave and ocean-wave families,
  and more. This is **display-only**: the canonical text used for search and
  duplicate detection is unchanged, so nothing re-indexes or re-dedupes.
- **The Caller's Box compound figures import faithfully.** A compound figure such as
  *revolving door* (a parent line with indented sub-steps) now imports as one figure
  with its definition intact, instead of being split into separate lines.
- **macOS builds are now signed and notarized** with an Apple Developer ID (Android
  builds remain signed). See Platforms & install for the updated first-launch steps.
- **Hardened the online-import and update paths.** Online imports (ContraDB and
  friends) now require `https` and bound how much data a response can pull in; the
  in-app update path likewise requires `https` manifest URLs and bounds its
  downloads. These are defense-in-depth limits on untrusted network input — the
  existing download-integrity (SHA-256) verification is unchanged.

### Fixed

- **Imported dances appear immediately.** The Collection list and its author filter
  now refresh the moment an import commits, instead of waiting for a manual reload or
  an app restart.
- **Dances with unfamiliar moves no longer crash the editor.** A figure whose move is
  unknown to the current build (authored in a newer version, or since renamed) now
  degrades gracefully and stays editable instead of throwing.

### Data / Migrations

- **Database schema 11 → 12 (automatic and lossless).** Stored *form an ocean wave*
  figures are rewritten onto the split moves *pass the ocean* / *form a short wave*
  to match the current taxonomy. **Your existing data is migrated in place** the
  first time you launch this build: a backup is taken before the migration runs, the
  database is integrity-checked at startup, and any figure that cannot be mapped is
  left untouched rather than dropped. No action is required on your part. (Note:
  downgrading back to beta.1 after this upgrade is not supported.)

### Known issues

- **Android beta testers must reinstall.** beta.2 unifies the Android application
  identifier with Apple (`org.callerscompendium.compendiumApp`). Because Android
  treats a changed application ID as a different app, a beta.1 sideload cannot upgrade
  in place — the new build installs alongside the old one and local data does **not**
  carry over automatically. **Before switching: export a backup (Settings ▸ General ▸
  Export a backup), uninstall the old app, install beta.2, then restore from that
  backup.**
- **In-app update checks remain minimal for beta.** Automatic checks and the beta
  channel are off by default and opt-in in Settings; watch the GitHub Releases page
  for new betas.
- **Windows and Linux desktop builds are still unsigned** (see Platforms & install).

### What you can do today

- **Build your Collection.** Create, edit, and tag dances, organize them your way,
  and soft-delete/restore anything (with a 30-day Recently Deleted safety net).
- **Plan Programs.** Assemble a set with event date, venue, ordered slots, and
  alternates; track program status; duplicate a program to reuse a good set.
- **Perform.** Open a program — or a single dance — in a large-print, auto-sizing
  Perform view built for reading across a dim hall, and mark dances as you call them.
- **Import your existing library.** Bring dances in from a JSON backup, The Caller's
  Box, ContraDB, and Caller's Companion (`.USR`); import **programs** from Caller's
  Companion (`.USR`) and now from **ContraDB** as well. Every import is reviewable and
  undoable with one tap.
- **Share between devices.** Send a program and its dances to another device, or open
  one that was shared with you.
- **Search the way you talk.** Dialect-aware search and filtering understands the
  terminology you use, whichever tradition you call in.
- **Keep your data yours.** Export a full backup to a single human-readable JSON file
  and restore it on another machine — no account, no cloud, no telemetry.

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
source is safe. Before a large import — or before upgrading across the schema change
noted above — you can export a backup from **Settings ▸ General ▸ Export a backup**
for extra peace of mind.

### Feedback

Please tell us what breaks or feels wrong:
<https://github.com/ibanner56/CallersCompendium/issues>. Include your platform, the
version (`0.1.0-beta.2`), and the steps you took. For import problems, a small
sanitized sample of the file you were importing helps enormously.

### License

Caller's Compendium is free software under the **AGPL-3.0**. The source is always
available at <https://github.com/ibanner56/CallersCompendium>.
