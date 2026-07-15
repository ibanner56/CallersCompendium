# Caller's Compendium — Roadmap

An open-source, local-first, multi-platform organizer for dance callers: maintain a
collection of dance transcriptions, build and run programs for events, and import
dances from community sources.

This document is the living plan of action. Work items are atomic and roughly
ordered; each phase gates the next. Status: `[ ]` todo · `[~]` in progress · `[x]` done.

## Guiding decisions (agreed 2026-07-10)

| Decision | Choice |
|---|---|
| Platforms | Desktop (Win/mac/Linux) + tablet + phone |
| Stack | **Flutter** — see [ADR-001](adr/001-application-stack.md) |
| Persistence | Fully offline / local-first; online sources are **import-only** |
| Dance forms | Contra first; schema designed to extend to ECD & Squares |
| Performance mode | Core to v1 (large-print calling view, program navigation) |
| Notation | Fully structured figures with a searchable free-text **Custom** figure fallback |
| CallersBox | Sanitize the dataset offline, rehost a normalized snapshot the app can pull |
| Migration | Seamless out-of-the-box import from Caller's Companion exports |
| License | AGPL-3.0 |

Non-goals for v1: cloud sync, user accounts, choreography validation (developed
separately; planned for a later milestone), authoring/publishing back to online sources.

## Phase 0 — Project foundations

- [x] 0.1 Contributor docs: CONTRIBUTING.md, CODE_OF_CONDUCT.md, expanded README
- [x] 0.2 Repo conventions: branching, commit style (in CONTRIBUTING.md), ADR template in `docs/adr/`
- [x] 0.3 Issue/PR templates and labels for community contributions

## Phase 1 — Investigation & design

Research items (each produces a short written finding in `docs/research/`):

- [x] 1.1 Survey Caller's Companion features & UX — [research/callers-companion.md](research/callers-companion.md)
- [x] 1.2 Survey ContraDB dialect & figure model — [research/contradb.md](research/contradb.md)
- [x] 1.3 Survey CallersBox data — [research/callersbox.md](research/callersbox.md)
- [x] 1.4 Caller's Companion export formats / migration path — covered in [research/callers-companion.md](research/callers-companion.md)
- [x] 1.5 Tech stack evaluation → Flutter — [ADR-001](adr/001-application-stack.md)
- [x] 1.6 Accessibility requirements baseline — [research/accessibility-baseline.md](research/accessibility-baseline.md)

Design items (each produces a design doc + review):

- [x] 1.7 Domain model — [design/domain-model.md](design/domain-model.md)
- [x] 1.8 Figure taxonomy v1 — [design/figure-taxonomy.md](design/figure-taxonomy.md)
- [x] 1.9 Dialect system design — [design/dialect.md](design/dialect.md)
- [x] 1.10 Import pipeline design — [design/imports.md](design/imports.md)
- [x] 1.11 UX design — [design/ux.md](design/ux.md) (wireframes to follow per screen before Phase 3)
- [x] 1.12 Local storage design — [design/storage.md](design/storage.md)
- [x] 1.13 CallersBox rehosting plan — [design/callersbox-snapshot.md](design/callersbox-snapshot.md) (maintainer contact pending)

## Phase 2 — Core skeleton

