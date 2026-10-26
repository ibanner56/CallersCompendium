// The inbound apply's concurrency guard (#1909). The guard compares each
// touched record against the hash the coordinator's merge snapshot saw, inside
// the apply transaction. That transaction holds the database's write lock from
// its first statement, so whatever the guard reads, every app write waits for.
// It used to read the whole library; it now reads only the records the batch
// touches, and these tests pin both halves of that: it reads little, and what
// it reads hashes exactly as the snapshot does.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException, sqlite3;
import 'package:test/test.dart';

import 'fixtures.dart';
import 'test_database.dart';

final _stamp = DateTime.utc(2026, 7, 15, 12);

/// Counts the rows every SELECT returns, so a test can tell a read of a few
/// records from a scan of the library.
final class _RowCounter extends QueryInterceptor {
  int rows = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runSelect(executor, statement, args);
    rows += result.length;
    return result;
  }
}

/// [blob] as a newer build would send it: the same record plus a top-level
/// field this build does not know, which this device keeps (spec §6.7).
SyncRecordBlob _withKept(SyncRecordBlob blob) => SyncRecordBlob(
  kind: blob.kind,
  id: blob.id,
  updatedAt: blob.updatedAt,
  deletedAt: blob.deletedAt,
  existenceAt: blob.existenceAt,
  body: {...blob.body, 'addedLater': 'kept'},
);

SyncRecordBlob _blob(SyncRecordKind kind, Object entity) =>
    syncRecordBlobForEntity(
      kind,
      entity,
      updatedAt: _stamp,
      existenceAt: _stamp,
      allowedCustomFieldIds: const {'cf-shared'},
    )!;

