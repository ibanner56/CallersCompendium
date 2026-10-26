// A storage instance's later snapshots reuse each unchanged record's blob and
// wire hash from its previous one, and rebuild exactly the records whose
// inputs changed (#1931). The memo is the snapshot's own business: its output
// must stay byte-identical to a fresh instance's, which the last group checks
// after random edits.
import 'dart:math';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/storage/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

final _stamp = DateTime.utc(2026, 7, 15, 12);

SyncRecordAddress _danceAt(String id) =>
    (kind: SyncRecordKind.dance, recordId: id);

const _choreographer = (kind: SyncRecordKind.choreographer, recordId: 'c1');
const _field = (kind: SyncRecordKind.customFieldDef, recordId: 'f1');

CustomFieldDef _customField({required bool shareable}) => CustomFieldDef(
  id: 'f1',
  key: 'shared_field',
  label: 'Shared field',
  type: CustomFieldType.text,
  shareable: shareable,
);

Provenance _provenance(String externalId) => Provenance(
  source: ProvenanceSource.contradb,
  externalId: externalId,
  importedAt: DateTime.utc(2026, 1, 2),
);

void main() {
  late CompendiumDatabase db;
  late CompendiumRepositories repositories;
  late CompendiumSyncStorage storage;
  late List<SyncRecordAddress> built;

  setUp(() async {
    db = openTestDatabase();
    repositories = CompendiumRepositories(db, contraTaxonomy);
    storage = CompendiumSyncStorage(repositories);
    built = [];
    debugOnSnapshotBlobBuild = built.add;
    addTearDown(() => debugOnSnapshotBlobBuild = null);
    // ignore: unused_result
    await repositories.choreographers.upsert(
      Choreographer(id: 'c1', name: 'Mary'),
      at: _stamp,
    );
    // ignore: unused_result
    await repositories.customFieldDefs.upsert(
      _customField(shareable: true),
      at: _stamp,
    );
    for (final id in ['d1', 'd2', 'd3']) {
      await repositories.dances.create(
        sampleDance(
          id: id,
          title: 'Dance $id',
          authorIds: const ['c1'],
          customFields: [CustomFieldValue(fieldId: 'f1', value: 'v-$id')],
        ),
      );
    }
  });

  tearDown(() => db.close());

  /// The records the next snapshot of [storage] builds rather than reuses.
  Future<Set<SyncRecordAddress>> rebuiltBy(Future<void> Function() edit) async {
    await storage.snapshot();
    await edit();
    built.clear();
    await storage.snapshot();
    return built.toSet();
  }

  /// [storage]'s snapshot beside a fresh instance's, record by record.
  Future<void> expectSameAsFresh() async {
    final memoised = await storage.snapshot();
    final fresh = await CompendiumSyncStorage(repositories).snapshot();
    expect(memoised.local.keys.toSet(), fresh.local.keys.toSet());
    for (final MapEntry(:key, :value) in fresh.local.entries) {
      final mine = memoised.local[key];
      expect(mine?.wireHash, value?.wireHash, reason: '$key');
      expect(mine?.blob.canonicalUtf8, value?.blob.canonicalUtf8);
    }
  }

  test('a snapshot with nothing changed builds no record again', () async {
    await storage.snapshot();
    expect(built, isNotEmpty);
    built.clear();
    final second = await storage.snapshot();
    expect(second.local, isNotEmpty);
    expect(built, isEmpty);
    await expectSameAsFresh();
  });

  group(
    'a later snapshot rebuilds exactly the records whose inputs changed:',
    () {
      test('a dance edit', () async {
        final rebuilt = await rebuiltBy(() async {
          final dance = await repositories.dances.getById('d1');
          await repositories.dances.update(
            dance!.copyWith(title: 'Renamed', updatedAt: _stamp),
          );
        });
        expect(rebuilt, {_danceAt('d1')});
        await expectSameAsFresh();
      });

      // `Dance.==` does not compare provenance, so a memo keyed on the entity
      // would keep the old provenance on the wire. The archive body has it.
      test('a provenance change that leaves every timestamp alone', () async {
        final rebuilt = await rebuiltBy(() async {
          final dance = await repositories.dances.getById('d1');
          await repositories.dances.update(
            dance!.copyWith(provenance: _provenance('x-1')),
          );
        });
        expect(rebuilt, {_danceAt('d1')});
        await expectSameAsFresh();
      });

      test('a timestamp alone', () async {
        final rebuilt = await rebuiltBy(() async {
          await (db.update(db.dances)..where((t) => t.id.equals('d2'))).write(
            DancesCompanion(existenceAt: Value(_stamp)),
          );
        });
        expect(rebuilt, {_danceAt('d2')});
        await expectSameAsFresh();
      });

      // Dances carry the choreographer's id, not the name, so only the
      // choreographer's own record changes.
      test('a linked choreographer renamed', () async {
        final rebuilt = await rebuiltBy(() async {
          // ignore: unused_result
          await repositories.choreographers.upsert(
            Choreographer(id: 'c1', name: 'Mary Renamed'),
            at: _stamp,
          );
        });
        expect(rebuilt, {_choreographer});
        await expectSameAsFresh();
      });

      // Making a field private changes every dance that carries it without
      // bumping any dance's `updatedAt`. The shareable ids are in every
      // record's key, not only a dance's, so every record is rebuilt: more
      // than needed, for a rare edit, and nothing to get wrong per kind.
      test('a custom field made private', () async {
        final rebuilt = await rebuiltBy(() async {
          // ignore: unused_result
          await repositories.customFieldDefs.upsert(
            _customField(shareable: false),
            at: _stamp,
          );
        });
        final snapshot = await storage.snapshot();
        expect(rebuilt, {...snapshot.local.keys, _field});
        expect(rebuilt, containsAll([_danceAt('d1'), _danceAt('d3')]));
        expect(
          snapshot.local[_danceAt('d1')]!.blob.body['customFields'],
          isEmpty,
        );
        await expectSameAsFresh();
      });

      test('kept parts for a newer version stored for one record', () async {
        final rebuilt = await rebuiltBy(() async {
          await repositories.syncLocal.setRetainedSyncFields(
            kind: SyncRecordKind.dance,
            recordId: 'd3',
            payload: canonicalJson({
              'futureField': {'v': 'from a newer build'},
            }),
          );
        });
        expect(rebuilt, {_danceAt('d3')});
        final snapshot = await storage.snapshot();
        expect(
          snapshot.local[_danceAt('d3')]!.blob.body['futureField'],
          'from a newer build',
        );
        await expectSameAsFresh();
      });

      test('a delete, then a restore', () async {
        final deleted = await rebuiltBy(
          () => repositories.dances.softDelete('d1', at: _stamp),
        );
        expect(deleted, {_danceAt('d1')});
        await expectSameAsFresh();
        final restored = await rebuiltBy(
          () => repositories.dances.restore(
            'd1',
            at: _stamp.add(const Duration(minutes: 1)),
          ),
        );
        expect(restored, {_danceAt('d1')});
        await expectSameAsFresh();
      });
    },
  );

  test(
    'a record gone from the library does not come back from the memo',
    () async {
      await storage.snapshot();
      await (db.delete(db.dances)..where((t) => t.id.equals('d2'))).go();
      final snapshot = await storage.snapshot();
      expect(snapshot.local.containsKey(_danceAt('d2')), isFalse);
      await expectSameAsFresh();
    },
  );

  // The property behind every case above: whatever is edited, in whatever
  // order, the memoised snapshot is the one a fresh instance takes. A key
  // that misses an input fails here even if no case above names that input.
  group('after random edits, the memoised snapshot is a fresh one', () {
    for (final seed in [1, 2, 3, 4, 5]) {
      test('seed $seed', () async {
        final random = Random(seed);
        var minute = 0;
        DateTime next() => _stamp.add(Duration(minutes: ++minute));
        final ids = ['d1', 'd2', 'd3'];
        String pick() => ids[random.nextInt(ids.length)];
        final edits = <Future<void> Function()>[
          () async {
            final dance = await repositories.dances.getById(
              pick(),
              includeDeleted: true,
            );
            await repositories.dances.update(
              dance!.copyWith(title: 'T${random.nextInt(4)}'),
            );
          },
          () async {
            final dance = await repositories.dances.getById(
              pick(),
              includeDeleted: true,
            );
            await repositories.dances.update(
              dance!.copyWith(provenance: _provenance('p${random.nextInt(3)}')),
            );
          },
          () async {
            final dance = await repositories.dances.getById(
              pick(),
              includeDeleted: true,
            );
            await repositories.dances.update(
              dance!.copyWith(
                customFields: [
                  CustomFieldValue(
                    fieldId: 'f1',
                    value: 'r${random.nextInt(3)}',
                  ),
                ],
              ),
            );
          },
          () async {
            final id = pick();
            await (db.update(db.dances)..where((t) => t.id.equals(id))).write(
              DancesCompanion(existenceAt: Value(next())),
            );
          },
          () async {
            // ignore: unused_result
            await repositories.choreographers.upsert(
              Choreographer(id: 'c1', name: 'Name ${random.nextInt(3)}'),
              at: next(),
            );
          },
          () async {
            // ignore: unused_result
            await repositories.customFieldDefs.upsert(
              _customField(shareable: random.nextBool()),
              at: next(),
            );
          },
          () => repositories.syncLocal.setRetainedSyncFields(
            kind: SyncRecordKind.dance,
            recordId: pick(),
            payload: random.nextBool()
                ? null
                : canonicalJson({
                    'futureField': {'v': 'k${random.nextInt(3)}'},
                  }),
          ),
          () => repositories.dances.softDelete(pick(), at: next()),
          () => repositories.dances.restore(pick(), at: next()),
        ];
        await storage.snapshot();
        for (var step = 0; step < 25; step++) {
          await edits[random.nextInt(edits.length)]();
          await expectSameAsFresh();
        }
      });
    }
  });
}
