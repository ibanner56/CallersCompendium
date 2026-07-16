import 'package:drift/drift.dart';

import '../model/enums.dart';
import '../model/formation.dart';
import 'tables.dart';

part 'database.g.dart';

/// The raw FTS5 virtual table backing full-text search.
///
/// Not a typed drift [Table]: it is a derived index that only the repository
/// layer ever writes to (in lockstep with [DanceFigures]); drift's typed FTS5
/// support targets `content=<table>`/`content=''` tables tied to a rowid
/// convention that doesn't map cleanly onto our text-typed `dances.id`
/// primary key. Deviating from the exact `content=''` sketch in
/// `docs/design/storage.md`, this table carries `dance_id` as an `UNINDEXED`
/// column instead, so rows are matched back to a dance directly without any
/// implicit-`rowid` bookkeeping. Same derived/rebuildable behavior, simpler
/// and more robust to maintain.
const String createDanceFtsSql = '''
CREATE VIRTUAL TABLE dance_fts USING fts5(
  dance_id UNINDEXED,
  title, authors, hook, notes, figures_text, custom_values, sources
)
''';

/// The schema-v2 helper index for section-aware figure search
/// (`docs/design/search.md`). Only the `(move, section)` index is created:
/// the `Then` sequence self-join keys on `(dance_id, idx)`, which is already
/// served by the implicit index SQLite creates for the `dance_figures`
/// composite primary key `{danceId, idx}` (same leading-column order), so no
/// separate `(dance_id, idx)` index is needed.
const List<String> searchIndexSql = [
  'CREATE INDEX IF NOT EXISTS dance_figures_move_section '
      'ON dance_figures(move, section)',
];

/// Settings key marking that a schema migration touched the derived figure
/// index and the `dance_figures` rows must be rebuilt from `figures_json`.
///
/// Written inside `onUpgrade` (so it is durable — it survives a crash between
/// the schema bump and the rebuild) and cleared by
/// [CompendiumRepositories.ensureMigrated] only after the rebuild succeeds.
const String derivedRebuildRequiredKey = '__derived_rebuild_required__';

