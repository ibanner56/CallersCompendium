// End to end through the real storage: an older build applies a newer build's
// record, keeps what it does not sync, and shares the record back with those
// parts in place (spec §6.7). The hash assertions are the point. A device whose
// rebuilt copy of a record differs from the peer's at the same `updatedAt`
// never agrees on it: the baseline never advances, and the record reaches the
// conflict machinery over a difference nobody on this device can see.
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

import 'test_database.dart';

final _stamp = DateTime.utc(2026, 7, 15, 12);

extension on SyncRecordBlob {
  SyncRecordAddress get address => (kind: kind, recordId: id);

  /// This blob as a newer build would send it: the same record plus a
  /// top-level field this build does not know.
  SyncRecordBlob get withKept => SyncRecordBlob(
    kind: kind,
    id: id,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    existenceAt: existenceAt,
    body: {...body, 'addedLater': 'kept'},
  );
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

  test('two peers\' tags with the same name and the same kept field are one '
      'tag, not a review', () async {
    // A natural-key collision at the same `updatedAt` compares the whole body,
    // and the local copy's body only carries the kept field because the
    // candidate builder puts it back. Without it the two copies differ in a
    // field neither user can see, and the pair is queued for a review that has
    // nothing to decide.
    SyncRecordBlob newerTag(String id) => syncRecordBlobForEntity(
      SyncRecordKind.tag,
      Tag(id: id, name: 'Same Tag'),
      updatedAt: _stamp,
      existenceAt: _stamp,
    )!.withKept;

    await apply(newerTag('t-a'));
    expect(await repositories.syncLocal.listRetainedSyncFields(), hasLength(1));

    final result = await const SyncApplyEngine().apply(
      candidates: [SyncMergeCandidate(blob: newerTag('t-b'))],
      storage: storage,
    );

    expect(result.reports, isEmpty);
    expect(await repositories.syncLocal.listReviewQueue(), isEmpty);
  });

  test('a setting this build syncs keeps a newer build\'s extra part and '
      'shares it back', () async {
    final peer = SyncRecordBlob(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      updatedAt: _stamp,
      deletedAt: null,
      existenceAt: _stamp,
      body: const {
        'value': ['Contra'],
        'addedLater': {'on': true},
      },
    );
    await apply(peer);

    // The known part lands in settings; the extra one is only kept.
    expect(await repositories.settings.get('custom_dialects'), ['Contra']);
    final mine = await published(peer.address);
    expect(mine.blob.body['addedLater'], {'on': true});
    expect(mine.wireHash, SyncMergeCandidate(blob: peer).wireHash);
  });

  group('a dance with kept parts that is merged with a duplicate', () {
    // The survivor of a dance merge is the whole record from then on, so the
    // parts it kept must be in the body the merge starts from. A candidate
    // built without them would clear the row when the merged record is stored.
    Dance dance(String id, {String move = 'swing'}) => Dance(
      id: id,
      title: 'Shared Dance',
      figures: [
        testFigure(move: move, params: const {'beats': 8}),
      ],
      createdAt: _stamp,
      updatedAt: _stamp,
    );

    Future<void> applyKeptDance(String id) async {
      final blob = syncRecordBlobForEntity(
        SyncRecordKind.dance,
        dance(id),
        updatedAt: _stamp,
        existenceAt: _stamp,
      )!;
      await apply(blob.withKept);
      expect(
        await repositories.syncLocal.getRetainedSyncFields(
          kind: SyncRecordKind.dance,
          recordId: id,
        ),
        isNotNull,
      );
    }

    Future<void> expectKept(String id) async {
      expect(
        await repositories.syncLocal.getRetainedSyncFields(
          kind: SyncRecordKind.dance,
          recordId: id,
        ),
        isNotNull,
        reason: 'the survivor\'s kept row is still stored',
      );
      final mine = await published((kind: SyncRecordKind.dance, recordId: id));
      expect(mine.blob.body['addedLater'], 'kept');
    }

    test('a fresh attach keeps them', () async {
      await applyKeptDance('a-survivor');
      await repositories.dances.create(dance('z-duplicate'));

      final result = await storage.deduplicateFreshAttach();

      expect(result.duplicateCount, 1);
      expect(await repositories.dances.getById('z-duplicate'), isNull);
      await expectKept('a-survivor');
    });

    test(
      'the dropped duplicate\'s own kept parts are not carried over',
      () async {
        // This pins the choice documented in `_applyDanceDedupeMerge`: the
        // merged body is the survivor's whole record, so what it keeps replaces
        // what the survivor and the duplicates kept before, and a duplicate's
        // parts do not turn up on the survivor. It is the implementation's
        // choice, not a spec rule and not a maintainer decision. It is in
        // tension with sync-spec's "A row MUST follow its record when two
        // identities become one", which can be read as the duplicate's row
        // moving onto the survivor; if that reading is the intended one, this
        // test and the `_storeRetained` call change together.
        //
        // Only top-level parts are covered. Merged link, custom-field and
        // citation items that carry nested unknown keys are not exercised here.
        await repositories.dances.create(dance('a-survivor'));
        await applyKeptDance('z-duplicate');

        await storage.deduplicateFreshAttach();

        expect(await repositories.dances.getById('z-duplicate'), isNull);
        expect(await repositories.syncLocal.listRetainedSyncFields(), isEmpty);
        final mine = await published((
          kind: SyncRecordKind.dance,
          recordId: 'a-survivor',
        ));
        expect(mine.blob.body.containsKey('addedLater'), isFalse);
      },
    );

    test('the user\'s Merge choice keeps them', () async {
      await applyKeptDance('a-survivor');
      await repositories.dances.create(dance('z-other', move: 'allemande'));
      await storage.deduplicateFreshAttach();
      final row = (await repositories.syncLocal.listReviewQueue()).single;
      expect(row.reason, syncDanceChoreographyAmbiguityReason);

      await storage.resolveReviewQueue(
        expectedRow: row,
        action: SyncReviewAction.merge,
      );

      expect(await repositories.dances.getById('z-other'), isNull);
      await expectKept('a-survivor');
    });
  });