void main() {
  group('currentCandidates', () {
    late CompendiumDatabase db;
    late CompendiumRepositories repositories;
    late CompendiumSyncStorage storage;

    setUp(() {
      db = openTestDatabase();
      repositories = CompendiumRepositories(db, contraTaxonomy);
      storage = CompendiumSyncStorage(repositories);
    });

    tearDown(() => db.close());

    Future<void> applyInbound(Iterable<SyncRecordBlob> blobs) async {
      final result = await const SyncApplyEngine().apply(
        candidates: [for (final blob in blobs) SyncMergeCandidate(blob: blob)],
        storage: storage,
      );
      expect(result.reports, isEmpty);
    }

    test('hashes every kind exactly as snapshot() does', () async {
      // A peer's records, so the kinds without a convenient local writer and
      // the kept parts of a newer build arrive the way they do in use.
      await applyInbound([
        _withKept(
          _blob(
            SyncRecordKind.choreographer,
            Choreographer(id: 'c1', name: 'Shared Caller'),
          ),
        ),
        _withKept(
          _blob(
            SyncRecordKind.program,
            Program(
              id: 'p1',
              title: 'Shared Program',
              slots: [ProgramSlot(id: 's1', position: 0, text: 'Break')],
              createdAt: _stamp,
              updatedAt: _stamp,
            ),
          ),
        ),
        _blob(
          SyncRecordKind.customFieldDef,
          CustomFieldDef(
            id: 'cf-shared',
            key: 'tempo',
            label: 'Tempo',
            type: CustomFieldType.number,
          ),
        ),
        _blob(
          SyncRecordKind.publishedSource,
          PublishedSource(id: 'src1', title: 'A Book', year: 1999),
        ),
        _blob(
          SyncRecordKind.difficultyLevel,
          DifficultyLevel(id: 'dl1', label: 'Fiendish', position: 9),
        ),
        _blob(
          SyncRecordKind.venue,
          Venue(id: 'v1', name: 'The Grange Hall', city: 'Anytown'),
        ),
        _blob(
          SyncRecordKind.glossaryEntry,
          StoredUserGlossaryEntry(
            id: 'entry-1',
            kind: 'compound',
            name: 'role1s chain',
            definition: 'A chain for role1s.',
            description: 'All the way round.',
            keywords: const ['chain'],
            notes: 'Mind the hands.',
            payloadJson: '{"params":[],"figures":[],"bindings":[]}',
            createdAt: _stamp,
          ),
        ),
        _blob(
          SyncRecordKind.figureNote,
          const FigureNote(figureId: 'swing', notes: 'Smooth.'),
        ),
        // A setting this build does not sync, kept whole.
        SyncRecordBlob(
          kind: SyncRecordKind.setting,
          id: 'a_setting_added_later',
          updatedAt: _stamp,
          deletedAt: null,
          existenceAt: _stamp,
          body: const {'value': 1},
        ),
      ]);

      // This device's own records: a private field and a private value on a
      // dance, which the shareable body leaves out; a deleted tag; dances
      // whose stored figures or tunes cannot be decoded, which are withheld.
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'cf-private',
          key: 'mine',
          label: 'Mine',
          type: CustomFieldType.text,
          shareable: false,
        ),
        at: _stamp,
      );
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 't1', name: 'Cited'),
        at: _stamp,
      );
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 't-gone', name: 'Gone'),
        at: _stamp,
      );
      await repositories.tags.delete(
        't-gone',
        at: _stamp.add(const Duration(minutes: 1)),
      );
      await repositories.dances.create(
        sampleDance(
          id: 'd1',
          authorIds: const ['c1'],
          tagIds: const ['t1'],
          customFields: [
            CustomFieldValue(fieldId: 'cf-shared', value: 1.5),
            CustomFieldValue(fieldId: 'cf-private', value: 'only here'),
          ],
        ),
      );
      await repositories.dances.create(sampleDance(id: 'd-figures'));
      await repositories.dances.create(sampleDance(id: 'd-tunes'));
      await repositories.ensureMigrated();
      await db.customStatement(
        'UPDATE dances SET figures_json = ? WHERE id = ?',
        ['[{"kind":', 'd-figures'],
      );
      await db.customStatement(
        'UPDATE dances SET tunes_json = ? WHERE id = ?',
        ['[1,2,3]', 'd-tunes'],
      );
      await repositories.settings.set('theme_mode', 'dark', at: _stamp);

      // Rows as an older build or a damaged file left them. Reading them back
      // through the archive decoder would clean them up — sanitise the text,
      // normalise the colour, clamp the choices — and so hash them differently
      // from the snapshot, which builds them straight from the row.
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(id: 'c-legacy', name: 'Legacy Caller'),
        at: _stamp,
      );
      await db.customStatement(
        'UPDATE choreographers SET notes = ? WHERE id = ?',
        ['a\u200Bb', 'c-legacy'],
      );
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 't-legacy', name: 'Translucent'),
        at: _stamp,
      );
      await db.customStatement('UPDATE tags SET color = ? WHERE id = ?', [
        0x00FF0000,
        't-legacy',
      ]);
      // ignore: unused_result
      await repositories.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'cf-legacy',
          key: 'era',
          label: 'Era',
          type: CustomFieldType.choice,
          choices: const ['a'],
        ),
        at: _stamp,
      );
      await db.customStatement(
        'UPDATE custom_field_defs SET choices_json = ? WHERE id = ?',
        [
          jsonEncode(['x' * 500, 'a', 'a']),
          'cf-legacy',
        ],
      );

      // A tombstone held back by the §6.8 referential guard: d1 still cites
      // t1, so the snapshot carries t1 as pending-live, not local.
      const t1 = (kind: SyncRecordKind.tag, recordId: 't1');
      final liveT1 = (await storage.snapshot()).local[t1]!.blob;
      final tombstone = SyncRecordBlob(
        kind: SyncRecordKind.tag,
        id: 't1',
        updatedAt: _stamp.add(const Duration(minutes: 2)),
        deletedAt: _stamp.add(const Duration(minutes: 2)),
        existenceAt: _stamp.add(const Duration(minutes: 2)),
        body: liveT1.body,
      );
      await repositories.syncLocal.upsertPendingDeletion(
        kind: SyncRecordKind.tag,
        recordId: 't1',
        tombstonedAt: tombstone.deletedAt!,
        tombstoneHash: SyncMergeCandidate.fromBlob(tombstone).wireHash,
        tombstoneBlob: encodeSyncRecordBlob(tombstone),
      );

      final snapshot = await storage.snapshot();
      final expected = {...snapshot.local, ...snapshot.pendingLive};

      // The fixture reaches what it claims to, so a parity failure cannot hide
      // behind a record that never made it into the snapshot.
      expect(
        {for (final address in expected.keys) address.kind},
        SyncRecordKind.values.toSet(),
        reason: 'every kind is compared',
      );
      expect(snapshot.pending, contains(t1));
      expect(snapshot.pendingLive[t1], isNotNull);
      expect(
        expected[(kind: SyncRecordKind.choreographer, recordId: 'c1')]!
            .blob
            .body['addedLater'],
        'kept',
      );
      expect(
        expected[(kind: SyncRecordKind.dance, recordId: 'd1')]!.blob.body
            .toString(),
        allOf(contains('cf-shared'), isNot(contains('cf-private'))),
      );

      final absent = {
        (kind: SyncRecordKind.dance, recordId: 'd-figures'),
        (kind: SyncRecordKind.dance, recordId: 'd-tunes'),
        (kind: SyncRecordKind.dance, recordId: 'no-such-dance'),
        (kind: SyncRecordKind.customFieldDef, recordId: 'cf-private'),
        (kind: SyncRecordKind.setting, recordId: 'sync_device_id'),
        (kind: SyncRecordKind.figureNote, recordId: 'no-such-figure'),
      };
      for (final address in absent) {
        expect(expected[address], isNull, reason: '$address');
      }

      final probe = {...expected.keys, ...absent};
      final current = await storage.currentCandidates(probe);
      for (final address in probe) {
        expect(
          current[address]?.wireHash,
          expected[address]?.wireHash,
          reason: '$address',
        );
      }
    });

    test('reads the records asked for, not the library', () async {
      final counter = _RowCounter();
      final countedDb = CompendiumDatabase(
        NativeDatabase.memory().interceptWith(counter),
      );
      addTearDown(countedDb.close);
      final counted = CompendiumRepositories(countedDb, contraTaxonomy);
      final countedStorage = CompendiumSyncStorage(counted);
      // ignore: unused_result
      await counted.tags.upsert(
        Tag(id: 't1', name: 'Touched'),
        at: _stamp,
      );
      const library = 40;
      for (var i = 0; i < library; i++) {
        await counted.dances.create(sampleDance(id: 'd$i', title: 'Dance $i'));
      }
      const touched = (kind: SyncRecordKind.tag, recordId: 't1');
      final hash = (await countedStorage.snapshot()).local[touched]!.wireHash;

      counter.rows = 0;
      final current = await countedStorage.currentCandidates({touched});

      expect(current[touched]!.wireHash, hash);
      // A whole-library read returns at least one row per dance; a read of
      // one tag returns a handful, whatever the library's size.
      expect(counter.rows, lessThan(library ~/ 4));
    });

    test('a local edit after the merge snapshot is refused as a concurrent '
        'change, and the rest of the batch applies', () async {
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 't1', name: 'One'),
        at: _stamp,
      );
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 't2', name: 'Two'),
        at: _stamp,
      );
      const t1 = (kind: SyncRecordKind.tag, recordId: 't1');
      const t2 = (kind: SyncRecordKind.tag, recordId: 't2');
      final merged = (await storage.snapshot()).local;

      // The user renames t1 after the coordinator merged against its old copy.
      // ignore: unused_result
      await repositories.tags.upsert(
        Tag(id: 't1', name: 'Renamed here'),
        at: _stamp.add(const Duration(minutes: 1)),
      );

      SyncMergeCandidate inbound(String id, String name) => SyncMergeCandidate(
        blob: syncRecordBlobForEntity(
          SyncRecordKind.tag,
          Tag(id: id, name: name),
          updatedAt: _stamp.add(const Duration(minutes: 2)),
          existenceAt: _stamp,
        )!,
      );
      final result = await const SyncApplyEngine().apply(
        candidates: [inbound('t1', 'Peer one'), inbound('t2', 'Peer two')],
        storage: storage,
        expectedWireHashes: {
          t1: merged[t1]!.wireHash,
          t2: merged[t2]!.wireHash,
        },
      );

      expect(result.applied, [t2]);
      expect(
        [for (final report in result.reports) (report.code, report.recordId)],
        [(SyncReportCode.concurrentLocalChange, 't1')],
      );
      expect((await repositories.tags.getById('t1'))!.name, 'Renamed here');
      expect((await repositories.tags.getById('t2'))!.name, 'Peer two');
    });
  });

  test('the engine asks only for the guarded addresses', () async {
    final storage = _MapStorage({
      _a: {'v': 1},
      _b: {'v': 1},
      _c: {'v': 1},
    });
    SyncMergeCandidate candidate(SyncRecordAddress address) =>
        SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: address.kind,
            id: address.recordId,
            updatedAt: _stamp,
            deletedAt: null,
            existenceAt: _stamp,
            body: {'id': address.recordId, 'name': address.recordId},
          ),
        );
    final unchanged = (await storage.currentCandidates({_a}))[_a]!.wireHash;
    storage.requested.clear();

    final result = await const SyncApplyEngine().apply(
      candidates: [candidate(_a), candidate(_b), candidate(_c)],
      storage: storage,
      // _b's expected hash is stale: the record changed after the merge.
      expectedWireHashes: {_a: unchanged, _b: 'stale'},
    );

    expect(storage.requested, [
      {_a, _b},
    ]);
    expect(result.applied, unorderedEquals([_a, _c]));
    expect(
      [for (final report in result.reports) (report.code, report.recordId)],
      [(SyncReportCode.concurrentLocalChange, _b.recordId)],
    );
  });

  test('an app write during the guard waits for the apply instead of failing '
      'it', () async {
    // Two connections to one file, as in use: the sync worker's and the
    // app's. The app write is issued while the guard is reading, the point at
    // which a deferred `BEGIN` has taken a read snapshot but no write lock. Had
    // it committed there, the apply's first write would fail with
    // SQLITE_BUSY_SNAPSHOT (517), which no busy timeout retries, and the whole
    // pass would throw. drift opens a native transaction with
    // `BEGIN IMMEDIATE`, so the app write waits for the commit instead; this
    // pins that, because the guard's design depends on it.
    final warned = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = warned,
    );
    final dir = await Directory.systemTemp.createTemp('sync_apply_guard');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/compendium.sqlite');
    final workerDb = CompendiumDatabase(
      NativeDatabase(file, setup: applyCompendiumSqliteSetup),
    );
    addTearDown(workerDb.close);
    final worker = CompendiumRepositories(workerDb, contraTaxonomy);
    // ignore: unused_result
    await worker.tags.upsert(
      Tag(id: 't1', name: 'One'),
      at: _stamp,
    );
    // In the background, as the app's connection is: a busy wait on this
    // isolate would also stall the transaction it is waiting for.
    final appDb = CompendiumDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: applyCompendiumSqliteSetup,
      ),
    );
    addTearDown(appDb.close);
    final app = CompendiumRepositories(appDb, contraTaxonomy);
    expect((await app.tags.getById('t1'))!.name, 'One');

    final workerStorage = CompendiumSyncStorage(worker);
    const t1 = (kind: SyncRecordKind.tag, recordId: 't1');
    final merged = (await workerStorage.snapshot()).local[t1]!.wireHash;

    Future<void>? appWrite;
    var appWriteDone = false;
    final storage = _GuardHookStorage(workerStorage, () async {
      // Deterministic, whatever the machine's speed: a third connection that
      // will not wait finds the write lock already taken. Under a deferred
      // `BEGIN` nothing has written yet, so this write would succeed.
      final probe = sqlite3.open(file.path);
      try {
        expect(
          () => probe.execute(
            "UPDATE tags SET name = 'probe' WHERE id = 'no-such-tag'",
          ),
          throwsA(isA<SqliteException>()),
          reason: 'the apply transaction does not hold the write lock',
        );
      } finally {
        probe.close();
      }
      // ignore: unused_result
      appWrite = app.tags
          .upsert(
            Tag(id: 't1', name: 'Edited in the app'),
            at: _stamp.add(const Duration(minutes: 5)),
          )
          .then((_) => appWriteDone = true);
      // Long enough for the app write to commit, had it not been blocked.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        appWriteDone,
        isFalse,
        reason: 'the app write committed inside the apply transaction',
      );
    });

    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate(
          blob: syncRecordBlobForEntity(
            SyncRecordKind.tag,
            Tag(id: 't1', name: 'From the peer'),
            updatedAt: _stamp.add(const Duration(minutes: 1)),
            existenceAt: _stamp,
          )!,
        ),
      ],
      storage: storage,
      expectedWireHashes: {t1: merged},
    );

    expect(result.reports, isEmpty);
    expect(result.applied, [t1]);
    await appWrite;
    // The app's edit landed after the apply and is what the device now holds.
    expect((await worker.tags.getById('t1'))!.name, 'Edited in the app');
  });
}