- [x] 2.1 Scaffold the chosen stack; CI (build + test + lint on all platforms) — pub workspace (`app/` + `packages/compendium_core/`), FVM-pinned Flutter 3.44.6, `.github/workflows/ci.yml`
- [x] 2.2 Local database layer + migrations + test harness — `packages/compendium_core/lib/src/storage`: drift/SQLite schema (14 tables), `CompendiumRepositories` facade (choreographer/tag/custom-field/settings/snapshot/program/dance repos), FTS5 full-text search + structural figure search, soft-delete/restore/purge, `figures_json`-derived rebuild, UTC-normalized DateTime round-tripping, migration-test scaffold; 66 storage tests (210 total core tests). One documented deviation from the literal `storage.md` SQL sketch: `dance_fts` uses a normal FTS5 table with an `UNINDEXED dance_id` column rather than `content=''` tied to SQLite's implicit rowid — same derived/rebuildable behavior, avoids coupling to rowid conventions inside drift's typed API (see comment in `database.dart`).
- [x] 2.3 Domain model implementation with comprehensive unit tests — `packages/compendium_core` model types, invariants, phrase-section derivation
- [x] 2.4 Figure serialization + dialect rendering engine with golden tests — `figures_json` codec, `Taxonomy`/`MoveDef` validation, two-flavor renderer (`%S`, quarter-turn words), `canonicalize()` chokepoint with round-trip property tests; 144 core tests
- [x] 2.4a Complete taxonomy data entry (remaining ContraDB moves) — full ContraDB v1 contra move set now modeled in `contra_taxonomy.dart` across five additive slices (PR1 simple, PR2 dancer-interaction, PR3 choice-enum + `centers`/single-dancer vocab, PR4 places family + `ParamKind.places`, PR5 hey/wave family). Exactly one new engine type was needed (`ParamKind.places`, int 1–10, renders "N places"); the reduced-but-structured `hey` model keeps four ricochet flags + full/half length; `box_circulate` intentionally carries no places param. `contraTaxonomyVersion` = 5; comprehensive per-move tests (validation, golden rendering, `goodBeats`, canonicalize round-trip). See docs/design/figure-taxonomy.md "Implementation status"

## Phase 3 — Collection management

- [x] 3.1 Dance list: browse, sort, filter — `app/lib/src/screens/dance_list_screen.dart`: virtualized `ListView` of dances (title, authors, formation chip, status/tag chips, `showInList` custom fields) sourced from `CompendiumRepositories`; sort by title/author/recently-added/last-called (`ProgramRepository.lastCalledByDance()`, new); a lightweight client-side quick-filter (text + tag/formation `FilterChip`s) over the loaded list — the unified FTS search bar and structured query-builder panel from `docs/design/ux.md` §1 are deferred to 3.2 per that item's explicit scope. Minimal `DanceDetailScreen` placeholder (title/authors/formation/hook/tags) navigated to from the list; full detail/edit UI is later roadmap work. DB now opened on-device via `drift_flutter`.
- [x] 3.2 Search: Title, Author, Type, Formation, Figures, custom fields; full-text
  - 3.2b (core, done): `DanceFilter`/`FigureQuery` AST + `FilterCompiler` (one parameterized SQL query over the derived indexes), schema **v2** migration (`dance_figures.section` column + `(move, section)`/`(dance_id, idx)` indexes, back-filled via the post-open integrity pass), `DanceRepository.search(DanceFilter) → ids`, migration test with a checked-in v1 fixture, and a 20k-dance CI perf benchmark (median < 50 ms). See `docs/design/search.md`.
  - 3.2c (app, done): the Collection screen (`app/lib/src/screens/dance_list_screen.dart`) now hosts the real search UI, replacing 3.1's interim client-side quick-filter. A unified full-text search bar (debounced `FullTextFilter`), a one-tap **Filters** facet panel (`app/lib/src/widgets/facet_panel.dart`: Type/Formation/Progression/Author/Tags/Status + choice/boolean custom fields, OR-within a facet, AND across facets), and an **Advanced** boolean-tree builder (`app/lib/src/widgets/advanced_query_builder.dart`: All/Any/None groups, "has figure" rows with a move type-ahead + section/param pickers, and "then" sequence rows) all compose one `DanceFilter` run through `DanceRepository.search` (dialect-canonicalized via `Dialect.canonical`). Composition logic lives in `app/lib/src/search/collection_query.dart`. Sort exposes Title/Author/Recently added/Last called plus Relevance (only for a bare full-text search); core `SearchSort` gained `recentlyAdded` (`created_at DESC`). Result counts are announced to AT via a live region; results reuse the 3.1 `DanceListTile` and open `DanceDetailScreen`. App startup now runs `CompendiumRepositories.ensureMigrated()` behind a loading gate (`app/lib/src/widgets/app_bootstrap.dart`) so the schema-v2 back-fill completes before the first read.
  - [x] 3.2d By-phrase figure search — Caller's Box-style per-phrase (A1/A2/B1/B2) "figures match" / "but do not match" search dropdown (`app/lib/src/widgets/by_phrase_panel.dart`, surfaced from `dance_list_screen.dart` between Filters and Advanced), compiling to the existing section-aware figure query. Within a phrase every "match" move must be present (positive sectioned `FigureFilter`) and no "do not match" move may be present (each a dance-level `NotFilter` over the sectioned leaf); across phrases all constraints AND, and By-Phrase AND-composes with full-text + Filters + Advanced via `buildCollectionFilter`. Reuses the Advanced builder's move type-ahead (extracted as `MoveTypeAheadField`); each input is keyboard/AT-reachable and labeled with phrase + match/exclude role. App-UI only — the section-aware backend (3.2b) already supported it; a core test confirms sectioned match/negation.
