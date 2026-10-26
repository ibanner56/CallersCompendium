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
final _later = DateTime.utc(2026, 8, 1);

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

  // One record of every entity kind, so a kind whose archive body could never
  // match itself (a value `_sameJson` does not accept, say) shows up here.
  test('a snapshot with nothing changed builds no record again', () async {
    // ignore: unused_result
    await repositories.tags.upsert(
      Tag(id: 't1', name: 'Tag'),
      at: _stamp,
    );
    // ignore: unused_result
    await repositories.publishedSources.upsert(
      PublishedSource(id: 'ps1', title: 'Source', author: 'A', year: 1999),
      at: _stamp,
    );
    await repositories.venues.upsert(
      Venue(id: 'v1', name: 'Town Hall', city: 'Brattleboro'),
      at: _stamp,
    );
    await repositories.programs.create(
      Program(
        id: 'p1',
        title: 'Program',
        venueId: 'v1',
        createdAt: _stamp,
        updatedAt: _stamp,
      ),
    );
    await repositories.userGlossary.upsert(
      UserGlossaryEntry(
        id: 'zoom-id',
        kindName: UserGlossaryEntryKind.customFigure.name,
        name: 'zoom',
        definition: 'A zoom.',
        description: 'Fast.',
        payload: {
          'form': 'contra',
          'template': '{who} zoom',
          'defaultBeats': 8,
          'params': [
            {'key': 'who', 'kind': 'dancerSet', 'default': 'neighbors'},
          ],
        },
        createdAt: _stamp,
      ),
      at: _stamp,
    );
    await repositories.figureNotes.set('swing', 'Notes.', at: _stamp);

    await storage.snapshot();
    expect({
      for (final address in built) address.kind,
    }, SyncRecordKind.values.toSet()..remove(SyncRecordKind.setting));
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

      // A choreographer's entity carries no timestamps, unlike a dance's, so
      // only the key's own timestamps can tell these apart. A tombstoned
      // choreographer also leaves the author lists of the dances citing it,
      // as they hydrate, so those are rebuilt too.
      final citing = {_danceAt('d1'), _danceAt('d2'), _danceAt('d3')};
      for (final (column, companion, dependents) in [
        (
          'updated_at',
          ChoreographersCompanion(updatedAt: Value(_later)),
          <SyncRecordAddress>{},
        ),
        (
          'existence_at',
          ChoreographersCompanion(existenceAt: Value(_later)),
          <SyncRecordAddress>{},
        ),
        (
          'deleted_at',
          ChoreographersCompanion(deletedAt: Value(_later)),
          citing,
        ),
      ]) {
        test(
          '$column alone, on a record whose entity has no timestamps',
          () async {
            final rebuilt = await rebuiltBy(() async {
              await (db.update(
                db.choreographers,
              )..where((t) => t.id.equals('c1'))).write(companion);
            });
            expect(rebuilt, {_choreographer, ...dependents});
            await expectSameAsFresh();
          },
        );
      }

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

      // Whether a dance shares a custom field's value is the definition's
      // state, not the dance's. The repository restamps the dances holding a
      // field when its shareability changes, so this writes the column
      // directly: the memo must not depend on that restamp. The shareable ids
      // are in every record's key, not only a dance's, so every record is
      // rebuilt: more than needed, for a rare edit, and nothing to get wrong
      // per kind.
      test('a custom field made private, with no dance restamped', () async {
        final rebuilt = await rebuiltBy(() async {
          await (db.update(db.customFieldDefs)..where((t) => t.id.equals('f1')))
              .write(const CustomFieldDefsCompanion(shareable: Value(false)));
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
            final at = Value<DateTime?>(next());
            await (db.update(db.choreographers)
                  ..where((t) => t.id.equals('c1')))
                .write(switch (random.nextInt(3)) {
                  0 => ChoreographersCompanion(updatedAt: at),
                  1 => ChoreographersCompanion(existenceAt: at),
                  _ => ChoreographersCompanion(deletedAt: at),
                });
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
          () async {
            await (db.update(
              db.customFieldDefs,
            )..where((t) => t.id.equals('f1'))).write(
              CustomFieldDefsCompanion(shareable: Value(random.nextBool())),
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
