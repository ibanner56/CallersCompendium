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

## Schema-level addendum (2026-07-12)

*The inventory above was compiled from the site tour + announcements. This
addendum records what a **direct parse of the shipped `.USR`** revealed, so our
parity + migration work is grounded in the real schema rather than marketing
copy. Method: built the open-source `fmptools` FM12 reader and dumped tables,
columns, and lookup rows from both the demo and full `CallersCompanion2.USR`.*

### Tables (22)

`Dance`, `Author`, `Set`, `SetItem`, `Phrase`, `Resource`, `Admin`, `Venue`,
`To Do List`, `Colors`, `Dance_Related`, `Term`, `Elements`, `InsertCall`,
`Import`, `AuthorPermission`, `MD_References`, `MD_Sources`, `MD_URL`,
`MD_Dances`, `UpdateImport`, `Videos`. (`MD_*` = a bundled "master dance"
cross-reference index of published collections.)

### Notable fields confirmed on `Dance` (≈230 columns; most are FileMaker
calc/display/search helpers, prefixed `zc_`/`zi_`/`zk_`). Substantive user data:

- Identity/authorship: `Name`, `Author1`/`Author2` (+ ids), `AuthorOrTraditional`,
  `IsTraditional`, `Editor`, `Credits`.
- Classification: `Type`/`SubType`, `Formation`/`FormationOther`, `ContraForm`
  (Improper/Becket/Proper…), `Progression`/`ProgressionOther`, `MinorSet`,
  **`Level`/`LevelNum`/`Mixed Level`**, `Direction`, `Symmetrical`.
- Body: `A1`/`A2`/`B1`/`B2`/`C1`/`C2` (+ `*_Parsed`), `Moves`, `CallList*`,
  `Phrase*`; the `Phrase` table holds per-section text incl. **gender-swapped
  variants** (`PhraseText_GenderSwap_LR/RL/Switch`). **The `Phrase` table is the
  real figure source** for a `.USR` (the `Dance`-row `A1..C2` columns are empty
  in shipped files): the importer joins it per dance (grouped by `zk_Dance_ID`,
  ordered by `PhraseNumber` A1→C2), reading the primary `PhraseText` only —
  never the gender-swapped variants — and routes each line through the shared
  free-text fan-out (see `docs/design/imports.md` §2). The `Dance`-row `A1..C2`
  path remains a fallback. Because `PhraseText` is untrusted external free text,
  the join is hardened (#561): each body line is sanitized at the ingestion
  boundary (control/bidi/format stripping) before it reaches storage, and the
  join is bounded fail-closed (`FmpReadLimits.maxPhraseRows` = 20 000,
  `maxFiguresPerDance` = 512, `maxBodyLineLength` = 2 000) with orphan/missing
  `zk_Dance_ID` rows degrading to warnings rather than throwing.
- Dates: **`DateComposed`/`DateRevised`** (+ partial day/month/year fields),
  separate from record created/modified stamps.
- Curation: **`Rating`**, `Status`, `StarterSet`, `DistinctiveMove`,
  `CountInSets`, `MostRecentSet`, `Mark`.
- Sources/media: `SourceURL`, up to **5 `VideoURL`s**, `Reference`/`PageNumber`,
  `ReferenceID`, `CallersBox_id` (import-by-id precedent), `ImportSource`.
- User customization: **`UserDefined_1..3`** with matching `*_Name` labels.
- Per-dance **`Elements`** (32-boolean checklist) drives the programming matrix.

### Lookup data extracted

- **Elements (32)**: N/P/M Swing, allemandes, Down 4, Gypsy, Hey (full/half),
  Half Fig 8, Petronella, chains, stars, RL, DSD, LLFB, Promenade, waves, etc.
  — the exact vocabulary CC's element-search + matrix depend on, and which our
  structured taxonomy replaces (derived, not hand-ticked).
- **InsertCall** buttons: label → `InsertButtonText` (+ `…Alt` gender-free
  variant) + `InsertButtonBeats` (e.g. `B&S-N` → "Neighbor balance and swing",
  alt "Neighbor gypsy and swing", 16). Confirms the per-user snippet model and
  that CC's gender-free switch is a second stored string per snippet.
- **Set / SetItem**: `Set` carries `Date`, `Location`, `Band`, `Caller`,
  `DancerLevel`, `Notes`, `TimeStart`/`TimeElapsed`, `GenderFree`,
  `SetList_HideALT`; `SetItem` carries `Order`, `Break`, `AlternateDance`,
  per-slot **`Caller`** (guest) and **`Time`**.
- **Author**: full contact card (address, phones, email, website, DOB,
  `Deceased`, notes) — richer than our `Choreographer`.
- **Venue**: name, address (`address1`/`address2`, city, state/province,
  country, postal code, ZIP+4 `plus4`), website, sponsor, event name, time,
  generic schedule, price, notes, and two contacts (name/phone/email each). Our
  shipped `Venue` entity (schema v14) mirrors this column set, dropping only CC's
  FileMaker plumbing (`VenueDisplay_c` — reimplemented as a computed
  `displayName` — plus `zc_*`/`zi_*` audit, `zk_Constant`, `SiteID`).
- **Term**: term + definition + source (a glossary).

### Parity implications (folded into ROADMAP Phase 4b/5/6 + design docs)

Model gaps to backfill: dance **`level`** (high), composed/revised **dates**,
**`rating`**, richer **choreographer** contact, structured **citation**;
program **band/caller/dancerLevel**, per-slot guest **caller**/**time**,
**venue entity**, **glossary**, and a decision on user **snippets** +
**localization**. Migration (6.5) now maps against these concrete tables.
