// End to end through the real storage: an older build applies a newer build's
// record, keeps what it does not sync, and shares the record back with those
// parts in place (spec §6.7). The hash assertions are the point. A device whose
// rebuilt copy of a record differs from the peer's at the same `updatedAt`
// never agrees on it: the baseline never advances, and the record reaches the
// conflict machinery over a difference nobody on this device can see.
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'test_database.dart';

final _stamp = DateTime.utc(2026, 7, 15, 12);

extension on SyncRecordBlob {
  SyncRecordAddress get address => (kind: kind, recordId: id);
}

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

  Program program({String title = 'Shared Program', DateTime? at}) => Program(
    id: 'p1',
    title: title,
    slots: [
      ProgramSlot(id: 's1', position: 0, text: 'Break'),
      ProgramSlot(id: 's2', position: 1, text: 'Waltz'),
    ],
    createdAt: _stamp,
    updatedAt: at ?? _stamp,
  );

  /// A newer build's copy of [entity]: what this build would send, plus a
  /// top-level field and a field on each list item this build does not know.
  SyncRecordBlob newerProgram(Program entity) {
    final blob = syncRecordBlobForEntity(
      SyncRecordKind.program,
      entity,
      updatedAt: entity.updatedAt,
      existenceAt: _stamp,
    )!;
    final body = Map<String, Object?>.of(blob.body)
      ..['payNoteV2'] = 'cash on the night'
      ..['slots'] = [
        for (final slot in blob.body['slots']! as List)
          {...(slot as Map<String, Object?>), 'cue': 'lights down'},
      ];
    return SyncRecordBlob(
      kind: SyncRecordKind.program,
      id: blob.id,
      updatedAt: blob.updatedAt,
      deletedAt: null,
      existenceAt: blob.existenceAt,
      body: body,
    );
  }

  Future<void> apply(SyncRecordBlob blob) async {
    final result = await const SyncApplyEngine().apply(
      candidates: [SyncMergeCandidate(blob: blob)],
      storage: storage,
    );
    expect(result.reports, isEmpty);
    expect(result.applied, [blob.address]);
  }

  Future<SyncMergeCandidate> published(SyncRecordAddress address) async =>
      (await storage.snapshot()).local[address]!;

  test(
    'a newer build\'s record is applied and shared back unchanged',
    () async {
      final peer = newerProgram(program());
      await apply(peer);

      final stored = await repositories.programs.getById('p1');
      expect(stored!.title, 'Shared Program');
      final mine = await published(peer.address);
      expect(mine.wireHash, SyncMergeCandidate(blob: peer).wireHash);
    },
  );

  test('the kept parts survive this device\'s own edit', () async {
    await apply(newerProgram(program()));

    final edited = program(
      title: 'Renamed here',
      at: _stamp.add(const Duration(hours: 1)),
    );
    await repositories.programs.update(edited);

    final body = (await published((
      kind: SyncRecordKind.program,
      recordId: 'p1',
    ))).blob.body;
    expect(body['title'], 'Renamed here');
    expect(body['payNoteV2'], 'cash on the night');
    for (final slot in body['slots']! as List) {
      expect((slot as Map)['cue'], 'lights down');
    }
  });

  test('a later version without the field drops it here too', () async {
    await apply(newerProgram(program()));
    final later = syncRecordBlobForEntity(
      SyncRecordKind.program,
      program(at: _stamp.add(const Duration(hours: 2))),
      updatedAt: _stamp.add(const Duration(hours: 2)),
      existenceAt: _stamp,
    )!;
    await apply(later);

    final mine = await published(later.address);
    expect(mine.blob.body.containsKey('payNoteV2'), isFalse);
    expect(mine.wireHash, SyncMergeCandidate(blob: later).wireHash);
    expect(await repositories.syncLocal.listRetainedSyncFields(), isEmpty);
  });

  test('a field this build keeps private is kept, not written into its own '
      'private column', () async {
    // ignore: unused_result
    await repositories.choreographers.upsert(
      Choreographer(id: 'c1', name: 'Caller', email: 'mine@example.com'),
      at: _stamp,
    );
    final peer = SyncRecordBlob(
      kind: SyncRecordKind.choreographer,
      id: 'c1',
      updatedAt: _stamp.add(const Duration(hours: 1)),
      deletedAt: null,
      existenceAt: _stamp,
      body: const {
        'id': 'c1',
        'name': 'Caller',
        'notes': null,
        'website': null,
        'email': 'shared@example.com',
      },
    );
    await apply(peer);

    final stored = await repositories.choreographers.getById('c1');
    expect(stored!.email, 'mine@example.com');
    final mine = await published(peer.address);
    expect(mine.blob.body['email'], 'shared@example.com');
    expect(mine.wireHash, SyncMergeCandidate(blob: peer).wireHash);
  });

  test('a setting this build does not sync is kept whole and shared back, '
      'and never written to settings', () async {
    final peer = SyncRecordBlob(
      kind: SyncRecordKind.setting,
      id: 'a_setting_added_later',
      updatedAt: _stamp,
      deletedAt: null,
      existenceAt: _stamp,
      body: const {
        'value': {'on': true},
      },
    );
    await apply(peer);

    expect(await db.select(db.settings).get(), isEmpty);
    final mine = await published(peer.address);
    expect(mine.wireHash, SyncMergeCandidate(blob: peer).wireHash);
  });

  test('kept parts go when their record is hard-deleted', () async {
    await apply(newerProgram(program()));
    expect(await repositories.syncLocal.listRetainedSyncFields(), hasLength(1));

    await repositories.programs.hardDelete(['p1']);
    await storage.snapshot();

    expect(await repositories.syncLocal.listRetainedSyncFields(), isEmpty);
  });

  test('a restore clears what was kept', () async {
    await apply(newerProgram(program()));
    await repositories.syncLocal.clearForRestore(restoredRecords: const []);
    expect(await repositories.syncLocal.listRetainedSyncFields(), isEmpty);
  });

  test('a key a newer build added inside a figure refuses the record', () {
    final dance = syncRecordBlobForEntity(
      SyncRecordKind.dance,
      Dance(
        id: 'd1',
        title: 'Shared Dance',
        figures: [
          Figure(move: 'swing', params: const {'beats': 8}),
        ],
        createdAt: _stamp,
        updatedAt: _stamp,
      ),
      updatedAt: _stamp,
      existenceAt: _stamp,
    )!;
    final json = dance.toJson();
    final body = Map<String, Object?>.of(json['body']! as Map<String, Object?>)
      ..['figures'] = [
        for (final figure in dance.body['figures']! as List)
          {...(figure as Map<String, Object?>), 'handHold': 'cross'},
      ];
    expect(
      () => SyncRecordBlob.fromJson({...json, 'body': body}),
      throwsA(
        isA<SyncNewerFieldException>().having(
          (e) => e.path,
          'path',
          'figures.handHold',
        ),
      ),
    );
  });
}
