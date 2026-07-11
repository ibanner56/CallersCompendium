import 'package:drift/drift.dart';

import '../../taxonomy/taxonomy.dart';
import '../database.dart';
import 'choreographer_repository.dart';
import 'custom_field_repository.dart';
import 'dance_repository.dart';
import 'program_repository.dart';
import 'settings_repository.dart';
import 'snapshot_repository.dart';
import 'tag_repository.dart';

/// Bundles every repository over a single [CompendiumDatabase], so app code
/// wires up storage once (`CompendiumRepositories(db, taxonomy)`) instead of
/// constructing each repository individually.
class CompendiumRepositories {
  CompendiumRepositories(this.db, Taxonomy taxonomy)
    : dances = DanceRepository(db, taxonomy),
      choreographers = ChoreographerRepository(db),
      tags = TagRepository(db),
      customFieldDefs = CustomFieldDefRepository(db),
      programs = ProgramRepository(db),
      settings = SettingsRepository(db),
      snapshots = SnapshotRepository(db);

  final CompendiumDatabase db;
  final DanceRepository dances;
  final ChoreographerRepository choreographers;
  final TagRepository tags;
  final CustomFieldDefRepository customFieldDefs;
  final ProgramRepository programs;
  final SettingsRepository settings;
  final SnapshotRepository snapshots;

  /// Opens the database (running any pending schema migration) and, if a
  /// migration owes a derived-index rebuild, back-fills it.
  ///
  /// This is where the schema-v2 `dance_figures.section` back-fill happens:
  /// `MigrationStrategy.onUpgrade` performs the DDL and durably records
  /// [derivedRebuildRequiredKey] in `settings`, but recomputing the derived
  /// rows needs the taxonomy/renderer owned by [DanceRepository], which the
  /// migration strategy can't reach. Call this once at startup, after
  /// constructing the repositories, before the first read.
  ///
  /// Crash-safe and idempotent: the marker persists until the rebuild
  /// succeeds, so an interrupted upgrade is retried on the next open;
  /// concurrent calls share one in-flight future.
  Future<void> ensureMigrated() => _migration ??= _runMigration();
  Future<void>? _migration;

  Future<void> _runMigration() async {
    // Force the lazily-opened database to run its migration strategy now, so
    // the marker (if any) reflects this open before we check it.
    await db.customSelect('SELECT 1').get();
    final marker = await db
        .customSelect(
          'SELECT value_json FROM settings WHERE key = ?',
          variables: [Variable.withString(derivedRebuildRequiredKey)],
        )
        .get();
    if (marker.isNotEmpty) {
      await dances.rebuildAllDerived();
      await db.customStatement('DELETE FROM settings WHERE key = ?', [
        derivedRebuildRequiredKey,
      ]);
    }
  }
}
