import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/enums.dart';
import '../../taxonomy/taxonomy.dart';
import '../database.dart';
import 'choreographer_repository.dart';
import 'custom_field_repository.dart';
import 'dance_repository.dart';
import 'program_repository.dart';
import 'published_source_repository.dart';
import 'settings_repository.dart';
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
       settings = settings ?? SettingsRepository(db);

  final CompendiumDatabase db;
  final DanceRepository dances;
  final ChoreographerRepository choreographers;
  final TagRepository tags;
  final CustomFieldDefRepository customFieldDefs;
  final ProgramRepository programs;
  final PublishedSourceRepository publishedSources;
  final VenueRepository venues;
  final SettingsRepository settings;

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
  ///
  /// [onDerivedRebuildProgress], when supplied, is forwarded to
  /// [DanceRepository.rebuildAllDerived] so the caller (e.g. the app's startup
  /// screen) can show determinate progress for the post-migration derived-index
  /// rebuild instead of an indeterminate spinner (#440).
  Future<void> ensureMigrated({
    DerivedRebuildProgressCallback? onDerivedRebuildProgress,
  }) => _migration ??= _runMigration(onDerivedRebuildProgress);
  Future<void>? _migration;

  Future<void> _runMigration(
    DerivedRebuildProgressCallback? onDerivedRebuildProgress,
  ) async {
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
        await runDerivedRebuild(onProgress: onDerivedRebuildProgress);
        await db.customStatement('DELETE FROM settings WHERE key = ?', [
          derivedRebuildRequiredKey,
        ]);
      }
      await _repairPurgeCorruptionIfNeeded();
      await _recomputeSectionLabelsIfNeeded();
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
  /// succeeds. [onProgress] is forwarded to [DanceRepository.rebuildAllDerived].
  @protected
  @visibleForTesting
  Future<void> runDerivedRebuild({
    DerivedRebuildProgressCallback? onProgress,
  }) => dances.rebuildAllDerived(onProgress: onProgress);

  /// One-time repair for databases corrupted by a pre-fix hard purge (#429,
  /// #466). A `program_slots` row nulled to `(danceId, text) = (null, null)`
  /// carries no dance and no caption, so it is removed; a `relatedDance`
  /// `dance_links` row whose `targetDanceId` was SET NULL no longer points at
  /// anything, so it too is removed. Both cases otherwise throw on load and
  /// take down the whole Programs / Collection listing.
  ///
  /// Guarded by [purgeCorruptionRepairDoneKey] so it runs at most once per
  /// database (idempotent — a healthy database simply deletes nothing and marks
  /// the sweep done). Runs in a single transaction with the marker write so an
  /// interrupted repair is retried on the next open. Deliberately schema-version
  /// agnostic: the corruption can exist in databases already at the current
  /// version, which a version-gated migration would miss.
  Future<void> _repairPurgeCorruptionIfNeeded() async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ?',
          variables: [Variable.withString(purgeCorruptionRepairDoneKey)],
        )
        .get();
    if (done.isNotEmpty) return;
    await db.transaction(() async {
      await db.customStatement(
        'DELETE FROM program_slots WHERE dance_id IS NULL AND text IS NULL',
      );
      await db.customStatement(
        'DELETE FROM dance_links WHERE kind = ? AND target_dance_id IS NULL',
        [LinkKind.relatedDance.name],
      );
      await db.customStatement(
        'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
        [purgeCorruptionRepairDoneKey, 'true'],
      );
    });
  }

  /// Recomputes `dance_figures.section` for all dances using the corrected
  /// zero-beat phrase-boundary rule (#844), if this has not already been done.
  ///
  /// Guarded by [sectionRuleVersionKey] so it runs at most once per database.
  /// The marker is written *after* [runDerivedRebuild] completes — an
  /// interrupted rebuild leaves the key absent and the sweep retries on the
  /// next open. On a fresh install the collection is empty and the rebuild is
  /// a no-op; the key is still written so the sweep is skipped on subsequent
  /// opens.
  Future<void> _recomputeSectionLabelsIfNeeded() async {
    final done = await db
        .customSelect(
          'SELECT 1 FROM settings WHERE key = ? AND value_json = ?',
          variables: [
            Variable.withString(sectionRuleVersionKey),
            Variable.withString('"$kSectionRuleVersion"'),
          ],
        )
        .get();
    if (done.isNotEmpty) return;
    await runDerivedRebuild();
    await db.customStatement(
      'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',
      [sectionRuleVersionKey, '"$kSectionRuleVersion"'],
    );
  }
}
