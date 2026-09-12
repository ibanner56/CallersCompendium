import 'dart:async';
import 'dart:convert';

import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unconfigured triggers make no transport calls', () async {
    final transport = _FakeTransport();
    final coordinator = SyncCoordinator(
      syncId: null,
      deviceId: 'device-a',
      store: _FakeStore(),
      transport: transport,
    );

    final results = await Future.wait([
      coordinator.onAppStart(),
      coordinator.onDebouncedChange(),
      coordinator.syncNow(),
    ]);

    expect(
      results.map((result) => result.status),
      everyElement(SyncPassStatus.skippedUnconfigured),
    );
    expect(transport.calls, isEmpty);
  });

  test('an isolated pass result still emits replacement once', () async {
    final events = <SyncReplacementRequiredEvent>[];
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(),
      transport: _FakeTransport(),
      passOperation: () async =>
          const SyncPassResult(SyncPassStatus.replacementRequired),
    );
    final subscription = coordinator.replacementRequired.listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      await coordinator.dispose();
    });

    final result = await coordinator.syncNow();
    await Future<void>.delayed(Duration.zero);

    expect(result.status, SyncPassStatus.replacementRequired);
    expect(events, hasLength(1));
    expect(
      (await coordinator.syncNow()).status,
      SyncPassStatus.replacementRequired,
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
  });

  test('replacement is coalesced and confirmation posts once', () async {
    final transport = _FakeTransport(
      missingKind: SyncStoreMissingKind.replacementRequired,
    );
    final events = <SyncReplacementRequiredEvent>[];
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(previouslyUsed: true),
      transport: transport,
    );
    final subscription = coordinator.replacementRequired.listen(events.add);
    addTearDown(subscription.cancel);

    await coordinator.onAppStart();
    await coordinator.syncNow();
    expect(events, hasLength(1));
    expect(transport.manifestCalls, 0);
    expect(transport.blobCalls, 0);
    expect(transport.createCalls, 0);

    final first = await coordinator.confirmReplacement();
    final second = await coordinator.confirmReplacement();
    expect(first.status, SyncPassStatus.freshAttachRequired);
    expect(second.status, SyncPassStatus.freshAttachRequired);
    expect(transport.createCalls, 1);
    expect(transport.storeCalls, 2);
    expect(transport.postMissingCalls, 0);
    expect(transport.requestLog, ['store', 'create', 'store']);
  });

  test('declining replacement keeps configured sync paused', () async {
    final transport = _FakeTransport(
      missingKind: SyncStoreMissingKind.replacementRequired,
    );
    final store = _FakeStore(previouslyUsed: true);
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: transport,
    );

    await coordinator.onAppStart();
    coordinator.declineReplacement();

    final background = await coordinator.onDebouncedChange();
    expect(background.status, SyncPassStatus.paused);
    expect(transport.storeCalls, 1);

    final reconsidered = await coordinator.syncNow();
    expect(reconsidered.status, SyncPassStatus.completed);
    expect(transport.storeCalls, 2);
    expect(store.publishedRecords, isEmpty);
    expect(store.baselineAdvances, 1);
  });

  test('holds one pass and queues one follow-up for all triggers', () async {
    final firstStoreRead = Completer<void>();
    final transport = _FakeTransport(storeReadGate: firstStoreRead);
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(),
      transport: transport,
    );

    final first = coordinator.onAppStart();
    await transport.firstStoreStarted.future;
    final queued = coordinator.onDebouncedChange();
    final coalesced = coordinator.syncNow();
    expect(identical(queued, coalesced), isTrue);
    expect(transport.storeCalls, 1);

    firstStoreRead.complete();
    await first;
    await queued;
    expect(transport.storeCalls, 2);
    expect(transport.manifestPuts, 2);
  });

  test(
    'the queued pass publishes the newer snapshot, not the stale one',
    () async {
      final firstStoreRead = Completer<void>();
      final first = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'first'),
      );
      final second = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'second', seconds: 1),
      );
      final store = _FakeStore(
        snapshotBuilder: (snapshotNumber) => SyncCoordinatorSnapshot(
          epoch: null,
          previouslyUsed: false,
          local: {first.address: snapshotNumber == 1 ? first : second},
          baseline: const {},
        ),
      );
      final transport = _FakeTransport(storeReadGate: firstStoreRead);
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final initial = coordinator.onAppStart();
      await transport.firstStoreStarted.future;
      final queued = coordinator.onDebouncedChange();
      final manual = coordinator.syncNow();
      expect(identical(queued, manual), isTrue);

      firstStoreRead.complete();
      await initial;
      await queued;

      final lastManifest = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.last),
      );
      expect(
        lastManifest.records[SyncRecordKind.setting]!['custom_dialects'],
        second.wireHash,
      );
      expect(store.snapshotCalls, 2);
    },
  );

  test(
    'marks published records before a failed manifest publication',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final store = _FakeStore(
        local: {candidate.address: candidate},
        lifecycle: <String>[],
      );
      final transport = _FakeTransport(
        putManifestStatus: 500,
        onManifestPut: (_) {
          expect(store.lifecycle, contains('markPublished'));
        },
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.failed);
      expect(store.publishedRecords, [candidate.address]);
      expect(store.baselineAdvances, 0);
    },
  );

  test(
    'publishes the post-apply local snapshot after storage repair',
    () async {
      final local = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final remote = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'remote', seconds: 1),
      );
      final repaired = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'repaired', seconds: 1),
      );
      final store = _FakeStore(
        snapshotBuilder: (snapshotNumber) => SyncCoordinatorSnapshot(
          epoch: null,
          previouslyUsed: false,
          local: {local.address: snapshotNumber == 1 ? local : repaired},
          baseline: const {},
        ),
      );
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.setting: {remote.blob.id: remote.wireHash},
          },
        ),
        blobResponses: {
          remote.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(remote.blob)),
          ),
        },
        missingResponses: const [
          <String>[],
          <String>['placeholder'],
        ],
      );
      transport.missingResponses[1] = [repaired.wireHash];
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      final manifest = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.single),
      );
      expect(
        manifest.records[SyncRecordKind.setting]!['custom_dialects'],
        repaired.wireHash,
      );
      expect(transport.postMissingCalls, 2);
      expect(transport.putBlobHashes, [repaired.wireHash]);
    },
  );

  test(
    'chunks initial and post-apply missing-blob negotiation at the protocol limit',
    () async {
      final initial = <SyncRecordAddress, SyncMergeCandidate?>{};
      for (var index = 0; index < 10000; index++) {
        final candidate = SyncMergeCandidate.fromBlob(
          _tag('tag-$index', 'local'),
        );
        initial[candidate.address] = candidate;
      }
      final remote = SyncMergeCandidate.fromBlob(
        _tag('tag-remote', 'remote', seconds: 1),
      );
      final finalLocal = {...initial, remote.address: remote};
      final store = _FakeStore(
        snapshotBuilder: (snapshotNumber) => SyncCoordinatorSnapshot(
          epoch: null,
          previouslyUsed: false,
          local: snapshotNumber == 1 ? initial : finalLocal,
          baseline: const {},
        ),
      );
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.tag: {remote.blob.id: remote.wireHash},
          },
        ),
        blobResponses: {
          remote.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(remote.blob)),
          ),
        },
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(transport.postMissingBatches.map((batch) => batch.length), [
        10000,
        10000,
        1,
      ]);
    },
  );

  test('a missing peer blob is reported and remains retryable', () async {
    final hash = _hash('a');
    final address = (kind: SyncRecordKind.setting, recordId: 'custom_dialects');
    final store = _FakeStore(
      baseline: {
        address: SyncBaselineEntry(
          kind: address.kind,
          recordId: address.recordId,
          wireHash: hash,
        ),
      },
    );
    final transport = _FakeTransport(
      devices: ['peer'],
      peerManifest: _manifest(
        deviceId: 'peer',
        records: {
          SyncRecordKind.setting: {address.recordId: hash},
        },
      ),
      blobResponses: {hash: _FakeTransport.response(404)},
    );
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: transport,
    );

    final result = await coordinator.syncNow();

    expect(result.reports.single.code, SyncReportCode.unresolvedBlob);
    expect(store.advancedEntries, isEmpty);
    expect(store.droppedRecords, isEmpty);
  });

  test('a wrong-envelope blob is reported and remains unapplied', () async {
    final wrong = SyncMergeCandidate.fromBlob(
      _setting('default_program_band', 'peer'),
    );
    final address = (kind: SyncRecordKind.setting, recordId: 'custom_dialects');
    final store = _FakeStore(
      baseline: {
        address: SyncBaselineEntry(
          kind: address.kind,
          recordId: address.recordId,
          wireHash: wrong.wireHash,
        ),
      },
    );
    final transport = _FakeTransport(
      devices: ['peer'],
      peerManifest: _manifest(
        deviceId: 'peer',
        records: {
          SyncRecordKind.setting: {address.recordId: wrong.wireHash},
        },
      ),
      blobResponses: {
        wrong.wireHash: _FakeTransport.response(
          200,
          body: utf8.encode(encodeSyncRecordBlob(wrong.blob)),
        ),
      },
    );
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: transport,
    );

    final result = await coordinator.syncNow();

    expect(result.reports.single.code, SyncReportCode.blobIdentityMismatch);
    expect(store.writes, isEmpty);
    expect(store.advancedEntries, isEmpty);
  });
}