  test('a conflict that now looks like this device\'s copy, kept part '
      'included, is not offered', () async {
    // The resolver drops a version that looks the same as this device's copy.
    // Spec §6.7 says that comparison draws only on the part this build syncs
    // (decided by Isaac), which this test does not assert. It works only
    // because for `setting` the visible-fields list is null
    // (`syncUserVisibleFields`), so every non-identity key, a kept one
    // included, counts as visible, and the resolver therefore has to compare
    // this device's copy with its kept part put back.
    //
    // Finding F4 (branch sync-kept-parts-not-visible-differences) strips kept
    // parts in `syncUserVisibleBody`. Once that lands, mutating the resolver to
    // compare a stripped copy becomes equivalent for settings and this test can
    // no longer fail: remove it with that change.
    const address = (kind: SyncRecordKind.setting, recordId: 'custom_dialects');
    SyncMergeCandidate peerCopy(String dialect) => SyncMergeCandidate.fromBlob(
      SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: address.recordId,
        updatedAt: _stamp,
        deletedAt: null,
        existenceAt: _stamp,
        body: {
          'value': [dialect],
          'addedLater': {'on': true},
        },
      ),
      peerId: 'peer',
    );
    await apply(peerCopy('Contra').blob);
    final local = await published(address);
    final plan = const SyncMergeEngine().plan(
      local: {address: local},
      baseline: const {},
      peers: [
        {address: peerCopy('Squares')},
      ],
    );
    await storage.refreshConflictReviews(plan.reviews);
    final resolver = SyncReviewQueueResolver(storage);
    expect(await resolver.listConflicts(), hasLength(1));

    await repositories.settings.set('custom_dialects', [
      'Squares',
    ], at: _stamp.add(const Duration(hours: 1)));

    expect(await resolver.listConflicts(), isEmpty);
  });

  test(
    'a natural-key survivor that takes over a record keeps its kept parts',
    () async {
      // Two peers' tags with one name become one record, under the lower id. The
      // newer content is this device's own record, kept parts included.
      SyncRecordBlob tag(String id, DateTime at, {bool kept = false}) {
        final blob = syncRecordBlobForEntity(
          SyncRecordKind.tag,
          Tag(id: id, name: 'Same Tag'),
          updatedAt: at,
          existenceAt: _stamp,
        )!;
        return kept ? blob.withKept : blob;
      }

      await apply(tag('t-z', _stamp.add(const Duration(hours: 2)), kept: true));
      await const SyncApplyEngine().apply(
        candidates: [SyncMergeCandidate(blob: tag('t-a', _stamp))],
        storage: storage,
      );

      final rows = await repositories.syncLocal.listRetainedSyncFields();
      expect(rows.map((row) => row.recordId), ['t-a']);
      final mine = await published((kind: SyncRecordKind.tag, recordId: 't-a'));
      expect(mine.blob.body['addedLater'], 'kept');
    },
  );

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

  test('making a shared custom field private with parts kept does not stop '
      'the snapshot', () async {
    // A peer's definition carries a field this build does not know, so it is
    // kept. The user then turns "shareable" off. This device now shares
    // nothing of the definition (spec §6.6), and what was kept for it goes
    // with it rather than being published as a record of its own.
    final field = CustomFieldDef(
      id: 'f1',
      key: 'shared_field',
      label: 'Shared field',
      type: CustomFieldType.text,
    );
    final shared = syncRecordBlobForEntity(
      SyncRecordKind.customFieldDef,
      field,
      updatedAt: _stamp,
      existenceAt: _stamp,
    )!;
    final peer = SyncRecordBlob(
      kind: SyncRecordKind.customFieldDef,
      id: shared.id,
      updatedAt: shared.updatedAt,
      deletedAt: null,
      existenceAt: shared.existenceAt,
      body: {...shared.body, 'addedLater': 'kept'},
    );
    await apply(peer);
    expect(await repositories.syncLocal.listRetainedSyncFields(), hasLength(1));

    // ignore: unused_result
    await repositories.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'f1',
        key: 'shared_field',
        label: 'Shared field',
        type: CustomFieldType.text,
        shareable: false,
      ),
      at: _stamp.add(const Duration(hours: 1)),
    );

    final snapshot = await storage.snapshot();
    expect(snapshot.local.containsKey(peer.address), isFalse);
    expect(await repositories.syncLocal.listRetainedSyncFields(), isEmpty);
    // And the next one is no different: nothing is left to trip over.
    expect((await storage.snapshot()).local.containsKey(peer.address), isFalse);
  });

  group('after an upgrade that starts syncing a kept field', () {
    // The kept rows below are what an older build stored for the program's
    // pay, before this build knew the field (#1714). This build knows it, so
    // it must not keep putting the old build's copy back over the record.
    Future<void> keepPayAsAnOlderBuildDid() async {
      await repositories.programs.create(program());
      await repositories.syncLocal.setRetainedSyncFields(
        kind: SyncRecordKind.program,
        recordId: 'p1',
        payload: canonicalJson({
          'payMinorUnits': {'v': 1250},
          'payCurrency': {'v': 'USD'},
          'cueSheet': {'v': 'still unknown here'},
        }),
      );
    }

    test('promotion moves the value into the record, keeps the rest, and '
        'leaves the wire hash as it was', () async {
      await keepPayAsAnOlderBuildDid();
      final before = await published((
        kind: SyncRecordKind.program,
        recordId: 'p1',
      ));

      await storage.promoteRetainedSyncFields();

      final stored = await repositories.programs.getById('p1');
      expect(stored!.payMinorUnits, 1250);
      expect(stored.payCurrency, 'USD');
      final row = await repositories.syncLocal.getRetainedSyncFields(
        kind: SyncRecordKind.program,
        recordId: 'p1',
      );
      expect(
        row!.payload,
        canonicalJson({
          'cueSheet': {'v': 'still unknown here'},
        }),
      );
      final after = await published((
        kind: SyncRecordKind.program,
        recordId: 'p1',
      ));
      expect(after.blob.body['payMinorUnits'], 1250);
      expect(after.blob.body['cueSheet'], 'still unknown here');
      expect(after.blob.updatedAt, before.blob.updatedAt);
    });

    test('ensureMigrated promotes at open', () async {
      await keepPayAsAnOlderBuildDid();
      final reopened = CompendiumRepositories(db, contraTaxonomy);
      await reopened.ensureMigrated();
      expect((await repositories.programs.getById('p1'))!.payCurrency, 'USD');
    });

    test('a kept copy never wins over the record, even unpromoted', () async {
      // Promotion skipped (or not yet run): the user's own edit to the now
      // synced field is what this device shares, not the old kept copy.
      await keepPayAsAnOlderBuildDid();
      final edited = Program(
        id: 'p1',
        title: 'Shared Program',
        slots: program().slots,
        payMinorUnits: 9900,
        payCurrency: 'EUR',
        createdAt: _stamp,
        updatedAt: _stamp.add(const Duration(hours: 1)),
      );
      await repositories.programs.update(edited);

      final body = (await published((
        kind: SyncRecordKind.program,
        recordId: 'p1',
      ))).blob.body;
      expect(body['payMinorUnits'], 9900);
      expect(body['payCurrency'], 'EUR');
      expect(body['cueSheet'], 'still unknown here');
    });

    test('a setting kept whole is applied once this build syncs its key, '
        'unless a newer copy is already here', () async {
      SyncRecordBlob dialects(DateTime at, Object value) => SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        updatedAt: at,
        deletedAt: null,
        existenceAt: at,
        body: {'value': value},
      );
      Future<void> keepWhole(SyncRecordBlob blob) =>
          repositories.syncLocal.setRetainedSyncFields(
            kind: SyncRecordKind.setting,
            recordId: blob.id,
            payload: encodeSyncRecordBlob(blob),
            wholeRecord: true,
          );

      await keepWhole(dialects(_stamp, const ['kept']));
      await storage.promoteRetainedSyncFields();
      expect(await repositories.settings.get('custom_dialects'), ['kept']);
      expect(await repositories.syncLocal.listRetainedSyncFields(), isEmpty);

      await keepWhole(
        dialects(_stamp.subtract(const Duration(days: 1)), ['older']),
      );
      await storage.promoteRetainedSyncFields();
      expect(await repositories.settings.get('custom_dialects'), ['kept']);
      expect(await repositories.syncLocal.listRetainedSyncFields(), isEmpty);
    });
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
