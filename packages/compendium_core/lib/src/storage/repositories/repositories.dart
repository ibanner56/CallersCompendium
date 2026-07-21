import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../taxonomy/taxonomy.dart';
import '../database.dart';
import 'choreographer_repository.dart';
import 'custom_field_repository.dart';
import 'dance_repository.dart';
import 'program_repository.dart';
import 'published_source_repository.dart';
import 'settings_repository.dart';
import 'snapshot_repository.dart';
import 'tag_repository.dart';
import 'venue_repository.dart';

/// Bundles every repository over a single [CompendiumDatabase], so app code
/// wires up storage once (`CompendiumRepositories(db, taxonomy)`) instead of
/// constructing each repository individually.
class CompendiumRepositories {
  CompendiumRepositories(
    this.db,
    Taxonomy taxonomy, {
    SettingsRepository? settings,
  }) : dances = DanceRepository(db, taxonomy),
       choreographers = ChoreographerRepository(db),
       tags = TagRepository(db),
       customFieldDefs = CustomFieldDefRepository(db),
       programs = ProgramRepository(db),
       publishedSources = PublishedSourceRepository(db),
       venues = VenueRepository(db),
       settings = settings ?? SettingsRepository(db),
       snapshots = SnapshotRepository(db);

  final CompendiumDatabase db;
  final DanceRepository dances;
  final ChoreographerRepository choreographers;
  final TagRepository tags;
  final CustomFieldDefRepository customFieldDefs;
  final ProgramRepository programs;
  final PublishedSourceRepository publishedSources;
  final VenueRepository venues;
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
  /// concurrent calls share one in-flight future. A failed attempt clears the
  /// memo so a later call retries rather than replaying the cached failure.
  Future<void> ensureMigrated() => _migration ??= _runMigration();
  Future<void>? _migration;

  Future<void> _runMigration() async {
    try {
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
        await runDerivedRebuild();
        await db.customStatement('DELETE FROM settings WHERE key = ?', [
          derivedRebuildRequiredKey,
        ]);
      }
    } catch (_) {
      // Don't cache a failed migration: clear the memo so a subsequent call
      // retries. The durable marker is still set (only deleted after a
      // successful rebuild), so the retry re-does the back-fill.
      _migration = null;
      rethrow;
    }
  }

  /// The derived-index rebuild step of [ensureMigrated]. Extracted so tests can
  /// inject a transient failure and assert the marker survives and the retry
  /// succeeds.
  @protected
  @visibleForTesting
  Future<void> runDerivedRebuild() => dances.rebuildAllDerived();
}
