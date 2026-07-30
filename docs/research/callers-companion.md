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
  `maxFiguresPerDance` = 512), while a single over-`maxBodyLineLength` (2 000)
  line is dropped with a warning rather than aborting the import, and
  orphan/missing `zk_Dance_ID` rows degrade to warnings rather than throwing.
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
  structured taxonomy replaces (derived, not hand-ticked). (A later live read of
  the `.USR` `Elements` **table** counted **45** rows — see § Phase 3 spike (#563);
  the "32" here is the per-dance checklist size, the 45 is the full tag-definition
  table.)
- **InsertCall** buttons: label → `InsertButtonText` (+ `…Alt` variant) +
  `InsertButtonBeats`. Confirms the per-user snippet model and that the alternate
  slot is a second stored call string (often a *different* call, not merely a
  gender re-phrasing) toggled by the same button. On `.USR` import these seed
  figure shorthands (#420) via an **opt-in, previewed** step (#562): each button
  whose text structures through the free-text fan-out to non-custom taxonomy
  figure(s) becomes a `token → figures` candidate (label = token), the alt is
  offered as a selectable alternate expansion for the same token, existing-token
  conflicts are surfaced (never overwritten), and re-import is idempotent. See
  `docs/design/imports.md` §2 and `packages/compendium_core/lib/src/imports/insert_call_shorthands.dart`.
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

## Phase 3 spike (#563): can CC's default `Elements` vocabulary boost recognition? (2026-07-30)

*Epic #558 Phase 3 spike — an investigation with a go/defer recommendation, **not**
a committed feature. It asks whether mapping CC's shipped default `Elements`
vocabulary onto our taxonomy/dialect measurably improves recognition of a CC
caller's free-text.* **Recommendation: DEFER — close #563 as a decision, ship no
durable feature.**

### Reframe (why the original framing was a dead end)

The issue's original idea — mine a *per-user* dialect from `Elements` — is blocked
by our never-fabricate rule: in the surveyed real `.USR` **all 45 `Elements` rows
are shipped defaults** (`zk_Constant = 1`), so there is no user-specific signal to
mine. (The `.USR` `Elements` **table** has 45 rows — the tag-definition vocabulary,
verified via a live read — which is distinct from the "up-to-32 per-dance boolean
Elements checklist" surveyed earlier in this doc (§ Feature inventory / Schema-level
addendum): the 45-row table is the vocabulary *source*, the ~32 checklist is the
per-dance *UI* that references it.) Inventing a dialect a user never expressed is
exactly the failure mode we forbid. The spike was therefore reframed to an honest,
non-fabricating question: does mapping CC's **default** `Elements` vocabulary (short
classification tags like a neighbor-swing tag, an allemande tag, a do-si-do tag)
onto our taxonomy lift recognition of the real `Phrase` free-text corpus?

### Method (reproducible; measured against the real `.USR`, nothing committed)

- Corpus: **all 294 `Phrase` call-lines across the 40 dances**, obtained through the
  existing `readCcUsrArchive` extraction (the same path the importer uses).
- Recognition metric: replay each line through the **real ingest path** —
  `splitCcBeatPrefix` → `parseFigureLinesFanOut` — and count a produced figure as
  *structured* when it is not a `custom` import-gap figure.
- Two passes over the identical corpus:
  1. **Baseline** — no Element help.
  2. **Element-normalized** — a deliberately **generous** normalization derived from
     the 45 default `Elements`: their abbreviated tags and the atom-abbreviations
     they decompose into (role/relational initials, allemande, swing, circle,
     promenade, forward, do-si-do, right-and-left-through, balance-and-swing, …) are
     expanded to the prose the recognizer understands, applied as a pre-scrub.
- Per-line flip accounting: lines that moved custom→structured (help) vs
  structured→custom (regression).

### Result

| Pass | Structured | Rate |
| --- | --- | --- |
| Baseline | 141 / 294 | **48.0 %** |
| Element-normalized (generous) | 143 / 294 | **48.6 %** |

**Delta: +0.6 percentage points (+2 figures); 2 lines helped, 0 regressions.**

Both "helps" came from **generic abbreviation expansion** (an abbreviated
"forward", a one-letter role initial in front of "chain"), **not** from any
role-vocabulary or spelling dialect signal.

### Why the lift is negligible

- **The role-dialect mapping is already done.** CC's default vocabulary leans on
  gendered role terms, but the `Phrase` free-text spells them out in prose, and our
  shared `scrubFigureText` chokepoint **already** canonicalizes those role words to
  canonical role tokens on import. An `Elements`-derived role map is redundant with
  work that already happens for every source.
- **`Elements` is abbreviated tag shorthand; `Phrase` is full prose.** Token overlap
  between the two is minimal, so a tag→taxonomy dictionary has almost nothing to fire
  on.
- **The real recognition ceiling is taxonomy/parser coverage, not vocabulary
  translation.** Categorizing the ~150 baseline custom figures (aggregate, paraphrased):

  | Category (paraphrased) | Share of custom figures |
  | --- | --- |
  | Positional / actives notation (ones-and-twos, numbered dancers) | ~36 % |
  | Move modifiers & fractions (half-a-move, three-quarter turns, diagonals) | ~16 % |
  | Traditional / triple-minor coverage (cast off, down-the-outside, bend the line) | ~12 % |
  | Compound / multi-clause lines | ~12 % |
  | Typos / spelling variants | ~7 % |
  | Other / uncategorized | ~17 % |

  None of these are a *vocabulary* problem an `Elements` map addresses.

### The one real signal → route to the general parser track (#382)

The only measured wins were **generic abbreviation expansions** (an abbreviated
"forward"; a role-initial before a move). If we ever choose to handle these, they
belong in the **shared parser/scrub**, because expanding common shorthand would help
**every** import source — not as a CC-specific dialect feature. Recorded here as a
data point for the general parser-coverage track (**#382**); no CC-scoped surface
area, no opt-in UI, and no new follow-up issue is created from this spike.

### Recommendation

**DEFER the Element-derived-dialect idea and close #563 as a decision.** A
+0.6 pp / two-line lift, none of it a genuine dialect signal, does not justify a
durable feature, an opt-in setting, or the maintenance surface — and a CC-scoped
normalizer would be the wrong home for the generic-abbreviation insight anyway. This
matches the epic's expectation that Phase 3 is "aspirational / likely defer past
beta.6."

### Licensing note

The measurement used a **local-only, git-ignored** copy of the real
`CallersCompanion2.USR`; no `.USR`, no verbatim `Elements` table, and no throwaway
measurement code are committed. This note records only **aggregate statistics and
paraphrased categories**, so none of CC's licensed default content is redistributed.
