# Changelog

All notable changes to Caller's Compendium (the app) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings use the semantic `major.minor.patch` version. Flutter's build
number — the `+build` segment of `version` in `app/pubspec.yaml` — is noted with
each release so store builds and tags can be traced back to an entry.

## [Unreleased]

## [0.1.0] - 2026-07-20

Flutter build: `0.1.0+1`.

This section covers the `0.1.0` line. **`v0.1.0-beta.3`** (this pre-release) builds
on **`v0.1.0-beta.2`** with a broad round of caller-facing features — new Perform
and analysis tools, richer ContraDB and browser-share importing, and a batch of
quality-of-life refinements to browsing, editing, and sharing. The changes **since
beta.2** are grouped first; the standing feature overview and install notes follow.

### Added

- **Tap-tempo visual metronome in Perform.** Tap out the beat on a large target and
  Perform shows a steady visual pulse and BPM you can follow or hold up to a band.
  It is opt-in per session, audio-free, and nothing is stored.
- **First/second-half calling stats for a dance.** The dance detail screen now shows
  how often a dance has been called in the first vs. second half of a program,
  including how many times it opened a first half or closed the evening — aggregated
  across every program that includes it.
- **First/second-half markers for programs.** A matrix dance now carries an
  accessible badge showing whether it falls in the first or second half of the set,
  derived from the program's first "Break" slot — no schema change, no retyping.
- **"Called ×N" count on the dance card.** Each dance in the Collection now shows how
  many times you've called it, matching the calling-history rule you've chosen in
  Settings (all occurrences, or performed-only).
- **Ascending/descending sort toggle.** Both the Collection and Programs lists gain an
  up/down direction toggle beside the sort menu — so, for example, Programs ▸ Event
  date can now show the most recent first. Each sort keeps its previous default, so
  nothing changes until you flip it.
- **Import ContraDB programs shared from your browser.** Share a `contradb.com`
  program link from Safari (iOS) or your browser (Android) and Caller's Compendium
  opens the import screen pre-filled and fetching, ready for you to review before
  committing.
- **Rotation-gated figures from The Caller's Box import with structure.** TCB
  "gate"-style rotation figures are now modeled as a first-class figure — who turns,
  which direction, how far, over how many beats, and the resulting facing — instead of
  being flattened into unstructured text.
- **User-editable per-formation label colours.** Give each formation its own highlight
  colour (e.g. Becket CW yellow, Becket CCW pink) from Appearance ▸ Formation colours;
  the tint appears on dance cards, dance detail, and the Perform header, with an
  automatically readable (WCAG-AA) text colour.
- **Opt-in decimal turn display.** A new display preference renders turn amounts as
  decimals (`0.75`, `1.5`) instead of fraction glyphs (`¾`, `1½`). Default stays
  fractions; the spoken/screen-reader wording is unaffected.
- **Inline emphasis for your own figure text.** In your figure notes and custom-figure
  text you can now mark words bold (`*word*`) or underlined (`_word_`); Perform renders
  the emphasis so you can stress the words you'll say. Use `\` to type a literal `*` or
  `_`. The markup is display-only — it changes no stored, searched, or exported text.

### Changed

- **Swiping a list row now reveals a Delete button instead of deleting.** On the
  Collection and Programs lists, a swipe left uncovers a Delete button and *tapping it*
  is the confirmation — a stray swipe can no longer delete a row on its own. Delete
  still routes through the same soft-delete and Undo snackbar.
- **The author filter is now a searchable multi-select.** The Collection's Author facet
  replaces its long list of per-author chips with a type-to-filter picker: search a
  name, add it as a removable chip, and combine several — much tidier as your
  collection of choreographers grows.
- **Smarter ContraDB program import.** Importing a ContraDB program now fills the
  caller from the program's contributor (falling back to your default caller) and
  best-effort detects the event date from the program title, shown with edit/clear
  controls and a "detected from title" hint so a wrong guess is easy to correct.
- **Swipe down to dismiss the keyboard.** Dragging down over the dance editor, program
  editor, Collection search, and Settings text fields now dismisses the on-screen
  keyboard on phones and tablets, matching the platform-native gesture.

### Fixed

- **Sharing a program on macOS no longer fails.** A program-with-dances share could
  fail on macOS with a generic "Couldn't share this program"; the bundle is now
  written correctly before it is handed to the share sheet.
- **AirDrop'd shares reliably open in Caller's Compendium.** Shared bundles now use a
  dedicated `.ccshare` type that macOS and iOS route back to the app for import,
  instead of silently saving the file with nothing offered to import.
- **The User Guide header no longer slides under the status bar.** On iPhone/iPad the
  in-app User Guide now reserves the top safe-area inset, so its header sits below the
  status bar and Dynamic Island like every other screen.
- **Collapsed filter sections stay collapsed.** Collapsing a section in the Collection
  filter panel and then applying a filter no longer re-expands it.
- **Imported program dances now count in calling history.** Marking an imported program
  as performed now stamps each of its dance slots, so those dances correctly appear in
  each dance's calling history and half-stats (previously they could be missed).

### Data / Migrations

- **No database schema change since beta.2.** The database schema stays at version 12,
  so upgrading from beta.2 touches none of your stored data — every change above is
  display- or behavior-only. (Upgrading *directly from beta.1* still runs the one-time,
  automatic, lossless ocean-wave migration described in the beta.2 notes.)

### Known issues

- **Coming from beta.1? A one-time Android reinstall is still required.** beta.2
  unified the Android application identifier with Apple
  (`org.callerscompendium.compendiumApp`), so a beta.1 sideload cannot upgrade in
  place. **Export a backup (Settings ▸ General ▸ Export a backup), uninstall the old
  app, install this build, then restore.** Upgrading from **beta.2 to beta.3 is a
  normal in-place install** — no reinstall and no data steps needed.
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
  Perform view built for reading across a dim hall, mark dances as you call them, and
  tap out the tempo on a built-in visual metronome.
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
source is safe. Before a large import — or any upgrade — you can export a backup from
**Settings ▸ General ▸ Export a backup** for extra peace of mind.

### Feedback

Please tell us what breaks or feels wrong:
<https://github.com/ibanner56/CallersCompendium/issues>. Include your platform, the
version (`0.1.0-beta.3`), and the steps you took. For import problems, a small
sanitized sample of the file you were importing helps enormously.

### License

Caller's Compendium is free software under the **AGPL-3.0**. The source is always
available at <https://github.com/ibanner56/CallersCompendium>.
