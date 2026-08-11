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
       created_at, updated_at, deleted_at, existence_at)
choreographers(id PK, name UNIQUE, website, notes,
               updated_at, deleted_at, existence_at)
dance_authors(dance_id, choreographer_id, position,
             PK(dance_id, choreographer_id),
             UNIQUE(dance_id, position))       -- no ambiguous ordering

dance_figures(dance_id, idx, move, beats, progression, params_json,
              PK(dance_id, idx))              -- derived
CREATE INDEX dance_figures_move ON dance_figures(move);

CREATE VIRTUAL TABLE dance_fts USING fts5(     -- derived; canonical text only
  title, authors, hook, notes, figures_text, custom_values, content='');

programs(id PK, title, event_date, venue, venue_id NULL, notes, status,
         created_at, updated_at, deleted_at,
         existence_at)                         -- venue_id → venues.id (v14)
program_slots(id PK, program_id FK, position, dance_id NULL, text,
              is_alt, performed_at)

venues(id PK, name, address1, address2, city, state_prov, country,
       postal_code, plus4, website, sponsor, event_name, time,
       generic_schedule, price, notes,
       contact1_name, contact1_phone, contact1_email,
       contact2_name, contact2_phone, contact2_email,
       updated_at, deleted_at, existence_at)           -- reusable venue (v14)

custom_field_defs(id PK, key UNIQUE, label, type, choices_json,
                  show_in_list, searchable,
                  updated_at, deleted_at, existence_at)
custom_field_values(dance_id, field_id, value_text, value_num,
                    PK(dance_id, field_id))
tags(id PK, name UNIQUE, color, updated_at, deleted_at, existence_at)
dance_tags(dance_id, tag_id, PK(...))
dance_links(id PK, dance_id, kind, url, target_dance_id, label)
provenance(dance_id PK, source, external_id, imported_at, permission,
           license, source_version)
settings(key PK, value_json,
         updated_at, deleted_at, existence_at)  -- dialects, prefs, source URLs

-- published_sources also carries (updated_at, deleted_at, existence_at); see
-- "The delete model" below for what the three mean and why they are separate.
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
- A **schema floor** (`kMinSupportedSchemaVersion`): versions below it are
  retired — their migration steps, fixtures and `drift_schemas/generated/`
  dumps are
  deleted — and a database stamped below the floor is refused rather than
  partially migrated. See "Retiring a schema version" below.
- `figures_json.schemaVersion` migrates lazily on read + bulk on upgrade.
- Derived tables rebuilt after any migration touching figures.

## Retiring a schema version

`kMinSupportedSchemaVersion`, declared in
[`database.dart`](../../packages/compendium_core/lib/src/storage/database.dart),
is the oldest on-disk version this build can still upgrade. It
is the schema version of the oldest *supported release*, not the oldest version
whose code happens to still exist.

Retiring versions below a new floor means deleting, together:

- the `if (from < N)` steps that can no longer fire (note the off-by-one:
  retiring versions up to and including vX kills steps through `if (from < X+1)`,
  because that step only ever applies to a vX-or-below database),
- the fixtures and generators under `test/storage/fixtures/`,
- the dumps under `drift_schemas/generated/` and their generated classes, and
- the corresponding `migration_test.dart` groups.

**The floor check is not bookkeeping.** Deleting those steps without it would
let a below-floor database open, run only the surviving steps and be stamped at
head while missing everything the deleted steps would have added — silently
corrupt, and permanently mislabelled, since no later migration would ever fire
for it. `onUpgrade` therefore refuses such a file outright, and
`test/storage/schema_floor_test.dart` covers both halves: below-floor is
refused and left untouched, at-floor still migrates to head.

Raising the floor is **user-visible** — databases below it stop opening — so it
belongs in `app/CHANGELOG.md` in user-facing terms, naming the release whose
schema version is being adopted. `tools/ci/check_schema_migration.py` fails any
PR that reintroduces a per-version artefact below the floor.

## The delete model

