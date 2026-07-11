# Research: Caller's Companion feature survey

*Roadmap item 1.1 / 1.4 · surveyed 2026-07-10 from callerscompanion.com and the
shipped Windows/macOS binaries (v2, April 2024 build).*

Caller's Companion (CC) is the incumbent desktop app in this niche (~140 users as of
March 2026, shareware, single maintainer). We are **not** cloning it; this survey
exists to make sure our feature set covers callers' real workflows and to plan a
seamless migration path for anyone who chooses to switch.

## Technical anatomy

- CC is a **FileMaker Pro Runtime** application. All application logic, layouts, and
  user data live in a single FileMaker 12-format database file,
  `CallersCompanion2.USR` (~20 MB shipped; grows with the user's data).
- The Windows directory and mac `.app` are just the FileMaker runtime engine
  (FMEngine/DBEngine/ClientUI + MFC/omniORB deps). No separate manual ships with it.
- iPad/iPhone use works by loading the same `.USR` into FileMaker Go; CC detects
  mobile and shows dedicated layouts (iPhone layouts are read-only search/display).
- Updates are distributed as new `.USR` files; the maintainer migrates user data
  between versions by hand/tooling. There is no public schema documentation.

### Migration implications (roadmap 6.5)

- User data is inside the binary `.USR`. Options, most promising first:
  1. **Direct file parse**: the FM12 format has been reverse-engineered by the
     open-source `fmptools` (HTML/JSON/SQLite converters) and similar projects.
     A CC-specific importer built on this would be genuinely "out of the box":
     point the app at your `.USR` and go. Needs validation against a real file —
     the shipped demo `.USR` (in the DMG) is a good test fixture.
  2. **Guided export**: FileMaker runtimes can export records (CSV/tab/XML *if* the
     app exposes an export script). CC has "copy formatted dance to clipboard" and
     emailed text set lists; worst case we parse those text formats.
  3. Ask users to request an export from the maintainer — not "seamless", last resort.
- The demo `.USR` from the public DMG should be committed (or cached) as a test
  fixture only if its license permits; otherwise keep it as a local-only fixture.

## Feature inventory (from site tour + announcements)

### Dance catalog
- Fields: Name, Author, Type, Formation, Level, Progression, First figure, Music,
  plus **user-customizable fields**.
- Transcription body is **free text**, entered via customizable **"Insert Call"
  buttons**: each button has a label + expansion text (e.g. `B&S-P` →
  `(16) Partner balance and swing`), so entry is fast and *personally* standardized
  — but not machine-standardized. Users edit the inserted text freely afterwards.
- **Elements checklist**: up to 32 per-dance boolean "elements" (figures/features),
  manually ticked. Powers the programming matrix and element search. Failure mode:
  depends entirely on manual upkeep.
- **Source area**: links to author website, video clip, and related dances
  (dance-to-dance links).
- Duplicate Dance function; formatted copy-to-clipboard for email.
- Calling history: per-dance list of every event/set it was called at.

### Sets (programs)
- Create/edit/save/duplicate **Sets** for events. Builder UI: dance filter/selector
  (name, author, type, formation, progression, level) on one side, ordered set list
  on the other; reorder up/down.
- **ALT dances**: a dance can be marked as an alternate in the list, decided at
  event time based on crowd level.
- Color-coding of set list rows by dance form/type (2024 addition).
- **Programming matrix** (à la Larry Jennings' *Give & Take*): grid of set dances ×
  32 elements to spot repetition across a program; highlights each dance's first
  element. Print/report version too.
- Print options: multiple formats for dances and sets; set lists emailable as text.

### Performance
- **On-screen calling view**: large type for calling from a laptop/tablet at
  standing distance.

### Dialect (partial)
- **Gendered ↔ Gender-free role-term switching on the fly** (Larks/Robins), added
  2024. Notably, the maintainer reports the Elements area could *not* be made
  gender-free easily — a warning about role terms baked into fixed vocabularies.
  Our design stores canonical roles and renders through dialect everywhere.

### Imports
- **Import dances by ID directly from The Caller's Box** (2024 addition) — precedent
  for our CallersBox integration, though CC imports them as free text.

### Localization
- Ships FileMaker dictionaries/resources for ~12 UI languages (runtime-provided, not
  CC-specific effort).

## Lessons for Caller's Compendium

1. **Free-text transcriptions cap searchability.** CC needed a parallel manually
   maintained Elements checklist to enable figure search/matrix. Structured figures
   give us this for free and stay correct.
2. **Role dialect must be designed in from day one.** Retrofitting gender-free terms
   onto CC's fixed Elements vocabulary stalled. Canonical storage + display-time
   dialect avoids this.
3. **Preserve the fast-entry feel.** Insert Call buttons are beloved because entry
   is fast and matches the caller's personal phrasing. Our structured figure editor
   must be at least as fast (keyboard-first entry, per-user display phrasing via
   dialect) or we lose users.
4. **Workflow features that must not be dropped**: calling history per dance, ALT
   dances in programs, programming matrix, duplicate dance/set, related-dance links,
   source/video links, large-type calling view, print/email formats.
5. **Tablet use is a first-class reality** (Nils Fredland photos, FileMaker Go
   support) — validates our desktop+tablet+phone platform decision.
