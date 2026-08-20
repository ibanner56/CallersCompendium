import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

Dance _dance(String id) => Dance(
  id: id,
  title: 'Dance $id',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

String _payload({List<Dance>? dances}) => encodeArchive(
  CompendiumArchive(
    exportedAt: DateTime.utc(2026, 1, 1),
    dances: dances ?? [_dance('d1')],
  ),
);

Map<String, Object?> _root() =>
    Map<String, Object?>.from(jsonDecode(_payload()) as Map);

String _json(Map<String, Object?> root) => jsonEncode(root);

void main() {
  final metadata = PublishedCollectionMetadata(
    collectionId: 'book',
    collectionVersion: 'v1',
    archiveDigest: 'sha256:digest',
    permission: 'author-granted',
    license: 'CC-BY-NC-4.0',
  );

  group('PublishedCollectionArchive', () {
    test('accepts a dance-only archive', () {
      expect(
        PublishedCollectionArchive.decode(_payload()).dances,
        hasLength(1),
      );
    });

    for (final entity in ['programs', 'venues', 'customFields']) {
      test('rejects non-empty top-level $entity', () {
        final root = _root()
          ..[entity] = <Map<String, Object?>>[<String, Object?>{}];
        expect(
          () => PublishedCollectionArchive.decode(_json(root)),
          throwsA(isA<ImportError>()),
        );
      });
    }

    test('rejects an unknown top-level entity', () {
      final root = _root()..['surprise'] = [];
      expect(
        () => PublishedCollectionArchive.decode(_json(root)),
        throwsA(isA<ImportError>()),
      );
    });

    test('rejects duplicate and missing dance ids', () {
      final duplicate = _root();
      duplicate['dances'] = [
        {'id': 'd1', 'title': 'One'},
        {'id': 'd1', 'title': 'Two'},
      ];
      expect(
        () => PublishedCollectionArchive.decode(_json(duplicate)),
        throwsA(isA<ImportError>()),
      );

      final missing = _root();
      missing['dances'] = [
        {'title': 'No id'},
      ];
      expect(
        () => PublishedCollectionArchive.decode(_json(missing)),
        throwsA(isA<ImportError>()),
      );
    });

    test('rejects embedded published provenance', () {
      final root = _root();
      final dance = Map<String, Object?>.from(
        (root['dances'] as List).single as Map,
      )..['provenance'] = {'source': 'publishedCollection'};
      root['dances'] = [dance];
      expect(
        () => PublishedCollectionArchive.decode(_json(root)),
        throwsA(isA<ImportError>()),
      );
    });
  });

  group('PublishedCollectionImporter', () {
    late CompendiumDatabase db;
    late DanceRepository dances;
    late CollectionImportEventRepository events;
    late PublishedCollectionImporter importer;

    setUp(() {
      db = openTestDatabase();
      dances = DanceRepository(db, contraTaxonomy);
      events = CollectionImportEventRepository(db);
      importer = PublishedCollectionImporter(
        ImportPipeline(dances, ChoreographerRepository(db)),
      );
    });

    tearDown(() => db.close());

    test('stamps manifest metadata and exposes an idempotent event', () async {
      final now = DateTime.utc(2026, 8, 20);
      final batch = await importer.plan(_payload(), metadata);
      final raw = batch.records.single.draft.raw;
      expect(raw.source, ProvenanceSource.publishedCollection);
      expect(raw.externalId, 'book/d1');
      expect(raw.sourceVersion, 'v1');
      expect(raw.permission, 'author-granted');
      expect(raw.license, 'CC-BY-NC-4.0');

      final result = await importer.commit(
        batch,
        metadata: metadata,
        now: now,
        newId: () => 'local-d1',
      );
      await events.record(result.event);
      await events.record(result.event);

      final dance = (await dances.listAll()).single;
      expect(dance.provenance?.source, ProvenanceSource.publishedCollection);
      expect(dance.provenance?.externalId, 'book/d1');
      expect(dance.provenance?.sourceVersion, 'v1');
      expect(dance.provenance?.permission, 'author-granted');
      expect(dance.provenance?.license, 'CC-BY-NC-4.0');
      expect(await events.listAll(), hasLength(1));
      expect(await events.heldCount('book'), 1);
      expect(await events.heldCount('book', version: 'v2'), 0);
    });
  });
}