- [x] 3.3 Dance editor: structured figure entry + Custom figure, validation of required fields
  - 3.3a (done): Metadata form — title, authors (with inline creation), formation, form/type,
    progression, phrase structure, hook, calling notes, tunes, tags, status, URL links, custom fields.
    Title-required hard validation, non-blocking `validate()` phrase warnings.
  - 3.3b (done): Keyboard-first structured figure entry — `MoveAutocomplete` type-ahead, per-parameter
    editors (`FigureParamEditor`: int/note/text/choice), progression toggle, custom-figure free-text with
    live lingo-line decoration (discouraged struck, role underlined). `FigureDraft` model, `toFigure()`/
    `fromFigure()`. Running beat count + section labels from `phraseStructure`.
  - 3.3c (done): Figure reordering — drag handle, move-up/down buttons, cut/paste (WCAG 2.5.7).
    `ReorderableListView` for drag; plain `Column` with interleaved paste buttons during cut; `didUpdateWidget`
    reseed pattern in `_LingoCustomTextField` + `_NoteField` so controller text stays in sync after
    any external draft change. `_WarningsCard` for non-blocking section / beat-count issues.
  - 3.3d (done): Autosave drafts + undo/redo. Debounced autosave (500 ms) to `SettingsRepository`
    keyed `editor_draft:<danceId|new>`. Restore/discard dialog on reopen. Clears on explicit save or
    back navigation. Draft schema v1 (versioned JSON) handles partial/incomplete drafts including
    null-move `FigureDraft`. In-memory bounded (50-entry) undo/redo stack of `EditorSnapshot`; undo/redo
    buttons in app bar; Ctrl/Cmd-Z / Ctrl/Cmd-Shift-Z / Ctrl-Y keyboard shortcuts; `_applySnapshot`
    resyncs all `TextEditingController`s and rebuilds figure drafts. Dropdowns use value-based keys for
    correct undo/redo resync.
- [x] 3.4 Custom user fields (define, edit, search) — `CustomFieldsScreen` (list/create/edit/delete,
    reachable via app-bar "Manage custom fields" icon on Collection screen); mutability guards: type
    locked once field has values on dances; key locked when in use; choice removal blocked when that
    choice value is stored on any dance; label/showInList/searchable always editable. Text and number
    custom-field facets added to `FacetPanel` + `FacetSelections` + `buildCollectionFilter` (text:
    contains/equals; number: eq/lt/gt/between).
- [x] 3.5 Dance duplication, soft-delete/restore — Duplicate action (app bar + copy title); soft-delete
  with undo snackbar (detail + swipe-to-dismiss on list); Recently Deleted screen (restore, purge
  ETA, permanent delete); startup purge sweep. **Phase 3 complete.**
- [x] 3.6 Batch tag — Collection multi-select (`docs/design/ux.md` §1). A selection mode on the
  Collection list (`app/lib/src/screens/dance_list_screen.dart`): entered via an app-bar **Select**
  button or long-pressing a row; tapping rows toggles a leading checkbox; a "N selected" live-region
  count and an exit action manage the mode (swipe-to-delete is suspended while selecting). Two batch
  actions — **Add tags** / **Remove tags** — open a picker (`app/lib/src/widgets/batch_tag_dialog.dart`):
  Add lists all tags with inline tag creation (`Tag(id: uuidV4())` + `TagRepository.upsert`), Remove
  lists only tags present on the selected dances. Applying unions (Add) or subtracts (Remove) the
  chosen tags across every selected dance via per-dance `DanceRepository.update` (dedup, preserving
  existing order), announces the result to AT (`SemanticsService.sendAnnouncement`), and offers a Snackbar
  **Undo** that restores each dance's captured prior tag set. Selection/checkbox state is conveyed by
  a checkmark + row highlight (never color alone) and is keyboard/AT reachable.