const _a = (kind: SyncRecordKind.tag, recordId: 'a');
const _b = (kind: SyncRecordKind.tag, recordId: 'b');
const _c = (kind: SyncRecordKind.tag, recordId: 'c');

/// An in-memory store that records which addresses the guard asks for.
final class _MapStorage implements SyncApplyConcurrencyStorage {
  _MapStorage(this.rows);

  final Map<SyncRecordAddress, Map<String, Object?>> rows;
  final requested = <Set<SyncRecordAddress>>[];

  @override
  Future<T> transaction<T>(Future<T> Function() action) => action();

  @override
  Future<Map<String, Object?>?> read(SyncRecordAddress address) async =>
      rows[address];

  @override
  Future<void> write(SyncApplyRecord record) async {
    rows[record.address] = record.body;
  }

  @override
  Future<void> rebuildDerivedIndexes() async {}

  @override
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> currentCandidates(
    Set<SyncRecordAddress> addresses,
  ) async {
    requested.add(Set.of(addresses));
    return {
      for (final address in addresses)
        address: SyncMergeCandidate(
          blob: SyncRecordBlob(
            kind: address.kind,
            id: address.recordId,
            updatedAt: _stamp,
            deletedAt: null,
            existenceAt: _stamp,
            body: {'id': address.recordId, ...?rows[address]},
          ),
        ),
    };
  }
}

