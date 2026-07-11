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
  title, authors, hook, notes, figures_text, custom_values
)
''';

/// The two derived-index helper indexes added in schema v2 for section-aware
/// figure search and the `Then` sequence self-join (`docs/design/search.md`).
const List<String> searchIndexSql = [
  'CREATE INDEX IF NOT EXISTS dance_figures_move_section '
      'ON dance_figures(move, section)',
  'CREATE INDEX IF NOT EXISTS dance_figures_dance_idx '
      'ON dance_figures(dance_id, idx)',
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
///   section` and `dance_figures_dance_idx` indexes. `onUpgrade` performs the
///   DDL and durably records [derivedRebuildRequiredKey]; the derived `section`
///   values are back-filled by a post-open integrity pass
///   ([DanceRepository.rebuildAllDerived]) that [CompendiumRepositories.ensureMigrated]
///   runs when the marker is set — the rebuild needs the taxonomy/renderer,
///   which `MigrationStrategy` can't reach.
///
/// Every future migration must (a) bump [schemaVersion], (b) add a
/// `MigrationStrategy` step for the new version, and (c) ship a test that
/// opens a fixture DB created at the previous version and asserts the
/// migrated schema/data (see `test/storage/migration_test.dart`).
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
    Settings,
    Snapshots,
  ],
)
class CompendiumDatabase extends _$CompendiumDatabase {
  CompendiumDatabase(super.executor);

  @override
  int get schemaVersion => 2;

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

  /// Runs SQLite's `PRAGMA quick_check`; intended to run once per app
  /// launch per `docs/design/storage.md` ("Durability").
  Future<bool> quickCheck() async {
    final rows = await customSelect('PRAGMA quick_check').get();
    return rows.length == 1 && rows.first.data.values.first == 'ok';
  }
}
