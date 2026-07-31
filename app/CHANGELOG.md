# Changelog

All notable changes to Caller's Compendium (the app) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Version headings use the semantic `major.minor.patch` version. Flutter's build
number — the `+build` segment of `version` in `app/pubspec.yaml` — is noted with
each release so store builds and tags can be traced back to an entry.

## [Unreleased]

### Added

- **First day of week is live.** The Language & region settings dropdown for
  first day of week (System default / Sunday / Monday / Saturday) is no
  longer disabled — it now has a real consumer, the Programs list's "this
  week" header strip, which reorders its weekday columns to match your
  choice (falling back to your app language's convention for System
  default). Closes #636.
- **Hide columns you don't need in the program matrix, with a one-tap
  reset.** Each move column in the wide grid now has a small eye glyph — always
  visible (not hover-only, so it works on touch and for keyboard/AT users too)
  and focusable — that hides that column from view. A "Show all columns"
  button next to the PDF-export button clears every hidden column at once; it's
  disabled whenever nothing is hidden. Hiding is a session-only view
  preference (it resets whenever you reopen the program) and only affects
  what's on screen — the PDF/print export always includes every column,
  hidden or not. The pinned Formation column isn't hideable, since it's part
  of each dance's identity rather than a move. Closes #669.
- **The program matrix now shows each dance's formation.** A new pinned
  "Formation" column sits next to the dance title in the wide grid — always
  visible while scrolling through moves, so callers can spot too many
  non-improper formations (Becket, triple minor, 4x4, …) stacking up in a
  row. The compact (phone-width) view announces the formation on every dance
  chip for screen readers, and shows it visually only for the atypical,
  non-duple-improper case, keeping the common-case chip uncluttered.
  Deliberately plain (icon + text, no colour tint) — the issue chose a
  dedicated column over colour-coding formations. The programming-matrix PDF
  export gets the same pinned formation column, so the on-screen and printed
  matrices stay in sync. Closes #663.
- **Comma-separated dates and single-digit days in your custom date format.**
  The custom date-format pattern (Settings ▸ Language & region ▸ Date format ▸
  Custom) now accepts a comma as a separator and a single, non-zero-padded `d`
  day token alongside the existing `dd` — so `MMMM d, yyyy` reads and renders
  the natural "June 3, 2026" (previously only "June 03 2026", via `dd`, was
  accepted). `d MMMM yyyy` similarly renders "3 June 2026". The comma also
  works when reading the same layout from a ContraDB program title on import.
  As before, the pattern stays an untrusted, strictly allowlisted input —
  only these two well-scoped additions were made, no arbitrary format strings
  are accepted, and every other rule (length cap, one field of each kind,
  bounded ReDoS-safe matching, 1900–2100 calendar validation) is unchanged.
  Follow-up to the written-out month support from the previous release.
  Closes #668.