/// Delegates to the real storage, running [onGuardRead] once the guard has
/// read and before the apply writes anything.
final class _GuardHookStorage
    implements
        SyncApplyReconciliationStorage,
        SyncApplyConcurrencyStorage,
        SyncApplyRestorableStorage {
  _GuardHookStorage(this._delegate, this.onGuardRead);

  final CompendiumSyncStorage _delegate;
  final Future<void> Function() onGuardRead;

  @override
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> currentCandidates(
    Set<SyncRecordAddress> addresses,
  ) async {
    final current = await _delegate.currentCandidates(addresses);
    await onGuardRead();
    return current;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      _delegate.transaction(action);

  @override
  Future<Map<String, Object?>?> read(SyncRecordAddress address) =>
      _delegate.read(address);

  @override
  Future<void> write(SyncApplyRecord record) => _delegate.write(record);

  @override
  Future<void> rebuildDerivedIndexes() => _delegate.rebuildDerivedIndexes();

  @override
  Future<SyncReport?> validateInboundReferences(
    SyncApplyRecord record, {
    Set<SyncRecordAddress> inboundLiveAddresses = const {},
    Set<SyncRecordAddress> inboundAddresses = const {},
    Map<SyncRecordAddress, SyncApplyRecord> inboundRecords = const {},
  }) => _delegate.validateInboundReferences(
    record,
    inboundLiveAddresses: inboundLiveAddresses,
    inboundAddresses: inboundAddresses,
    inboundRecords: inboundRecords,
  );

  @override
  Future<SyncReport?> writeWithReport(SyncApplyRecord record) =>
      _delegate.writeWithReport(record);

  @override
  Future<SyncReport?> writeParentWithReport(SyncApplyRecord record) =>
      _delegate.writeParentWithReport(record);

  @override
  Future<SyncReport?> writeJoinsWithReport(SyncApplyRecord record) =>
      _delegate.writeJoinsWithReport(record);

  @override
  Future<SyncApplyPreparation> reconcileInbound(
    List<SyncMergeCandidate> candidates, {
    Map<SyncRecordAddress, String?>? expectedWireHashes,
  }) => _delegate.reconcileInbound(
    candidates,
    expectedWireHashes: expectedWireHashes,
  );

  @override
  Future<void> setInboundTombstoneContext(
    Set<SyncRecordAddress> tombstonedAddresses,
  ) => _delegate.setInboundTombstoneContext(tombstonedAddresses);

  @override
  Future<void> clearReconciliationContext() =>
      _delegate.clearReconciliationContext();

  @override
  Future<Object?> capturePreImage(SyncRecordAddress address) =>
      _delegate.capturePreImage(address);

  @override
  Future<void> restorePreImage(SyncRecordAddress address, Object? preImage) =>
      _delegate.restorePreImage(address, preImage);
}
