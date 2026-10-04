import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

/// Set `UPDATE_GOLDEN=1` to re-record the fixture. A change here is a change to
/// every peer's record hash, so it needs a wire-version decision, not a
/// refresh.
const _goldenPath = 'test/storage/fixtures/sync_snapshot_wire_hashes.json';

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repositories;
  late CompendiumSyncStorage storage;

  setUp(() {
    db = openTestDatabase();
    repositories = CompendiumRepositories(db, contraTaxonomy);
    storage = CompendiumSyncStorage(repositories);
  });

  tearDown(() => db.close());

  test(
    'snapshot() wire hashes match the recorded golden for the fixture library',
    () async {
      final stamp = DateTime.utc(2025, 3, 4, 5, 6, 7);
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Café Choreo', website: 'https://e.org'),
        at: stamp,
      );
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 't1', name: 'Zesty'),
        at: stamp,
      );
      // ignore: unused_result
      await repositories.publishedSources.upsert(
        PublishedSource(id: 'ps1', title: 'Source', author: 'A', year: 1999),
        at: stamp,
      );
      await repositories.difficultyLevels.upsert(
        DifficultyLevel(id: 'lvl1', label: 'Fixture level', position: 90),
        at: stamp,
      );
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'cf1',
          key: 'fixture_key',
          label: 'Fixture',
          type: CustomFieldType.text,
        ),
        at: stamp,
      );
      await repositories.venues.upsert(
        Venue(id: 'v1', name: 'Town Hall', city: 'Brattleboro'),
        at: stamp,
      );
      await repositories.dances.create(
        Dance(
          id: 'd1',
          title: 'Fixture Dance ☃',
          authorIds: const ['c1'],
          hook: 'A hook',
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await repositories.dances.create(
        Dance(
          id: 'd2',
          title: 'Second',
          createdAt: stamp,
          updatedAt: stamp.add(const Duration(hours: 1)),
        ),
      );
      await repositories.programs.create(
        Program(
          id: 'p1',
          title: 'Fixture Program',
          venueId: 'v1',
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );

      final snapshot = await storage.snapshot();
      final actual = <String, String>{
        for (final entry in snapshot.local.entries)
          // The seeded built-in levels carry install-time stamps, so their
          // hashes are not reproducible.
          if (entry.value != null &&
              !entry.key.recordId.startsWith('difficulty-'))
            '${entry.key.kind.name}:${entry.key.recordId}':
                entry.value!.wireHash,
      };
      expect(
        {for (final k in actual.keys) k.split(':').first},
        containsAll(<String>{
          'dance',
          'program',
          'choreographer',
          'tag',
          'publishedSource',
          'customFieldDef',
          'difficultyLevel',
          'venue',
        }),
      );

      final file = File(_goldenPath);
      if (Platform.environment['UPDATE_GOLDEN'] == '1') {
        final sorted = {
          for (final k in actual.keys.toList()..sort()) k: actual[k],
        };
        file.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
        );
      }
      final golden = (jsonDecode(file.readAsStringSync()) as Map)
          .cast<String, String>();
      expect(actual, golden);
    },
  );
}