- **"Meanwhile" (simultaneous) figures now display as "A while B" (#594).**
  The dance detail figure table, Perform view, plain-text export, and PDF
  export all show a simultaneity pair together on one row/line, joined by
  "while", with the shared beat count shown once — never split into two
  rows/lines and never double-counted.
- **Importing a simultaneous-action line now keeps both sides instead of one
  opaque blob (#591).** The Caller's Box `||` operator (e.g. "Women allemande
  left 1 || Men orbit clockwise ½") and ContraDB free-text joined by
  "while"/"whiles" (e.g. "ladles allemande left 1½ around while the
  gentlespoons orbit clockwise ½ around") now import as a "meanwhile"
  container with each side parsed independently, instead of the whole line
  becoming a single unstructured custom figure. A side that isn't recognized
  still imports safely as its own custom sub-figure — nothing is dropped or
  invented — and the shared beat count is counted once. Re-syncing an
  existing dance upgrades any older `||`/"while" line the same way. Part of
  #572.
- **Author simultaneous ("meanwhile") figures in the figure editor.** A figure
  row's overflow menu now offers **Group with next as meanwhile**, merging it
  with the row right after into one editable group of 2–6 concurrent sides —
  each authored with the same move-picker/param/note editor as any other
  figure, plus a single **shared beats** field for the whole group (a side's
  own beats is display-only and hidden to avoid a confusing dead control).
  Add or remove a side with clear inline controls; removing down to 1 side
  automatically collapses the group back to a plain figure. The group is
  always **flat** — a side can never itself become a meanwhile group — and
  the 2–6 side range is enforced right in the editor with a clear message at
  the cap, not just a thrown error. Undo/redo and autosave carry a group
  through losslessly. Builds on the `meanwhile` model container (#590).
  (#593, part of #572)

- **Write out the month in your custom date format.** The custom date-format
  pattern (Settings ▸ Language & region ▸ Date format ▸ Custom) now understands
  written-out month tokens alongside the numeric ones: `MMM` renders a short
  month name (e.g. `dd MMM yyyy` → `03 Jun 2026`) and `MMMM` a full one
  (e.g. `MMMM dd yyyy` → `June 03 2026`). Month names are localized — they
  reuse the app's existing translated short names, with English full names where
  a translation isn't available yet. The token legend under the field documents
  the new tokens, and the live example plus the inline "unrecognized pattern"
  warning work with them too. When a ContraDB program title contains a written
  month (e.g. `Spring Fling — 12 May 2026`), a custom pattern that uses `MMM`/
  `MMMM` now reads that date on import. As before, the pattern is untrusted
  input: it is length-capped, month names are matched against a fixed allowlist
  (no catastrophic-backtracking risk), and anything unrecognized simply falls
  back to the system default. Follow-up to the custom date format from the
  previous release.

- **Partial heys can name the dancer you run until you meet.** When a hey is set
  to **less than half** or **between half and full**, the editor now offers a
  **meet target** — the pair you weave until you meet (e.g. partners, neighbors,
  larks/robins). The dance then reads "…until neighbors meet" instead of the
  generic "…until someone meets". Leave it **unspecified** (the default) and
  everything renders exactly as before; the field only appears for those two
  partial lengths, and clears itself if you switch the hey back to a half or full
  hey. The target is an allow-listed set of pairs, so imported or hand-edited data
  can never inject unexpected text. (#576)
- **See which ContraDB programs you've already imported.** When you search or
  preview a program in **Import program ▸ From ContraDB**, rows you've likely
  already brought in are marked: a firm **Imported** badge (with the import date
  in its tooltip) when the exact ContraDB program was imported before, and a
  softer **Possibly imported** badge when a program with the same title already
  exists but isn't linked to that event. Each badge pairs an icon with a label so
  colour is never the only signal, and the same hint shows atop the preview.
  Re-importing is still always allowed. ContraDB program imports now record the
  source program id so the firm match works; programs imported earlier (with no
  stored id) fall back to the title-only hint. ContraDB titles and ids are treated
  as untrusted input — normalized, length-capped, and matched with ReDoS-safe
  comparisons. (#586)
- **Custom date format.** The **Settings ▸ Language & region ▸ Date format**
  picker gains a **Custom…** option that reveals a text box for your own pattern
  (e.g. `MM.DD.YY`), with an always-visible token legend (`yyyy`/`yy` = year,
  `MM` = month, `dd` = day; separators `-` `/` `.` or space), a live example, and
  an inline warning when the pattern isn't recognized. A valid custom pattern
  renders program event dates and helps disambiguate numeric dates when
  auto-detecting the event date from a ContraDB program title. The pattern is
  treated as untrusted input — length-capped, allowlist-validated, and
  ReDoS-safe — and any empty, unrecognized, or corrupted value falls back to the
  system default everywhere until it's corrected. (#584)
- **Scope calling history to your own programs.** A new **General ▸ Calling
  history** setting, **Track calling history for all callers** (off by
  default), lets a caller who has set a *default caller for new programs*
  (**Settings ▸ Defaults**) count only the programs **they** led toward each
  dance's calling history and "called ×N" totals. With the toggle off and a
  default caller set, history and counts include only programs whose host
  caller matches that name (ignoring surrounding spaces and letter case);
  turning it on — or leaving the default caller blank — tracks every program
  that contains the dance, exactly as before. The filter matches on the
  program's host caller (per-slot guest callers are not considered) and applies
  on top of the existing *Require "mark performed" for calling history* gate
  (both must pass). (#583)
- **Program matrix flags same-figure-same-phrase repeats between neighbouring
  dances.** In the Matrix tab, a cell now shows an alert marker instead of the
  plain check when the same move lands in the *same phrase* (A1/A2/B1/B2…) in
  two dances that run **back-to-back** in the program — the kind of adjacent
  repeat that can make two dances feel samey on the floor. Only the two
  colliding cells are flagged; repeats that are non-adjacent or in a different
  phrase are left alone. The alert carries into the landscape **PDF matrix
  export** and its legend, and — like the existing star/flag/check markers — is
  conveyed with a distinct shape plus a localized screen-reader announcement,
  never colour alone (WCAG 1.4.1). (#582)

### Changed

- **"Allemande orbit" figures are now stored as two concurrent moves.** The
  combined "one couple allemandes while the other orbits" figure is no longer a
  single fused move — it's now an allemande and a first-class *orbit* happening
  at the same time (a "meanwhile"), matching how callers actually notate the
  two sides. Existing collections are upgraded automatically on first launch: a
  one-time database migration rewrites any stored allemande-orbit figures into
  the new form, deriving each side faithfully from the saved values, so no
  dance loses its choreography. (#295)

### Removed

- **The automatic "can carry progression" hint is gone from the figure
  editor.** Swing and allemande no longer show an info-icon/tooltip nudge
  beside the Progression toggle. The manual **Progression** toggle is
  unaffected — you can still flag any figure as the progression yourself.
  The underlying `progressionCapable` taxonomy flag (non-serialized static
  metadata) was removed along with it. Closes #551.

### Security

- **ContraDB dance and program imports are now restricted to the official
  ContraDB host.** `buildContraDbUrl` and `buildContraDbProgramUrl` used to
  preserve whatever host a pasted URL carried, verbatim — trusting any public
  host as "ContraDB" so long as the path looked like `/dances/N` or
  `/programs/N`. Both builders now enforce the same host allowlist
  (`contradb.com` / `www.contradb.com`) already used to auto-detect a pasted
  ContraDB link, rejecting any other host before a URL is even built, and now
  require `https` (a bare `http://` link is rejected as an insecure scheme).
  This mirrors the Caller's Box host allowlist from the previous release
  (#621) and intentionally drops self-hosted-ContraDB-mirror support — the
  existing fetch-time SSRF guard (blocking loopback/private-IP targets)
  remains independent defense-in-depth regardless of host. (#667)

### Fixed

- **Program import no longer silently duplicates a dance already in your
  collection.** Multi-author strings (choreographer fields, Caller's Box
  author arrays, Caller's Companion "by" lines) are now tokenized
  consistently across every import source (see the `compendium_core`
  changelog), so an already-owned dance's author set reliably overlaps on
  re-import instead of scoring a spurious zero. On top of that, the
  non-interactive program-import path (plaintext program import and the
  ContraDB program import's Caller's Box fallback) now consults the local
  dedupe index before importing an online-resolved dance: a confident
  local-duplicate match (exact title + overlapping authors) is skipped
  rather than force-imported, leaving the line on its existing note-slot
  fallback instead of creating a silent duplicate. The interactive
  search-and-tap-Import flow is unchanged. (#685)

- **Off-screen program-matrix columns are now discoverable, and redundant
  column-header tooltips are gone.** The matrix's pinned column-header strip
  gave no visual cue when a program had more moves than fit on screen — a
  hey or half-hey column sitting just off the right edge could go completely
  unnoticed, requiring the caller to already know to scroll sideways. The
  header strip now shows a gradient-fade-plus-chevron edge cue on whichever
  side(s) still have hidden columns, purely decorative and driven by the same
  scroll position as the body (which already has a visible scrollbar);
  presence is conveyed with shape and gradient together, never colour alone
  (WCAG 1.4.1). Separately, every column header's hover tooltip — which just
  repeated the visible heading text — has been removed as pure noise; the
  header's accessible name for screen readers came from an independent
  semantics label all along, so nothing is lost for assistive tech. (#662)

- **The program-matrix PDF export's ★ (program-debut), ▸ (dance's-first-figure),
  and ✓ (present) markers now actually render, instead of silently rendering
  blank.** The bundled Roboto font used for PDF export doesn't include those
  three glyphs, and the `pdf` package silently drops any glyph missing from
  the active font — so exported/printed matrices lost their legend and cell
  markers entirely, even though the on-screen matrix (which uses Material
  icons, not these Unicode glyphs) looked correct. The alert marker (`‼`,
  #582) was unaffected, since Roboto does include it. Rather than swap the
  documented `★`/`▸`/`✓` marks for different characters, PDF export now
  registers a small, static (non-variable, consistent with #614's
  static-font decision), OFL-licensed fallback font — a hand-subsetted
  instance of Google's Noto Sans Symbols 2, trimmed to just these three
  glyphs — as a `fontFallback`, scoped only to the matrix's marker/legend
  text. (#633)

- **A dance or program's autosave draft no longer resurrects itself after a
  save, delete, or discard.** The debounced autosave and the draft cleanup it
  triggers could race: if a save/discard/delete ran while an autosave write to
  the settings store was still in flight, the write could land *after* the
  cleanup removed the draft, silently recreating stale content that would then
  prompt "restore your draft?" the next time you opened the editor — even
  though you'd already saved or intentionally discarded it. Cleanup now waits
  for any in-flight autosave write to finish before removing the draft, so the
  removal always wins. (#616)

- **Figure notes now follow your active dialect.** A figure's note is
  free text alongside calling notes and the walkthrough, but it was the only
  one of those fields displayed verbatim instead of through the same
  dialect-aware renderer. A note authored with a role token (e.g. "role2s
  scoop them up") now reads in your active dialect's terms (e.g. "robins
  scoop them up") everywhere a figure note is shown — the figure table, the
  large-print Perform view, and the exported PDF. (#619)

- **Your typed dialect terms are now stored dialect-agnostically and re-render
  for every reader.** The design promises that all free text passes through a
  single canonicalization chokepoint before it's saved, so prose is stored in
  canonical terms and shown in each reader's active dialect — but for hand-typed
  dance prose (the hook, calling notes, and walkthrough) that step wasn't wired:
  your terms were saved verbatim, so a reader on another dialect saw your words
  unchanged and free-text search wasn't dialect-agnostic. Now those fields are
  canonicalized on save and rendered under the active dialect on read (the hook
  was also the last of the three still shown verbatim on the detail screen — now
  fixed), so switching dialects re-renders them and search over prose ignores
  dialect. A one-time migration canonicalizes prose you already typed as a beta
  user; it's conservative and roles-only, so only exact role terms are rewritten
  and all other prose is preserved exactly. (Program notes and free-text program
  slots are a separate, still-verbatim case tracked as a follow-up.) (#613)

- **A backup restore that saves your content but can't apply your settings now
  says so — and lets you retry.** Restoring writes two independent stores that
  can't share one transaction: your core content (dances, programs, everything
  in the database) commits first, then your saved settings (dialects, themes,
  preferences) are applied separately. If that second step genuinely failed —
  the settings store was momentarily unavailable — the app used to report a
  blanket "couldn't restore the backup," even though your dances and programs
  had in fact been restored. Now that case is handled explicitly: the restored
  content is kept (never rolled back or lost), and you get a clear message that
  your content is safe but settings couldn't be applied, with a **Retry
  settings** action that re-applies just the settings without re-importing
  anything. The retry re-runs the same integrity check and per-setting
  validation (from the previous release) every time, so it can't be used to slip
  an unchecked value through, and it's safe to press more than once. (#608)
- **The single-dance Perform view no longer exits on one stray tap or back
  gesture.** Exiting single-dance Perform mode used to pop the screen
  immediately on a single tap of the close control, with no `PopScope` to
  catch a system/predictive back gesture either — an accidental brush could
  drop a caller out of the stage view mid-dance, losing wake-lock and their
  adjusted text scale. The close control and system back now route through
  the same deliberate confirm dialog ("Exit performance view?" / Cancel /
  Exit) already used by the multi-dance program Perform view (#434), keeping
  the two Perform surfaces consistent. (#612)
- **The program Perform exit dialog can no longer be stacked by rapid taps.**
  A quick double-tap on the close control, or repeated back gestures while
  the confirmation was already up, could open a second "Exit performance
  view?" dialog on top of the first — confirming the top one could then pop
  more than one screen. The exit confirmation is now guarded against
  re-entrancy, matching the guard already added to the single-dance Perform
  view (#612), so only one dialog is ever shown and exactly one screen is
  popped. (#666)
- **A corrupt backup can no longer brick startup.** Restoring a backup applied
  its saved preferences without checking them, and one startup read cast the
  theme preference with an unchecked cast — so a backup carrying a wrong-typed
  or out-of-range value (whether corrupted, truncated, hand-edited, or crafted:
  the file's checksum proves integrity, not that the contents make sense) could
  make the app throw on launch and keep throwing on every launch after, the
  kind of failure only clearing app data recovers from. Restored preferences are
  now validated at the trust boundary against a per-setting type/range schema:
  any value that doesn't fit is dropped so that setting falls back to its safe
  default (with a non-fatal notice), while every valid setting still restores,
  and startup reads the theme defensively so a bad value degrades to the default
  theme instead of crashing. (#609)
- **ContraDB import: single-file promenade, single-file circle, and "take
  neighbors" now recognize instead of falling through to custom.** Deferred
  from the #585 recognizer sweep: `single file promenade …` (e.g. `single
  file promenade along major set to new neighbors`) now imports as
  `promenade`, defaulting to everyone and keeping the trailing path as a note;
  `promenade single file around the circle/ring [N places]` now imports as a
  single-file `circle`; and a bare `<who> take <whom>` with no `give &` clause
  (e.g. `ladles take neighbors`) now imports as `give_and_take` (take-only).
  No new taxonomy moves were introduced — all three reuse existing `promenade`,
  `circle`, and `give_and_take` moves with a new `singleFile` flag on the
  first two. Any figure that doesn't match one of these patterns still falls
  through to editable custom, unchanged. (#634)
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
- **Caller's Box import: the trailing balance on "pass the ocean" now merges
  into the ocean instead of importing as a separate figure.** The Caller's Box
  writes the figure across two lines — `(4) Pass the ocean` followed by
  `(4) Balance wave of four …` — and only a _preceding_ balance line was being
  folded in, so the trailing balance-wave was left as its own custom figure. The
  cross-line merge now folds a trailing balance-wave line into the preceding
  ocean/wave figure (`pass the ocean`, `form a wave`, `form a long wave`),
  setting its balance flag and summing the beats (4 + 4 = 8). The match is
  conservative: it only folds a balance-_wave_ line (never a plain dancer balance
  destined for a following swing), only immediately-adjacent lines within a
  phrase, and never drops or fabricates choreography. (#577)

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
