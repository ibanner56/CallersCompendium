# Design: Local storage

*Roadmap item 1.12 · v0.1 (2026-07-10). SQLite via drift (ADR-001); schema
lives in the core package; all access through repositories.*

## Approach

- One SQLite database file per profile (`compendium.sqlite`), in a per-app
  data directory that is never a user-visible, cloud-synced folder
  (`resolveDatabaseFile`): `%LOCALAPPDATA%\org.callerscompendium\Caller's
  Compendium` on Windows (Local, not Roaming: roaming profiles copy Roaming, a
  poor home for a live WAL database; `path_provider` exposes LocalAppData only
  as the application *cache* directory, which is what the resolver asks for),
  the application support directory (`$XDG_DATA_HOME/<app id>`) on Linux, and the
  app's own documents directory on Android, iOS and macOS (sandboxed or
  app-private). On Windows the `<CompanyName>` folder comes from the
  `Runner.rc` version resource, pinned to `org.callerscompendium` by
  `tools/ci/check_windows_company_name.py`: changing it moves every Windows data
  folder. Earlier builds used `Documents` on Windows and Linux, which
  OneDrive's folder backup syncs and which on Linux is `$HOME` itself when
  `XDG_DOCUMENTS_DIR` is unset. The first launch after updating moves the
  database, its `-wal`/`-shm` sidecars and the pre-migration snapshots out of
  Documents (and out of the Roaming fallback directory an earlier build could
  use on Windows) inside the migration preflight, before anything opens the file
  (`relocateLegacyDatabase`): copy, fsync, verify size, rename into place, then
  delete the source; it never overwrites a destination, and if a database exists
  at both the old and new location, or the move fails, nothing is deleted and
  startup stops on a non-retryable screen (`DatabaseRelocationBlocked`) that
  lists each conflicting copy's location, size and last change (never a path).
  The whole move runs under an exclusive advisory lock on `.relocation.lock` in the
  database directory (the single-instance guard's `AdvisoryFileLock`, plus an
  in-process queue), and its preconditions are checked only once that lock is
  held, so a second process that waited finds nothing left to move. It refuses
  to move a database another connection has open, and keeps every other
  connection out until the old file is deleted: the checking connection stays
  open from the check to the delete with `locking_mode = EXCLUSIVE` and
  `BEGIN EXCLUSIVE`, after taking a WAL database out of WAL mode (which SQLite
  refuses while any other connection, even an idle one, has the file). The
  main file is copied through a handle kept open until after that connection
  closes, because closing any other descriptor would release POSIX record
  locks. Limits: a pre-WAL rollback-journal file gives no signal for an idle
  connection; on Windows the lock is released just before the delete (an open
  file cannot be deleted there, so an opener in that gap makes the delete fail
  and the move roll back), and a database over 1 GiB cannot be copied while
  locked (the move fails, nothing deleted). The Windows behaviour is reasoned
  from SQLite's and Dart's sources; CI does not run tests on Windows.
  A rollback never removes the new copy unless the old database file is still
  there. While no database exists at the new location, a Documents path that does not
  exist (a redirected folder on a disconnected share or drive letter), or a
  Documents folder Windows cannot resolve, also stops startup
  (`legacyUnreachable`) instead of reading as "no library". Only a missing path
  is detected: an unmounted volume that leaves an empty mount-point folder
  behind reads as an empty Documents. After a move, a breadcrumb *folder*
  named `compendium.sqlite` (holding a `README.txt` that names the new
  location) is at the old path: it is made inside the delete step, right after
  the main file is deleted (on Windows, after the lock was released for that
  delete), so a move
  that cannot make it rolls back (only a crash in the instant between the
  delete and the breadcrumb leaves the path free, unrepaired), and it is added
  best-effort at each other old path whose folder exists. Every
  earlier build (v0.1.0 to v0.5.4, all on drift_flutter 0.3.1) skips its
  preflight because `File.exists()` is false for a folder, then fails to open
  the path (SQLite cannot open a folder) and shows its startup error screen
  instead of creating an empty library; the relocation ignores it for the same
  reason. Pre-migration snapshots go in `db_backups/` beside
  the file. User-triggered backup/restore = timestamped JSON export/import (6.6), not
  file copying.