### Deferred from 3.3a (dance editor metadata form) — tracked follow-ups

- ~~Custom-figure lingo line: underline recognized **taxonomy move** keywords (3.3a/c
  ships only `canonicalize()`'s discouraged-strike + role-underline; ux.md §3 partial).~~
  **Resolved in Consolidation PR2** (consolidation-pr2-lingo-move-keywords): `moveKeywordSpans()`
  in core (word/phrase-boundary matching across all `MoveDef`/`MoveAlias` display names + search
  keywords, excluding `custom`); `LingoTextEditingController` extended with optional `taxonomy`
  field and priority-3 dotted-underline events (discouraged-strike > role-underline > move-dotted);
  a11y: dotted vs solid underline is shape-distinct (not color-alone); move highlighting is
  supplementary (helper text updated to describe all three styles).
- ~~`relatedDance` link target picker (3.3a links editor is URL-based only).~~
  **Resolved in Consolidation PR3** (consolidation-pr3-related-dance-picker):
  `_LinkDraft` generalized to carry either URL or `targetDanceId`; `relatedDance` added to the
  link-kind dropdown; dance type-ahead picker (excludes self + soft-deleted); `_preservedLinks`
  shunt removed — all four `LinkKind`s are now fully editable; snapshot/undo/autosave-draft updated
  (draft codec bumped to v2); detail screen resolves and displays target dance title with tappable
  navigation; dangling targets show `(missing dance)` placeholder.
- ~~Desktop list/detail **split-pane** editor layout (v1 ships a full-screen editor route).~~
  **Resolved in Consolidation PR5** (consolidation-pr5-split-pane-layout): `CollectionShell`
  responsive wrapper in `app/lib/src/screens/collection_shell.dart`; breakpoint 900 px logical
  width; wide mode = 400 px fixed list pane (with `DanceListScreen` + `onSelectDance`/
  `selectedDanceId`/`refreshTrigger` seam) + flexible detail pane (`DanceDetailScreen` or
  empty-state placeholder); `DanceDetailScreen` gains `onDeleted`/`onNavigateTo` so delete
  and duplicate work correctly without a route pop; narrow mode behavior fully unchanged.
  `main.dart` home updated to `CollectionShell`. Selected-row highlight via `ListTile.selected`.
  All deferred follow-ups from Phase 3/3.2 are now addressed **except** per-Type
  taxonomy selection in the figure builder — blocked until ECD/Square taxonomy
  data exists (see "ECD and Squares support" under Later milestones).
  (`DanceRepository.listIdsAndTitles()` — the lightweight id+title query that
  avoids N+1 `getById` lookups — is now built and used by the auto
  cross-reference links; see below.)
- [x] 3.7 Auto-linked dance cross-references — dance titles mentioned in another
  dance's hook / calling notes render as tappable inline links that open the
  referenced dance's detail (distinct from the explicit `relatedDance` link).
  App-side matcher in `app/lib/src/screens/dance_detail_screen.dart`
  (`_DanceTitleLinker` + `_CrossReferenceText`): case-insensitive, word-boundary
  (Unicode look-arounds), longest-title-wins, regex-safe title escaping, single
  compiled matcher over `DanceRepository.listIdsAndTitles()` (new lightweight
  core query), never self-links. Each link is one accessible node (link role +
  "Open dance: <title>" label + focusable + tap) and navigates like a
  `relatedDance` link. Dialect rendering of the notes is preserved.
- Cross-session / persistent **undo** (3.3d ships in-memory undo/redo only).
- ~~`revisit-lingo-dialect` — active dialect settings (persisted user-selectable dialect,
  settings screen, threading through detail toggle / lingo line / search).~~
  **Resolved in Consolidation PR1** (dialect-settings branch): `Dialect.presets` +
  `Dialect.forName` in core; `ActiveDialectScope` (`InheritedNotifier<ValueNotifier<Dialect>>`);
  `SettingsScreen` dialect editor; Collection app bar Settings entry;
  default = `Dialect.larksRobins`. **Extended** to a full editable dialect
  (ContraDB-aligned): role-neutral presets only (gendered presets removed —
  gendered terms via custom role-terms input), editable move substitutions and
  discouraged-terms list, `Dialect.toJson`/`fromJson`, and the active dialect
  persisted as full JSON.
- [ ] **Dialect manager — named dialects + term editor** (`docs/design/ux.md` §6):
  a library of named, user-created dialects (create / duplicate-from-preset /
  rename / delete) alongside shipped presets, a term editor with **live
  preview** + collision validation, and dialect **quick-switch** on the dance
  card / perform screens. Builds on the existing (single-active) editor above.
  - PR1 (this branch, `dialect-term-editor`): core `Dialect.resolveByName`
    (custom-wins-over-preset resolver superseding `forName`); app
    `DialectLibraryController` + `DialectLibraryScope` (settings keys
    `custom_dialects` / `active_dialect_ref`) with CRUD, active-fallback on
    delete, and legacy `active_dialect` blob migration. Fully unit-tested;
    wired into the app + UI in PR2/PR3.
- (2.4a full taxonomy data is now **complete** — full ContraDB contra move set shipped.
  The only still-open 3.2 follow-up is per-Type taxonomy selection, blocked on multi-form data.)
  - ~~Nested figure groups inside `then`~~: **Resolved in Consolidation PR4**
    (consolidation-pr4-nested-figure-groups): `BuilderFigureNode` sealed
    hierarchy (`BuilderFigure` + `BuilderFigureGroup`) in `collection_query.dart`;
    `BuilderThen.before/after` generalized from a fixed `BuilderFigure` to any
    `BuilderFigureNode`; `_FigureOperandEditor` + `_FigureGroupEditor` widgets in
    `advanced_query_builder.dart`; "Group figures" / "Single figure" affordances
    in the `then` row; no compiler changes needed (filter_compiler already handles
    nested `FigureQuery` in `ThenFilter`). Model supports arbitrary nesting depth;
    UI exposes one level. **Per-Type taxonomy selection remains deferred** (blocked
    on multi-form taxonomy data — ECD/square taxonomy does not yet exist).

## Phase 4 — Programs

- [x] 4.1 Program CRUD: create, edit, save, duplicate
- [x] 4.2 Program builder UX: add/reorder dances, notes/breaks, event metadata.
  **Event metadata must reach CC parity** (schema audit 2026-07-12,
  research/callers-companion.md): program-level `band`, `caller`, `dancerLevel`
  in addition to date/venue/notes; per-slot **guest caller** and **planned
  time/length** (CC `SetItem.Caller`/`Time`) as structured fields, not just the
  free-text slot note; ALT dances (done in model via `isAlt`).
- [x] 4.3 Program printing/export (PDF, plain text, **emailable text set list** —
  CC parity: "email set list")
- [x] 4.4 Programming matrix view (figures × dances, computed from structured
  figures; first-figure highlight) — CC's Elements matrix without the manual
  checklist. See design/ux.md §4. Derivation is a pure, Flutter-free core
  (`buildProgramMatrix`); UI is a Matrix tab on the Program builder with pinned
  headers and full table semantics. **Delivered follow-on**: a print/report
  version of the matrix — a dedicated LANDSCAPE PDF (`buildProgramMatrixPdf`,
  reusing the bundled-font PDF theme) rendering the moves × dances table with
  shape/text markers (★ first figure, ✓ present) plus a legend, wired to a
  keyboard-reachable export/print control on the Matrix tab. **Intentional
  design decision (won't-do)**: per-cell within-dance repeat **counts** — the
  matrix stays BOOLEAN presence to match CC's checklist semantics; adding
  counts would diverge from CC parity, so it is not planned.

- [x] 4.5 Per-dance calling history — dance detail shows the programs that
  **include** the dance (a slot referencing it), a derived query over
  `ProgramSlot`s (`ux.md` §2 / wireframe `2-dance-detail` "History"). Read-only,
  tappable to open each program, most-recent first (ordered by the slot's
  `performedAt` when set, else the program's `eventDate`, else `updatedAt`).
  Backed by a focused Flutter-free core query
  (`ProgramRepository.callingHistoryForDance`, mirroring `lastCalledByDance`).
  By **default** a program appears as soon as it contains the dance, whether or
  not the slot was marked performed; the query takes an optional `performedOnly`
  flag (default `false`) as the hook for **G.2** (General settings, off by
  default — see below), which will optionally restrict history to
  actually-performed slots. G.2 and the "mark performed" write path remain
  separate, unbuilt items.

## Phase 4b — Caller's Companion parity backfill (dance & metadata model)

*Added 2026-07-12 from a schema-level audit of the shipped CC `.USR` (22 tables
parsed with an fmptools build), comparing against the Phase 2–3 domain model.
These are fields/entities CC exposes natively that our model does not yet carry.
Phases 0–3 are considered complete; this is additive follow-on work and is
sequenced here so it lands before/with Programs, which depend on some of it.
See research/callers-companion.md "Schema-level addendum" and
design/domain-model.md "CC parity backfill".*

- [x] 4b.1 **Dance difficulty / level** — a first-class `level` field (CC
  `Level`/`LevelNum`, plus a "mixed level" marker). High priority: callers
  filter and program by level constantly. Add to the domain model, the schema
  (+ back-fillable index), the editor metadata form, the Collection list/facet,
  and search (`Level` filter leaf in design/search.md).
  - Resolved (4b.1b): the **Advanced query-builder `Level` lte/gte UI row** is
    CLOSED as an unneeded convenience. The Advanced builder is
    figure-query-specific, so `Level` never belonged there. Because `DanceLevel`
    is a small ORDERED enum, the Collection Level facet's exact multi-select
    ALREADY lets users express any ordered range by ticking a contiguous set
    (e.g. "≤ intermediate" = beginner + … + intermediate). The ordered
    `lte`/`gte` capability is therefore fully covered in the UI via multi-select;
    a dedicated ≤/≥ operator control adds no reach. The engine ops
    (`LevelFilter` `eq`/`lte`/`gte`) remain available and tested for
    programmatic/query use.
- [x] 4b.2 **Composed / revised dates** — optional `composedOn` / `revisedOn`
  (CC keeps partial y/m/d); distinct from record `createdAt`/`updatedAt`. Editor
  field + optional sort. Delivered: pure-Dart `PartialDate` (partial-precision,
  ISO-like canonical serialization), schema v4→v5, precision-aware editor input,
  and a `composedOn` search sort.
- [x] 4b.3 **Rating** — optional star `rating` on a dance (CC `Rating`,
  sortable), a first-class nullable `int? rating` (`1..5`, `null` = unrated).
  Delivered in two parts: **4b.3a core** — schema v5→v6 (`dances.rating`),
  `Dance.rating` with range validation, `SearchSort.rating`, and the
  `RatingFilter` search leaf; **4b.3b UI** — accessible editor star control
  (keyboard-reachable, per-star + clear semantics, shape-not-colour state),
  draft codec v4→v5, Collection list-tile rating indicator, and a
  minimum-rating (`≥N★`) facet emitting `RatingFilter`.
- [x] 4b.4 **Choreographer contact card** — extend `Choreographer` beyond
  name/website/notes toward CC `Author` (email, location, deceased flag) for
  users who maintain composer contacts. Keep optional; privacy-aware.
- [x] 4b.5 **Published-source citation** — structured `reference` + page/number
  on a dance (CC `Reference`/`PageNumber`, `MD_*` collection) beyond a bare URL
  `DanceLink`, so book/collection provenance is first-class and searchable.
  Delivered as three atomic PRs: **a** reusable `PublishedSource` entity +
  storage (schema v8), **b** search/FTS integration + `SourceFilter`, **c**
  editor UI. Box is checked when **c** lands.

## Phase 5 — Performance mode

- [x] 5.1 Large-print dance card view with dialect applied — full-screen Perform
  card for a single dance (`PerformDanceScreen`), entered from the dance detail
  screen and exiting back to it. Renders the header (title/authors/formation/
  level/status) and section-grouped figures reusing the core `deriveSections` +
  `FigureRenderer` path, applies the active dialect with the same canonical ⇄
  dialect quick-toggle as the detail card, and adds an in-view large-print size
  control (A-/A+, large default, no practical upper bound). In-view size state
  only; cross-session persistence to settings is a later follow-up.
- [x] 5.2 Program navigation (next/prev, jump), screen-wake lock, high-contrast theme;
  optional per-slot / running **program timing** (CC `Set.TimeStart`/`TimeElapsed`,
  `SetItem.Time`) surfaced during an event
  - Program navigation delivered: program-mode Perform view walking `Program.grouped`
    groups (next/prev via on-screen buttons, giant edge hit zones, and keyboard
    arrows/page keys), a jump-to-slot overview, and one-tap ALT swap within a group,
    reusing the shared large-print `PerformCard`. Screen wake-lock delivered:
    both Perform views (single-dance and program) hold a `wakelock_plus`
    wake-lock while open and release it on exit, so a propped tablet does not
    auto-sleep. High-contrast / 7:1 dark-stage theme delivered: both Perform
    views open in the outline-driven `AppTheme.highContrast` scheme by default
    with an in-view toggle (keyboard-reachable, on/off state exposed to AT) to
    fall back to the app's inherited theme; in-view only, persistence to
    Settings deferred as a later follow-up (mirrors the 5.1 size-control
    decision). Program timing delivered: the program Perform view surfaces a
    running program clock and a per-slot elapsed timer (the latter resets on
    every navigation — next/prev/jump/alt-swap) in the bottom status bar, shows a
    slot's `plannedMinutes` (CC `SetItem.Time`) as "planned N min" with a subtle
    icon+text over-run cue when elapsed passes it, and offers a pause/resume
    toggle for interruptions. Timing is in-view-only and read-only toward the
    model (no `performedAt`/persistence — that is 5.3); timers are driven by a
    single 1s `Timer` cancelled on exit, and the readouts expose an on-demand
    (non-live-region) accessible label to avoid per-second AT spam.
  - Program summary Perform entry point: the wide-screen program summary pane
    (`_ProgramSummaryPane`) offers a prominent "Perform this program" action
    (disabled with a tooltip when the program has no slots), so Perform is
    reachable directly from a program without opening the builder.
- [x] 5.2a Dance print/share — export a single dance card as PDF + shareable/
  copyable plain text, dialect-aware, from the dance detail app bar (ux.md §2
  dance-detail actions). Mirrors the Phase 4.3 program-export stack: a
  Flutter-free core renderer (`danceToPlainText`, `compendium_core`) laying out
  title/authors/formation/level/status/phrase then the figure table grouped by
  derived section and the calling notes, rendered dialect-aware via the shared
  `deriveSections` + `FigureRenderer` path so the export matches the on-screen
  card; an app PDF (`buildDancePdf`) reusing the bundled-font PDF theme; and a
  keyboard/AT-reachable `DanceExportMenu` (share via `share_plus`, copy to
  clipboard, print/save PDF via `printing`) on the detail app bar. Preserves the
  4b.4 privacy invariant — authors render by name only, so choreographer contact
  fields never enter a shared export (regression-tested).
- [x] 5.3 On-the-fly program adjustments during an event
  - Delivered: a non-destructive **"adjust" sheet** on the program Perform view
    (`docs/design/ux.md` §5) that never disturbs the reading view underneath.
    From it the caller can **reorder the remaining slots** (drag handle **plus** a
    non-drag move up/down alternative, WCAG 2.5.7 — the current group and every
    later group are reorderable, already-passed groups stay fixed), **insert a
    dance from quick-search** (reusing the builder's `CollectionPicker` stack) and
    **add an ad-hoc note slot**, both landing right after the current slot ("play
    this next"), and **mark the current slot performed** — the 5.2-deferred
    `performedAt` WRITE path (a toggle; `ProgramSlot.copyWith` gains a pure
    `clearPerformedAt` flag). Edits apply to the live view (grouping / navigation
    recompute, keeping the reading position on the same dance by slot id) and
    **persist** through `ProgramRepository.update` (bumping `updatedAt`) via an
    `onProgramChanged` callback — the saved-program summary persists immediately
    and reloads; the editor's still-unsaved draft folds edits back into its
    working slots to save through the normal flow. Every adjustment is **undoable**
    via the app-wide SnackBar pattern, and the adjust controls are keyboard/AT
    reachable with button role, name and (for mark-performed) toggled state.
- [x] 5.4 **Verbose / screen-reader figure rendering** — an expanded, spoken-friendly
  rendering of figures for assistive tech (distinct from the terse canonical/dialect
  display text), per the accessibility baseline ([research/accessibility-baseline.md](research/accessibility-baseline.md)) and
  the [figure-taxonomy.md](design/figure-taxonomy.md) "verbose rendering still TODO" note. Applies to the dance
  detail card and the Phase 5 large-print performance view.

## General settings

Cross-cutting application preferences, persisted across sessions via
`SettingsRepository` and surfaced in the Settings screen (`docs/design/ux.md`
§6). Distinct from in-the-moment, per-view toggles — this section is the home
for app-wide preference switches as they accrue.

- [ ] G.1 **Auto-size performance cards to fit the screen** — a General settings
  toggle (**on by default**) that auto-scales each Perform card so the current
  dance/slot's full text fits the visible viewport without scrolling,
  recomputing on dance/slot change, orientation change, and window resize.
  When off, Perform uses the manual large-print A-/A+ control (Phase 5.1) with
  its large default and no upper bound. The A-/A+ controls stay available
  either way; turning auto-size off restores the last manual size. The Phase 5
  "user-set size, no upper bound" model remains the manual mode — auto-size is
  an opt-out convenience layer on top.

- [x] G.2 **Require "mark performed" for calling history** — a General settings
  toggle (**off by default**) controlling whether a program must have the dance's
  slot marked performed (`ProgramSlot.performedAt` set) to appear in that dance's
  calling-history section (per-dance calling history; `docs/design/ux.md` §2).
  Default (off): a program appears in a dance's history as soon as it contains
  that dance, regardless of whether the slot was marked performed (i.e. not
  strictly limited to performed programs as currently described in
  `docs/design/ux.md` §2). When on: only programs with the dance's slot marked performed appear, matching the
  behavior described in `docs/design/domain-model.md`. Persisted via `SettingsRepository`.

## Phase 6 — Imports & migration

- [ ] 6.1 Source adapter framework + provenance tracking
- [ ] 6.2 CallersBox sanitization pipeline (separate tool) + hosted snapshot
- [ ] 6.3 CallersBox snapshot import in-app
- [ ] 6.4 ContraDB import
- [ ] 6.5 Caller's Companion migration import — map CC tables discovered in the
  schema audit: `Dance` (incl. `Level`, composed/revised dates, `Rating`,
  `UserDefined_*` → custom fields), `Set`+`SetItem` → Programs (with band/caller/
  dancerLevel, ALT flags, guest caller, timing), `Author` → Choreographers,
  `Venue` → venue entity, `Term` → glossary, `Dance_Related` → related links.
  Free-text figures import as `custom` (see design/imports.md §2).
- [ ] 6.6 Generic import/export (JSON) for backup and inter-user sharing

## Phase 7 — Release

- [ ] 7.1 Packaging/signing for all platforms; update channel
- [ ] 7.2 User documentation
- [ ] 7.3 Beta program with real callers; feedback triage

## Later milestones

- Choreography validation integration (external project)
- ECD and Squares support
- Optional device-to-device sync
- **Venue as a reusable entity** (CC `Venue`: address, contacts, sponsor, price,
  website, generic schedule) rather than a per-program free-text `venue` string,
  so venues are picked once and reused across programs.
- **Glossary / terms** (CC `Term`: term + definition + source) — a browsable
  reference of caller terminology, dialect-aware.
- **User-defined quick-entry snippets** — CC's beloved "Insert Call" buttons
  (per-user label → expansion text + beats + a gender-free alternate). Our
  taxonomy type-ahead covers entry *speed*, but not personal shortcut phrasing;
  evaluate whether power users still want savable snippets on top of structured
  entry. (Decision needed — may be declined in favor of dialect + taxonomy.)
- **UI localization / multi-language** — CC ships ~12 runtime UI languages; we
  have no i18n plan yet. Scope an intl framework if community demand appears.
