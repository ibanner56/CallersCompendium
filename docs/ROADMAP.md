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

- [ ] 0.1 Contributor docs: CONTRIBUTING.md, CODE_OF_CONDUCT.md, expanded README
- [ ] 0.2 Decide repo conventions: branching, commit style, ADR (architecture decision record) template in `docs/adr/`
- [ ] 0.3 Issue/PR templates and labels for community contributions

## Phase 1 — Investigation & design

Research items (each produces a short written finding in `docs/research/`):

- [x] 1.1 Survey Caller's Companion features & UX — [research/callers-companion.md](research/callers-companion.md)
- [x] 1.2 Survey ContraDB dialect & figure model — [research/contradb.md](research/contradb.md)
- [x] 1.3 Survey CallersBox data — [research/callersbox.md](research/callersbox.md)
- [x] 1.4 Caller's Companion export formats / migration path — covered in [research/callers-companion.md](research/callers-companion.md)
- [x] 1.5 Tech stack evaluation → Flutter — [ADR-001](adr/001-application-stack.md)
- [x] 1.6 Accessibility requirements baseline — [research/accessibility-baseline.md](research/accessibility-baseline.md)

Design items (each produces a design doc + review):

- [ ] 1.7 Domain model: Dance, Figure (structured + Custom), Formation, Program, ProgramSlot, Tag/custom fields, Source/provenance — extensible to ECD/Squares
- [ ] 1.8 Figure taxonomy v1: canonical figure list, parameters (who/direction/beats), serialization format
- [ ] 1.9 Dialect system design: role terms (e.g. Larks/Robins/Gents/Ladies), figure-term substitution, per-user local config, round-trip safety
- [ ] 1.10 Import pipeline design: source adapters (CallersBox snapshot, ContraDB, Caller's Companion migration), dedupe/provenance, conflict handling
- [ ] 1.11 UX design: information architecture, core screens (Collection, Dance editor, Program builder, Performance mode, Settings/Dialect), wireframes, a11y annotations
- [ ] 1.12 Local storage design: SQLite schema, migrations strategy, full-text search
- [ ] 1.13 CallersBox rehosting plan: sanitization pipeline, snapshot format/versioning, hosting location, update cadence, licensing/attribution

## Phase 2 — Core skeleton

- [ ] 2.1 Scaffold the chosen stack; CI (build + test + lint on all platforms)
- [ ] 2.2 Local database layer + migrations + test harness
- [ ] 2.3 Domain model implementation with comprehensive unit tests
- [ ] 2.4 Figure serialization + dialect rendering engine with golden tests

## Phase 3 — Collection management

- [ ] 3.1 Dance list: browse, sort, filter
- [ ] 3.2 Search: Title, Author, Type, Formation, Figures, custom fields; full-text
- [ ] 3.3 Dance editor: structured figure entry + Custom figure, validation of required fields
- [ ] 3.4 Custom user fields (define, edit, search)
- [ ] 3.5 Dance duplication, soft-delete/restore

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