- **Hybrid figure storage** (fixing ContraDB's unqueryable JSON blob):
  1. `dances.figures_json` — authoritative ordered figure list (named params,
     schemaVersion) for lossless load/save.
  2. `dance_figures` — derived, rebuilt on every dance write: one row per
     figure for indexed structural search.
  3. `dance_fts` — FTS5 virtual table over canonical text for full-text search.
  Derived tables are rebuildable from `figures_json` at any time (integrity
  check + repair on migration). One more input since #1023: a use of a figure
  of your own is indexed as it renders, from its live definition in
  `user_glossary_entries`, and its reference stays in `params_json` only while
  the use is attached and its figure is live. A local write of such a
  definition rebuilds the derived rows of the live dances using it (found by
  their `figures_json`) without rewriting the dances themselves; a dance in
  the Trash is rebuilt when restored, and a sync apply batch that applies a
  glossary entry rebuilds the rows of every dance using it, in the Trash too,
  from the live figures (#1920). Deleting a figure freezes each use
  in a live dance as plain text; a dance in the Trash keeps the line its use
  last stored. After the delete, the app also freezes the uses in the default
  figure lists in the settings, rendering them as the dances are
  (`freezeUserFigureUsesIn`), and drops the figure's dialect entries and
  matrix column (plan C9). These are settings values, not dances, so the
  delete's caller writes them, outside the delete's transaction and best
  effort: a failure is logged, and the figure stays deleted.
  Switching a figure to the shipped figure of its name (maintainer decision 5,
  for a name a later version ships) is the delete's twin:
  `switchUserFigureToBuiltIn` rewrites each attached use in a live dance as a
  figure of the shipped move or alias, through a mapping of every parameter
  and choice value (`switchUserFigureUsesIn`), and retires the figure, in one
  transaction. Each switched use states its beats, so a dance's sections
  don't move. A use it can't map (detached, or holding a value no longer the
  figure's) is frozen as plain text instead, and the Trash is left as it is.
  As for a delete, the uses in the settings, the dialect entries and the
  matrix column are its caller's to rewrite or drop, outside the transaction.

## Tables (abridged)

A sketch, not the schema: the authoritative column list is `tables.dart`, and
the FTS and index DDL is `database.dart`.

```sql
dances(id PK, title, form, formation_shape, formation_detail, progression,
       phrase_structure, figures_json, hook, calling_notes, status, level_id NULL,
       tunes_json,
       created_at, updated_at, deleted_at, existence_at)
difficulty_levels(id PK, label UNIQUE, position,
                  updated_at, deleted_at, existence_at)
choreographers(id PK, name UNIQUE, website, notes,
               updated_at, deleted_at, existence_at)
dance_authors(dance_id, choreographer_id, position,
             PK(dance_id, choreographer_id),
             UNIQUE(dance_id, position))       -- no ambiguous ordering

dance_figures(dance_id, idx, move, beats, progression, params_json,
              PK(dance_id, idx))              -- derived
CREATE INDEX dance_figures_move ON dance_figures(move);

CREATE VIRTUAL TABLE dance_fts USING fts5(     -- derived; canonical text only
  dance_id UNINDEXED, title, authors, hook, notes, figures_text,
  custom_values, sources,
  tokenize = 'unicode61 remove_diacritics 1', prefix = '1 2');
-- `dance_id` is UNINDEXED, so deleting a dance's row is a scan of the whole table.
-- Writing an *existing* dance therefore replaces its rows (delete, then insert);
-- writing a *new* one only inserts — a dance with no `dances` row has none to
-- delete, since a hard delete removes its derived rows with it — and a bulk
-- rebuild clears the table once instead of deleting per dance. Deleting per new
-- dance made an N-dance import O(N²) (1,000 → 8,000 dances: 0.57 → 1.66 ms per
-- dance).
-- The one exception is the batch edits of level, rating and tunes
-- (`DanceRepository._updateMany`, `rebuildDerived: false`): none of them is an
-- input to a derived row, so they leave the rows as they are. A custom-field
-- batch edit changes `custom_values` and does rebuild.

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
- `then` (sequence) → self-join within a dance, correlated on
  `dance_figures.group_idx` (not `idx`; #748).
No full-table in-memory scans (ContraDB pitfall #2). Target: <50 ms over
20k dances (TCB-scale) on tablet hardware — benchmarked in CI.

## Migrations

- drift schema versions with stepwise migrations; every migration ships with
  a test that instantiates the previous version from its generated schema
  snapshot (`GeneratedHelper`) and seeds the rows it asserts on.
- The **floor version also keeps a real binary fixture**:
  `test/storage/fixtures/v35.sqlite`, written by the `v0.4.0-beta` release with
  representative rows. A schema snapshot carries structure only, so it cannot
  show that `onUpgrade` preserved data; `real_release_fixture_test.dart`
  opens the fixture, migrates it to head and reads the rows, FTS content,
  links, provenance, program and settings back. A second one, `v38.sqlite`
  from `v0.6.0-beta`, covers the bridge release. See "Floor fixtures" below.
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
- the fixtures and generators under `test/storage/fixtures/` for the retired
  versions (the **new floor keeps its own**: see the next list),
- the dumps under `drift_schemas/generated/` and their generated classes, and
- the corresponding `migration_test.dart` groups.

And adding, together, a fixture for the new floor:

- **capture `test/storage/fixtures/v<new floor>.sqlite` from the new floor
  release's tag** with `tool/fixture_generators/generate_release_fixture.dart`
  (the recipe, including making the package resolve standalone at the tag, is in
  its header), and record its sha256 under "Floor fixtures" below. The
  existence test in `real_release_fixture_test.dart` derives the file name from
  `kMinSupportedSchemaVersion`, so a floor raise without the new fixture is a
  red test, not a silent loss of coverage.

And noting that the release which carries the raise must decide whether to
announce the end of life for versions below the new floor: an entry in
`tools/release/retirements.json`, committed before the tag
([releasing.md](../dev/releasing.md), "Announcing an end of life for older
builds"). No CI check ties a floor raise to an entry, so the release checklist
asks.

**The floor check is not bookkeeping.** Deleting those steps without it would
let a below-floor database open, run only the surviving steps and be stamped at
head while missing everything the deleted steps would have added — silently
corrupt, and permanently mislabelled, since no later migration would ever fire
for it. `onUpgrade` therefore refuses such a file outright, and
`test/storage/schema_floor_test.dart` covers both halves: below-floor is
refused and left untouched, at-floor still migrates to head.

Raising the floor is **user-visible** — databases below it stop opening — so it
needs an app entry in a `changelog.d/` fragment, naming the release whose schema
version is being adopted. `tools/ci/check_schema_migration.py` fails any
PR that reintroduces a per-version artefact below the floor.

### Floor fixtures

A drift schema snapshot has the tables but no rows, so the tests built on
`GeneratedHelper` seed only what they assert on and cannot detect a migration
that destroys, truncates or reinterprets existing data (an
`UPDATE dances SET figures_json = '[]'` at the top of `onUpgrade` leaves every
one of them green). The fixtures below are databases written by the real
release code, holding four dances (a fully populated one with figures including
a `meanwhile`, tags, an author, tunes, links, a source citation, a custom field
and provenance; a plain one; a soft-deleted one; a diacritic-titled one), a
program with three slots, a venue, choreographers, and the settings markers that
release's startup wrote. They are not shipped user databases: they are what that
release produces for this seed, which is the same code path a real collection
went through.

`real_release_fixture_test.dart` copies each one to a temporary directory, opens
it with the current `CompendiumDatabase`, runs `ensureMigrated`, and asserts
`user_version` reached head, `foreign_key_check` and `integrity_check` are
clean, and that every value the generator seeds to something other than a
default reads back unchanged in the tables a user sees content from: the dances
(titles, hooks, calling notes, walkthrough, rating, tunes, timestamps, figures
with their moves and params, tags, authors, custom-field values, links with
kind, url, label and target, citations, provenance), the tags and their colours,
authors, the venue, the published source, the custom-field definition, the
program (date, venue, level, caller, band, notes, timestamps, and slots with
ids, positions, minutes and guest caller), the `ui.*` settings and the default
difficulty levels. Columns left at their defaults are not read, nor are the
bookkeeping timestamps of the tag, author, venue, source, custom-field,
difficulty-level and settings rows. FTS search is only checked to *work*
(including diacritic folding). Values the open legitimately rebuilds are not
compared: the FTS tables, `dance_figures` (including `canonical_text`) and the
`__*_done` repair markers, which a migration that deleted them would be
indistinguishable from, because startup re-creates them.

| Fixture | Written by | Schema | sha256 |
| --- | --- | --- | --- |
| `v35.sqlite` (the floor) | `v0.4.0-beta` (`04ab10c7`) | 35 | `bce61632dce3f44ff56cd32cec101747dadc1339c17788b3951bccfaf884b290` |
| `v38.sqlite` (the bridge release) | `v0.6.0-beta` (`a6d52290`) | 38 | `44dfb5a4b25143445a17feb1af6b224a6caa2a4ba5bf9ec3ecc315c000ac1286` |

`v38.sqlite` is the release `kBelowFloorBridgeTags` sends v20–v34 collections
through, so it is the file many migrating collections really reach head from. It
is not below the floor, so the below-floor gate allows it; once the floor passes
v38, delete it and its group in the test. The floor fixture, by contrast, has its
name derived from the constant, so raising the floor without a new fixture fails
the existence test, and a test fails if any `v*.sqlite` below the floor is left
in the fixtures directory. Neither guard stops someone deleting the test itself
or editing both the constant and the expectations in the same PR: review still
has to notice that.

Regenerate by running `tool/fixture_generators/generate_release_fixture.dart`
from a checkout of the release tag (recipe in its header); the output is
byte-reproducible on the same sqlite3 build, so the digest above can be
re-derived.

## Schema version history

`CompendiumDatabase.schemaVersion` (in
[`database.dart`](../../packages/compendium_core/lib/src/storage/database.dart))
is the on-disk schema version, and this is its per-version log. It lives here
rather than on the class because it is a ledger of decisions already shipped:
it constrains nothing on the declaration, and it grows on every bump, so every
reader of that file paid for the whole history. What *does* constrain the
declaration — the four things a bump must ship, and the rule that a bump never
rides a PATCH release — stays there, next to the constant it governs.

**Every bump appends an entry here, in the same PR.**
`tools/ci/check_version_history.py` fails a PR that moves the constant without
adding the matching entry. A change added to a version that has not shipped yet
(see CONTRIBUTING.md, "Adding to an unreleased version") amends that version's
entry instead. The gate cannot see that case, because the constant does not
move.

### Retired (v1–v34): history only

**v1–v34 are RETIRED** (#837, then floor raises since, the latest to v35 once
every release before `v0.4.0-beta` was retired): they predate `v0.4.0-beta`,
the oldest supported release, so their migration steps, fixtures and schema
dumps have been deleted and [kMinSupportedSchemaVersion] refuses a database
stamped below v35. Their entries are kept below as history — they explain why later
columns exist and are still referenced by the steps that survive — but there
is no longer any code path that migrates from them.

- v1 (2026-07-10): initial schema — see ["Tables (abridged)"](#tables-abridged)
  above.
- v2 (2026-07-11): section-aware search (`docs/design/search.md`). Adds the
  nullable `dance_figures.section` column plus the `dance_figures_move_
  section` index (the `Then` self-join's `(dance_id, idx)` access is
  already served by the composite primary key's implicit index).
  `onUpgrade` performs the DDL and durably records
  [derivedRebuildRequiredKey]; the derived `section` values are back-filled
  by a post-open integrity pass ([DanceRepository.rebuildAllDerived]) that
  [CompendiumRepositories.ensureMigrated] runs when the marker is set — the
  rebuild needs the taxonomy/renderer, which `MigrationStrategy` can't
  reach.
- v3 (2026-07-13): CC-parity program event metadata (`docs/design/
  domain-model.md` "CC parity backfill"). Adds nullable `programs.band`,
  `programs.caller`, `programs.dancer_level`, `program_slots.guest_caller`,
  and `program_slots.planned_minutes`. All nullable with no back-fill
  (existing rows get NULL); programs/slots do not feed the derived
  `dance_figures`/`dance_fts` indexes, so no derived rebuild is required.
- v4 (2026-07-13): CC-parity dance difficulty (`docs/design/domain-model.md`
  "CC parity backfill", ROADMAP 4b.1). Adds the nullable
  `dances.level` (ordered [DanceLevel], persisted by name) and
  `dances.mixed_level` (bool, defaults `false`) columns. Existing rows get
  `level` NULL / `mixed_level` false. `level`/`mixed_level` are dance-scalar
  metadata, not figure text, so they do not feed the derived
  `dance_figures`/`dance_fts` indexes and no derived rebuild is required.
- v5 (2026-07-13): CC-parity composed/revised dates (`docs/design/
  domain-model.md` "CC parity backfill", ROADMAP 4b.2). Adds the nullable
  `dances.composed_on` and `dances.revised_on` columns, each holding a
  canonical partial-precision [PartialDate] string (`YYYY`/`YYYY-MM`/
  `YYYY-MM-DD`). Existing rows get NULL. These are author/bibliographic
  scalar metadata (distinct from the record stamps `created_at`/
  `updated_at`), not figure text, so they do not feed the derived
  `dance_figures`/`dance_fts` indexes and no derived rebuild is required.
- v6 (2026-07-13): CC-parity dance rating (`docs/design/domain-model.md`
  "CC parity backfill", ROADMAP 4b.3). Adds the nullable `dances.rating`
  column (an `int` star rating validated to `1..5` at the [Dance] boundary;
  `null` = unrated). Existing rows get NULL. `rating` is dance-scalar
  curation metadata, not figure text, so it does not feed the derived
  `dance_figures`/`dance_fts` indexes and no derived rebuild is required.
- v7 (2026-07-14): CC-parity author contact (`docs/design/domain-model.md`
  "CC parity backfill", ROADMAP 4b.4). Adds the nullable
  `choreographers.email` and `choreographers.location` columns plus
  `choreographers.deceased` (bool, defaults `false`). Existing rows get
  email/location NULL and deceased false. Choreographer contact is
  scalar author metadata (not figure text) and choreographers do not feed
  the derived `dance_figures`/`dance_fts` indexes, so no derived rebuild is
  required. (`email`/`location` are private — never emitted in shareable
  exports; see [Choreographer].)
- v8 (2026-07-14): first-class published-source citations
  (`docs/design/domain-model.md` "CC parity backfill", ROADMAP 4b.5).
  Adds two brand-new tables: `published_sources` (a reusable bibliographic
  entity — id/title plus nullable author/year/url/notes) and the ordered
  `dance_sources` join (danceId/sourceId FKs cascade, freeform nullable
  page/number, position). No columns are added to existing tables and no
  data is back-filled (fresh tables start empty). These new tables do NOT
  feed the derived `dance_fts`/`dance_figures` indexes (searchability is
  ROADMAP 4b.5b), so NO derived rebuild is required by this migration.
- v9 (2026-07-14): published-source citations become SEARCHABLE (ROADMAP
  4b.5b). Adds a `sources` column to the `dance_fts` FTS5 virtual table
  holding the searchable text (title + author) of each cited
  [PublishedSources] row. Because an FTS5 table's column set is fixed at
  creation, the migration DROPs and recreates `dance_fts` with the new
  shape; the FTS rows cannot be repopulated in the migration (that needs the
  taxonomy/renderer to re-derive figure text and the repository to join the
  citation → published-source text), so — exactly like the v2
  `dance_figures.section` back-fill — `onUpgrade` durably records
  [derivedRebuildRequiredKey] and [CompendiumRepositories.ensureMigrated]
  performs the full derived rebuild ([DanceRepository.rebuildAllDerived]),
  which repopulates every `dance_fts` row (including the new `sources`
  column) and clears the marker. No table columns are added elsewhere.
- v10 (2026-07-15): program import provenance. Adds one brand-new table
  (`program_provenance`); no columns added to existing tables and no
  back-fill. It does NOT feed the derived `dance_fts`/`dance_figures`
  indexes, so no derived rebuild is required.
- v11 (2026-07-15): CC-parity "hide alternates in set list". Adds a single
  additive boolean column `hide_alternates` on `programs` (defaults false).
  Programs don't feed the derived indexes, so no derived rebuild is required.
- v12 (2026-07-19): issue #290 ocean-wave cleanup — the sanctioned
  canonical-changing migration. The `form_an_ocean_wave` MoveDef was removed
  from the taxonomy, so `onUpgrade` REWRITES every stored figure with
  `move == 'form_an_ocean_wave'` in each `dances.figures_json` blob to
  `pass_the_ocean` (when `passThru` is true — its default) or
  `form_a_short_wave` (when false), dropping `passThru` and carrying the rest.
  This changes those figures' `canonicalText`/FTS, so — like the v2/v9 steps
  — `onUpgrade` durably records [derivedRebuildRequiredKey] and
  [CompendiumRepositories.ensureMigrated] runs the full
  [DanceRepository.rebuildAllDerived] (which regenerates `dance_figures` +
  `dance_fts` from the rewritten `figures_json` through the renderer) and
  clears the marker. The rewrite is parse-never-throw and lossless: any row
  or figure that can't be cleanly remapped is left byte-identical so it falls
  through to the non-destructive unknown-move path (issue #358) at read time,
  never dropped or corrupted.
- v13 (2026-07-22): performance-only index. Adds
  `dance_links_dance_id` (`dance_links(dance_id)`) so the batched link
  hydration in [DanceRepository.listAll] (and the single-id lookup behind
  `getById`) seeks by index instead of full-scanning `dance_links` on every
  `dance_id IN (…)` chunk. Pure DDL: no columns/tables added, no data
  rewritten, and the derived `dance_fts`/`dance_figures` indexes are
  untouched, so no derived rebuild is required.
- v14 (2026-07-22): first-class venue entity. Adds one brand-new table,
  `venues` (a reusable venue — id/name plus 20 nullable address/contact/
  schedule columns, faithful to CC's `Venue` table), and a single nullable
  `programs.venue_id` soft reference to it. Purely additive: `createTable` +
  `addColumn`, no data back-fill (fresh table starts empty; existing
  programs get `venue_id` NULL and keep their free-text `venue` label). The
  free-text `programs.venue` label and the `venue_id` entity link coexist
  non-destructively. `venue_id` is a deliberately un-constrained soft
  reference (no FK) — referential integrity is enforced at the app layer by
  `VenueRepository.delete`'s guard — so this migration adds NO FK and no
  rebuild marker. It DOES add one plain lookup index, `programs_venue_id`
  (see [venueLookupIndexSql]), so that guard's reference-count query stays
  cheap instead of full-scanning `programs`. Venues do NOT feed the derived
  `dance_fts`/`dance_figures` indexes, so NO derived rebuild is required.
- v15 (2026-07-28): dedicated per-dance walkthrough (issue #370). Adds a
  single additive `dances.walkthrough` text column (defaults to `''`) — a
  free-form step-by-step walkthrough, distinct from the short
  `calling_notes`. Purely additive `addColumn`; existing rows get `''` and
  stay valid. It is dance-scalar *content* (not figure text), so it does NOT
  feed the derived `dance_fts`/`dance_figures` indexes and NO derived rebuild
  is required.
- v16 (2026-07-30): performance-only index (issue #627). Adds
  `program_slots_dance_id` (`program_slots(dance_id)`) so the per-dance
  calling-history/stats lookups (`lastCalledByDance`, `countByDance`,
  `callingHistoryForDance`, `halfCallingStatsForDance`,
  `_sortByLastCalled`, `_cleanupDanglingReferences`) seek by index instead
  of full-scanning `program_slots`. Mirrors the v13 `dance_links_dance_id`
  index. Pure DDL: no columns/tables added, no data rewritten, and the
  derived `dance_fts`/`dance_figures` indexes are untouched, so no derived
  rebuild is required.
- v17 (2026-07-30, REVERTED before release): typed-prose canonicalization
  (issue #613). The step routed `hook`/`calling_notes`/`walkthrough` through
  `canonicalizeText`, but that substitution's always-on synonym set includes
  ordinary English words and proper nouns (`man`, `men`, `lady`, `ladies`,
  `lark(s)`, `robin(s)`, …), so across long-form prose it corrupted dance
  titles, tune names and people's names ("Lady of the Lake" → "role2 of the
  Lake"). No released build ever contained it, so no database in the wild
  was rewritten. The version number is retained as a no-op step so v18+
  keep their numbering. Free prose is stored verbatim; figure notes are
  still canonicalized (they carry figure-adjacent modifiers).
- v18 (issue #295): fused-move retirement + figure rewrite. The
  `allemande_orbit` MoveDef was removed from the taxonomy (v19); its stored
  figures are rewritten in each `dances.figures_json` blob to a
  `meanwhile` container `[allemande{who, hand, turn=old inner},
  orbit{who=invert(who), turn=direction derived from hand, amount=old
  outer}]`, carrying the fused figure's `beats` as the shared container
  total. This is a SANCTIONED canonical-changing migration (cf. the v12
  ocean-wave rewrite): rewriting `figures_json` changes those figures'
  derived `canonicalText`/FTS, so it schedules a derived rebuild (marker),
  but only when a figure actually changed. Per-row and per-figure
  parse-never-throw: a blob or entry that can't be cleanly remapped (e.g. a
  wildcard `hand`, or a `who` with no pair-inverse) is left byte-identical,
  falling through to the #358 unknown-move path rather than being
  dropped/corrupted.
- v19 (issue #295): taxonomy move RENAME. `form_a_short_wave` became
  `form_short_waves` at taxonomy v21, so every stored figure with
  `move == 'form_a_short_wave'` in each `dances.figures_json` blob is
  rewritten to the new id — including sides nested inside a `meanwhile`
  container (which the v18 rewrite can itself create). Params are carried
  over untouched: this is purely an identity change. Like v12/v18 it is a
  SANCTIONED canonical-changing migration (the display/canonical text moves
  from "form a wave" to "form short waves"), so it schedules a derived
  rebuild (marker) — but only when a figure actually changed. Per-row and
  per-figure parse-never-throw: a malformed blob or entry is left
  byte-identical, falling through to the #358 unknown-move path. Note the
  historical v12 step still writes the OLD id (it is frozen history); a
  long-hop upgrade from ≤ v11 therefore lands on `form_a_short_wave` at v12
  and is renamed here at v19.

- v20 (gate merge): duplicate-move retirement + figure rewrite. `gate` and
  `rotation_gate` — which both rendered the display name "gate" and showed
  as two identical picker rows — are MERGED into one `gate` move (taxonomy
  v22), and stored figures of BOTH are rewritten in each
  `dances.figures_json` blob onto it. `rotation_gate`'s `who` becomes the
  merged move's **`pair`**, NOT its `who`: TCB's subject names the pairing
  you gate WITH, while ContraDB's `who` names the side that extends a hand
  and backs up (libfigure `figure.js:844`), so reusing the slot would
  silently reinterpret every TCB-imported gate. The legacy `gate`'s `who`,
  `whom` and `face` keep their meaning exactly (`face` was already the
  ENDING facing). Each retired move's own defaults are materialized
  explicitly for omitted params, since the merged move defaults every slot
  to `unspecified`; `beats` is carried verbatim so beat totals are
  unchanged. Recurses into `meanwhile` containers (a TCB `||` line can hold
  two gates), bounded in depth. A SANCTIONED derived-data-changing migration
  (cf. v12, v18, and the v19 wave-move rename): it schedules a derived
  rebuild, but only when a figure actually changed. The rebuild is owed
  because `dance_figures` projects the move id and `params_json` as well as
  the canonical text — `danceIdsWithFigure` queries exactly those two — so
  skipping it would leave structured search matching the RETIRED
  `rotation_gate` id and missing every migrated `gate`. Per-row and per-figure
  parse-never-throw. Chains cleanly after v19 — that step only rewrites the
  `form_a_short_wave` move id and touches no gate figure, and neither step
  adds a column or table, so schema 18/19/20 are structurally identical.
- v21 (issues #781/#782): first structural REMOVAL. Drops
  `provenance.raw_payload` and `program_provenance.raw_payload` (rebuilt via
  `TableMigration`, the portable route that doesn't require SQLite 3.35+
  `DROP COLUMN`) and the unused `snapshots` table. None fed the derived
  `dance_fts`/`dance_figures` indexes, so NO derived rebuild is required.
- v22 (issue #748): adds the derived `dance_figures.group_idx` correlation
  column so the `Then` sequence operator distinguishes a genuine before/after
  pair from two *concurrent* sides of one `meanwhile` container. Previously
  `Then` correlated on `a.idx < b.idx`, but the #590 flattener gives a
  container's sides consecutive `idx` (the `{danceId, idx}` PK forces a
  distinct idx per row), so simultaneous sides looked sequential and
  `Then(X, Y)`/`Then(Y, X)` both matched an `X while Y` container. The signal
  was absent from the index, so this needs a column, not just a query change.
  `group_idx` is shared by every row flattened from one top-level figure and
  monotonic across them; `Then` now correlates on `a.group_idx < b.group_idx`.
  Like the v2 `section` add, existing rows get the column DEFAULT (0) — wrong
  for correlation — so it schedules a derived rebuild (marker) that
  repopulates `group_idx` from `figures_json`.
- v23 (issue #780): adds `custom_field_defs.shareable` — a per-field flag
  controlling whether this field's definition and values may travel in a
  shared archive (file export, share sheet, future sync). Purely additive
  `addColumn`; existing rows get `DEFAULT 1` (shareable = true), preserving
  today's behaviour exactly — every previously-created custom field
  continues to travel in archives. Users opt out per-field via the custom
  fields settings screen. No figure index is involved; no derived rebuild
  is required.
- v24 (issue #732): adds `dances.mixer` — a boolean flag marking a dance in
  which dancers change partners each time through (a "mixer"). Modelled as a
  flag orthogonal to `formation`, not a `FormationShape` value, because the
  two are independent in the corpus (830 Caller's Box mixers, 176 of them in
  non-mixer formations; 628 mixer-named non-mixers, 589 of them Sicilian
  Circles) — see `Dance.mixer`. Purely additive `addColumn`; existing rows
  get `DEFAULT 0` (mixer = false), preserving today's behaviour exactly
  (nothing was a mixer before because the concept could not be expressed).
  No figure index is touched; no derived rebuild is required.

- v25 (issue #898): the Device Sync schema migration. Adds the sync
  timestamp triple — `updated_at`, `deleted_at`, `existence_at` — to every
  syncable kind: twenty columns over eight tables. Six tables (`settings`,
  `choreographers`, `tags`, `published_sources`, `custom_field_defs`,
  `venues`) gain all three; `dances` and `programs` already carried the
  first two and gain only `existence_at`. All are nullable, because SQLite
  cannot ADD COLUMN a NOT NULL column without a *constant* default and no
  constant is a truthful timestamp; the step back-fills every existing row
  instead. `updated_at` is stamped at migration time, while `existence_at`
  takes a single sampled constant T₀ for live rows and the row's own
  `deleted_at` for an already-tombstoned one — and specifically NOT
  `updated_at`, which would make an ordinary content edit read as an
  existence transition and resurrect records on first sync. The same step
  converts the six entity-level hard deletes (`ChoreographerRepository`,
  `TagRepository`, `PublishedSourceRepository`, `CustomFieldDefRepository`,
  `VenueRepository`, `SettingsRepository`) to tombstones, so a deletion
  leaves something a peer can learn from; the `hardDelete` import-undo paths
  stay hard, because a rollback must leave nothing to publish. No figure
  index is touched; no derived rebuild is required. Behaviour-preserving from
  the user's point of view: nothing reads `existence_at` for a merge decision
  yet. The stamping helper in `storage/existence.dart` does read it, to
  advance a tie causally — see the note below, which corrects the flat form of
  this claim.
- v26 (issue #899): provenance-based venue dedupe for shared bundles. Adds
  one brand-new table, `venue_provenance` (one row per imported venue,
  keyed on the venue id, mirroring `provenance` and `program_provenance`).
  The importer stamps provenance on every freshly-minted venue so that
  re-importing the same bundle can recognise the venue by its exact
  `(source, external_id)` pair even when the postal address block is absent
  (it is redacted in shared bundles, making the content-fingerprint path
  produce no key). Purely additive: `createTable`; no columns are added to
  existing tables and no data is back-filled (existing imported venues have
  no `venue_provenance` row and will not provenance-dedupe, but the new path
  takes effect for every bundle imported after the upgrade). No figure index
  is touched; no derived rebuild is required.
- v27 (issue #862): published collection import history. Adds the
  `collection_import_events` table, keyed by collection id and manifest
  version, with the archive digest and import timestamp. The row is
  idempotent and remains after imported dances are deleted; no existing data is
  back-filled and no derived rebuild is required.
- v28 (issue #1005): scoped Collection text search. Recreates `dance_fts` with
  short-token prefix indexes and adds the raw `dance_substring_fts` trigram
  index. Existing dances are repopulated through the durable derived-rebuild
  marker before reads proceed; both indexes remain derived and are maintained
  by every dance write, delete, archive replacement, and repair path.
- v29 (issue #1111): adds `normalisation_skips`, durable local bookkeeping for
  unique natural-key collisions encountered by the shareable-text repair pass.
  Repository writes now store NFC/sanitized shareable text, and the post-open
  pass backfills existing values without changing timestamp triples. The table
  is device-local and is not part of transfer or sync payloads.
- v30 (issue #1123): removes the redundant normalized target snapshot from
  `normalisation_skips`. Existing skip identities are preserved while the
  target is re-derived from the live source row on each retry; no user content
  or timestamps are changed.
- v31 (issue #1130): adds `dance_links.transitive`, a boolean marker for
  related-dance links that participate in editor-managed transitive groups.
  Existing links default to `false`, preserving ordinary pairwise behavior;
  import paths remain directional and do not invoke group reconciliation.
- v32 (ADR-004/W4): adds the local-only Device Sync baseline metadata and
  entries, ID aliases, pending deletions, review queue, and published-record
  history. Baseline metadata uses an enforced singleton row so an empty
  manifest retains its epoch; all six tables are device-scoped except the
  retransmitted pending tombstone blob.
- v33 (issue #1196): adds `program_slots.is_purged_dance`, an explicit marker
  for text captions left behind when a dance is purged. New slots use `false`
  for ordinary text-only announcements, while pre-v33
  rows remain `NULL` because their text-only meaning is ambiguous. New purge
  captions are marked so ordinary text-only announcements can receive
  display-only discouraged-term conversion without rewriting tombstone titles.
- v34 (issue #1200): replaces `dances.level`'s fixed enum-name storage with
  the `difficulty_levels` vocabulary and nullable `dances.level_id` reference,
  including Device Sync timestamps. The migration seeds immutable IDs for
  Beginner, Intermediate, and Advanced, then maps every valid legacy enum name
  to that ID. Invalid legacy names abort the migration rather than being
  discarded. The foreign key and repository write guard reject dangling IDs;
  repository deletion is transactional and refuses a level used by any dance,
  including a tombstoned dance that could be restored later.
### Supported (v35 and later)

These are the versions a database can still be stamped at. v35 is the floor:
its own migration step is retired along with the older ones, because a floor
database already carries it. The steps that can still fire are v36 onward.

- v35 (issues #1104 and #1233): rewrites persisted figure parameter keys and
  consolidates the legacy `pull_by_dancers`/`pull_by_direction` move IDs to
  the v35 taxonomy representation, and replaces nullable
  `program_slots.planned_minutes` with nullable `walkthrough_minutes` and
  `dance_minutes`. The migration recursively normalizes nested `meanwhile`
  figures, copies legacy slot timing to `dance_minutes`, and rebuilds the
  derived figure and search indexes.
- v36: adds nullable `review_queue.local_hash`, the queue-time wire hash of
  the affected local record. Actionable review resolution rejects a row whose
  local record changed after enqueue; v35 rows retain NULL and fail closed.
- v37 (issue #1554): adds nullable `programs.dialect_name`, the name of the
  dialect Perform uses for that program; NULL (every existing row) means Perform
  follows the application dialect. A soft reference by name, deliberately not
  validated at write time and not cascaded on dialect delete (amended 2026-10-29:
  a dialect rename is now carried to the programs that name it, trashed ones
  included, by `ProgramRepository.renameDialect`; see `dialect.md`): a name
  that does not resolve falls back to the application dialect when Perform
  resolves it. Written NFC-normalised like every shareable string: the dialect
  library's own names are NFC-normalised on their way to storage
  (`custom_dialects` is a shareable setting), and Device Sync rejects a program
  body that is not already canonical. Not length-limited, because the library
  imposes no name cap. Additive `addColumn`; no back-fill and no derived
  rebuild.
- v38 (issue #1418): adds nullable `programs.pay_minor_units` (integer) and
  `programs.pay_currency` (ISO 4217 code): what the caller is paid for the
  program, as integer minor units so no floating point is stored. The two are
  set together or not at all and the amount is never negative (enforced by
  `Program` and by archive decode); NULL in both (every existing row) means no
  pay recorded. Shareable, so it syncs and is exported in archives (program
  share files included, so it reaches other people), but it is
  not part of the shared program text or PDF and `Program.duplicate` does not
  copy it. A backup holding pay or a v37 dialect name is written under backup
  envelope v2 (`backupSchemaVersionProgramPay`), so 0.5.2 to 0.5.4 refuse it
  instead of restoring it without them; the core archive version is unchanged,
  so share files are not affected (#1885). Additive `addColumn`s; no back-fill
  and no derived rebuild.
- v39 (sync-spec §6.7): adds the `retained_sync_fields` table — `kind`,
  `record_id`, `whole_record` (bool) and `payload` (canonical JSON text), keyed
  by `(kind, record_id)`. It holds what this device keeps of a synced record
  for a newer version of the app: the parts of a peer's body this build does
  not sync, put back verbatim whenever it shares the record again, or, for a
  setting whose key this build does not sync, the peer's whole blob. `payload`
  is `shareable` (unclassifiedPersonal / thirdParty, the tombstone payload's
  classification); the other columns are Device Sync bookkeeping. Sync state,
  not library content: never backed up or exported. Additive `createTable`; no
  back-fill and no derived rebuild.
  The same step adds nullable `baseline_state.published_manifest_hash`
  (SHA-256 of the manifest this device last published, encoded with its
  `writtenAt` fixed) and `baseline_state.published_verified_at` (when the store
  last confirmed every blob that manifest names, epoch milliseconds UTC;
  sync-spec §6.3 step 8). A pass whose manifest hashes the same, within the
  refresh interval, skips the blob check and the manifest `PUT`. Device Sync
  bookkeeping: never backed up, exported or synchronized. They live on the
  epoch row so that anything that resets the epoch or the baseline forgets them
  too. Additive `addColumn`s; no back-fill (null means "publish as before").
  Added to v39 before it was released, rather than as v40.
  The same step adds the `peer_manifests` table: `peer_id` (primary key), `epoch`,
  `etag` and `body`. Each row is the last verified manifest of another device and
  the `ETag` the server sent with it, so the first pass after a restart asks with
  `If-None-Match` instead of downloading every peer's manifest again
  (sync-spec §5.2). It is a cache: any row can be dropped and the next pass
  fetches that manifest in full. `peer_id` and `etag` are `protocolIdentifier`s
  (both are sent back to the store); `epoch` and `body` are Device Sync
  bookkeeping. It is cleared with the baseline, and so on
  an epoch change, detach and restore. Never backed up, exported or
  synchronized. Additive `createTable`; no back-fill.
- v40 (issue #709): adds two tables for the user's own glossary.
  `user_glossary_entries` holds every kind of user entry in one table, keyed
  by a UUID `id`: `kind` (`compound`, #709; `customFigure` and `term`,
  #1023), the required `name` and `definition`, and `description` (shown to the user as
  "More Details"; required text until it became optional, so it may be empty),
  `keywords_json` (a JSON array of strings, default `[]`), nullable `notes`,
  nullable `payload_json` (the kind's payload: a compound's definition, a
  figure of your own's definition, or a term's dance form and source citation), and
  `created_at`, which an edit never moves, so of two entries sharing a name the
  later-created one is the one flagged for rename. Names are not unique: a
  duplicate that arrives by restore or by sync is kept, not refused.
  `figure_notes` holds the user's note on a shipped figure, keyed by the
  shipped move or alias id (`figure_id`); a note on an id the taxonomy no
  longer has is kept and not shown. Both carry the `updated_at` /
  `deleted_at` / `existence_at` triple and are `shareable`. They travel in a
  backup's `app.glossary` section, not in the core archive, and never in a
  `.ccshare` export. Device Sync carries them as the `glossaryEntry` and
  `figureNote` record kinds, behind the capability gate (sync-spec §4.3,
  §6.15); those kinds came later in #709 and needed no schema change. An entry
  of a kind this build does not know, or whose payload no longer decodes as a
  definition, is kept as it is. Additive `createTable`s; no back-fill and no
  derived rebuild.

  **The glossary's size budget.** Each field has its own bound
  (`maxUserGlossaryNameLength`, `maxUserGlossaryTextLength`,
  `maxUserGlossaryPayloadLength`), but the two tables together are also held to
  `maxUserGlossaryBytes` (4 MiB) when the user writes a row, because a backup is
  one file capped at 50 MiB (`kMaxBackupFileBytes`) that export refuses to write
  past: without a total, a large glossary left the user unable to back up at
  all. A row counts for the UTF-8 bytes of its stored text columns (an entry's
  `id`, `kind`, `name`, `definition`, `description`, `keywords_json`, `notes`
  and `payload_json`; a note's `figure_id` and `notes`) plus
  `kGlossaryRowOverheadBytes` (512, for the keys and timestamp the backup writes
  around it); tombstones count for nothing, as a backup does not carry them.
  `UserGlossaryRepository.upsert` and `FigureNoteRepository.set` measure the
  tables after the write, inside the transaction, and roll back with
  `UserGlossaryEntryInvalid.overBudget()` (`field` is `budget`) or
  `FigureNoteInvalid(overBudget: true)` when the total is past the budget **and**
  the row grew. A write that does not grow its row always succeeds, so a
  glossary already over the budget still loads, exports, and can be edited down
  and deleted from; it cannot grow. The budget is 4 MiB because the
  double-encoded backup container writes a stored `"` or `\` as four bytes (a
  newline as three), so the glossary adds at most four times its counted size to
  the file: 16 MiB, under a third of the cap, leaving 34 MiB for the rest (about
  30 MiB for a lean 20,000-dance library, per `kMaxBackupFileBytes`).
  `app/test/data/backup_glossary_budget_test.dart` measures that factor, and the
  per-row overhead, on a real export. A collection that is near the cap by
  itself can still reach it; the budget bounds only what the glossary adds.

  **Two paths are exempt, on purpose** (the decision of the session that wrote
  this change, not the maintainer's; both bring in data the user already had).
  *Device Sync* (`writeFromSync`, a separate path from `upsert` and `set` per
  sync-spec §6.7): refusing a peer's row would leave the two devices unable to
  converge, so a synced glossary can exceed the budget (devices with different
  entries add up). Held-back alternative: refuse at apply and quarantine the
  row, which needs a sync-spec change. *Restore* (`upsertFromRestore` and
  `setFromRestore`, called only by `BackupService._applyGlossary`): the backup
  already fit the file cap and was exportable, and a restore that stopped at the
  budget would delete live rows the backup lacks (replace mode) and then skip
  the newest entries and notes, which the user would see only as a generic
  "problems skipped" count: silent loss on the operation meant to bring data
  back. Every per-field bound still applies to a restored item. Rejected:
  keeping the refusal and naming it in the restore outcome. Either way a
  glossary left over the budget exports while the file is under the cap, and can
  be edited down and deleted from, but not grown; the user-initiated writes stay
  budgeted.

- v41 (issue #1935): performance-only indexes. Adds
  `dance_authors_choreographer_id`, `dance_tags_tag_id`,
  `dance_sources_source_id` and `custom_field_values_field_id`, one plain
  lookup index on the cited-id column of each dance join table (see
  [citedIdLookupIndexSql]). Each table's primary key leads with `dance_id`, so
  "who cites this record" scanned the whole table. Two queries ask it:
  `CompendiumSyncStorage._hasCitation` (a choreographer, tag, published source
  or custom field; run per pending deletion on every `snapshot()` and per
  inbound tombstone) and `DanceRepository.danceIdsDerivingFrom` (all but
  tags). `_hasCitation` also became one `EXISTS` over the join and `dances`,
  not a `dances` select per citing row. The other lookups it makes were
  already indexed (`dance_links_target_transitive`, `program_slots_dance_id`,
  `programs_venue_id`, `dances_level_id`). Run in `onCreate` and in the
  `from < 41` step, guarded by `IF NOT EXISTS`. Pure DDL: no columns or tables
  added, no data rewritten, no derived rebuild.

## The delete model

Every syncable kind — dances, programs, choreographers, tags, published
sources, custom field definitions, difficulty levels, venues, settings keys,
and the user's glossary entries and figure notes —
carries three timestamps. Most kinds gained this shape in schema v25 (issue
#898); difficulty levels gained the same triple in v34, and the glossary's two
tables were created with it in v40. They answer three
different questions and are deliberately not collapsed into fewer columns:

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

`existence_at` is the discriminator Device Sync (ADR-004) merges on:
`SyncMergeEngine` resolves existence from it before it looks at content, and
never from `updated_at`. The causal advance described just above reads it too.
Until the sync engine landed this paragraph said nothing read it for a merge
decision and that Device Sync was not implemented; both are now false, and the
migration that added the column remains behaviour-preserving on its own.

**Deletion is a tombstone, with two named exceptions.** Deleting an entity
writes `deleted_at` and leaves the row on disk, so the deletion is something a
peer can learn from rather than an absence. The exceptions are both erasures
rather than deletions:

- The `hardDelete` / `permanent: true` paths, used only to roll back a
  just-committed import. A rollback treats the import as never having happened,
  so a tombstone would advertise the removal of a record no other device saw.
  **Unless the record was already published**: once Device Sync has named a
  record in a final manifest snapshot it forfeits the right to erase it
  (`sync-spec.md` §3.1), because a peer may hold it live and the next pass
  would download it back. Those rows are tombstoned instead, so an undo of an
  already-synced import is a partial rollback by construction.
- `DanceRepository`'s orphaned-reference GC (#462), which runs inside the
  retention purge and collects reusable rows the purge left unreferenced.
  Nobody deleted those; they went away as a side effect. Only *bare* rows go
  (N2-6 (b)): a tag with a colour, an author with a website, notes, email,
  location or deceased mark, or a source with an author, year, URL or notes
  survives, unused. The user removes it in the Library managers (N2-T2 and
  N2-T3), which have not shipped yet; until then only a tag's Undo path deletes
  a reference row in the app.

**Two consequences follow from soft delete, and both are load-bearing:**

- **Reads that join through a soft-deletable parent must filter
  `parent.deleted_at IS NULL`.** A tombstone fires no FK cascade, so the
  `dance_tags`, `custom_field_values`, `dance_sources` and `dance_authors` rows
  a hard delete used to clear now outlive the delete. They are kept
  deliberately — clearing them would mean a revived tag came back with no
  dances — so the reads filter instead. `tags` is the case that bites: its
  ordinary tombstoning delete is the one converted kind's delete with no
  referential guard, so a tombstone with live join rows is reachable by ordinary
  use rather than only defensively. (That is safe precisely because it strands
  nothing. The tag's *erasing* branch is a different matter, and has carried a
  guard since issue #1357 — see below.)
- **The referential guards stay.** Soft delete does not make it safe to remove
  an entity a live record still references, and a tombstone for a still-cited
  entity could not be applied by a peer anyway.
- **An erasure must not cascade off a tombstoned owner either.** The four join
  tables above are `ON DELETE CASCADE`, so a `permanent: true` erase of a
  choreographer, tag, published source or custom field definition destroys the
  join rows a *tombstoned* dance is still holding — and the dance comes back
  without its author, tag, citation or value when the user restores it. Those
  hatches therefore downgrade to a tombstone whenever any join row survives,
  which keeps the association and still takes the parent out of every live view.
  Venues are the one soft-reference case (`programs.venue_id` is not a foreign
  key, so nothing cascades) and are kept **live** instead, because the
  referencing program has no other way to show its venue. Issue #1357; the
  ruling is stated in `sync-spec.md` §3.1.

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

- WAL mode; foreign keys ON; `PRAGMA quick_check` once per launch, after the first frame (advisory banner on failure).
- WAL and the busy timeout are set by `applyCompendiumSqliteSetup`, which
  **every** connection to the database file must run. Device Sync opens a
  second connection from its worker isolate, so both it and `openAppDatabase`
  pass it as their `DatabaseSetup`. Neither is a default: sqlite ships the
  rollback journal (under which a sync write blocks every app read) and a zero
  busy timeout (under which an app write landing during an inbound apply fails
  with "database is locked" rather than waiting). The same setup registers
  `cc_venue_key(text)`, the venue fold a typed-venue calling-history search
  compiles to (see [search.md](search.md)); the shared test-database helpers
  and the core benchmarks pass it too, so that search runs there.
- All writes in transactions via repository layer; dance/program soft deletes
  purge after a configurable retention (default 30 days) via startup sweep,
  except for rows Device Sync has published: those are retained as tombstones
  indefinitely so peers keep the deletion evidence (`sync-spec.md` §3.1), and
  once expired are **blanked** as Permanently delete blanks them (next bullet),
  except that `existence_at` is left alone (a tie between tombstones takes the
  mark, `sync-spec.md` §6.4), and the records citing a dance are not rewritten
  (a cited dance keeps its title until nothing cites it); `sync-spec.md` §3.2
  gives the reasons. The
  six kinds that became soft-deletable in v25 have no retention sweep yet:
  their tombstones accumulate until Device Sync, which owns retention, adds
  one.
- **Permanently delete** (Recently deleted) marks a dance or program with
  `deleted_at` = the unix epoch, then erases it, or, if it is published,
  **blanks** it: every content column is reset, its join rows, derived rows and
  `retained_sync_fields` row are deleted, and `updated_at` is stamped after the
  content it replaces, so the blank body wins on peers too. Only the deletion
  record remains, and Recently deleted hides any row with the epoch mark
  (LIFE-2; maintainer decision 2026-10-29, round 2: hide and blank, no
  retirement). Program slots and related-dance links that cited a blanked dance
  get what a purge would leave them, and their owners are restamped. A startup
  sweep finishes every marked row whatever the retention setting, which also
  blanks rows marked by builds that predate blanking; being automatic and
  pre-sync, it leaves citers alone and a cited dance keeps its title. See
  `lib/src/storage/permanent_deletion.dart`.

### Migration safety (app-layer preflight)

Before the app opens the drift database it runs a preflight
(`app/lib/src/data/migration_guard.dart`). It first moves a database an earlier
build left in a legacy location into the database directory
(`relocateLegacyDatabase`, see Approach). It then reads the file's persisted
`PRAGMA user_version` — via a short-lived, WAL-aware `sqlite3` connection, not
by opening drift — and compares it to the running `kCompendiumSchemaVersion`:

- **Downgrade protection.** If the file's version is *higher* than the running
  schema (it was written by a newer build), the preflight refuses to open it and
  routes to the `AppBootstrap` error screen ("created by a newer version …
  Update the app, then reopen it"). drift is forward-only with no `onDowngrade`, so
  migrating such a file would silently stamp the version down and risk
  corruption; a belt-and-suspenders guard in `MigrationStrategy.onUpgrade`
  (`from > to` throws) backstops any open path that bypasses the preflight.
- **Schema floor.** If the file's version is *below* `kMinSupportedSchemaVersion`
  (its upgrade steps were retired), the preflight throws
  `DatabaseBelowFloorError`, which names the bridge release that can still
  migrate the file, and `AppBootstrap` renders a recovery screen with
  Back-Up-and-Reset / Reset and no Retry (issue #841). The same
  belt-and-suspenders guard in `onUpgrade` (`from < kMinSupportedSchemaVersion`
  throws) backstops any open path that bypasses the preflight; without it a
  below-floor file would run only the surviving steps and end up structurally
  wrong with no error at all.
- **Atomic upgrade.** drift runs `onUpgrade` with no transaction of its own and
  stamps `user_version` only after it returns, so `onUpgrade` runs every step
  inside a single `transaction()` (after the two refusal guards, which throw
  before any DDL). A failure anywhere in the body — an exception from a later
  step, a process death — rolls back to the pre-upgrade file, which the next
  launch migrates again from the start, instead of leaving earlier steps' DDL
  committed under the old stamp where the next open re-enters them and fails.
- **Backup-before-migrate.** If an upgrade is pending (file version < running),
  the preflight first checkpoints the WAL and copies the whole SQLite file to
  `<database directory>/db_backups/compendium.pre-v<from>-<UTC-timestamp>.sqlite.bak`,
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
  `compendium.sqlite` in the database directory (see Approach) with the chosen
  `.sqlite.bak` (renaming it back to `compendium.sqlite`), and relaunch. Because
  the snapshot is stamped at the older `user_version`, opening it with the build
  that created the backup migrates it forward again; if the migration itself was
  the problem, open it with the matching older app version instead.

**The four terminal startup screens (amendment, 2026-10-30).** The downgrade,
below-floor, snapshot-aborted and relocation-blocked outcomes above each render
a terminal `AppBootstrap` screen. Every one offers **Copy details** and a link
to the Releases page; none offers Retry or a "Check again". Copy details is the
error's type, typed discriminators (storage versions, the failure cause or
reason as an enum name, each conflicting copy's folder and size) and the stack
scrubbed by `CrashRedactor`; it never includes the error's own message, which
can carry a path or text from the database that just failed (CWE-209). The
reason for no re-run (maintainer decision R2-check-again, 2026-10-30): whatever
the caller does to clear the cause, the app has to be reopened afterwards, so
each screen's copy says to reopen it. A re-run could succeed for the last two
outcomes (the caller frees disk space, or moves a copy aside), so this was a
choice rather than a necessity; it was rejected to keep these screens strictly
terminal.