final class _FakeStore implements SyncCoordinatorStore {
  _FakeStore({
    this.previouslyUsed = false,
    Map<SyncRecordAddress, SyncMergeCandidate?>? local,
    Map<SyncRecordAddress, SyncBaselineEntry>? baseline,
    this.snapshotBuilder,
    List<String>? lifecycle,
  }) : local = local ?? const {},
       baseline = baseline ?? const {},
       lifecycle = lifecycle ?? <String>[];

  final bool previouslyUsed;
  final Map<SyncRecordAddress, SyncMergeCandidate?> local;
  final Map<SyncRecordAddress, SyncBaselineEntry> baseline;
  final SyncCoordinatorSnapshot Function(int snapshotNumber)? snapshotBuilder;
  final List<String> lifecycle;
  final List<SyncRecordAddress> publishedRecords = [];
  final List<SyncRecordAddress> advancedEntries = [];
  final List<SyncRecordAddress> droppedRecords = [];
  final List<SyncApplyRecord> writes = [];
  int snapshotCalls = 0;
  int baselineAdvances = 0;

  @override
  Future<SyncCoordinatorSnapshot> snapshot() async {
    snapshotCalls++;
    return snapshotBuilder?.call(snapshotCalls) ??
        SyncCoordinatorSnapshot(
          epoch: null,
          previouslyUsed: previouslyUsed,
          local: local,
          baseline: baseline,
        );
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    lifecycle.add('transaction');
    return action();
  }

