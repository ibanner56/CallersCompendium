# Design: Local storage

*Roadmap item 1.12 · v0.1 (2026-07-10). SQLite via drift (ADR-001); schema
lives in the core package; all access through repositories.*

## Approach

- One SQLite database file per profile, in the platform app-data directory;
  user-triggered backup/restore = timestamped JSON export/import (6.6), not
  file copying.
- **Hybrid figure storage** (fixing ContraDB's unqueryable JSON blob):
  1. `dances.figures_json` — authoritative ordered figure list (named params,
     schemaVersion) for lossless load/save.
  2. `dance_figures` — derived, rebuilt on every dance write: one row per
     figure for indexed structural search.
  3. `dance_fts` — FTS5 virtual table over canonical text for full-text search.
  Derived tables are rebuildable from `figures_json` at any time (integrity
  check + repair on migration).

## Tables (abridged)

```sql
dances(id PK, title, form, formation_base, formation_detail, progression,
       phrase_structure, figures_json, hook, calling_notes, status, tunes_json,
       created_at, updated_at, deleted_at)
choreographers(id PK, name UNIQUE, website, notes)
dance_authors(dance_id, choreographer_id, position, PK(dance_id, choreographer_id))

dance_figures(dance_id, idx, move, beats, progression, params_json,
              PK(dance_id, idx))              -- derived
CREATE INDEX dance_figures_move ON dance_figures(move);

CREATE VIRTUAL TABLE dance_fts USING fts5(     -- derived; canonical text only
  title, authors, hook, notes, figures_text, custom_values, content='');

programs(id PK, title, event_date, venue, notes, status,
         created_at, updated_at, deleted_at)
program_slots(id PK, program_id FK, position, dance_id NULL, text,
              is_alt, performed_at)

custom_field_defs(id PK, key UNIQUE, label, type, choices_json,
                  show_in_list, searchable)
custom_field_values(dance_id, field_id, value_text, value_num,
                    PK(dance_id, field_id))
tags(id PK, name UNIQUE, color); dance_tags(dance_id, tag_id, PK(...))
dance_links(id PK, dance_id, kind, url, target_dance_id, label)
provenance(dance_id PK, source, external_id, imported_at, permission,
           license, raw_payload, source_version)
settings(key PK, value_json)                   -- dialects, prefs, source URLs
snapshots(source PK, snapshot_date, manifest_json, imported_at)
```

## Search execution

Filter expressions (ContraDB-style composable tree — and/or/no/then/figure/
formation/…, see future search design in Phase 3) compile to SQL:
- structural leaves → `EXISTS (SELECT 1 FROM dance_figures WHERE move=? AND
  params_json ->> '$.who' = ?)` (JSON1 on derived rows),
- text leaves → `dance_fts MATCH ?`,
- `then` (sequence) → self-join on `dance_figures.idx` ordering.
No full-table in-memory scans (ContraDB pitfall #2). Target: <50 ms over
20k dances (TCB-scale) on tablet hardware — benchmarked in CI.

## Migrations

- drift schema versions with stepwise migrations; every migration ships with
  a test that opens a fixture DB from the previous version.
- `figures_json.schemaVersion` migrates lazily on read + bulk on upgrade.
- Derived tables rebuilt after any migration touching figures.

## Durability

- WAL mode; foreign keys ON; nightly-on-launch `PRAGMA quick_check`.
- All writes in transactions via repository layer; soft deletes purge after a
  configurable retention (default 30 days) via startup sweep.
