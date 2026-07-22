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
| CallersBox | Import directly from the primary source in-app (online search + link/record import) |
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
- [x] 1.13 CallersBox rehosting plan — [design/callersbox-snapshot.md](design/callersbox-snapshot.md) — **superseded**: direct in-app import from CallersBox replaces the hosted-snapshot approach (see 6.2/6.3 below)

## Phase 2 — Core skeleton

- [x] 2.1 Scaffold the chosen stack; CI (build + test + lint on all platforms) — pub workspace (`app/` + `packages/compendium_core/`), FVM-pinned Flutter 3.44.6, `.github/workflows/ci.yml`
- [x] 2.2 Local database layer + migrations + test harness — `packages/compendium_core/lib/src/storage`: drift/SQLite schema (14 tables), `CompendiumRepositories` facade (choreographer/tag/custom-field/settings/snapshot/program/dance repos), FTS5 full-text search + structural figure search, soft-delete/restore/purge, `figures_json`-derived rebuild, UTC-normalized DateTime round-tripping, migration-test scaffold; 66 storage tests (210 total core tests). One documented deviation from the literal `storage.md` SQL sketch: `dance_fts` uses a normal FTS5 table with an `UNINDEXED dance_id` column rather than `content=''` tied to SQLite's implicit rowid — same derived/rebuildable behavior, avoids coupling to rowid conventions inside drift's typed API (see comment in `database.dart`).
- [x] 2.3 Domain model implementation with comprehensive unit tests — `packages/compendium_core` model types, invariants, phrase-section derivation
- [x] 2.4 Figure serialization + dialect rendering engine with golden tests — `figures_json` codec, `Taxonomy`/`MoveDef` validation, two-flavor renderer (`%S`, quarter-turn words), `canonicalize()` chokepoint with round-trip property tests; 144 core tests
- [x] 2.4a Complete taxonomy data entry (remaining ContraDB moves) — full ContraDB v1 contra move set now modeled in `contra_taxonomy.dart` across five additive slices (PR1 simple, PR2 dancer-interaction, PR3 choice-enum + `centers`/single-dancer vocab, PR4 places family + `ParamKind.places`, PR5 hey/wave family). Exactly one new engine type was needed (`ParamKind.places`, int 1–10, renders "N places"); the reduced-but-structured `hey` model keeps four ricochet flags + full/half length; `box_circulate` intentionally carries no places param. `contraTaxonomyVersion` = 5; comprehensive per-move tests (validation, golden rendering, `goodBeats`, canonicalize round-trip). See docs/design/figure-taxonomy.md "Implementation status" (`hey.length` was later expanded to the full set of ContraDB named durations — `full`/`half`/`lessThanHalf`/`betweenHalfAndFull` — bumping `contraTaxonomyVersion` to 6; the dynamic `dancer%%N` meeting encodings remain out of scope).

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
- [x] **Dialect manager — named dialects + term editor** (`docs/design/ux.md` §6):
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
  - PR2 delivered (branch `isaacbanner-dialect-pr2`): the library is wired into
    the app — `DialectLibraryController`/`DialectLibraryScope` mounted in
    `main.dart`, with the controller driving the existing `ActiveDialectScope`
    notifier (a listener mirrors `controller.active` into it) so every existing
    consumer is backed by the library with zero changes. Settings → Dialect is
    now a **library manager**: shipped presets (read-only) + custom dialects,
    single active selection, new / duplicate-from / rename / delete, and a
    reusable `DialectEditorScreen` term editor for custom dialects (presets
    offer "Duplicate to customize"). Live preview, collision validation, and
    dance-card/perform quick-switch remain **PR3**.
  - PR3 delivered (branch `isaacbanner-dialect-pr3`): completes the manager. The
    `DialectEditorScreen` now reassembles the working dialect on every edit and
    runs core `Dialect.validate()` live — collision (two terms → one word) and
    empty-substitution issues surface inline via the existing
    `dialect-validation-error` surface as the user types, not only on Save (the
    Save guard is unchanged; detection is core `validate()`, not new logic). A
    labeled **Preview** section renders representative sample figures through the
    working dialect via `FigureRenderer` — `allemande` with `role1s` (role-term
    plural), `swing` with `partners` and `do si do` with `neighbors` (dancer
    term + move substitution), plus a free-text line exercising role-term prose
    substitution — updating live. A reusable
    `DialectQuickSwitch` (`app/lib/src/widgets/dialect_quick_switch.dart`,
    `PopupMenuButton` listing `DialectLibraryScope.all` with the active one
    checked → `setActive`) is placed in the app bars of the dance-detail and
    both perform screens for per-gig quick switching; the whole app re-renders
    live through the existing `ActiveDialectScope` bridge.
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
  **Delivered follow-on — Venue as a reusable entity** (schema v14): the
  per-program free-text `venue` is joined by an optional link to a first-class,
  reusable `Venue` (CC `Venue`: address, contacts, sponsor, price, website,
  generic schedule), so venues are picked once and reused across programs. A
  Settings toggle chooses the editor's entry mode (free-text vs. picker); the
  free-text label and the linked record persist independently (lossless,
  reversible). A linked venue's details win on-screen and in text/PDF export
  (the set-list PDF renders a richer venue block). **Out of scope (follow-up,
  #382 family)**: importing CC `Venue` rows from a Caller's Companion `.USR`.
- [x] 4.3 Program printing/export (PDF, plain text, **emailable text set list** —
  CC parity: "email set list")
- [x] 4.4 Programming matrix view (figures × dances, computed from structured
  figures; first-figure highlight) — CC's Elements matrix without the manual
  checklist. See design/ux.md §4. Derivation is a pure, Flutter-free core
  (`buildProgramMatrix`); UI is a Matrix tab on the Program builder with pinned
  headers and full table semantics. **Delivered follow-on**: a print/report
  version of the matrix — a dedicated LANDSCAPE PDF (`buildProgramMatrixPdf`,
  reusing the bundled-font PDF theme) rendering the moves × dances table with
  shape/text markers (★ program-debut, ▸ dance's first figure, ✓ present) plus
  a legend, wired to a
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

Note: default-value preferences (new-program, display, and dance-authoring
defaults) live in the **Defaults** pane section below.

- [x] G.1 **Auto-size performance cards to fit the screen** — a General settings
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

- [x] G.4 **Soft-delete retention period** — expose the retention window used by
  the startup purge sweep (`DanceRepository.purgeDeleted`, currently hardcoded
  to 30 days) as a user setting (e.g. 30 / 90 days / never auto-purge). Callers
  are protective of their collections; letting them lengthen or disable
  auto-purge is a low-risk safety preference. Touches core only insofar as the
  purge call reads the configured window; default remains 30 days. Persisted
  via `SettingsRepository`.

- [x] G.5 **Back up / restore all data** — a General settings entry point to
  export the full collection + programs + custom fields/dialects/themes to a
  single JSON file and restore from one, plus an optional backup-reminder
  cadence. Addresses Caller's Companion's biggest pain point (data lock-in /
  loss with the binary `.USR`). Overlaps the Phase 6.6 generic JSON
  import/export — this item is the *Settings entry point + backup-reminder
  preference*; the underlying serialization is shared with 6.6. Persisted
  (reminder cadence + last-backup timestamp) via `SettingsRepository`.

- [x] G.7 **Accessibility preferences** — app-wide a11y toggles grounded in
  `research/accessibility-baseline.md`: reduce-motion (dampen non-essential
  animation), always-verbose figure rendering (always apply the roadmap 5.4
  screen-reader/verbose figure rendering in the dance view, not only for AT),
  and confirm-before-delete (an explicit confirm dialog instead of the
  undo-snackbar delete pattern). Persisted via `SettingsRepository`.

- [x] G.8 **Localization & regional formats** — the i18n **framework has landed**
  (PR 1 of a phased extraction). The app now wires `flutter_localizations` +
  `flutter gen-l10n` with **English as the source locale** (`app/lib/l10n/app_en.arb`),
  a live **app-language selector**, and regional-format preferences — a
  **date format** (which controls how program event dates render) plus a
  **first day of week** preference — all persisted via `SettingsRepository` and
  validated on load (OWASP: a
  corrupted/unknown stored value falls back safely, never crashing). Translations
  are **community-driven**: dropping an `app_<locale>.arb` into `lib/l10n/` makes a
  language appear in the selector with no code change (see
  [docs/dev/localization.md](dev/localization.md)). Remaining UI strings are
  extracted into the ARB incrementally in follow-up PRs ("UI localization /
  multi-language" under Later milestones). NOTE: Flutter's `showDatePicker` derives
  its first day of week from the locale and can't be overridden per-call, and the
  app draws no week/month grid of its own yet, so the first-day-of-week preference
  has no consumer today. Its plumbing (pref/`FirstDayOfWeekScope`/storage, validated
  on load) still ships for a future consumer, but the Settings control is presented
  as a disabled "Coming soon" row rather than a live control that changes nothing.

## Defaults (settings pane)

A dedicated Settings pane (sibling to General / Appearance / Dialect) for
app-wide default values — the defaults applied when creating new content
(programs and dances) and the default display/starting-view preferences.
Persisted via `SettingsRepository`; all are local preferences that only affect
NEW entry or the starting display state — existing data and the canonical
taxonomy are unchanged.

**Program defaults**

- [x] G.3 **Default caller & band for new programs** — saved default values used
  to prefill a new program's event metadata (Phase 4.2): the caller name (the
  user is usually the caller) and, optionally, a default band. Caller's
  Companion stores caller/band per set; prefilling saves re-typing at every
  event. Editable per program; defaults only prefill. Persisted via
  `SettingsRepository`.

**Display defaults**

- [x] G.6 **Display defaults** — persisted display preferences: (a) the default
  Collection sort order (title / author / recently-added / last-called), and
  (b) the default dance-detail rendering (canonical vs active-dialect view) —
  some callers always want dialect applied. Both are app-only, small, and
  persist the user's preferred starting state via `SettingsRepository`.

**Dance-authoring defaults**

- [x] DD.1 **New-dance metadata defaults** — configurable defaults applied when
  creating a new dance: form/type, formation, progression, and phrase
  structure. The domain model currently hardcodes these (`Formation(dupleImproper)`,
  `Progression.single`, `4×16` phrase structure); this surfaces them as user
  preferences so a caller who works mostly in one idiom sets them once instead
  of re-picking on every new dance (mirrors how Caller's Companion callers work
  from a "home" configuration). App-only: seed the `DanceEditorScreen` initial
  metadata from the saved defaults.

- [x] DD.2 **Default new-dance template (starting figures)** — the figure list a
  blank new dance begins with, user-editable. Default matches ContraDB's new-dance
  template for now: a single `stand_still` figure of 8 beats (`stand_still × 8`).
  A caller who always opens with the same skeleton (e.g. a balance or a specific
  intro) can set it once. App-only: seed the `DanceEditorScreen` initial figure
  list from the saved template; the taxonomy is unaffected. Persisted via
  `SettingsRepository` (store the template as the same `figures_json` shape used
  for a dance's figures).

- [x] DD.3 **Per-move figure-entry defaults** — user-configurable default
  parameter values applied when INSERTING a given move during dance entry,
  overriding that move's built-in taxonomy `MoveDef` defaults *locally* (the
  canonical `MoveDef` defaults remain the fallback and the shipped taxonomy is
  never mutated). Examples: default a `circle` to `left` + `3 places`; default a
  `hey` to `half` length; set a preferred default `beats` per move. Applied at
  figure-insert time in the editor's figure builder. Persisted via
  `SettingsRepository` as a per-move param-override map keyed by move id; unset
  moves fall through to the taxonomy defaults. This is the entry-speed analogue
  of Caller's Companion's per-user "Insert Call" presets, expressed over our
  structured taxonomy rather than free text.

## Phase 6 — Imports & migration

- [x] 6.1 Source adapter framework + provenance tracking — pure-Dart import pipeline in `packages/compendium_core/lib/src/imports/`: `SourceAdapter` (discover/fetch/parse), `RawRecord` (verbatim payload → provenance), `StructuredDraft`+`ParseQuality` (structured-vs-custom score; parse-never-fails custom fallback), structured `ImportError`s with source context + partial-batch tolerance, dedupe primitives (exact `(source, externalId)` re-import + fuzzy title/author → link/duplicate/skip), and `ImportPipeline` (transactional commit writing provenance) with a session-scoped in-memory undo log (`ImportSession`; no schema bump — provenance persists via the existing v9 table, `DanceRepository.hardDelete` supports undo). Exercised end-to-end by an in-memory fake adapter (test-only). Real source adapters remain 6.2–6.6; review-queue UI is 6.3.
  - **Author resolve-or-create seam delivered** (proposed sub-note — not ticking any box): fulfils the "author linking left to the pipeline; no ids fabricated" promise made across 6.2–6.5. Adapters now carry raw author/choreographer names on `StructuredDraft.authorNames`; `ImportPipeline.commit` resolves each name to a `Choreographer` (`Dance.authorIds`) — exact normalized match (trim/collapse-ws/lowercase, punctuation significant, **no fuzzy**), else create a name-only row; blank names skipped, batch-de-duped to one row per new author, seeded Traditional/Unknown reused. Undo removes only choreographers this batch created and only when unreferenced (repo referenced-guard respected). **Behavior change:** author names are no longer folded into `callingNotes` and the `*_unresolved` info issues are gone; per-name resolution (matched vs created) is surfaced on `CommittedRecord.authorResolutions`. Re-import replaces the resolved author list. See design/imports.md §"Author resolution".
- [ ] ~~6.2 CallersBox sanitization pipeline (separate tool) + hosted snapshot~~ — **Cut**: superseded by direct in-app import from the primary source; we will not ingest a full snapshot or host it for download
- [ ] ~~6.3 CallersBox snapshot import in-app~~ — **Cut**: folded into direct import (no hosted snapshot to consume)
  - Adapter-agnostic import review-queue UI delivered (`app/lib/src/screens/import_review_screen.dart`): source input (.json file / paste) → non-destructive plan → review queue (parse-quality, issues, new/reimport/ambiguous actions; ambiguous defaults to skip) → commit → result summary → undo, with a live Collection refresh. Reached from Settings › General; currently wired to `GenericJsonAdapter`. The CallersBox-specific in-app import shipped via direct link import (see below); the hosted-snapshot path is cut.
  - **Core `CallersBoxAdapter` delivered** (pure-Dart CORE `SourceAdapter`, `ProvenanceSource.callersbox`): parses The Caller's Box **per-dance JSON** (`dance.php?id=N&format=JSON`) through the standard pipeline (discover → fetch → parse). Core stays I/O-free — it parses a payload string; the app URL-fetch + wiring lands in a follow-up PR (so no line ticks and CallersBox import is not yet user-reachable). `Name`→title, `FormationBase`/`FormationDetail`→`FormationShape` best-effort (original kept as detail), `Progression`/`PhraseStructure` best-effort, `CallingNotes`/`OtherNames`/`Appearances`/`Music`→callingNotes, `Tunes`→tunes, `Authors[]`→callingNotes + one info issue each (author linking left to the pipeline; no ids fabricated). **Headline: gendered-term dialect scrubbing** — each `(beats) text` figure line is beats-parsed and routed through the CORE `canonicalizeText(…, Dialect.canonical)` chokepoint (gents/ladies/larks/robins/ladles/gentlespoons → `role1`/`role2` tokens), with a `gypsy`→`shoulder round` legacy-move safety net; the canonicalized text is stored (storage is dialect-agnostic). **Permission tiers honored exactly**: `full` imports figures; `search`/blank/omitted → metadata-only stub with a warning issue (figures never fabricated). Figures import as **custom** (dialect-scrubbed text + beats); free-text `(beats) text` → structured-move grammar parsing is **deferred to a follow-up** (same scope call as ContraDB 6.4 / CC 6.5). Validated against synthetic fixtures + the real id=1 example ("The Nice Combination").
  - **User-facing CallersBox-by-link import wired** (`import_review_screen.dart` + `import_io.dart`): the import screen now offers an explicit source selector; picking "The Caller's Box" resolves a pasted dance URL (`…/dance.php?id=N`) or a bare numeric id to the `&format=JSON` endpoint (`buildCallersBoxJsonUrl`, app-layer), fetches it via the existing `UrlFetcher` seam (single user-initiated fetch — no crawl), and parses it with the core `CallersBoxAdapter` through the same plan → review → commit → undo pipeline; the resolved endpoint is stashed on `ImportRequest.uri` for provenance. Core stays I/O-free. *(6.2/6.3 cut: direct link import is the shipped path; there is no hosted snapshot to consume.)*
  - **Free-text figures now structure where recognized** (shared-parser phase): CallersBox figure lines route through the new core `parseFigureLine` (`imports/figure_parser.dart`), which conservatively upgrades recognized moves (swing/balance/circle/star/chain/allemande/do-si-do/shoulder-round/…) into structured taxonomy figures and degrades everything else to the same dialect-scrubbed `custom` figure as before (parse-never-fails; source beats preserved). Section labels are no longer prefixed onto the figure text (they derive from cumulative beats via the domain model, and beats are already a structured field — the old `'$label: $scrubbed'` prefix duplicated structured data), so custom figures now store clean scrubbed text. The previously-deferred `(beats) text` → taxonomy structuring for CallersBox is delivered here.
- [x] 6.4 ContraDB import
  - `ContraDbAdapter` (pure-Dart CORE `SourceAdapter`, `ProvenanceSource.contradb`) imports ContraDB JSON **per dance** through the standard pipeline (discover → fetch → parse → dedupe → commit). ContraDB's `figures_json` move/parameter model maps move-for-move onto our taxonomy via a **positional→named** conversion table per move (~45 moves), with the gyre → `shoulder_round` term migration and the see saw / swat the flea / meltdown swing aliases. Parse-never-fails: unmapped moves, the ContraDB `custom` move, and unconvertible params fall back to `customFigure` / taxonomy defaults with non-fatal `ImportIssue`s. `start_type` free text is classified to a `FormationShape` best-effort (original kept as detail); `hook` → hook, `preamble`/`notes`/choreographer name → callingNotes (author linking left to the pipeline). **Validated against SYNTHETIC fixtures only** — ContraDB is a grey-code site with no committed real export, so the input shape and per-move positional orders are assumed from the documented `defineFigure` model; revisit with a real dump when available. This `figures_json` path remains **web-unobtainable** (ContraDB serves no JSON: `dances/N.json` → HTTP 406, no public API), so it is reachable only from a self-hosted instance, a DB dump, or the AGPL seed data — the user-facing import (below) uses the HTML page instead.
  - **User-facing ContraDB-by-link import delivered (HTML scrape).** Delivered via HTML scrape of `contradb.com/dances/N` (`ContraDbHtmlAdapter`, pure-Dart CORE `SourceAdapter`, `ProvenanceSource.contradb`): since the `figures_json` path above is web-unobtainable (406 / no API), the user-facing import parses the **server-rendered dance page** — the page a normal website visitor gets — into a `StructuredDraft` (`html` package added to core; still Flutter-free per ADR-001). It reads `h1.dance-show-title`→title, `p.dance-show-formation`→`FormationShape` best-effort (original kept as detail; unknown→other+warning), `p.dance-show-choreographer`→callingNotes + one info issue (`authorIds` left empty; no ids fabricated), and walks `table.contra-table-nonfluid` rows as (section-label, beats, free-text) tuples — carrying the last non-empty section label forward onto continuation rows and capturing `<u>`/`⁋` progression markers via the figure progression flag. Figure text shares the **CallersBox/CC free-text path**: `gypsy`→`shoulder round` safety net + the CORE `canonicalizeText(…, Dialect.canonical)` chokepoint (gendered role terms → `role1`/`role2`), stored with the section label preserved as a prefix (`'$label: $scrubbed'`). Parse-never-fails: malformed/missing elements → non-fatal `ImportIssue`s; a page with no figures table imports as a metadata stub with a warning. Core stays I/O-free — the app fetches. **App wiring:** `import_io.dart` gains `buildContraDbUrl` (bare id or pasted `…/dances/N` URL → canonical `https://contradb.com/dances/N`; user-info dropped), and Settings › Import offers a third **"ContraDB"** source (single user-initiated fetch via the existing `UrlFetcher`, no crawl; resolved URL stashed on `ImportRequest.uri`). Validated against synthetic HTML fixtures modeled on the real `dances/1` DOM **and** the live `contradb.com/dances/1` page (1 dance, 7 figures with correct beats + progression flags, `improper` formation, "Dan Pearl" folded into notes). **Honest scope note:** figures still import as **custom** (scrubbed text + beats + progression flag) — the shared free-text → structured-move taxonomy parser (common to ContraDB / CallersBox / CC 6.5) is now scoped as its **own follow-up phase**, not a per-adapter task.
  - **Shared free-text parser landed (that follow-up phase).** The ContraDB-HTML figure path now routes its scrubbed `(beats, text)` tuples through the core `parseFigureLine` (`imports/figure_parser.dart`): recognized moves become structured taxonomy figures, the rest fall back to the identical `custom` figure (progression flag + source beats preserved). Section labels are no longer prefixed onto the text (they derive from beats), so custom figures store clean scrubbed text — this drops the earlier `'$label: $scrubbed'` prefix. Validated against the real `dances/1`-modeled "The Rendezvous" fixture (balance & swing, long lines, circle → structured; the "or"/multi-move lines correctly stay custom).
- [ ] 6.5 Caller's Companion migration import — map CC tables discovered in the
  schema audit: `Dance` (incl. `Level`, composed/revised dates, `Rating`,
  `UserDefined_*` → custom fields), `Set`+`SetItem` → Programs (with band/caller/
  dancerLevel, ALT flags, guest caller, timing), `Author` → Choreographers,
  `Venue` → venue entity (the entity itself has shipped — schema v14, Phase 4.2
  — though this CC import mapping into it is still pending), `Term` → glossary,
  `Dance_Related` → related links.
  Free-text figures import as `custom` (see design/imports.md §2).
  - **Clipboard/text migration adapter delivered** (part 1 of 2):
    `CallersCompanionTextAdapter` (pure-Dart CORE `SourceAdapter`,
    `ProvenanceSource.callersCompanion`) imports **dances** from CC's "copy
    formatted dance" clipboard/text export through the standard import pipeline
    (discover → fetch → parse → dedupe → commit). CC records map into our model
    via a source-agnostic `mapCallersCompanionDance` unit (`callers_companion_
    mapping.dart`) — header fields → title/level/formation/progression/dates,
    free-text body `(beats) text` lines → `custom` figures (design §2;
    opportunistic structuring deferred until the TCB grammar parser lands),
    author names surfaced for review (no fabricated ids). No stable CC id →
    fuzzy title/author dedupe.
  - **Binary `.USR` migration adapter delivered** (part 2 of 2; box stays open —
    see caveats): the headline FileMaker-12 binary path landed in PR #204,
    reusing the `mapCallersCompanionDance` unit above.
    - Pure-Dart FileMaker-12 `.USR` binary reader (`readFmp12` + SCSU text
      decode) — block/sector chain + catalog table/field-name recovery —
      **validated against the real `CallersCompanion2.USR`** (22 tables, 40
      dances, 205 authors; byte-for-byte cross-check against the `fmptools`
      reference across five real files). Stays **Flutter-free** (pure
      `dart:typed_data`; passes the ADR-001 guard).
    - `CallersCompanionUsrAdapter` imports **dances end-to-end** through the
      existing pipeline (discover → fetch → parse → dedupe → commit), reusing
      `mapCallersCompanionDance`; `externalId` = CC `zk_Dance_ID`; `Rating` →
      `Dance.rating`, `UserDefined_*` → calling notes.
    - **Shared free-text parser now applied to CC figures** (shared-parser
      phase): `mapCallersCompanionDance` routes every body line through the core
      `parseFigureLine`, so recognized moves structure and the rest fall back to
      `custom` (parse-never-fails; beats + section label preserved). Two
      intentional, flagged behavior changes: (1) the CC **text** adapter now
      dialect-scrubs figure text like the other adapters (it previously did not),
      and (2) recognized lines carry structured moves rather than `custom`. Still
      **not validated against real CC figure notation** (the sample `.USR`
      library has no `A1`–`B2`/`Moves` text) — real-figure validation for the
      parser is anchored to the CallersBox/ContraDB fixtures instead, per the
      phase brief.
    - `Set`/`SetItem` → `Program` **builder** (`buildCcPrograms`) delivered and
      **real-file-validated for FK linkage** — it joins on CC's own field values
      `zk_Set_ID`/`zk_Dance_ID`, not the FileMaker record ids. The **app-layer
      program persistence + undo wiring is now delivered** (#273):
      `CallersCompanionUsrImporter` commits the built programs alongside the
      dances in the same review/commit flow and rolls them back on undo, and
      **program provenance dedupe** landed (#284) so re-importing updates existing
      programs instead of duplicating them.
    - Honest caveats keeping 6.5 open: the free-text figure → `custom` scrub is
      **unvalidated against real figure data** (the sample library has no
      `A1`–`B2`/`Moves` notation); and `Author`/`Term`/`Dance_Related`
      tables are confirmed present in the real file but their entity resolution
      is **deferred** (no models yet). The `Venue` entity now **exists**
      (shipped, schema v14 — see Phase 4.2), but importing CC `Venue` rows into
      it from a `.USR` file is still deferred (the #382 follow-up).
- [x] 6.6 Generic import/export (JSON) for backup and inter-user sharing
  - Export/backup delivered under G.5 (whole-collection archive + restore/merge).
  - Inter-user-sharing **import** delivered: `GenericJsonAdapter` (pure-Dart CORE
    `SourceAdapter`, `ProvenanceSource.json`) imports our canonical
    `CompendiumArchive` JSON **per dance** through the standard import pipeline
    (discover → fetch → parse → dedupe → commit). App-side wiring / review-queue
    UI now delivered under 6.3, making JSON import user-reachable end to end.
  - **Program sharing between devices delivered** (send #339; receive #298/#361):
    a program can be shared as one self-contained `CompendiumArchive` bundle that
    carries the program *and* every dance it references, handed to the OS share
    sheet (AirDrop on Apple platforms, share intent elsewhere). The app is also a
    **share target** — opening a received bundle (AirDrop / "Open with" / share
    intent) launches the app, imports the program and its dances through the
    shared import/commit pipeline (identity-first dedupe, untrusted-input
    validation) and auto-opens the program without stopping at the step-by-step
    review queue. Platform intake wiring:
    iOS declares `LSSupportsOpeningDocumentsInPlace` for the share-import type
    (#372); macOS routes incoming files through a native bridge (#361/#377).

## Phase 7 — Release

- [ ] 7.1 Packaging/signing for all platforms; update channel
  - Architecture — [ADR-002](adr/002-distribution-and-update-channels.md); release runbook — [releasing.md](dev/releasing.md). Box stays open: **Android release APKs are now signed** (upload keystore + four CI secrets configured, validated end-to-end on a release run) and **macOS release builds are now signed with a Developer ID and notarized**, but **Windows and Linux** desktop builds still ship **unsigned** (deferred signing wave). GitHub Pages is now enabled, so the per-channel update manifests are hosted and served (and a public landing page ships from `site/`); as of beta.4 the in-app update path also **verifies a signed (Ed25519) update manifest, restricts artifacts to a GitHub-owned host allowlist, and gates launch on that verification**. The **first public beta is well underway** — `v0.1.0-beta.1` (desktop + Android), `v0.1.0-beta.2`, `v0.1.0-beta.3`, and the current `v0.1.0-beta.4` are published on the [Releases page](https://github.com/ibanner56/CallersCompendium/releases); each build ships signed + notarized macOS and signed Android artifacts alongside unsigned Windows/Linux, with iPhone/iPad delivered to TestFlight testers (see the CHANGELOG, including the one-time Android reinstall note for the unified application id).
  - **Delivered**
    - Reusable CI (`_checks.yml` via `workflow_call`) with a thin `ci.yml` caller (#228).
    - Release pipeline `release.yml` (#230): a `v*` tag reuses the checks gate, then a build matrix produces a **draft** GitHub Release of **unsigned** desktop artifacts — Linux x64 (AppImage + tar.gz), macOS universal (dmg + zip), Windows x64 (installer + zip) — under deterministic `CallersCompendium-<ver>-<platform>-<arch>.<ext>` names, plus a `SHA256SUMS` manifest, keyless SLSA build-provenance + artifact attestation, and the per-channel `stable.json` / `beta.json` update manifests. Least-privilege (global `contents: read`; only the publish job elevates), canonical-repo + tag guards, SHA-pinned actions.
    - CHANGELOG-driven release notes (`tools/release/gen_release_notes.py`), channel-conditional — stable fails fast without a `## [x.y.z]` section; beta/rc degrade gracefully (#235).
    - CycloneDX SBOM per release (`tools/release/gen_sbom.py`), folded into `SHA256SUMS` and attested (#242).
    - In-app update client **Stage 1** (A11a, #245): pure-Dart manifest model + schema guard, SemVer compare, channel filter, a dedicated Settings **Updates** section (manual check + beta opt-in + auto-check; the last two default OFF), and a dismissible update banner linking the release page.
    - **Stage 1.5** assisted download (A11b, #250): desktop-only, user-initiated download → mandatory sha256 verify → OS handoff (mobile stays link-only); fails loudly on every path.
    - Update-manifest hosting (A11c, #249): the pipeline publishes each channel's manifest to a persistent `gh-pages` branch (cross-channel-preserving; [releasing.md](dev/releasing.md#publishing-the-update-manifest-github-pages)).
    - **GitHub Pages enabled + public landing page** (#408): Pages is turned on (Deploy from a branch → `gh-pages` → `/ (root)`), so the hosted update manifests are live and a dependency-free landing page ships from `site/` at https://ibanner56.github.io/CallersCompendium/ (auto-aligning download links from `beta.json`, beta-signup CTA, and user-guide links).
    - Android release signing **complete**: Gradle `release` `signingConfig` from `key.properties` in `app/android/app/build.gradle.kts` — with **no** debug fallback (a release build without `key.properties` fails loudly rather than silently debug-signing, #450) (#244) + a `release.yml` build+sign+stage universal-APK leg (#251). The upload keystore and all four `ANDROID_*` CI secrets are now configured, and a release run built + signed `CallersCompendium-<ver>-android-universal.apk` end-to-end (the JDK-21 fix in #265 keeps release lint enabled). Users can sideload the signed APK from GitHub Releases — no Play Store required.
    - iOS release signing + TestFlight leg **wired** (gated on the Apple API-key secrets, which are configured): a `release.yml` iOS leg (`macos-latest`) archives + signs an App Store `.ipa` using **automatic signing driven by an App Store Connect API key** (App Manager role — **no manual cert or provisioning profile**) and uploads it to **TestFlight** via `xcrun altool --upload-app`. The `CFBundleVersion` is a monotonic `GITHUB_RUN_NUMBER` (TestFlight rejects duplicates; `pubspec.yaml` untouched), and the upload is gated to **real `v*` tags** (a `workflow_dispatch` builds + signs for validation but never uploads). iOS is **store-delivered** — the `.ipa` is not a GitHub Release asset / `SHA256SUMS` / manifest entry. Targets **iPhone + iPad**; first channel is internal TestFlight (no Beta App Review). **Now live:** beta.2 was archived, signed, and uploaded to TestFlight, and invited testers are running the iOS/iPadOS build (bug reports have come in against `0.1.0` on iOS). See [releasing.md](dev/releasing.md#ios-testflight-via-app-store-connect-api).
    - **macOS Developer ID signing + notarization delivered** (#311, notarization wait bounded in #329): the `release.yml` macOS leg signs the universal build with an Apple Developer ID and notarizes it (gated on the configured Apple secrets), so the macOS `.dmg`/`.zip` now open without the Gatekeeper right-click workaround. Shipped in beta.2.
  - **Remaining (maintainer — one-time, $0)**
    - Document Android upload-keystore custody (owner, secure backup, rotation policy) — the key is generated and wired into CI, so this is governance, not a build blocker (see [ADR-002](adr/002-distribution-and-update-channels.md) §6).
  - **Deferred** (later signing wave — needs paid developer accounts / a decision; see [ADR-002](adr/002-distribution-and-update-channels.md) §6)
    - Windows Authenticode/Store (MSIX) signing — Windows and Linux desktop currently ship UNSIGNED, so users bypass OS trust prompts manually. (macOS is now signed + notarized and iOS is distributed via TestFlight — see **Delivered** above.)
    - Optional store distribution (Google Play, F-Droid, Flathub). For Linux, the post-beta channel evaluation is decided in [ADR-003](adr/003-linux-native-distribution-channel.md): **Flathub-first** (auto-update + desktop integration + trusted-publisher signing, no self-run infra), with Snap/Launchpad PPA secondary and a self-hosted apt repo only on clear demand.
    - Reconcile the bundle-id mismatch — **done**: all platforms now unify on the Apple form `org.callerscompendium.compendiumApp` (Android `applicationId`/namespace + Linux `APPLICATION_ID` updated to match; Apple was already the target and is the source of truth, since Apple bundle IDs disallow underscores).
- [ ] 7.2 User documentation
  - **Delivered** — the [user-guide hub](user/README.md) + [style guide](user/style-guide.md), and the guides: Getting Started, Dialect (flagship), Imports & migration, Backup & portability, Collection & search, Programs & matrix, Perform mode, Accessibility, Settings, FAQ & troubleshooting, and Glossary; plus an offline **in-app User Guide** (#233). (#219/#222/#223/#224/#229/#233/#239/#240/#243)
  - **Remaining (blocked on other work)**
    - Per-platform install page — the public landing page ([site/](../site/), #408) now surfaces per-platform downloads, and the [Installation guide](user/installation.md) covers first-launch steps; a dedicated install page is optional.
    - Screenshots pass — needs a runnable branded build.
    - Beta-program page — tracked under 7.3.
    - Optional hosted docs site — Pages is enabled; rendering the user guides as a browsable site (beyond the landing page) is still optional.
- [ ] 7.3 Beta program with real callers; feedback triage
  - **Delivered**
    - Triage label taxonomy (`.github/labels.yml` + `label-sync.yml`) and structured issue forms — general feedback, import-source problem, beta check-in, a **beta signup / "Join the beta"** form (#413), plus revised bug/feature reports — with a Discussions + private-email contact config (#221).
    - Beta docs: [beta guide](beta/beta-guide.md), [test charter](beta/test-charter.md), [triage rubric](beta/triage-rubric.md) (#227); a [beta-recruitment plan](product/beta-recruitment.md); and CONTRIBUTING/README feedback hooks.
    - **GitHub Discussions is enabled** (with categories), so the contact/community links resolve.
  - **Remaining (maintainer ops)**
    - Confirm the feedback email/alias (config currently routes to the maintainer's address).
  - **In progress**
    - Beta execution — recruit → run → interview → GA. Underway: builds ship for every platform (macOS signed + notarized and Android signed; Windows and Linux still unsigned; iPhone/iPad via TestFlight), the Getting Started guide is live, and invited callers are filing beta feedback against `v0.1.0-beta.x`. Remaining is the run → interview → GA arc with more real callers.

## Later milestones

- ECD and Squares support
- Optional device-to-device sync, beyond Apple-native AirDrop support.
- **Glossary / terms** (CC `Term`: term + definition + source) — a browsable
  reference of caller terminology, dialect-aware.
- **User-defined quick-entry snippets** — CC's "Insert Call" buttons (per-user
  label → expansion text + beats + a gender-free alternate). **Accepted, reframed**
  over our structured model (see #401): a user shorthand maps to a fully-configured
  taxonomy *figure* (move + params) rather than expansion *text* — beats become a
  figure param and the gender-free alternate is produced by the existing dialect
  system, so there are no per-snippet text/beats/alternate fields. Tracked as #420
  (shorthand→figure mappings), which built on #419 (free-text figure entry mode)
  and #398 (parser-gap flagging); sequencing #398 → #419 → #420, **all delivered in
  beta.4**. The *structured* analogue already shipped as DD.3 (per-move figure-entry
  defaults).
- **UI localization / multi-language** — the i18n **framework has landed** (see
  G.8): `flutter_localizations` + `gen-l10n`, app-language-selector scaffolding, and
  **English as the source locale**. UI-string extraction into `app_en.arb` is
  **substantially complete and continuing in phased PRs** (the final batch is in
  flight); the app remains **English-only** for now, with no translations shipped. What
  remains is finishing extraction and then welcoming **community-contributed**
  `app_<locale>.arb` translations, which require no code
  change to appear. See [docs/dev/localization.md](dev/localization.md).

### Plugin system (user-installable extensions)

A user-installable **plugins folder** that lets the community extend the app
without forking. A plugin is dropped into a known location, discovered and
loaded by the app, and enabled by the user. Plugins can add net-new
destinations to the main navigation rail or otherwise augment the app UX
(buttons, panels, renderers). Local-first and opt-in: this keeps the core lean
while giving power users and contributors a supported extension surface.

Design questions to settle before committing (deferred):

- **Extension surface / API contract** — which hooks a plugin may use: register
  a rail destination, inject actions into the dance/program views, contribute a
  renderer, and read/write collection data through a stable, sandboxed API.
- **Trust, sandboxing, and distribution** — where plugins come from, how they're
  vetted, and how much of the app/data (and network) a plugin may touch.
  Publish/export plugins that need credentials and network access raise the
  trust bar substantially.
- **Packaging + versioning** — how a plugin declares compatibility with the
  app's data model and taxonomy version so upgrades don't silently break it.

Motivating plugins (concrete asks driving the design):

- **ContraDB export / publication** — add buttons to the dance and program views
  to export/publish a dance or program up to ContraDB. This is a *write*
  integration, so it requires the user to be **logged in to their ContraDB
  account** — unlike our read-only search + import, which needs no auth.
  ContraDB today runs plain Devise session auth with **no delegated-auth
  surface** (no OAuth/OIDC provider, no token or API-key system; the only API
  is anonymous read-only). So a publish plugin would either depend on an
  **upstream ContraDB change** to add OAuth/scoped tokens (the clean path) or
  fall back to insecure credential custody (password/session handling) — which
  we would not ship without that upstream capability. Tracked here so the auth
  prerequisite is explicit.
- **Dance visualization / rendering** (from
  [dperelman](https://github.com/dperelman)) — a plugin that visualizes and
  renders dances (spatial/animated choreography views) as a net-new view,
  rather than baking it into core.
- **Choreography validation integration** - dance "compiler" that lets the user
  know whether the choreography entered progresses correctly the expected number
  of times, baked into the dance view as a warning alongside the beat counter.
