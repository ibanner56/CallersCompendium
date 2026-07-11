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
- [ ] 2.4a Complete taxonomy data entry (remaining ContraDB moves) — needs param-vocab decisions (`places`, hey model, ocean/long-wave); see docs/design/figure-taxonomy.md "Implementation status"

## Phase 3 — Collection management

- [x] 3.1 Dance list: browse, sort, filter — `app/lib/src/screens/dance_list_screen.dart`: virtualized `ListView` of dances (title, authors, formation chip, status/tag chips, `showInList` custom fields) sourced from `CompendiumRepositories`; sort by title/author/recently-added/last-called (`ProgramRepository.lastCalledByDance()`, new); a lightweight client-side quick-filter (text + tag/formation `FilterChip`s) over the loaded list — the unified FTS search bar and structured query-builder panel from `docs/design/ux.md` §1 are deferred to 3.2 per that item's explicit scope. Minimal `DanceDetailScreen` placeholder (title/authors/formation/hook/tags) navigated to from the list; full detail/edit UI is later roadmap work. DB now opened on-device via `drift_flutter`.
- [x] 3.2 Search: Title, Author, Type, Formation, Figures, custom fields; full-text
  - 3.2b (core, done): `DanceFilter`/`FigureQuery` AST + `FilterCompiler` (one parameterized SQL query over the derived indexes), schema **v2** migration (`dance_figures.section` column + `(move, section)`/`(dance_id, idx)` indexes, back-filled via the post-open integrity pass), `DanceRepository.search(DanceFilter) → ids`, migration test with a checked-in v1 fixture, and a 20k-dance CI perf benchmark (median < 50 ms). See `docs/design/search.md`.
  - 3.2c (app, done): the Collection screen (`app/lib/src/screens/dance_list_screen.dart`) now hosts the real search UI, replacing 3.1's interim client-side quick-filter. A unified full-text search bar (debounced `FullTextFilter`), a one-tap **Filters** facet panel (`app/lib/src/widgets/facet_panel.dart`: Type/Formation/Progression/Author/Tags/Status + choice/boolean custom fields, OR-within a facet, AND across facets), and an **Advanced** boolean-tree builder (`app/lib/src/widgets/advanced_query_builder.dart`: All/Any/None groups, "has figure" rows with a move type-ahead + section/param pickers, and "then" sequence rows) all compose one `DanceFilter` run through `DanceRepository.search` (dialect-canonicalized via `Dialect.canonical`). Composition logic lives in `app/lib/src/search/collection_query.dart`. Sort exposes Title/Author/Recently added/Last called plus Relevance (only for a bare full-text search); core `SearchSort` gained `recentlyAdded` (`created_at DESC`). Result counts are announced to AT via a live region; results reuse the 3.1 `DanceListTile` and open `DanceDetailScreen`. App startup now runs `CompendiumRepositories.ensureMigrated()` behind a loading gate (`app/lib/src/widgets/app_bootstrap.dart`) so the schema-v2 back-fill completes before the first read.
- [ ] 3.3 Dance editor: structured figure entry + Custom figure, validation of required fields
- [ ] 3.4 Custom user fields (define, edit, search)
- [ ] 3.5 Dance duplication, soft-delete/restore

### Deferred from 3.3a (dance editor metadata form) — tracked follow-ups

- Custom-figure lingo line: underline recognized **taxonomy move** keywords (3.3a/c
  ships only `canonicalize()`'s discouraged-strike + role-underline; ux.md §3 partial).
- `relatedDance` link target picker (3.3a links editor is URL-based only).
- Desktop list/detail **split-pane** editor layout (v1 ships a full-screen editor route).
- Cross-session / persistent **undo** (3.3d ships in-memory undo/redo only).
- (Already tracked elsewhere, pointers only: 2.4a full taxonomy data; the 3.2
  follow-ups — text/number custom-field search UI, nested figure groups inside
  `then`, per-Type taxonomy selection.)

## Phase 4 — Programs

- [ ] 4.1 Program CRUD: create, edit, save, duplicate
- [ ] 4.2 Program builder UX: add/reorder dances, notes/breaks, event metadata
- [ ] 4.3 Program printing/export (PDF, plain text)

## Phase 5 — Performance mode

- [ ] 5.1 Large-print dance card view with dialect applied
- [ ] 5.2 Program navigation (next/prev, jump), screen-wake lock, high-contrast theme
- [ ] 5.3 On-the-fly program adjustments during an event

## Phase 6 — Imports & migration

- [ ] 6.1 Source adapter framework + provenance tracking
- [ ] 6.2 CallersBox sanitization pipeline (separate tool) + hosted snapshot
- [ ] 6.3 CallersBox snapshot import in-app
- [ ] 6.4 ContraDB import
- [ ] 6.5 Caller's Companion migration import
- [ ] 6.6 Generic import/export (JSON) for backup and inter-user sharing

## Phase 7 — Release

- [ ] 7.1 Packaging/signing for all platforms; update channel
- [ ] 7.2 User documentation
- [ ] 7.3 Beta program with real callers; feedback triage

## Later milestones

- Choreography validation integration (external project)
- ECD and Squares support
- Optional device-to-device sync