  @override
  Future<void> markSyncUsed(String syncId) async {}

  @override
  Future<Map<String, Object?>?> read(SyncRecordAddress address) async {
    for (final write in writes.reversed) {
      if (write.address == address) return write.body;
    }
    return null;
  }

  @override
  Future<void> write(SyncApplyRecord record) async {
    writes.add(record);
  }

  @override
  Future<void> rebuildDerivedIndexes() async {}

  @override
  Future<void> markPublished(Iterable<SyncRecordAddress> records) async {
    lifecycle.add('markPublished');
    publishedRecords.addAll(records);
  }

  @override
  Future<void> advanceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
    required Iterable<SyncRecordAddress> drop,
  }) async {
    baselineAdvances++;
    advancedEntries.addAll(
      entries.map((entry) => (kind: entry.kind, recordId: entry.recordId)),
    );
    droppedRecords.addAll(drop);
  }
}

final class _FakeTransport implements SyncCoordinatorTransport {
  _FakeTransport({
    this.missingKind,
    this._storeReadGate,
    this.devices = const [],
    this.peerManifest,
    this.blobResponses = const {},
    List<List<String>>? missingResponses,
    this.putManifestStatus = 200,
    this.onManifestPut,
  }) : missingResponses = [
         for (final response in missingResponses ?? const <List<String>>[[]])
           [...response],
       ];

  final SyncStoreMissingKind? missingKind;
  final Completer<void>? _storeReadGate;
  final List<String> devices;
  final SyncManifest? peerManifest;
  final Map<String, SyncHttpResponse> blobResponses;
  final List<List<String>> missingResponses;
  final int putManifestStatus;
  final void Function(List<int> body)? onManifestPut;
  final firstStoreStarted = Completer<void>();
  final requestLog = <String>[];
  final manifestBodies = <List<int>>[];
  int storeCalls = 0;
  int createCalls = 0;
  int manifestCalls = 0;
  int manifestPuts = 0;
  int blobCalls = 0;
  int postMissingCalls = 0;
  final putBlobHashes = <String>[];
  final postMissingBatches = <List<String>>[];

