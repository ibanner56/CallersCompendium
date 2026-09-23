import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

Future<void> _storeRawTunes(CompendiumDatabase db, String id, String raw) =>
    db.customStatement('UPDATE dances SET tunes_json = ? WHERE id = ?', [
      raw,
      id,
    ]);

Future<String> _storedTunes(CompendiumDatabase db, String id) async =>
    (await db
            .customSelect(
              'SELECT tunes_json FROM dances WHERE id = ?',
              variables: [Variable<String>(id)],
            )
            .getSingle())
        .read<String>('tunes_json');

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repos;

  setUp(() {
    db = openTestDatabase();
    repos = CompendiumRepositories(db, contraTaxonomy);
  });

  tearDown(() => db.close());

  // Measured, not inferred. Three of the four are TypeError rather than
  // FormatException, and the element failures are lazy — `cast<String>()` did
  // not throw at the cast, it threw when `List.unmodifiable` iterated it inside
  // the Dance constructor.
  const undecodable = <String, String>{
    'not JSON at all': '[{"a":',
    'root is not a list': '{"a":1}',
    'element is not a string (TypeError)': '[1,2,3]',
    'null element (TypeError)': '[null]',
  };

  group('an undecodable tune list does not take down the load path', () {
    undecodable.forEach((label, raw) {
      test('$label: the dance still loads and keeps its text', () async {
        await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
        await repos.ensureMigrated();
        await _storeRawTunes(db, 'd1', raw);

        await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

        final dance = await repos.dances.getById('d1');
        expect(dance, isNotNull);
        expect(
          dance!.tunesSource,
          isA<UnreadableTunes>().having((s) => s.storedJson, 'storedJson', raw),
        );
        expect(await repos.dances.listAll(), hasLength(1));
      });
    });
  });

  test('a pending one-time sweep completes with an undecodable tune list', () async {
    // The case that reopened after the rebuild gate was removed: with a repair
    // owed, the sweep loads every dance. A guard that runs after
    // `ensureMigrated()` has written the markers cannot see this, so the marker
    // is cleared first.
    await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
    await repos.ensureMigrated();
    await _storeRawTunes(db, 'd1', '[1,2,3]');
    await db.customStatement('DELETE FROM settings WHERE key = ?', [
      normalisationDerivedIndexRepairDoneKey,
    ]);

    await CompendiumRepositories(db, contraTaxonomy).ensureMigrated();

    expect(await _storedTunes(db, 'd1'), '[1,2,3]');
  });

  test('an ordinary edit leaves an unreadable tune list untouched', () async {
    const raw = '[{"a":';
    await repos.dances.create(sampleDance(id: 'd1', title: 'Before'));
    await repos.ensureMigrated();
    await _storeRawTunes(db, 'd1', raw);

    final loaded = await repos.dances.getById('d1');
    await repos.dances.update(loaded!.copyWith(title: 'After'));

    expect(await _storedTunes(db, 'd1'), raw);
    expect((await repos.dances.getById('d1'))!.title, 'After');
  });

  test('a duplicate carries the stored tune text through', () async {
    const raw = '[1,2,3]';
    await repos.dances.create(sampleDance(id: 'd1', title: 'Original'));
    await repos.ensureMigrated();
    await _storeRawTunes(db, 'd1', raw);

    final loaded = await repos.dances.getById('d1');
    await repos.dances.create(
      loaded!.duplicate(newId: 'd2', now: DateTime.utc(2026, 5, 1)),
    );

    expect(await _storedTunes(db, 'd2'), raw);
  });

  group('batch tune edits skip a row they cannot read', () {
    setUp(() async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
      await repos.ensureMigrated();
      await _storeRawTunes(db, 'd1', '[1,2,3]');
    });

    test('adding tunes does not rewrite it', () async {
      await repos.dances.addTunesForMany(
        const ['d1'],
        tunes: const ['Reel'],
        now: DateTime.utc(2026, 5, 1),
      );
      expect(await _storedTunes(db, 'd1'), '[1,2,3]');
    });

    test('clearing tunes does not rewrite it', () async {
      // Clearing is the user's intent, but a BATCH clear would destroy text the
      // undo snapshot cannot restore: the snapshot is a `List<String>`.
      await repos.dances.clearTunesForMany(
        const ['d1'],
        now: DateTime.utc(2026, 5, 1),
      );
      expect(await _storedTunes(db, 'd1'), '[1,2,3]');
    });
  });

  group('archive', () {
    test('a healthy library is not pushed to v6', () async {
      await repos.dances.create(sampleDance(id: 'd1', title: 'Fine'));
      await repos.ensureMigrated();

      final archive = await ArchiveExporter(repos).export();
      expect(encodeArchive(archive).contains('tunesRaw'), isFalse);
      expect(
        requiredSchemaVersion(archive),
        lessThan(archiveSchemaVersionUnreadableTunes),
      );
    });

    test('an undecodable tune list round-trips verbatim at v6', () async {
      const raw = '[1,2,3]';
      await repos.dances.create(sampleDance(id: 'd1', title: 'Corrupt'));
      await repos.ensureMigrated();
      await _storeRawTunes(db, 'd1', raw);

      final archive = await ArchiveExporter(repos).export();
      expect(
        requiredSchemaVersion(archive),
        archiveSchemaVersionUnreadableTunes,
      );

      final encoded = encodeArchive(archive);
      final decoded = decodeArchive(encoded);
      expect(
        decoded.archive.dances.singleWhere((d) => d.id == 'd1').tunesSource,
        isA<UnreadableTunes>().having((s) => s.storedJson, 'storedJson', raw),
      );
      expect(encodeArchive(decoded.archive), encoded);
    });
  });
}
