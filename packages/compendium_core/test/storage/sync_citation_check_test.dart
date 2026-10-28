// The citation check Device Sync runs for a choreographer, tag, published
// source or custom field (#1935): `CompendiumSyncStorage._hasCitation` asks
// whether a live dance still cites the record, once per pending deletion on
// every `snapshot()` and once per inbound tombstone.
//
// Two things are pinned here. The behaviour is that of the per-citing-row loop
// the single `EXISTS` replaced, owner state by owner state. And every one of
// those lookups seeks an index on the cited-id column instead of scanning the
// join table, because each join table's primary key leads with `dance_id`.
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:test/test.dart';

import 'test_database.dart';

/// One record kind the check covers, with what it takes to seed it, to cite it
/// from a dance, and to tombstone it.
final class _CitedKind {
  const _CitedKind({
    required this.name,
    required this.kind,
    required this.joinTable,
    required this.citedColumn,
    required this.indexName,
    required this.seed,
    required this.cite,
    required this.body,
    required this.exists,
  });

  final String name;
  final SyncRecordKind kind;
  final String joinTable;
  final String citedColumn;
  final String indexName;
  final Future<void> Function(CompendiumRepositories repositories) seed;
  final Dance Function(Dance dance) cite;
  final Map<String, Object?> Function() body;
  final Future<bool> Function(CompendiumRepositories repositories) exists;
}

const _id = 'cited-record';

