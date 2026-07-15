import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';
import 'support/fake_adapter.dart';

String Function() sequentialIds() {
  var n = 0;
  return () => 'imported-${++n}';
}

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ChoreographerRepository choreographers;
  late ImportPipeline pipeline;
  late String Function() nextId;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    pipeline = ImportPipeline(dances, choreographers);
    nextId = sequentialIds();
  });

  tearDown(() => db.close());

  final now = DateTime.utc(2026, 7, 15);

  Map<String, Object?> record(
    String id,
    String title, {
    List<Map<String, Object?>> figures = const [],
    String? version,
    String? permission,
    String? license,
  }) => {
    'id': id,
    'title': title,
    'version': ?version,
    'permission': ?permission,
    'license': ?license,
    'figures': figures,
  };

  group('commit writes provenance transactionally', () {
    test('a new dance is inserted with a full provenance row', () async {
      final adapter = FakeSourceAdapter([
        record(
          'fake-1',
          'Rory OMore',
          version: 'v3',
          permission: 'full',
          license: 'CC-BY',
          figures: [
            {'beats': 16, 'text': 'balance and swing', 'move': 'swing'},
            {'beats': 8, 'text': 'give and take'},
          ],
        ),
      ]);

      final batch = await pipeline.plan(adapter, const ImportRequest());
      expect(batch.records.single.verdict.isNewDance, isTrue);
      expect(batch.records.single.draft.quality.score, 0.5);

      final session = await pipeline.commit(batch, now: now, newId: nextId);
      expect(session.committedCount, 1);

      final id = session.insertedDanceIds.single;
      final loaded = await dances.getById(id);
      expect(loaded, isNotNull);
      expect(loaded!.title, 'Rory OMore');
      final prov = loaded.provenance!;
      expect(prov.source, ProvenanceSource.json);
      expect(prov.externalId, 'fake-1');
      expect(prov.importedAt, now);
      expect(prov.permission, 'full');
      expect(prov.license, 'CC-BY');
      expect(prov.sourceVersion, 'v3');
      expect(prov.rawPayload, contains('"title":"Rory OMore"'));
    });

    test('custom-figure text is searchable after commit', () async {
      final adapter = FakeSourceAdapter([
        record(
          'fake-2',
          'Custom Only',
          figures: [
            {'beats': 16, 'text': 'weave the star basket'},
          ],
        ),
      ]);
      final batch = await pipeline.plan(adapter, const ImportRequest());
      final session = await pipeline.commit(batch, now: now, newId: nextId);
      final id = session.insertedDanceIds.single;
      final hits = await dances.searchText('basket');
      expect(hits, contains(id));
    });
  });

  group('re-import by (source, externalId)', () {
    test('updates the same dance + provenance, preserving createdAt', () async {
      final first = FakeSourceAdapter([
        record('fake-1', 'Original Title', version: 'v1'),
      ]);
      final s1 = await pipeline.commit(
        await pipeline.plan(first, const ImportRequest()),
        now: now,
        newId: nextId,
      );
      final id = s1.insertedDanceIds.single;
      final created = (await dances.getById(id))!.createdAt;

      // Re-fetch the same external record, changed title + version.
      final again = FakeSourceAdapter([
        record('fake-1', 'Revised Title', version: 'v2'),
      ]);
      final later = DateTime.utc(2026, 8, 1);
      final batch = await pipeline.plan(again, const ImportRequest());
      expect(batch.records.single.verdict.isReimport, isTrue);
      expect(batch.records.single.verdict.targetDanceId, id);

      final s2 = await pipeline.commit(batch, now: later, newId: nextId);
      expect(s2.insertedDanceIds, isEmpty);

      final reloaded = (await dances.getById(id))!;
      expect(reloaded.title, 'Revised Title');
      expect(reloaded.createdAt, created);
      expect(reloaded.provenance!.sourceVersion, 'v2');
      expect(reloaded.provenance!.importedAt, later);
      // Exactly one dance exists (no duplicate inserted).
      expect((await dances.listAll()).length, 1);
    });
  });

  group('fuzzy ambiguous match', () {
    Future<String> seedExisting() async {
      final adapter = FakeSourceAdapter([
        record('fake-1', 'The Nice Combination'),
      ]);
      final s = await pipeline.commit(
        await pipeline.plan(adapter, const ImportRequest()),
        now: now,
        newId: nextId,
      );
      return s.insertedDanceIds.single;
    }

    test(
      'unresolved ambiguous record is skipped (no silent mutation)',
      () async {
        final existingId = await seedExisting();
        final incoming = FakeSourceAdapter([
          record('fake-2', 'Nice Combination'),
        ]);
        final batch = await pipeline.plan(incoming, const ImportRequest());
        expect(batch.records.single.verdict.isAmbiguous, isTrue);

        final session = await pipeline.commit(batch, now: now, newId: nextId);
        expect(session.records.single.action, CommitAction.skip);
        // Only the seeded dance remains untouched.
        final all = await dances.listAll();
        expect(all.length, 1);
        expect(all.single.id, existingId);
        expect(all.single.title, 'The Nice Combination');
      },
    );

    test('resolution link updates the chosen existing dance', () async {
      final existingId = await seedExisting();
      final incoming = FakeSourceAdapter([
        record('fake-2', 'Nice Combination'),
      ]);
      final batch = await pipeline.plan(incoming, const ImportRequest());
      final session = await pipeline.commit(
        batch,
        now: now,
        newId: nextId,
        resolutions: {0: DedupeResolution.link(existingId)},
      );
      expect(session.records.single.action, CommitAction.link);
      final all = await dances.listAll();
      expect(all.length, 1);
      expect(all.single.id, existingId);
      expect(all.single.title, 'Nice Combination');
    });

    test('resolution duplicate imports a separate new dance', () async {
      await seedExisting();
      final incoming = FakeSourceAdapter([
        record('fake-2', 'Nice Combination'),
      ]);
      final batch = await pipeline.plan(incoming, const ImportRequest());
      final session = await pipeline.commit(
        batch,
        now: now,
        newId: nextId,
        resolutions: {0: DedupeResolution.duplicate()},
      );
      expect(session.records.single.action, CommitAction.duplicate);
      expect((await dances.listAll()).length, 2);
    });
  });

  group('partial-batch tolerance & structured errors', () {
    test('a failed fetch is reported; the rest import', () async {
      final adapter = FakeSourceAdapter(
        [
          record('ok-1', 'Good One'),
          record('bad', 'Never Fetched'),
          record('ok-2', 'Good Two'),
        ],
        failFetchExternalIds: {'bad'},
      );
      final batch = await pipeline.plan(adapter, const ImportRequest());
      expect(batch.records.length, 2);
      expect(batch.errors.length, 1);
      final err = batch.errors.single;
      expect(err.stage, ImportStage.fetch);
      expect(err.externalId, 'bad');
      expect(err.toString(), isNot(contains('#0'))); // no stack trace

      final session = await pipeline.commit(batch, now: now, newId: nextId);
      expect(session.committedCount, 2);
    });

    test('an invalid payload yields a structured parse error', () async {
      // A record with no title triggers a parse ImportError in the adapter.
      final adapter = FakeSourceAdapter([
        {'id': 'no-title', 'figures': const []},
      ]);
      final batch = await pipeline.plan(adapter, const ImportRequest());
      expect(batch.records, isEmpty);
      expect(batch.errors.single.stage, ImportStage.parse);
      expect(batch.errors.single.externalId, 'no-title');
    });

    test('a discovery failure aborts the whole batch as one error', () async {
      final adapter = FakeSourceAdapter([], discoverThrows: true);
      final batch = await pipeline.plan(adapter, const ImportRequest());
      expect(batch.records, isEmpty);
      expect(batch.errors.single.stage, ImportStage.discover);
    });
  });

  group('undo', () {
    test('removes freshly inserted dances', () async {
      final adapter = FakeSourceAdapter([
        record('fake-1', 'One'),
        record('fake-2', 'Two'),
      ]);
      final session = await pipeline.commit(
        await pipeline.plan(adapter, const ImportRequest()),
        now: now,
        newId: nextId,
      );
      expect((await dances.listAll()).length, 2);

      await pipeline.undo(session);
      expect(await dances.listAll(), isEmpty);
      expect(session.isUndone, isTrue);

      // Idempotent.
      await pipeline.undo(session);
      expect(await dances.listAll(), isEmpty);
    });

    test('restores an updated dance to its prior state', () async {
      final first = FakeSourceAdapter([record('fake-1', 'Before')]);
      final s1 = await pipeline.commit(
        await pipeline.plan(first, const ImportRequest()),
        now: now,
        newId: nextId,
      );
      final id = s1.insertedDanceIds.single;

      final again = FakeSourceAdapter([record('fake-1', 'After')]);
      final s2 = await pipeline.commit(
        await pipeline.plan(again, const ImportRequest()),
        now: DateTime.utc(2026, 9, 1),
        newId: nextId,
      );
      expect((await dances.getById(id))!.title, 'After');

      await pipeline.undo(s2);
      final restored = (await dances.getById(id))!;
      expect(restored.title, 'Before');
    });
  });
}
