// The migration control markers in `settings`, and why they must not be
// readable as present once tombstoned (issue #898).
//
// `settings` became soft-deletable in schema v25, and this table also holds
// four internal markers that `CompendiumRepositories.ensureMigrated` reads with
// raw SQL to decide whether a one-time repair still needs to run. Three of them
// are "done" markers, where a marker wrongly read as present **skips a repair
// permanently** — for `purgeCorruptionRepairDoneKey` that repair is the one
// that removes rows which otherwise throw on load and take down the whole
// Programs / Collection listing (#429, #466). That is a far nastier failure
// than a stale row, so it is proved here rather than reasoned about.
//
// THE ROUTE IS ORDINARY CODE, NOT A HYPOTHETICAL. `isBackupEligibleSettingKey`
// in `app/lib/src/data/backup_service.dart` denylists eight named keys plus the
// `editor_draft:` / `program_editor_draft:` prefixes; none of the four markers
// is on either list. So `_applyAppSettings` calls `SettingsRepository.remove`
// on any marker that exists locally but is absent from the backup being
// restored — exactly what a backup taken before that marker was written looks
// like. Before v25 that was harmless: the marker hard-deleted, read as absent,
// and the idempotent repair simply re-ran. The `deleted_at IS NULL` filters on
// those raw reads are what keep it harmless now.
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'test_database.dart';

void main() {
  late CompendiumDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  /// Tombstones [key] the way a backup restore does — through the repository,
  /// not with a raw DELETE — and asserts the row really is still on disk, so a
  /// test that "passes" because the row vanished is impossible.
  Future<void> tombstoneMarker(
    CompendiumRepositories repos,
    String key,
    Object? value,
  ) async {
    await repos.settings.set(key, value);
    await repos.settings.remove(key);
    final rows = await db
        .customSelect(
          'SELECT deleted_at FROM settings WHERE key = ?',
          variables: [Variable.withString(key)],
        )
        .get();
    expect(
      rows,
      hasLength(1),
      reason: '$key must still be on disk as a tombstone, not erased',
    );
    expect(rows.single.data['deleted_at'], isNotNull, reason: key);
  }

  /// Inserts a `program_slots` row nulled to `(danceId, text) = (null, null)` —
  /// the #429 corruption the one-time repair removes.
  Future<void> seedPurgeCorruption(CompendiumRepositories repos) async {
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Set',
        slots: [ProgramSlot(id: 's-ok', position: 0, text: 'Waltz')],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    await db.customStatement(
      'INSERT INTO program_slots (id, program_id, position, dance_id, text, '
      'is_alt) VALUES (?, ?, ?, NULL, NULL, 0)',
      ['s-bad', 'p1', 1],
    );
  }

  Future<List<String>> slotIds() async {
    final rows = await db
        .customSelect('SELECT id FROM program_slots ORDER BY id')
        .get();
    return [for (final r in rows) r.read<String>('id')];
  }

  test('a tombstoned purge-repair marker does NOT skip the repair', () async {
    final repos = CompendiumRepositories(db, contraTaxonomy);
    await tombstoneMarker(repos, purgeCorruptionRepairDoneKey, true);
    await seedPurgeCorruption(repos);

    await repos.ensureMigrated();

    expect(
      await slotIds(),
      ['s-ok'],
      reason:
          'the tombstoned marker must read as absent, so the one-time repair '
          'runs; reading it as present would strand a row that throws on load',
    );
  });

  test('a LIVE purge-repair marker still skips the repair', () async {
    // The other half of the pair. Without this, a filter that accidentally
    // matched nothing at all would pass the test above while silently
    // re-running a one-shot sweep on every open.
    final repos = CompendiumRepositories(db, contraTaxonomy);
    await repos.settings.set(purgeCorruptionRepairDoneKey, true);
    await seedPurgeCorruption(repos);

    await repos.ensureMigrated();

    expect(await slotIds(), [
      's-bad',
      's-ok',
    ], reason: 'a live marker means the sweep has already run');
  });

  test('a tombstoned section-rule marker does NOT skip the recompute', () async {
    final repos = _CountingRepositories(db, contraTaxonomy);
    await tombstoneMarker(repos, sectionRuleVersionKey, kSectionRuleVersion);
    // Take the other two one-time passes out of the picture so the rebuild
    // count attributes to the section recompute alone.
    await repos.settings.set(inversePairNormalisationDoneKey, 'done');

    await repos.ensureMigrated();

    expect(
      repos.rebuildAttempts,
      greaterThan(0),
      reason: 'a tombstoned done-marker must not suppress the recompute',
    );
    // ...and the marker is written back live afterwards, so the next open skips.
    expect(
      await repos.settings.get(sectionRuleVersionKey),
      kSectionRuleVersion,
    );
  });

  test(
    'a tombstoned inverse-pair marker does NOT skip the normalisation',
    () async {
      final repos = _CountingRepositories(db, contraTaxonomy);
      await tombstoneMarker(repos, inversePairNormalisationDoneKey, 'done');
      await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);

      await repos.ensureMigrated();

      expect(repos.rebuildAttempts, greaterThan(0));
      expect(await repos.settings.get(inversePairNormalisationDoneKey), 'done');
    },
  );

  test(
    'a tombstoned rebuild-required marker is not treated as work owed',
    () async {
      // Opposite polarity to the three above: here *present* means "a rebuild is
      // owed". Pin the other two one-time passes live so this marker is the only
      // thing that could trigger a rebuild, then assert none happens.
      final repos = _CountingRepositories(db, contraTaxonomy);
      await tombstoneMarker(repos, derivedRebuildRequiredKey, 'true');
      await repos.settings.set(sectionRuleVersionKey, kSectionRuleVersion);
      await repos.settings.set(inversePairNormalisationDoneKey, 'done');

      await repos.ensureMigrated();

      expect(
        repos.rebuildAttempts,
        0,
        reason:
            'a removed rebuild marker must not resurrect as owed work on every '
            'open',
      );
    },
  );
}

/// Counts [runDerivedRebuild] calls without interfering with the real rebuild.
class _CountingRepositories extends CompendiumRepositories {
  _CountingRepositories(super.db, super.taxonomy);

  int rebuildAttempts = 0;

  @override
  Future<void> runDerivedRebuild({
    DerivedRebuildProgressCallback? onProgress,
  }) async {
    rebuildAttempts++;
    await super.runDerivedRebuild(onProgress: onProgress);
  }
}
