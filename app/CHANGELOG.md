# Changelog

All notable changes to Caller's Compendium (the app) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings use the semantic `major.minor.patch` version. Flutter's build
number — the `+build` segment of `version` in `app/pubspec.yaml` — is noted with
each release so store builds and tags can be traced back to an entry.

## [Unreleased]

### Changed

- **Android application identifier unified with Apple.** The Android app now uses
  the application ID `org.callerscompendium.compendiumApp` (previously
  `org.callerscompendium.compendium_app`), matching the Apple/iOS/macOS bundle
  identifier. The Linux GTK application ID was updated to match as well. (The Dart
  package name `compendium_app` is unchanged — this only affects the OS-level
  application identifier.)

### Known issues

- **Android beta testers must reinstall.** Because Android treats a changed
  application ID as a different app, testers who sideloaded **v0.1.0-beta.1**
  cannot upgrade in place: the new build installs alongside the old one and local
  app data does **not** carry over automatically. Before switching, **export a
  backup first (Settings ▸ General ▸ Export a backup), then uninstall the old app,
  install the new one, and restore from that backup.** In-place upgrade and
  automatic data carry-over are not possible across this identifier change.

## [0.1.0] - 2026-07-17

Flutter build: `0.1.0+1`.

Caller's Compendium is a local-first, cross-platform organizer for contra dance
callers. This is the **first public beta** — the core of the app is here and
working, and we want real callers to put it through its paces before a stable 1.0.

### What you can do today

- **Build your Collection.** Create, edit, and tag dances, organize them your way,
  and soft-delete/restore anything (with a 30-day Recently Deleted safety net).
- **Plan Programs.** Assemble a set with event date, venue, ordered slots, and
  alternates; track program status; duplicate a program to reuse a good set.
- **Perform.** Open a program — or a single dance — in a large-print, auto-sizing
  Perform view built for reading across a dim hall, and mark dances as you call them.
- **Import your existing library.** Bring dances in from a JSON backup, The Caller's
  Box, ContraDB, and Caller's Companion (`.USR`) — every import is reviewable and
  undoable with one tap.
- **Search the way you talk.** Dialect-aware search and filtering understands the
  terminology you use, whichever tradition you call in.
- **Keep your data yours.** Export a full backup to a single human-readable JSON file
  and restore it on another machine — no account, no cloud, no telemetry.

### Platforms & install

This beta provides:

- **Android** — a signed universal `.apk`. Install it directly (sideload); you may
  need to allow "install unknown apps" for your browser or file manager. It is **not**
  on the Play Store yet.
- **Linux** (x64), **macOS** (universal), and **Windows** (x64) — desktop builds.

**Desktop builds are unsigned for this beta**, so your OS will warn you before it runs:

- macOS: right-click the app → **Open**, then confirm (Gatekeeper).
- Windows: **More info → Run anyway** on the SmartScreen prompt.
- Linux: the **`.tar.gz`** is the no-setup path — extract and run. The `.AppImage`
  needs the **FUSE 2** runtime (`libfuse.so.2`) — package `libfuse2` on Debian/Ubuntu,
  `fuse-libs` on Fedora — which some recent distros don't preinstall; install it, or
  launch with `./CallersCompendium-*.AppImage --appimage-extract-and-run`.

You can verify any download against the published `SHA256SUMS` if you want
belt-and-suspenders.

### Known limitations

- **Unsigned desktop builds** (see above) — expected for beta; code signing comes later.
- **Program import is Caller's Companion only.** JSON, The Caller's Box, and ContraDB
  imports bring in **dances**; only Caller's Companion (`.USR`) also imports **programs**.
  (The Caller's Box has no programs to import; ContraDB program import is planned —
  see [issue #291](https://github.com/ibanner56/CallersCompendium/issues/291).)
- **In-app update checks are minimal for beta.** Automatic checks and the beta channel
  are **off by default** and must be opted into in Settings; even then, the in-app
  checker may not surface every later 0.1.0 beta. Watch the GitHub Releases page for
  new betas.
- **No iOS build** in this beta.

### Your data & safety

Everything lives locally on your device. There is no telemetry and nothing is sent
anywhere. Imports are previewed before they commit and are undoable, so trying a new
source is safe. Before a large import you can export a backup from **Settings ▸
General ▸ Export backup** for extra peace of mind.

### Feedback

Please tell us what breaks or feels wrong:
<https://github.com/ibanner56/CallersCompendium/issues>. Include your platform, the
version (`0.1.0-beta.1`), and the steps you took. For import problems, a small
sanitized sample of the file you were importing helps enormously.

### License

Caller's Compendium is free software under the **AGPL-3.0**. The source is always
available at <https://github.com/ibanner56/CallersCompendium>.