/// The Caller's Compendium local database.
///
/// Schema version history:
/// - v1 (2026-07-10): initial schema — see `docs/design/storage.md`.
/// - v2 (2026-07-11): section-aware search (`docs/design/search.md`). Adds the
///   nullable `dance_figures.section` column plus the `dance_figures_move_
///   section` index (the `Then` self-join's `(dance_id, idx)` access is
///   already served by the composite primary key's implicit index).
///   `onUpgrade` performs the DDL and durably records
///   [derivedRebuildRequiredKey]; the derived `section` values are back-filled
///   by a post-open integrity pass ([DanceRepository.rebuildAllDerived]) that
///   [CompendiumRepositories.ensureMigrated] runs when the marker is set — the
///   rebuild needs the taxonomy/renderer, which `MigrationStrategy` can't
///   reach.
/// - v3 (2026-07-13): CC-parity program event metadata (`docs/design/
///   domain-model.md` "CC parity backfill"). Adds nullable `programs.band`,
///   `programs.caller`, `programs.dancer_level`, `program_slots.guest_caller`,
///   and `program_slots.planned_minutes`. All nullable with no back-fill
///   (existing rows get NULL); programs/slots do not feed the derived
///   `dance_figures`/`dance_fts` indexes, so no derived rebuild is required.
/// - v4 (2026-07-13): CC-parity dance difficulty (`docs/design/domain-model.md`
///   "CC parity backfill", ROADMAP 4b.1). Adds the nullable
///   `dances.level` (ordered [DanceLevel], persisted by name) and
///   `dances.mixed_level` (bool, defaults `false`) columns. Existing rows get
///   `level` NULL / `mixed_level` false. `level`/`mixed_level` are dance-scalar
///   metadata, not figure text, so they do not feed the derived
///   `dance_figures`/`dance_fts` indexes and no derived rebuild is required.
/// - v5 (2026-07-13): CC-parity composed/revised dates (`docs/design/
///   domain-model.md` "CC parity backfill", ROADMAP 4b.2). Adds the nullable
///   `dances.composed_on` and `dances.revised_on` columns, each holding a
///   canonical partial-precision [PartialDate] string (`YYYY`/`YYYY-MM`/
///   `YYYY-MM-DD`). Existing rows get NULL. These are author/bibliographic
///   scalar metadata (distinct from the record stamps `created_at`/
///   `updated_at`), not figure text, so they do not feed the derived
///   `dance_figures`/`dance_fts` indexes and no derived rebuild is required.
/// - v6 (2026-07-13): CC-parity dance rating (`docs/design/domain-model.md`
///   "CC parity backfill", ROADMAP 4b.3). Adds the nullable `dances.rating`
///   column (an `int` star rating validated to `1..5` at the [Dance] boundary;
///   `null` = unrated). Existing rows get NULL. `rating` is dance-scalar
///   curation metadata, not figure text, so it does not feed the derived
///   `dance_figures`/`dance_fts` indexes and no derived rebuild is required.
/// - v7 (2026-07-14): CC-parity author contact (`docs/design/domain-model.md`
///   "CC parity backfill", ROADMAP 4b.4). Adds the nullable
///   `choreographers.email` and `choreographers.location` columns plus
///   `choreographers.deceased` (bool, defaults `false`). Existing rows get
///   email/location NULL and deceased false. Choreographer contact is
///   scalar author metadata (not figure text) and choreographers do not feed
///   the derived `dance_figures`/`dance_fts` indexes, so no derived rebuild is
///   required. (`email`/`location` are private — never emitted in shareable
///   exports; see [Choreographer].)
/// - v8 (2026-07-14): first-class published-source citations
///   (`docs/design/domain-model.md` "CC parity backfill", ROADMAP 4b.5).
///   Adds two brand-new tables: `published_sources` (a reusable bibliographic
///   entity — id/title plus nullable author/year/url/notes) and the ordered
///   `dance_sources` join (danceId/sourceId FKs cascade, freeform nullable
///   page/number, position). No columns are added to existing tables and no
///   data is back-filled (fresh tables start empty). These new tables do NOT
///   feed the derived `dance_fts`/`dance_figures` indexes (searchability is
///   ROADMAP 4b.5b), so NO derived rebuild is required by this migration.
/// - v9 (2026-07-14): published-source citations become SEARCHABLE (ROADMAP
///   4b.5b). Adds a `sources` column to the `dance_fts` FTS5 virtual table
///   holding the searchable text (title + author) of each cited
///   [PublishedSources] row. Because an FTS5 table's column set is fixed at
///   creation, the migration DROPs and recreates `dance_fts` with the new
///   shape; the FTS rows cannot be repopulated in the migration (that needs the
///   taxonomy/renderer to re-derive figure text and the repository to join the
///   citation → published-source text), so — exactly like the v2
///   `dance_figures.section` back-fill — `onUpgrade` durably records
///   [derivedRebuildRequiredKey] and [CompendiumRepositories.ensureMigrated]
///   performs the full derived rebuild ([DanceRepository.rebuildAllDerived]),
///   which repopulates every `dance_fts` row (including the new `sources`
///   column) and clears the marker. No table columns are added elsewhere.
///
/// Every future migration must (a) bump [schemaVersion], (b) add a
/// `MigrationStrategy` step for the new version, and (c) ship a test that
/// opens a fixture DB created at the previous version and asserts the
/// migrated schema/data (see `test/storage/migration_test.dart`). CI enforces
/// (c): a change to this constant fails the build unless the same PR also
/// adds/changes a migration test or a `test/storage/fixtures/` fixture.
///
/// Release rule: **never bump [schemaVersion] in a PATCH release** — a schema
/// change is a data-format change and must ride at least a MINOR bump (see
/// CONTRIBUTING.md).
@DriftDatabase(
  tables: [
    Dances,
    Choreographers,
    DanceAuthors,
    DanceFigures,
    Programs,
    ProgramSlots,
    CustomFieldDefs,
    CustomFieldValues,
    Tags,
    DanceTags,
    DanceLinks,
    Provenance,
    PublishedSources,
    DanceSources,
    Settings,
    Snapshots,
  ],
)
class CompendiumDatabase extends _$CompendiumDatabase {
  CompendiumDatabase(super.executor);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(createDanceFtsSql);
      for (final sql in searchIndexSql) {
        await customStatement(sql);
      }
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(danceFigures, danceFigures.section);
        for (final sql in searchIndexSql) {
          await customStatement(sql);
        }
        // The `section` back-fill needs the domain renderer/taxonomy, which is
        // unreachable here. Durably mark that a rebuild is owed so it survives
        // a crash before CompendiumRepositories.ensureMigrated() completes it.
        await customStatement(
          'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
          [derivedRebuildRequiredKey, 'true'],
        );
      }
      if (from < 3) {
        // CC-parity program event metadata. All nullable; existing rows get
        // NULL. Programs/slots don't feed the derived indexes, so no rebuild.
        await m.addColumn(programs, programs.band);
        await m.addColumn(programs, programs.caller);
        await m.addColumn(programs, programs.dancerLevel);
        await m.addColumn(programSlots, programSlots.guestCaller);
        await m.addColumn(programSlots, programSlots.plannedMinutes);
      }
      if (from < 4) {
        // CC-parity dance difficulty. `level` is nullable (existing rows get
        // NULL); `mixed_level` defaults to false. Both are dance-scalar
        // metadata (not figure text), so they don't feed the derived
        // `dance_figures`/`dance_fts` indexes and no rebuild is required.
        await m.addColumn(dances, dances.level);
        await m.addColumn(dances, dances.mixedLevel);
      }
      if (from < 5) {
        // CC-parity composed/revised dates. Both nullable (existing rows get
        // NULL); each stores a canonical partial-precision PartialDate string.
        // Author/bibliographic scalar metadata (not figure text), so they don't
        // feed the derived `dance_figures`/`dance_fts` indexes — no rebuild.
        await m.addColumn(dances, dances.composedOn);
        await m.addColumn(dances, dances.revisedOn);
      }
      if (from < 6) {
        // CC-parity dance rating. Nullable (existing rows get NULL); the 1..5
        // range is validated at the Dance boundary, not by a DB constraint.
        // Dance-scalar curation metadata (not figure text), so it doesn't feed
        // the derived `dance_figures`/`dance_fts` indexes — no rebuild.
        await m.addColumn(dances, dances.rating);
      }
      if (from < 7) {
        // CC-parity author contact. `email`/`location` nullable (existing rows
        // get NULL); `deceased` defaults to false. Scalar author metadata (not
        // figure text) and choreographers don't feed the derived
        // `dance_figures`/`dance_fts` indexes — no rebuild is required.
        await m.addColumn(choreographers, choreographers.email);
        await m.addColumn(choreographers, choreographers.location);
        await m.addColumn(choreographers, choreographers.deceased);
      }
      if (from < 8) {
        // First-class published-source citations. Two brand-new tables; no
        // columns added to existing tables, no back-fill. They don't feed the
        // derived `dance_fts`/`dance_figures` indexes (search is ROADMAP
        // 4b.5b), so no derived rebuild is required.
        await m.createTable(publishedSources);
        await m.createTable(danceSources);
      }
      if (from < 9) {
        // Published-source citations become searchable: `dance_fts` gains a
        // `sources` column. An FTS5 table's columns are fixed at creation, so
        // drop and recreate it with the new shape. The FTS rows can't be
        // repopulated here (that needs the taxonomy/renderer plus the
        // citation → published-source join owned by the repository layer), so
        // durably record that a derived rebuild is owed — exactly like the v2
        // `section` back-fill. CompendiumRepositories.ensureMigrated() runs
        // DanceRepository.rebuildAllDerived(), which refills every `dance_fts`
        // row (including `sources`) and clears the marker.
        await customStatement('DROP TABLE IF EXISTS dance_fts');
        await customStatement(createDanceFtsSql);
        await customStatement(
          'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
          [derivedRebuildRequiredKey, 'true'],
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      if (details.wasCreated) return;
      // Defensive: guards a hand-rolled DB (e.g. restored from an
      // external backup) that predates the FTS5 table.
      final tables = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='dance_fts'",
      ).get();
      if (tables.isEmpty) {
        await customStatement(createDanceFtsSql);
      }
    },
  );

  /// Runs SQLite's `PRAGMA quick_check`, returning `true` when the database
  /// reports `ok`. Wired into app startup (`_CompendiumAppState._startupSequence`
  /// in `app/lib/main.dart`) so it runs once per app launch per
  /// `docs/design/storage.md` ("Durability"); a failure is surfaced to the user
  /// as a non-fatal corruption warning.
  Future<bool> quickCheck() async {
    final rows = await customSelect('PRAGMA quick_check').get();
    return rows.length == 1 && rows.first.data.values.first == 'ok';
  }
}
