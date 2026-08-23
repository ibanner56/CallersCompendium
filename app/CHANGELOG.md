# Changelog

All notable changes to Caller's Compendium (the app) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings use the semantic `major.minor.patch` version. Flutter's build
number — the `+build` segment of `version` in `app/pubspec.yaml` — is noted with
each release so store builds and tags can be traced back to an entry.

## [Unreleased]

### Fixed

- **Database reset recovery** — resetting an unsupported database now reloads
  the app in-process with a fresh runtime instead of leaving the recovery dialog
  visible until the application is reopened.
  
### Added

- **Experimental settings** — a new section provides a home for features that
  are still in development.

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

### Known issues

- **Coming from beta.1? A one-time Android reinstall is still required.** beta.2
  unified the Android application identifier with Apple
  (`org.callerscompendium.compendiumApp`), so a beta.1 sideload cannot upgrade in
  place. **Export a backup (Settings ▸ General ▸ Export a backup), uninstall the old
  app, install this build, then restore.**
- **Have an older `.ccbackup` file?** The encrypted-backup format from beta.4 can no
  longer be opened. Restore it with the beta.4 build and export a fresh `.json` backup.
- **Check your gates.** Since beta.6, gates no longer invent an ending facing the
  source never stated. If you recorded gates before beta.6, some may still be
  showing a facing that was wrong — worth a look.
- **In-app update checks remain opt-in.** Automatic checks and the beta channel are off
  by default and enabled in Settings; when on, updates are signature-verified. Either
  way, you can always watch the GitHub Releases page for new betas.
- **Windows and Linux desktop builds are still unsigned** (see Platforms & install).
- **The user guide has no screenshots yet.** The written guides are current; the
  images pass is still to come.

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
  Box, ContraDB, and Caller's Companion (`.USR`) — with the choreography, your
  venues, related-dance links and call-button shorthands coming across too; import
  **programs** from Caller's Companion (`.USR`) and from **ContraDB** as well. Every
  import is reviewable and undoable with one tap, and near-duplicates are flagged
  before they land.
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
version (`0.1.0-beta.6`), and the steps you took. For import problems, a small
sanitized sample of the file you were importing helps enormously.

### License

Caller's Compendium is free software under the **AGPL-3.0**, with an
[additional permission](https://github.com/ibanner56/CallersCompendium/blob/main/LICENSE-EXCEPTION.md)
that allows distribution through managed application marketplaces (Apple's App
Store, Google Play, and comparable stores) under those stores' required terms —
while the source stays fully AGPL-3.0 and every user keeps their rights to it. The
source is always available at <https://github.com/ibanner56/CallersCompendium>.
