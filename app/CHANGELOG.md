# Changelog

All notable changes to Caller's Compendium (the app) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings use the semantic `major.minor.patch` version. Flutter's build
number — the `+build` segment of `version` in `app/pubspec.yaml` — is noted with
each release so store builds and tags can be traced back to an entry.

## [Unreleased]

### Changed

- **Dialect move wording templates** — optionally customize the display sentence
  for each taxonomy move in Settings → Dialect. Templates support computed move
  slots and are bounded and sanitized on import; canonical text, search, and
  deduplication remain unchanged.

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

- **Windows release artifacts are now signed via Azure Trusted Signing** when the release
  workflow's repository variables are configured: the portable bundle binaries
  and generated installer are signed through the WUS2 endpoint. Releases retain
  an unsigned fallback when that configuration is absent.

- **Settings → Program** — a new **Program** settings section now holds the
  program-facing preferences that previously lived under **General**: the reusable
  **Venues** toggle and venue manager, the programming-matrix **Flag exact beat
  overlap only** toggle, the **Auto-size Perform cards** toggle, and the two
  **Calling history** toggles. Nothing about what these settings do changed — only
  where they live. (issue #935)

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
  removed columns (keeping your renames) or restore the shipped defaults behind a
  confirm. (issue #935)

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

## [0.1.0] - 2026-08-14

Flutter build: `0.1.0+1`.

This section covers the `0.1.0` line. **`v0.1.0-beta.8`** (this pre-release) builds
on **`v0.1.0-beta.7`** and covers the latest improvements since that release.
The changes since beta.7 are grouped first; the standing feature overview and
install notes follow.

### Added

- **`chain` now carries a `hand` param** (left/right), matching ContraDB's
  model. Importing "ladles left-hand chain" (ContraDB's own rendering) or
  "Men do a right-hand ladies chain to partner" (TCB-style phrasing) no
  longer falls back to a custom figure; a hand that agrees with the
  chaining role's implicit side (ladies → right, gents → left) renders
  silently, exactly as before, while a stated hand that contradicts the
  role still renders, hyphenated. Existing chains stored before this
  release are updated in place on first launch so structured search
  (Advanced ▸ has figure ▸ chain ▸ hand) finds them too, regardless of
  when they were imported. (#976)
- **Replace a program slot's dance in place, from the "Edit dance slot"
  dialog.** Previously the only way to swap a dance was to add the
  replacement, drag it into position, and delete the old one; the dialog now
  offers a **Replace…** button that opens the dance picker and swaps the
  slot's dance, keeping its caller note, guest caller, planned minutes, alt
  flag, and mark-performed status exactly as they were. (#964)
- A note slot in the program builder (e.g. one left behind when a title-list
  import couldn't find a matching dance) can now be turned into a real dance
  in place: its overflow menu offers **Create a dance from this**, which opens
  the dance editor pre-filled from the note and links the slot to the new
  dance once you save. (#881)
- **Both the Collection and Programs lists now offer a "Last used" option** for
  their default sort in Settings ▸ Defaults, alongside the existing fixed
  choices. With "Last used" selected, the sort key **and** direction you pick
  while browsing survive closing and reopening the app; with a fixed sort
  selected, behavior is unchanged from before. The Programs list previously
  had no default-sort setting at all. (#895)
- **Pasted-program title-list import falls back to ContraDB.** "Resolve
  unmatched online" on the pasted-title-list program import now tries The
  Caller's Box first and, for any title Caller's Box cannot resolve
  confidently, ContraDB next — a title that only lives in ContraDB no longer
  has to be imported by hand afterwards. A title either source finds several
  exact matches for (and neither source resolves it confidently) is now
  offered to you to pick from, instead of always silently becoming a note.
- **The programming matrix now disambiguates allemande/chain by role and
  swing by its balance/meltdown prefix**, mirroring the existing swing/hey
  role/length split. Allemande and chain each split into per-role columns
  (partner/neighbor/larks/robins/shadow/…, shown only when a dance actually
  uses that role); swing additionally splits each role into a plain column
  plus present-only "bal & swing" / "meltdown swing" sub-columns. A
  `meltdown_swing` figure now shows up under its role's `swing` column
  (e.g. "partner meltdown swing") instead of a separate, unlabelled column.
  This also fixes the same-figure-same-phrase collision check, which
  previously flagged e.g. a lark allemande next to a robin allemande, or a
  plain swing next to a balance-and-swing, as the same figure repeating.
  (#933)
- **New Settings ▸ General ▸ Programs setting: "Flag exact beat overlap
  only."** Controls how the programming matrix's alert marker decides that a
  repeated move in two back-to-back dances is worth a second look — see
  **Changed** below for what the new default does differently. Turning it off
  restores the matrix's previous same-phrase behavior. (#962)

### Changed

- **The programming matrix's same-figure alert now defaults to flagging exact
  beat overlap, not merely the same named phrase.** Previously, a move
  repeating in two back-to-back dances was flagged whenever it merely
  *started* in the same phrase bucket (A1, A2, B1, B2…) — even when the two
  occurrences' beats didn't actually overlap (e.g. one dance's balance at
  beats 32–39 and the next dance's at beats 40–47, both in bucket B1 but never
  overlapping). The matrix — and its PDF export, which always uses the same
  legend — now flags a repeat only when the beats genuinely overlap between
  the two dances. This changes what existing programs' matrices flag; turn
  off the new "Flag exact beat overlap only" setting in Settings ▸ General ▸
  Programs to restore the previous same-phrase behavior. (#962)
- **The diagnostic log now captures errors you see on screen, not just
  crashes.** Previously it recorded only outright application crashes; an
  error that was caught and shown to you as a snackbar or an inline message
  (a failed import, a blocked delete, a failed backup) never reached it, so
  exporting logs after one of those could turn up nothing. It's still fully
  offline — nothing is sent anywhere unless you explicitly export it from
  Settings ▸ Diagnostics. (#963)

### Removed

- **Support for collections last opened by beta.5 or earlier.** Caller's
  Compendium will no longer open a collection file that old; it stops rather
  than upgrading it halfway, which would leave the file quietly incomplete.
  Every tester is on beta.6 or later, so in practice no collection is
  affected. If you do still have a pre-beta.6 file, open it once with beta.6
  — or any later release you already have — and it will be upgraded normally,
  after which this release can open it. (This raises the floor set in the
  previous release, which retired support for beta.1-or-earlier collections.)

### Fixed

- **A dance's detail view now updates while you are looking at it.** Editing a
  dance from somewhere else — a batch tag or level change in the Collection, an
  import, a re-parse, or an edit made on another screen — left the open dance
  card showing the pre-edit title, authors, tags, custom fields, sources and
  provenance until you navigated away and came back. It now follows the
  database directly, so those changes appear as they happen. Its **Calling
  history** already worked this way and is unchanged; adding the dance to a
  program still updates that section alone rather than reloading the whole
  card. (#768)
- **The dance editor's author, tag, related-dance and published-source pickers
  now update while the editor is open**, the same way the read-only dance
  detail view already does. A choreographer renamed, a tag added, or another
  dance retitled elsewhere previously left the editor's pickers showing
  stale options until you closed and reopened it; they now follow the
  database directly. Nothing you are actively editing is affected — your
  draft, undo history and autosave are untouched by this. (#768)
- Rotating a tablet across the Collection/Programs split-pane breakpoint
  (900px) no longer resets the list's current sort, search text, filters, or
  scroll position. Previously the list was rebuilt from scratch on that
  transition, discarding all of it. (#895)
- **Renaming or deleting a venue now updates every place its name is shown.**
  The programs list, a program's summary, the program editor's linked-venue
  note, and a dance's calling history all kept showing the old name until you
  navigated away and back — the venue manager itself updated, but nothing that
  merely *displayed* a venue did. (#944)
- The tag and author/choreographer picker on phones no longer closes after
  every other addition. Adding entries in a row now keeps the picker open
  each time until you save or close it yourself. Fixes an issue where a
  keyboard/screen-reader user who dismissed the picker without picking
  anything also had to navigate past the field twice to reopen it. (#894)
- Settings ▸ Defaults ▸ Dance-authoring defaults now renders in the order
  documented in the user guide. Two prior feature additions had each inserted
  a new tile near the top of the list instead of at its documented
  position — most visibly, splitting **Free-text entry** from **Figure
  shorthands**, which are contextually dependent. (#942)
- **More ContraDB figures now import as structured moves instead of custom
  text.** A dance that uses an ordinal dancer set (`3rd neighbors`,
  `4th neighbors`, `2nd shadows`) previously dropped every plain `neighbors`/
  `shadows` figure in that same dance to custom too, because ContraDB
  silently renders those as `1st neighbors`/`2nd neighbors`/`1st shadows` for
  the whole dance once any figure uses the ordinal — the import now
  recognises all six forms. Lines like "dance out while ... dance in to a
  long wave in the center" (previously split into a custom half plus a
  structured half) now import as one structured figure. And "trade by
  left/right [shoulder]" — the MWSD "Trade By" call — now imports as a
  pass-by instead of custom text. (#945)

### Data / Migrations

- **Taxonomy advances from version 27 to 28.** This documentary marker reflects
  updated recognition and matching behavior; it is not read at runtime and does
  not itself rewrite the database.

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
