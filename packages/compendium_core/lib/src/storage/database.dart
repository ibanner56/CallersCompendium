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
  int get schemaVersion => 5;

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
