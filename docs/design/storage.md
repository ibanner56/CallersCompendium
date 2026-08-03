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
dance_authors(dance_id, choreographer_id, position,
             PK(dance_id, choreographer_id),
             UNIQUE(dance_id, position))       -- no ambiguous ordering

dance_figures(dance_id, idx, move, beats, progression, params_json,
              PK(dance_id, idx))              -- derived
CREATE INDEX dance_figures_move ON dance_figures(move);

CREATE VIRTUAL TABLE dance_fts USING fts5(     -- derived; canonical text only
  title, authors, hook, notes, figures_text, custom_values, content='');

programs(id PK, title, event_date, venue, venue_id NULL, notes, status,
         created_at, updated_at, deleted_at)   -- venue_id → venues.id (v14)
program_slots(id PK, program_id FK, position, dance_id NULL, text,
              is_alt, performed_at)

venues(id PK, name, address1, address2, city, state_prov, country,
       postal_code, plus4, website, sponsor, event_name, time,
       generic_schedule, price, notes,
       contact1_name, contact1_phone, contact1_email,
       contact2_name, contact2_phone, contact2_email)  -- reusable venue (v14)

custom_field_defs(id PK, key UNIQUE, label, type, choices_json,
                  show_in_list, searchable)
custom_field_values(dance_id, field_id, value_text, value_num,
                    PK(dance_id, field_id))
tags(id PK, name UNIQUE, color); dance_tags(dance_id, tag_id, PK(...))
dance_links(id PK, dance_id, kind, url, target_dance_id, label)
provenance(dance_id PK, source, external_id, imported_at, permission,
           license, source_version)
settings(key PK, value_json)                   -- dialects, prefs, source URLs
```

Two pieces of this sketch were built and later removed, both at schema v21:

- `provenance.raw_payload` (and its `program_provenance` twin) stored the
  verbatim imported source record. Nothing ever read it, and for an HTML import
  it held the whole source page, so it was dropped (#781). Re-import dedupes on
  `(source, external_id)` and re-fetches from the source, which needs no stored
  copy.
- A `snapshots(source PK, snapshot_date, manifest_json, imported_at)` table
  recorded the last-imported hosted-archive snapshot so the app could offer
  "update available" prompts. That feature was cut in favour of direct in-app
  import (ROADMAP 6.2/6.3; see `callersbox-snapshot.md`, marked superseded), and
  nothing ever wrote a row, so the table was dropped (#782).

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

### Migration safety (app-layer preflight)

Before the app opens the drift database it runs a preflight
(`app/lib/src/data/migration_guard.dart`) that reads the file's persisted
`PRAGMA user_version` — via a short-lived, WAL-aware `sqlite3` connection, not
by opening drift — and compares it to the running `kCompendiumSchemaVersion`:

- **Downgrade protection.** If the file's version is *higher* than the running
  schema (it was written by a newer build), the preflight refuses to open it and
  routes to the `AppBootstrap` error screen ("created by a newer version …
  please update the app"). drift is forward-only with no `onDowngrade`, so
  migrating such a file would silently stamp the version down and risk
  corruption; a belt-and-suspenders guard in `MigrationStrategy.onUpgrade`
  (`from > to` throws) backstops any open path that bypasses the preflight.
- **Backup-before-migrate.** If an upgrade is pending (file version < running),
  the preflight first checkpoints the WAL and copies the whole SQLite file to
  `<app-documents>/db_backups/compendium.pre-v<from>-<UTC-timestamp>.sqlite.bak`,
  retaining the newest 5. This is a raw byte snapshot, distinct from the
  user-triggered JSON backup/restore (6.6/G.5): the JSON path is a *logical*
  export through the current-schema repositories and cannot run against a file
  that hasn't been migrated to that schema yet, whereas a byte copy is
  schema-agnostic and the highest-fidelity rollback for a botched migration.

  **If the snapshot fails, the preflight fails closed** (issue #442). A backup
  that cannot be written (disk full, unwritable `db_backups`, checkpoint
  failure) previously logged and migrated anyway; it now instead surfaces a
  blocking consent dialog that explains the data-loss risk and names the likely
  cause (low storage / unwritable backups folder). The user chooses **Quit**
  (the default — abort so they can free space, fix permissions, or take a manual
  backup first) or **Proceed without a backup**. Without an explicit "proceed"
  the migration is aborted (`MigrationSnapshotAborted`, rendered on a
  non-retryable `AppBootstrap` screen, mirroring the downgrade guard) so a failed
  upgrade can never become an unrecoverable one. A successful snapshot is
  unchanged — no prompt.

  **Restoring a pre-migration snapshot:** quit the app, replace the live
  `compendium.sqlite` in the app-documents directory with the chosen
  `.sqlite.bak` (renaming it back to `compendium.sqlite`), and relaunch. Because
  the snapshot is stamped at the older `user_version`, opening it with the build
  that created the backup migrates it forward again; if the migration itself was
  the problem, open it with the matching older app version instead.

