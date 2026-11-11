import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// A restore of a backup stamps what it writes at the backup's creation time,
/// not at restore time (SYNC-1, sync-spec §6.11). The two-device behaviour is
/// covered in the app's `backup_restore_two_device_test.dart`; this pins the
/// stamp itself and its clamp.
void main() {
  group('restoreStampFor', () {
    final now = DateTime.utc(2026, 11, 11, 12);

    test('is the backup creation time when that is in the past', () {
      expect(
        restoreStampFor(DateTime.utc(2026, 10, 1), now: now),
        DateTime.utc(2026, 10, 1),
      );
    });

    test('clamps a future-dated backup to now', () {
      expect(restoreStampFor(DateTime.utc(2099), now: now), now);
    });

    test('is now when no backup time is given', () {
      expect(restoreStampFor(null, now: now), now);
    });

    test('is UTC whatever the input zone', () {
      final local = DateTime(2026, 10, 1, 9);
      final stamp = restoreStampFor(local, now: now);
      expect(stamp.isUtc, isTrue);
      expect(stamp, local.toUtc());
    });
  });

  group('ArchiveRestorer stamps', () {
    Future<Map<String, int>> stamps(
      CompendiumRepositories repos,
      String table,
      String id,
    ) async {
      final row = await repos.db
          .customSelect(
            'SELECT updated_at, existence_at FROM $table WHERE id = ?',
            variables: [Variable<String>(id)],
          )
          .getSingle();
      return {
        'updated': row.read<int>('updated_at'),
        'existence': row.read<int>('existence_at'),
      };
    }

    int seconds(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

    CompendiumArchive archive() => CompendiumArchive(
      schemaVersion: archiveSchemaVersion,
      exportedAt: DateTime.utc(2026, 10, 1),
      tags: [Tag(id: 't1', name: 'Flowing')],
      choreographers: [Choreographer(id: 'c1', name: 'Alice')],
      venues: [Venue(id: 'v1', name: 'Hall')],
      publishedSources: [PublishedSource(id: 's1', title: 'Zesty Contras')],
      customFields: [
        CustomFieldDef(
          id: 'f1',
          key: 'origin',
          label: 'Origin',
          type: CustomFieldType.text,
        ),
      ],
      difficultyLevels: [
        DifficultyLevel(id: 'l1', label: 'Challenge', position: 0),
      ],
    );

    const everyKind = [
      ('tags', 't1'),
      ('choreographers', 'c1'),
      ('venues', 'v1'),
      ('published_sources', 's1'),
      ('custom_field_defs', 'f1'),
      ('difficulty_levels', 'l1'),
    ];

    test('reference kinds take the backup creation time', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repos = CompendiumRepositories(db, contraTaxonomy);
      final made = DateTime.utc(2026, 10, 1);
      final result = await ArchiveRestorer(
        repos,
      ).restore(archive(), backupCreatedAt: made);
      expect(result.hasErrors, isFalse, reason: '${result.errors}');
      for (final (table, id) in everyKind) {
        expect(await stamps(repos, table, id), {
          'updated': seconds(made),
          'existence': seconds(made),
        }, reason: table);
      }
    });

    test('a future-dated backup is stamped no later than now', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repos = CompendiumRepositories(db, contraTaxonomy);
      final before = seconds(DateTime.now().toUtc());
      await ArchiveRestorer(
        repos,
      ).restore(archive(), backupCreatedAt: DateTime.utc(2099));
      final after = seconds(DateTime.now().toUtc());
      final stamp = await stamps(repos, 'tags', 't1');
      expect(stamp['updated'], inInclusiveRange(before, after));
      expect(stamp['existence'], inInclusiveRange(before, after));
    });

    // A sample-library seed restores without a backup time: it is not a
    // restore of earlier state, so it stamps as an ordinary write does.
    test('without a backup time every kind is stamped now', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final repos = CompendiumRepositories(db, contraTaxonomy);
      final before = seconds(DateTime.now().toUtc());
      await ArchiveRestorer(repos).restore(archive());
      final after = seconds(DateTime.now().toUtc());
      for (final (table, id) in everyKind) {
        final stamp = await stamps(repos, table, id);
        expect(
          stamp['updated'],
          inInclusiveRange(before, after),
          reason: table,
        );
        expect(
          stamp['existence'],
          inInclusiveRange(before, after),
          reason: table,
        );
      }
    });

    // The shared-figure import's Undo puts a replaced entry back through
    // `upsertFromRestore` without a backup time: that is this device's own
    // edit, so it must stay causal and stamped now.
    test(
      'upsertFromRestore without a backup time revives causally, now',
      () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final repos = CompendiumRepositories(db, contraTaxonomy);
        final entry = UserGlossaryEntry(
          id: 'g',
          kindName: 'compound',
          name: 'Term',
          definition: 'd',
          description: 'd',
          keywords: const [],
          createdAt: DateTime.utc(2026),
        );
        await repos.userGlossary.upsert(entry, at: DateTime.utc(2026, 1, 1));
        // A deletion stamped in the future, so a causal revival must exceed it.
        final deletedAt = DateTime.now().toUtc().add(const Duration(hours: 1));
        await repos.userGlossary.delete('g', at: deletedAt);
        final before = seconds(DateTime.now().toUtc());
        await repos.userGlossary.upsertFromRestore(entry);
        final after = seconds(DateTime.now().toUtc());
        final row = await repos.db
            .customSelect(
              'SELECT updated_at, existence_at, deleted_at FROM '
              'user_glossary_entries WHERE id = ?',
              variables: [Variable<String>('g')],
            )
            .getSingle();
        expect(row.read<int?>('deleted_at'), isNull);
        expect(row.read<int>('updated_at'), inInclusiveRange(before, after));
        expect(row.read<int>('existence_at'), greaterThan(seconds(deletedAt)));
      },
    );
  });
}