  List<String> get calls => [
    if (storeCalls > 0) 'store',
    if (createCalls > 0) 'create',
    if (manifestCalls > 0) 'manifest',
    if (manifestPuts > 0) 'manifest-put',
    if (blobCalls > 0) 'blob',
  ];

  @override
  Future<SyncStoreResult> getStore({required bool previouslyUsed}) async {
    storeCalls++;
    requestLog.add('store');
    if (!firstStoreStarted.isCompleted) firstStoreStarted.complete();
    if (_storeReadGate != null) await _storeReadGate.future;
    final response = _response(
      missingKind == null || storeCalls > 1 ? 200 : 404,
      body: jsonEncode({'epoch': 'epoch-1', 'devices': devices}),
    );
    return SyncStoreResult(
      response: response,
      missingKind: storeCalls == 1 ? missingKind : null,
    );
  }

  @override
  Future<SyncHttpResponse> createStore() async {
    createCalls++;
    requestLog.add('create');
    return _response(201);
  }

  @override
  Future<SyncHttpResponse> getManifest(String deviceId, {String? etag}) async {
    manifestCalls++;
    requestLog.add('manifest');
    return _response(
      200,
      body: peerManifest == null
          ? null
          : utf8.decode(encodeSyncManifestUtf8(peerManifest!)),
    );
  }

  @override
  Future<SyncHttpResponse> putManifest(String deviceId, List<int> body) async {
    manifestPuts++;
    requestLog.add('manifest-put');
    manifestBodies.add(body);
    onManifestPut?.call(body);
    return _response(putManifestStatus);
  }

  @override
  Future<SyncHttpResponse> postMissing(Iterable<String> hashes) async {
    postMissingBatches.add(hashes.toList(growable: false));
    postMissingCalls++;
    requestLog.add('missing');
    final response = missingResponses.length >= postMissingCalls
        ? missingResponses[postMissingCalls - 1]
        : const <String>[];
    return _response(200, body: jsonEncode({'missing': response}));
  }

  @override
  Future<SyncHttpResponse> getBlob(String hash) async {
    blobCalls++;
    requestLog.add('blob');
    return blobResponses[hash] ?? _response(404);
  }

  @override
  Future<SyncHttpResponse> putBlob(String hash, List<int> body) async {
    putBlobHashes.add(hash);
    return _response(201);
  }

  static SyncHttpResponse response(int status, {List<int>? body}) =>
      _response(status, body: body == null ? null : utf8.decode(body));

  static SyncHttpResponse _response(int status, {String? body}) =>
      SyncHttpResponse(
        statusCode: status,
        kind: switch (status) {
          200 => SyncResponseKind.success,
          201 => SyncResponseKind.created,
          404 => SyncResponseKind.notFound,
          500 => SyncResponseKind.serverError,
          _ => SyncResponseKind.unexpectedStatus,
        },
        headers: const {},
        body: body == null ? const [] : utf8.encode(body),
      );
}

SyncManifest _manifest({
  required String deviceId,
  required Map<SyncRecordKind, Map<String, String>> records,
}) => SyncManifest(
  deviceId: deviceId,
  epoch: 'epoch-1',
  writtenAt: DateTime.utc(2026, 7, 15, 12),
  records: records,
);

SyncRecordBlob _setting(String id, String value, {int seconds = 0}) {
  final stamp = DateTime.utc(2026, 7, 15, 12).add(Duration(seconds: seconds));
  return SyncRecordBlob(
    kind: SyncRecordKind.setting,
    id: id,
    updatedAt: stamp,
    deletedAt: null,
    existenceAt: stamp,
    body: {'value': value},
  );
}

SyncRecordBlob _tag(String id, String name, {int seconds = 0}) {
  final stamp = DateTime.utc(2026, 7, 15, 12).add(Duration(seconds: seconds));
  return SyncRecordBlob(
    kind: SyncRecordKind.tag,
    id: id,
    updatedAt: stamp,
    deletedAt: null,
    existenceAt: stamp,
    body: {'id': id, 'name': name},
  );
}

String _hash(String character) => List.filled(64, character).join();
