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

### Fixed

- **macOS shutdown** — quitting from the Dock, menu, or Command-Q now waits for
  the local database to close before macOS tears down the app.
  
- **Windows shutdown** — closing the app now completes Flutter's native window
  teardown before the runner releases COM resources, preventing a crash on exit.

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