Every syncable kind — dances, programs, choreographers, tags, published
sources, custom field definitions, venues and settings keys — carries three
timestamps as of schema v25 (issue #898). They answer three different questions
and are deliberately not collapsed into fewer columns:

| Column | Question it answers |
| --- | --- |
| `updated_at` | Which copy's **content** is newer. |
| `deleted_at` | **Retention**: NULL is live, non-NULL is a tombstone and starts the purge / "Recently Deleted" countdown. |
| `existence_at` | Which **existence transition** — live→deleted or deleted→live — happened later. |

`existence_at` is separate from `updated_at` because an ordinary content edit
must not read as an existence transition, and separate from `deleted_at`
because a *revival* has no `deleted_at` to order by: that column is NULL exactly
when the record is live. It is stamped causally, as
`max(localNow, currentExistenceAt + 1 tick)`, so a transition is always strictly
later than the one it supersedes even when the clock has not advanced — delete
and undo inside one second is an ordinary user action, and a tie resolves in
favour of the tombstone. One tick is one **second**, because drift stores
`DateTime` as unix seconds; a smaller increment would round away and the stamp
would tie. See `lib/src/storage/existence.dart`.

Nothing reads `existence_at` yet. It exists for Device Sync (ADR-004), which is
not implemented; the migration that adds it is deliberately behaviour-preserving.

**Deletion is a tombstone, with two named exceptions.** Deleting an entity
writes `deleted_at` and leaves the row on disk, so the deletion is something a
peer can learn from rather than an absence. The exceptions are both erasures
rather than deletions:

- The `hardDelete` / `permanent: true` paths, used only to roll back a
  just-committed import. A rollback treats the import as never having happened,
  so a tombstone would advertise the removal of a record no other device saw.
- `DanceRepository`'s orphaned-reference GC (#462), which runs inside the
  retention purge and collects reusable rows the purge left unreferenced.
  Nobody deleted those; they went away as a side effect.

**Two consequences follow from soft delete, and both are load-bearing:**

- **Reads that join through a soft-deletable parent must filter
  `parent.deleted_at IS NULL`.** A tombstone fires no FK cascade, so the
  `dance_tags`, `custom_field_values`, `dance_sources` and `dance_authors` rows
  a hard delete used to clear now outlive the delete. They are kept
  deliberately — clearing them would mean a revived tag came back with no
  dances — so the reads filter instead. `tags` is the case that bites: it is the
  only converted kind with no referential guard, so a tombstone with live join
  rows is reachable by ordinary use rather than only defensively.
- **The referential guards stay.** Soft delete does not make it safe to remove
  an entity a live record still references, and a tombstone for a still-cited
  entity could not be applied by a peer anyway.

**A tombstone still occupies its UNIQUE natural key.** `choreographers.name`,
`tags.name` and `custom_field_defs.key` are UNIQUE, and drift's upsert targets
the primary key, so re-creating a deleted entity under the same name would hit
the constraint on a row every read filters out — the name looks free and the
insert fails. The upsert therefore *adopts* a tombstoned row holding the
incoming natural key: it writes onto that row's id and returns it. A **live**
row holding the key is left alone and still raises the constraint, exactly as
before. Callers minting a fresh UUID must use the id the upsert returns.

Adoption is **not** revival, and the difference is visible to the user.
Re-writing an entity under *its own* id is "this record is back", and it keeps
its join rows — a revived tag returns with its dances. Adoption is a *new*
entity that happens to want a name a tombstone still holds, so it clears the
adopted row's join rows: before v25 the hard delete had cascaded them away and
the user got an empty tag, and keeping them would mean deleting a tag from two
hundred dances and then re-creating it silently re-tagged all two hundred.
Reusing the old row's id is an implementation detail forced by the foreign keys
and does not leak into what the user sees.

## Durability

- WAL mode; foreign keys ON; nightly-on-launch `PRAGMA quick_check`.
- All writes in transactions via repository layer; dance/program soft deletes
  purge after a configurable retention (default 30 days) via startup sweep. The
  six kinds that became soft-deletable in v25 have no retention sweep yet:
  their tombstones accumulate until Device Sync, which owns retention, adds
  one.

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