final _kinds = <_CitedKind>[
  _CitedKind(
    name: 'choreographer',
    kind: SyncRecordKind.choreographer,
    joinTable: 'dance_authors',
    citedColumn: 'choreographer_id',
    indexName: 'dance_authors_choreographer_id',
    seed: (repositories) async {
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(id: _id, name: 'Cited'),
        at: DateTime.utc(2025, 1, 2, 12),
      );
    },
    cite: (dance) => dance.copyWith(authorIds: const [_id]),
    body: () => syncBodyForEntity(
      SyncRecordKind.choreographer,
      Choreographer(id: _id, name: 'Cited'),
    ),
    exists: (repositories) async =>
        await repositories.choreographers.getById(_id) != null,
  ),
  _CitedKind(
    name: 'tag',
    kind: SyncRecordKind.tag,
    joinTable: 'dance_tags',
    citedColumn: 'tag_id',
    indexName: 'dance_tags_tag_id',
    seed: (repositories) async {
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: _id, name: 'Cited'),
        at: DateTime.utc(2025, 1, 2, 12),
      );
    },
    cite: (dance) => dance.copyWith(tagIds: const [_id]),
    body: () =>
        syncBodyForEntity(SyncRecordKind.tag, Tag(id: _id, name: 'Cited')),
    exists: (repositories) async =>
        await repositories.tags.getById(_id) != null,
  ),
  _CitedKind(
    name: 'published source',
    kind: SyncRecordKind.publishedSource,
    joinTable: 'dance_sources',
    citedColumn: 'source_id',
    indexName: 'dance_sources_source_id',
    seed: (repositories) async {
      await repositories.publishedSources.upsert(
        PublishedSource(id: _id, title: 'Cited'),
        at: DateTime.utc(2025, 1, 2, 12),
      );
    },
    cite: (dance) =>
        dance.copyWith(sourceCitations: [SourceCitation(sourceId: _id)]),
    body: () => syncBodyForEntity(
      SyncRecordKind.publishedSource,
      PublishedSource(id: _id, title: 'Cited'),
    ),
    exists: (repositories) async =>
        await repositories.publishedSources.getById(_id) != null,
  ),
  _CitedKind(
    name: 'custom field',
    kind: SyncRecordKind.customFieldDef,
    joinTable: 'custom_field_values',
    citedColumn: 'field_id',
    indexName: 'custom_field_values_field_id',
    seed: (repositories) async {
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: _id,
          key: 'cited',
          label: 'Cited',
          type: CustomFieldType.text,
        ),
        at: DateTime.utc(2025, 1, 2, 12),
      );
    },
    cite: (dance) => dance.copyWith(
      customFields: [CustomFieldValue(fieldId: _id, value: 'v')],
    ),
    body: () => syncBodyForEntity(
      SyncRecordKind.customFieldDef,
      CustomFieldDef(
        id: _id,
        key: 'cited',
        label: 'Cited',
        type: CustomFieldType.text,
      ),
    ),
    exists: (repositories) async =>
        await repositories.customFieldDefs.getById(_id) != null,
  ),
];

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repositories;
  late CompendiumSyncStorage storage;

  final stamp = DateTime.utc(2025, 1, 2, 12);
  final tombstoneStamp = stamp.add(const Duration(minutes: 5));

  setUp(() {
    db = openTestDatabase();
    repositories = CompendiumRepositories(db, contraTaxonomy);
    storage = CompendiumSyncStorage(repositories);
  });

  tearDown(() => db.close());

  Future<void> createCiter(_CitedKind k, String id) => repositories.dances
      .create(
        k.cite(Dance(id: id, title: id, createdAt: stamp, updatedAt: stamp)),
      )
      .then((_) {});

  SyncMergeCandidate tombstone(
    SyncRecordKind kind,
    String id,
    Map<String, Object?> body,
  ) => SyncMergeCandidate(
    blob: SyncRecordBlob(
      kind: kind,
      id: id,
      updatedAt: tombstoneStamp,
      deletedAt: tombstoneStamp,
      existenceAt: tombstoneStamp,
      body: body,
    ),
  );

  Future<bool> isPending(_CitedKind k) async =>
      await repositories.syncLocal.getPendingDeletion(
        kind: k.kind,
        recordId: _id,
      ) !=
      null;

  Future<void> applyAll(List<SyncMergeCandidate> candidates) async {
    final result = await const SyncApplyEngine().apply(
      candidates: candidates,
      storage: storage,
    );
    expect(result.reports, isEmpty);
  }

  for (final k in _kinds) {
    group('${k.name} citation check', () {
      test(
        'a live dance citing it holds the inbound tombstone pending',
        () async {
          await k.seed(repositories);
          await createCiter(k, 'live');

          await applyAll([tombstone(k.kind, _id, k.body())]);

          expect(await isPending(k), isTrue);
          expect(await k.exists(repositories), isTrue);
        },
      );

      test('a dance in the Trash does not hold it', () async {
        await k.seed(repositories);
        await createCiter(k, 'trashed');
        await repositories.dances.softDelete('trashed', at: stamp);

        await applyAll([tombstone(k.kind, _id, k.body())]);

        expect(await isPending(k), isFalse);
        expect(await k.exists(repositories), isFalse);
      });

      test('one live citer among trashed ones is enough', () async {
        await k.seed(repositories);
        await createCiter(k, 'trashed-a');
        await createCiter(k, 'live');
        await createCiter(k, 'trashed-b');
        await repositories.dances.softDelete('trashed-a', at: stamp);
        await repositories.dances.softDelete('trashed-b', at: stamp);

        await applyAll([tombstone(k.kind, _id, k.body())]);

        expect(await isPending(k), isTrue);
      });

      test(
        'a citer tombstoned by the same inbound batch does not hold it',
        () async {
          await k.seed(repositories);
          await createCiter(k, 'citer');
          final citer = await repositories.dances.getById('citer');

          await applyAll([
            tombstone(k.kind, _id, k.body()),
            tombstone(
              SyncRecordKind.dance,
              'citer',
              syncBodyForEntity(SyncRecordKind.dance, citer!),
            ),
          ]);

          expect(await isPending(k), isFalse);
          expect(await k.exists(repositories), isFalse);
        },
      );

      test('a citer left live by the batch still holds it', () async {
        await k.seed(repositories);
        await createCiter(k, 'citer');
        await createCiter(k, 'other-citer');
        final citer = await repositories.dances.getById('citer');

        await applyAll([
          tombstone(k.kind, _id, k.body()),
          tombstone(
            SyncRecordKind.dance,
            'citer',
            syncBodyForEntity(SyncRecordKind.dance, citer!),
          ),
        ]);

        expect(await isPending(k), isTrue);
      });

      test('a join row whose dance row is missing does not hold it', () async {
        await k.seed(repositories);
        await createCiter(k, 'gone');
        // Orphan the join row: with foreign keys off the delete does not
        // cascade, which is the only way a join row can outlive its dance.
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await db.customStatement("DELETE FROM dances WHERE id = 'gone'");
        await db.customStatement('PRAGMA foreign_keys = ON');
        final orphans = await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM ${k.joinTable} WHERE dance_id = ?',
              variables: [Variable.withString('gone')],
            )
            .getSingle();
        expect(orphans.read<int>('n'), 1, reason: 'the join row must remain');

        await applyAll([tombstone(k.kind, _id, k.body())]);

        expect(await isPending(k), isFalse);
      });

      test(
        'the lookup seeks the cited-id index, not a scan of ${k.joinTable}',
        () async {
          for (final excluding in [false, true]) {
            final plan = await db
                .customSelect(
                  'EXPLAIN QUERY PLAN ${liveDanceCitationSql(k.joinTable, k.citedColumn, excludingIds: excluding)}',
                  variables: [
                    Variable.withString(_id),
                    if (excluding) Variable.withString('["x"]'),
                  ],
                )
                .get();
            final details = [
              for (final row in plan) row.read<String>('detail'),
            ];
            expect(
              details,
              contains(
                matches(
                  RegExp('SEARCH j USING (COVERING )?INDEX ${k.indexName}\\b'),
                ),
              ),
              reason: 'excluding=$excluding plan:\n${details.join('\n')}',
            );
            expect(
              details,
              isNot(contains(matches(RegExp(r'SCAN j\b')))),
              reason: 'excluding=$excluding plan:\n${details.join('\n')}',
            );
          }
        },
      );
    });
  }

  test('a fresh database has all four cited-id indexes', () async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final names = {for (final row in rows) row.read<String>('name')};
    expect(names, containsAll([for (final k in _kinds) k.indexName]));
  });
}
