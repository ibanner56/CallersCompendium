import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart'
    show
        ApplyInterceptor,
        QueryExecutor,
        QueryExecutorUser,
        QueryInterceptor,
        TransactionExecutor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

void main() {
  test(
    'coordinator store dispatches inbound reconciliation before apply',
    () async {
      final repositories = openTestRepositories();
      final store = CompendiumSyncCoordinatorStore(repositories);
      final stamp = DateTime.utc(2025, 1, 2, 12);
      // ignore: unused_result
      await repositories.choreographers.upsert(
        Choreographer(id: 'z-local', name: 'Shared author'),
        at: stamp,
      );
      final inbound = Choreographer(id: 'a-peer', name: 'Shared author');

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate(
            blob: SyncRecordBlob(
              kind: SyncRecordKind.choreographer,
              id: inbound.id,
              updatedAt: stamp.add(const Duration(minutes: 1)),
              deletedAt: null,
              existenceAt: stamp.add(const Duration(minutes: 1)),
              body: syncBodyForEntity(SyncRecordKind.choreographer, inbound),
            ),
          ),
        ],
        storage: store,
      );

      expect(result.reports, isEmpty);
      expect(
        await repositories.syncLocal.resolveAlias(
          kind: SyncRecordKind.choreographer,
          recordId: 'z-local',
        ),
        'a-peer',
      );
      expect(await repositories.choreographers.getById('z-local'), isNull);
      expect(await repositories.choreographers.getById('a-peer'), isNotNull);
    },
  );

  test('normalizes peer aliases before baseline observation', () async {
    final local = SyncMergeCandidate.fromBlob(_tag('canonical', 'Shared tag'));
    final remote = SyncMergeCandidate.fromBlob(
      _tag('legacy', 'Shared tag', seconds: 1),
    );
    final canonical = (kind: SyncRecordKind.tag, recordId: 'canonical');
    final legacy = (kind: SyncRecordKind.tag, recordId: 'legacy');
    final store = _FakeStore(
      aliases: {legacy: canonical},
      snapshotBuilder: (snapshotNumber) => SyncCoordinatorSnapshot(
        epoch: 'epoch-1',
        previouslyUsed: false,
        local: {canonical: snapshotNumber == 1 ? local : remote},
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
    expect(store.advancedEntries, [canonical]);
  });

  test(
    'rejects a future peer record once while preserving the batch',
    () async {
      final now = DateTime.utc(2026, 7, 15, 12);
      final future = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        updatedAt: now.add(const Duration(hours: 25)),
        deletedAt: null,
        existenceAt: now,
        body: const {'value': 'future'},
      );
      final valid = _setting('default_program_band', 'valid', seconds: 1);
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.setting: {
              future.id: SyncMergeCandidate.fromBlob(future).wireHash,
              valid.id: SyncMergeCandidate.fromBlob(valid).wireHash,
            },
          },
        ),
        blobResponses: {
          SyncMergeCandidate.fromBlob(future).wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(future)),
          ),
          SyncMergeCandidate.fromBlob(valid).wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(valid)),
          ),
        },
      );
      final store = _FakeStore();
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
        now: () => now,
      );
      addTearDown(coordinator.dispose);

      final first = await coordinator.syncNow();
      final second = await coordinator.syncNow();

      expect(
        first.reports.where((r) => r.code == SyncReportCode.malformedRecord),
        [isNotNull],
      );
      expect(
        second.reports.where((r) => r.code == SyncReportCode.malformedRecord),
        isEmpty,
      );
      expect(store.writes.map((write) => write.address), [
        (kind: valid.kind, recordId: valid.id),
        (kind: valid.kind, recordId: valid.id),
      ]);
      expect(
        store.writes.any(
          (write) => write.address == (kind: future.kind, recordId: future.id),
        ),
        isFalse,
      );
    },
  );

  test('clock-suspect requires observed peer values', () async {
    final now = DateTime.utc(2026, 7, 15, 12);
    final future = SyncRecordBlob(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      updatedAt: now.add(const Duration(hours: 25)),
      deletedAt: null,
      existenceAt: now.add(const Duration(hours: 25)),
      body: const {'value': 'future'},
    );
    final futureCandidate = SyncMergeCandidate.fromBlob(future);
    final observedCoordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(),
      transport: _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.setting: {future.id: futureCandidate.wireHash},
          },
        ),
        blobResponses: {
          futureCandidate.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(future)),
          ),
        },
      ),
      now: () => now,
    );
    addTearDown(observedCoordinator.dispose);

    final observed = await observedCoordinator.syncNow();

    expect(
      observed.reports.map((report) => report.code),
      contains(SyncReportCode.clockSuspect),
    );

    final soloCoordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(),
      transport: _FakeTransport(),
      now: () => now,
    );
    addTearDown(soloCoordinator.dispose);

    final solo = await soloCoordinator.syncNow();

    expect(
      solo.reports.map((report) => report.code),
      isNot(contains(SyncReportCode.clockSuspect)),
    );
  });

  test(
    'repairs a quarantined local record from a matching peer copy',
    () async {
      final now = DateTime.utc(2026, 7, 15, 12);
      final local = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: SyncRecordKind.setting,
          id: 'custom_dialects',
          updatedAt: now.add(const Duration(hours: 25)),
          deletedAt: null,
          existenceAt: now,
          body: const {'value': 'local'},
        ),
      );
      final peer = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: SyncRecordKind.setting,
          id: 'custom_dialects',
          updatedAt: now.add(const Duration(hours: 1)),
          deletedAt: null,
          existenceAt: now,
          body: const {'value': 'local'},
        ),
      );
      final store = _FakeStore(
        local: {local.address: local},
        snapshotBuilder: (snapshotNumber) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: {local.address: snapshotNumber == 1 ? local : peer},
          publication: {local.address: snapshotNumber == 1 ? local : peer},
          baseline: {
            local.address: SyncBaselineEntry(
              kind: local.address.kind,
              recordId: local.address.recordId,
              wireHash: local.wireHash,
              bodyHash: local.bodyHash,
            ),
          },
        ),
      );
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.setting: {peer.blob.id: peer.wireHash},
          },
        ),
        blobResponses: {
          peer.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(peer.blob)),
          ),
        },
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
        now: () => now,
      );
      addTearDown(coordinator.dispose);

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(store.writes, hasLength(1));
      expect(store.writes.single.address, local.address);
      expect(store.writes.single.updatedAt, peer.updatedAt);
      final published = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.single),
      );
      expect(
        published.records[SyncRecordKind.setting]?[local.blob.id],
        peer.wireHash,
      );
    },
  );

  test('fresh-attaches before repairing a pre-W9 dance baseline', () async {
    final now = DateTime.utc(2026, 7, 15, 12);
    final local = SyncMergeCandidate.fromBlob(
      _dance('dance-1', updatedAt: now.add(const Duration(hours: 25))),
    );
    final peer = SyncMergeCandidate.fromBlob(
      _dance('dance-1', updatedAt: now.add(const Duration(hours: 1))),
    );
    late final _FakeStore store;
    store = _FakeStore(
      local: {local.address: local},
      baseline: {
        local.address: SyncBaselineEntry(
          kind: local.address.kind,
          recordId: local.address.recordId,
          wireHash: local.wireHash,
          bodyHash: local.bodyHash,
          bodyHashVersion: SyncBaselineBodyHashVersion.legacyFullBody,
        ),
      },
      snapshotBuilder: (snapshotNumber) {
        final current = snapshotNumber >= 3 ? peer : local;
        return SyncCoordinatorSnapshot(
          epoch: snapshotNumber == 1 ? 'epoch-1' : null,
          previouslyUsed: false,
          local: {local.address: current},
          publication: {local.address: current},
          baseline: store.baseline,
        );
      },
    );
    final transport = _FakeTransport(
      devices: ['peer'],
      peerManifest: _manifest(
        deviceId: 'peer',
        records: {
          SyncRecordKind.dance: {peer.blob.id: peer.wireHash},
        },
      ),
      blobResponses: {
        peer.wireHash: _FakeTransport.response(
          200,
          body: utf8.encode(encodeSyncRecordBlob(peer.blob)),
        ),
      },
    );
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: transport,
      now: () => now,
    );
    addTearDown(coordinator.dispose);

    final result = await coordinator.syncNow();

    expect(result.status, SyncPassStatus.completed);
    expect(store.epochStateClears, 1);
    expect(store.writes, hasLength(1));
    expect(store.writes.single.address, local.address);
    expect(store.writes.single.updatedAt, peer.updatedAt);
    expect(store.baselineReplacements, 1);
  });

  test(
    'withholds quarantined publication and its enforced dependents',
    () async {
      final now = DateTime.utc(2026, 7, 15, 12);
      final root = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: SyncRecordKind.choreographer,
          id: 'author-1',
          updatedAt: now.add(const Duration(hours: 25)),
          deletedAt: null,
          existenceAt: now,
          body: const {'id': 'author-1', 'name': 'Author'},
        ),
      );
      final dependent = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: SyncRecordKind.dance,
          id: 'dance-1',
          updatedAt: now,
          deletedAt: null,
          existenceAt: now,
          body: const {
            'id': 'dance-1',
            'title': 'Dance',
            'authorIds': ['author-1'],
          },
        ),
      );
      final fallbackHash = _hash('a');
      final store = _FakeStore(
        snapshotBuilder: (_) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: {root.address: root, dependent.address: dependent},
          publication: {root.address: root, dependent.address: dependent},
          baseline: {
            root.address: SyncBaselineEntry(
              kind: root.address.kind,
              recordId: root.address.recordId,
              wireHash: fallbackHash,
            ),
          },
        ),
      );
      final transport = _FakeTransport();
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
        now: () => now,
      );
      addTearDown(coordinator.dispose);

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(transport.putBlobHashes, isEmpty);
      final published = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.single),
      );
      expect(
        published.records[SyncRecordKind.choreographer]?[root.blob.id],
        fallbackHash,
      );
      expect(
        published.records[SyncRecordKind.dance]?[dependent.blob.id],
        isNull,
      );
    },
  );

  test(
    'reports an unreflected publication on the third observed pass',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final store = _FakeStore(
        local: {candidate.address: candidate},
        snapshotBuilder: (_) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: {candidate.address: candidate},
          publication: {candidate.address: candidate},
          baseline: const {},
        ),
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: _FakeTransport(
          devices: ['peer'],
          peerManifest: _manifest(deviceId: 'peer', records: const {}),
        ),
        now: () => DateTime.utc(2026, 7, 15, 12),
      );
      addTearDown(coordinator.dispose);

      final first = await coordinator.syncNow();
      final second = await coordinator.syncNow();
      final third = await coordinator.syncNow();

      expect(
        first.reports.map((report) => report.code),
        isNot(contains(SyncReportCode.unreflectedPublication)),
      );
      expect(
        second.reports.map((report) => report.code),
        isNot(contains(SyncReportCode.unreflectedPublication)),
      );
      expect(
        third.reports.map((report) => report.code),
        contains(SyncReportCode.unreflectedPublication),
      );
    },
  );

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
      passOperation: ({SyncStoreResult? initialStore}) async =>
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
    final store = _FakeStore(
      previouslyUsed: true,
      snapshotEpochs: [null, null, null, 'epoch-1'],
    );
    final events = <SyncReplacementRequiredEvent>[];
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
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

    final firstFuture = coordinator.confirmReplacement();
    final secondFuture = coordinator.confirmReplacement();
    final first = await firstFuture;
    final second = await secondFuture;
    expect(first.status, SyncPassStatus.completed);
    expect(second.status, SyncPassStatus.completed);
    expect(transport.createCalls, 1);
    expect(transport.storeCalls, 3);
    expect(transport.postMissingCalls, 0);
    expect(transport.requestLog, [
      'store',
      'create',
      'store',
      'store',
      'manifest-put',
    ]);
  });

  test('failed replacement confirmation can be retried', () async {
    final transport = _FakeTransport(
      missingKind: SyncStoreMissingKind.replacementRequired,
      createResponses: [
        _FakeTransport.response(500),
        _FakeTransport.response(201),
      ],
    );
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(
        previouslyUsed: true,
        snapshotEpochs: [null, null, null, 'epoch-1'],
      ),
      transport: transport,
    );
    addTearDown(coordinator.dispose);

    await coordinator.onAppStart();

    expect(
      (await coordinator.confirmReplacement()).status,
      SyncPassStatus.failed,
    );
    expect(
      (await coordinator.confirmReplacement()).status,
      SyncPassStatus.completed,
    );
    expect(transport.createCalls, 2);
    expect(transport.storeCalls, 3);
  });

  test(
    'replacement confirmation keeps the isolated pass single-flight gate',
    () async {
      final release = Completer<void>();
      final passStarted = Completer<void>();
      var operationCalls = 0;
      var activeOperations = 0;
      var maximumActiveOperations = 0;
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(),
        transport: _FakeTransport(),
        passOperation: ({SyncStoreResult? initialStore}) async {
          operationCalls++;
          activeOperations++;
          maximumActiveOperations = maximumActiveOperations < activeOperations
              ? activeOperations
              : maximumActiveOperations;
          try {
            if (operationCalls == 1) {
              return const SyncPassResult(SyncPassStatus.replacementRequired);
            }
            if (operationCalls == 2) {
              passStarted.complete();
              await release.future;
            }
            return const SyncPassResult(SyncPassStatus.completed);
          } finally {
            activeOperations--;
          }
        },
      );
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await coordinator.dispose();
      });

      expect(
        (await coordinator.onAppStart()).status,
        SyncPassStatus.replacementRequired,
      );
      final confirmation = coordinator.confirmReplacement();
      await passStarted.future;

      var queuedFinished = false;
      final queued = coordinator.syncNow();
      queued.then((_) => queuedFinished = true);
      await Future<void>.delayed(Duration.zero);
      expect(queuedFinished, isFalse);

      release.complete();
      expect((await confirmation).status, SyncPassStatus.completed);
      expect((await queued).status, SyncPassStatus.completed);
      expect(operationCalls, 3);
      expect(maximumActiveOperations, 1);
    },
  );

  test('create conflict reports and stops without fresh attach', () async {
    final transport = _FakeTransport(
      missingKind: SyncStoreMissingKind.replacementRequired,
      createResponses: [_FakeTransport.response(409)],
    );
    final store = _FakeStore(
      previouslyUsed: true,
      snapshotEpochs: ['epoch-1', 'epoch-1'],
    );
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: transport,
    );

    await coordinator.onAppStart();
    final result = await coordinator.confirmReplacement();

    expect(result.status, SyncPassStatus.failed);
    expect(transport.createCalls, 1);
    expect(transport.storeCalls, 1);
    expect(transport.manifestCalls, 0);
    expect(transport.postMissingCalls, 0);
    expect(transport.manifestPuts, 0);
    expect(store.baselineReplacements, 0);
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

  test('dispose settles queued work and does not start a follow-up', () async {
    final passGate = Completer<void>();
    var passRuns = 0;
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(),
      transport: _FakeTransport(),
      passOperation: ({SyncStoreResult? initialStore}) async {
        passRuns++;
        await passGate.future;
        return const SyncPassResult(SyncPassStatus.completed);
      },
    );

    final first = coordinator.syncNow();
    final queued = coordinator.syncNow();
    var disposeCompleted = false;
    final disposing = coordinator.dispose().then((_) {
      disposeCompleted = true;
    });

    expect((await queued).status, SyncPassStatus.failed);
    expect(passRuns, 1);
    await Future<void>.delayed(Duration.zero);
    expect(
      disposeCompleted,
      isFalse,
      reason: 'dispose must await the active pass while it is still gated',
    );
    passGate.complete();
    expect((await first).status, SyncPassStatus.completed);
    await disposing;
    expect(disposeCompleted, isTrue);
    expect(passRuns, 1);
    expect((await coordinator.syncNow()).status, SyncPassStatus.failed);
  });

  test('reuses a cached peer manifest after a 304 response', () async {
    final peerManifest = _manifest(deviceId: 'peer', records: const {});
    final encodedManifest = encodeSyncManifestUtf8(peerManifest);
    final transport = _FakeTransport(
      devices: ['peer'],
      manifestResponses: {
        'peer': [
          SyncHttpResponse(
            statusCode: 200,
            kind: SyncResponseKind.success,
            headers: const {'etag': '"peer-v1"'},
            body: encodedManifest,
          ),
          const SyncHttpResponse(
            statusCode: 304,
            kind: SyncResponseKind.notModified,
            headers: {},
            body: [],
          ),
        ],
      },
    );
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(),
      transport: transport,
    );

    expect((await coordinator.syncNow()).status, SyncPassStatus.completed);
    expect((await coordinator.syncNow()).status, SyncPassStatus.completed);
    expect(transport.manifestEtags, [null, '"peer-v1"']);
  });

  test(
    'keeps a concurrently-created record in the final publication',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'created-during-pass'),
      );
      final store = _FakeStore(
        snapshotBuilder: (snapshotNumber) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: snapshotNumber == 1
              ? {candidate.address: null}
              : {candidate.address: candidate},
          baseline: {
            candidate.address: SyncBaselineEntry(
              kind: candidate.address.kind,
              recordId: candidate.address.recordId,
              wireHash: _hash('baseline'),
            ),
          },
        ),
      );
      final transport = _FakeTransport();
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
        manifest.records[candidate.address.kind]![candidate.address.recordId],
        candidate.wireHash,
      );
      expect(store.droppedRecords, [candidate.address]);
    },
  );

  test(
    'reuses verified local blobs across cached and duplicate manifests',
    () async {
      final localCandidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final peerCandidate = SyncMergeCandidate.fromBlob(
        _setting('default_program_band', 'peer'),
      );
      final manifest = _manifest(
        deviceId: 'peer-a',
        records: {
          SyncRecordKind.setting: {
            localCandidate.blob.id: localCandidate.wireHash,
            peerCandidate.blob.id: peerCandidate.wireHash,
          },
        },
      );
      final encodedManifest = encodeSyncManifestUtf8(manifest);
      final transport = _FakeTransport(
        devices: ['peer-a', 'peer-b'],
        manifestResponses: {
          'peer-a': [
            SyncHttpResponse(
              statusCode: 200,
              kind: SyncResponseKind.success,
              headers: const {'etag': '"peer-a-v1"'},
              body: encodedManifest,
            ),
            const SyncHttpResponse(
              statusCode: 304,
              kind: SyncResponseKind.notModified,
              headers: {},
              body: [],
            ),
          ],
          'peer-b': [
            SyncHttpResponse(
              statusCode: 200,
              kind: SyncResponseKind.success,
              headers: const {'etag': '"peer-b-v1"'},
              body: encodedManifest,
            ),
            const SyncHttpResponse(
              statusCode: 304,
              kind: SyncResponseKind.notModified,
              headers: {},
              body: [],
            ),
          ],
        },
        blobResponses: {
          peerCandidate.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(peerCandidate.blob)),
          ),
        },
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(local: {localCandidate.address: localCandidate}),
        transport: transport,
      );

      expect((await coordinator.syncNow()).status, SyncPassStatus.completed);
      expect((await coordinator.syncNow()).status, SyncPassStatus.completed);
      expect(transport.blobCalls, 2);
    },
  );

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
          epoch: 'epoch-1',
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
      expect(store.snapshotCalls, 4);
    },
  );

  test(
    'marks published records before blob and failed manifest publication',
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
        onPostMissing: (_) async {
          expect(store.publishedRecords, [candidate.address]);
          expect(store.lifecycle, contains('markPublished'));
          expect(store.lifecycle, isNot(contains('markSyncUsed')));
        },
        onManifestPut: (_) {
          expect(store.lifecycle, contains('markPublished'));
          expect(store.lifecycle, contains('markSyncUsed'));
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
      expect(store.publishedBatches, hasLength(2));
      expect(store.publishedTransactionDepths.first, greaterThan(0));
      final manifest = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.single),
      );
      expect(store.publishedBatches.first, _manifestAddresses(manifest));
      expect(store.baselineAdvances, 0);
    },
  );

  for (final entry in const {
    'dance': SyncRecordKind.dance,
    'program': SyncRecordKind.program,
  }.entries) {
    test(
      'protects a ${entry.key} from hard-delete during blob publication',
      () async {
        final repositories = openTestRepositories();
        final stamp = DateTime.utc(2026, 7, 15, 12);
        final recordId = 'publication-race-${entry.key}';
        if (entry.value == SyncRecordKind.dance) {
          await repositories.dances.create(
            Dance(
              id: recordId,
              title: 'Publication race dance',
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
        } else {
          await repositories.programs.create(
            Program(
              id: recordId,
              title: 'Publication race program',
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
        }
        await repositories.syncLocal.resetEpoch(epoch: 'epoch-1');

        final transport = _FakeTransport(
          onPostMissing: (_) async {
            if (entry.value == SyncRecordKind.dance) {
              await repositories.dances.hardDelete([recordId]);
            } else {
              await repositories.programs.hardDelete([recordId]);
            }
          },
        );
        final coordinator = SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device-a',
          store: CompendiumSyncCoordinatorStore(repositories),
          transport: transport,
        );

        final result = await coordinator.syncNow();

        expect(result.status, SyncPassStatus.completed);
        final DateTime? deletedAt;
        if (entry.value == SyncRecordKind.dance) {
          final retained = await repositories.dances.getById(
            recordId,
            includeDeleted: true,
          );
          expect(retained, isNotNull);
          deletedAt = retained?.deletedAt;
        } else {
          final retained = await repositories.programs.getById(
            recordId,
            includeDeleted: true,
          );
          expect(retained, isNotNull);
          deletedAt = retained?.deletedAt;
        }
        expect(deletedAt, isNotNull);
        final manifest = decodeSyncManifest(
          utf8.decode(transport.manifestBodies.single),
        );
        expect(manifest.records[entry.value]?[recordId], isNotNull);
      },
    );
  }

  for (final entry in const {
    'dance': SyncRecordKind.dance,
    'program': SyncRecordKind.program,
  }.entries) {
    test(
      'protects a ${entry.key} from hard-delete between snapshot and marker',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'publication-marker-race-',
        );
        final databaseFile = File('${directory.path}/test.sqlite');
        final writerDatabase = CompendiumDatabase(
          NativeDatabase(
            databaseFile,
            setup: (database) {
              database.execute('PRAGMA busy_timeout = 5000');
            },
          ),
          closeStreamsSynchronously: true,
        );
        final deleteTransactionGate = _TransactionStartGate();
        final deletingDatabase = CompendiumDatabase(
          NativeDatabase.createInBackground(
            databaseFile,
            setup: (database) {
              database.execute('PRAGMA busy_timeout = 5000');
            },
          ).interceptWith(deleteTransactionGate),
          closeStreamsSynchronously: true,
        );
        final repositories = CompendiumRepositories(
          writerDatabase,
          contraTaxonomy,
        );
        final deletingRepositories = CompendiumRepositories(
          deletingDatabase,
          contraTaxonomy,
        );
        addTearDown(() async {
          await writerDatabase.close();
          await deletingDatabase.close();
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        });

        final stamp = DateTime.utc(2026, 7, 15, 12);
        final recordId = 'publication-marker-race-${entry.key}';
        if (entry.value == SyncRecordKind.dance) {
          await repositories.dances.create(
            Dance(
              id: recordId,
              title: 'Publication marker race dance',
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
          expect(
            await deletingRepositories.dances.getById(recordId),
            isNotNull,
          );
        } else {
          await repositories.programs.create(
            Program(
              id: recordId,
              title: 'Publication marker race program',
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
          expect(
            await deletingRepositories.programs.getById(recordId),
            isNotNull,
          );
        }
        await repositories.syncLocal.resetEpoch(epoch: 'epoch-1');
        deleteTransactionGate.arm();

        late Future<void> deleteFuture;
        final store = _SnapshotInterleavingStore(
          CompendiumSyncCoordinatorStore(repositories),
          afterFinalSnapshot: () async {
            deleteFuture = entry.value == SyncRecordKind.dance
                ? deletingRepositories.dances.hardDelete([recordId])
                : deletingRepositories.programs.hardDelete([recordId]);
            await deleteTransactionGate.started;
          },
          afterTransaction: () async {
            deleteTransactionGate.release();
            await deleteFuture;
          },
        );
        final transport = _FakeTransport();
        final coordinator = SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device-a',
          store: store,
          transport: transport,
        );

        final result = await coordinator.syncNow();
        await deleteFuture;

        expect(result.status, SyncPassStatus.completed);
        final DateTime? deletedAt;
        if (entry.value == SyncRecordKind.dance) {
          final retained = await deletingRepositories.dances.getById(
            recordId,
            includeDeleted: true,
          );
          expect(retained, isNotNull);
          deletedAt = retained?.deletedAt;
        } else {
          final retained = await deletingRepositories.programs.getById(
            recordId,
            includeDeleted: true,
          );
          expect(retained, isNotNull);
          deletedAt = retained?.deletedAt;
        }
        expect(deletedAt, isNotNull);
        expect(store.snapshotCalls, 2);
        final manifest = decodeSyncManifest(
          utf8.decode(transport.manifestBodies.single),
        );
        expect(manifest.records[entry.value]?[recordId], isNotNull);
      },
    );
  }

  test(
    'retains the record marker without marking the sync used on upload failure',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final store = _FakeStore(local: {candidate.address: candidate});
      final transport = _FakeTransport(
        postMissingStatuses: [500],
        onPostMissing: (_) async {
          expect(store.publishedRecords, [candidate.address]);
          expect(store.lifecycle, isNot(contains('markSyncUsed')));
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
      expect(store.lifecycle, isNot(contains('markSyncUsed')));
      expect(transport.manifestPuts, 0);
    },
  );

  test('retires aliases from the complete current peer-manifest set', () async {
    final store = _FakeStore();
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(deviceId: 'peer', records: const {}),
      ),
    );

    final result = await coordinator.syncNow();

    expect(result.status, SyncPassStatus.completed);
    expect(store.retiredPeerAddresses, [<SyncRecordAddress>{}]);
  });

  test('does not retire aliases when a peer manifest is unavailable', () async {
    final store = _FakeStore();
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          'peer': [_FakeTransport.response(500)],
        },
      ),
    );

    final result = await coordinator.syncNow();

    expect(result.status, SyncPassStatus.completed);
    expect(store.retiredPeerAddresses, isEmpty);
  });

  test(
    'returns staleEpoch when manifest publication loses the epoch race',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final store = _FakeStore(local: {candidate.address: candidate});
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: _FakeTransport(putManifestStatus: 409),
      );

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.staleEpoch);
      expect(store.baselineAdvances, 0);
    },
  );

  test(
    'a stale manifest conflict defers fresh attach to the next trigger',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final store = _FakeStore(
        local: {candidate.address: candidate},
        snapshotEpochs: ['epoch-1', 'epoch-1', 'epoch-1', 'epoch-1', 'epoch-2'],
      );
      final transport = _FakeTransport(
        storeEpochs: ['epoch-1', 'epoch-2', 'epoch-2'],
        putManifestStatuses: [409, 200],
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final first = await coordinator.syncNow();
      expect(first.status, SyncPassStatus.staleEpoch);
      expect(store.baselineReplacements, 0);

      final second = await coordinator.syncNow();
      expect(second.status, SyncPassStatus.completed);
      expect(store.baselineReplacements, 1);
      expect(transport.manifestPuts, 2);
    },
  );

  test(
    'fresh attach replaces the baseline before one steady continuation',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final store = _FakeStore(
        epoch: null,
        local: {candidate.address: candidate},
        snapshotEpochs: [null, null, 'epoch-1'],
      );
      var postMissingCall = 0;
      final transport = _FakeTransport(
        onPostMissing: (_) async {
          postMissingCall++;
          if (postMissingCall == 1) {
            expect(store.publishedRecords, isEmpty);
          } else {
            expect(store.publishedRecords, [candidate.address]);
            expect(store.lifecycle, isNot(contains('markSyncUsed')));
          }
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
      expect(transport.manifestCalls, 0);
      expect(transport.blobCalls, 0);
      expect(transport.postMissingCalls, 2);
      expect(transport.manifestPuts, 1);
      expect(store.baselineReplacements, 1);
      expect(store.baselineAdvances, 0);
      expect(store.epochStateClears, 1);
      expect(postMissingCall, 2);
    },
  );

  test(
    'incomplete fresh attach retries before applying or publishing a partial union',
    () async {
      final local = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final store = _FakeStore(epoch: null, local: {local.address: local});
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(deviceId: 'peer', records: const {}),
        manifestResponses: {
          'peer': [_FakeTransport.response(500)],
        },
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final first = await coordinator.syncNow();

      expect(first.status, SyncPassStatus.failed);
      expect(store.freshAttachDedupeCalls, 0);
      expect(store.writes, isEmpty);
      expect(store.baselineReplacements, 0);
      expect(transport.manifestPuts, 0);

      final second = await coordinator.syncNow();

      expect(second.status, SyncPassStatus.completed);
      expect(store.freshAttachDedupeCalls, 1);
      expect(store.baselineReplacements, 1);
      expect(transport.manifestPuts, 1);
    },
  );

  test(
    'incomplete fresh attach retries when a listed peer blob is unavailable',
    () async {
      final peer = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'remote'),
      );
      final store = _FakeStore(epoch: null);
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.setting: {peer.blob.id: peer.wireHash},
          },
        ),
        blobResponses: {},
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final first = await coordinator.syncNow();

      expect(first.status, SyncPassStatus.failed);
      expect(first.reports.single.code, SyncReportCode.unresolvedBlob);
      expect(store.freshAttachDedupeCalls, 0);
      expect(store.baselineReplacements, 0);
      expect(transport.manifestPuts, 0);

      transport.blobResponses[peer.wireHash] = _FakeTransport.response(
        200,
        body: utf8.encode(encodeSyncRecordBlob(peer.blob)),
      );
      final second = await coordinator.syncNow();

      expect(second.status, SyncPassStatus.completed);
      expect(store.freshAttachDedupeCalls, 1);
      expect(store.baselineReplacements, 1);
      expect(transport.manifestPuts, 1);
    },
  );

  test(
    'failed fresh attach retries after its epoch state is cleared',
    () async {
      final store = _FakeStore(epoch: null, failFreshAttachDedupeOnce: true);
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: _FakeTransport(),
      );

      await expectLater(coordinator.syncNow(), throwsA(isA<StateError>()));
      expect(store.baselineReplacements, 0);

      final retried = await coordinator.syncNow();

      expect(retried.status, SyncPassStatus.completed);
      expect(store.epochStateClears, 2);
      expect(store.baselineReplacements, 1);
    },
  );

  test('failed fresh-attach publication retries the complete attach', () async {
    final store = _FakeStore(epoch: null);
    final transport = _FakeTransport(putManifestStatuses: [500, 200]);
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: transport,
    );

    final failed = await coordinator.syncNow();

    expect(failed.status, SyncPassStatus.failed);
    expect(store.epochStateClears, 1);
    expect(store.baselineReplacements, 0);

    final retried = await coordinator.syncNow();

    expect(retried.status, SyncPassStatus.completed);
    expect(store.epochStateClears, 2);
    expect(store.baselineReplacements, 1);
    expect(transport.manifestPuts, 2);
  });

  test(
    'fresh attach excludes pending live rows from the replacement baseline',
    () async {
      final live = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'live'),
      );
      final tombstoneBlob = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: live.blob.id,
        updatedAt: live.blob.updatedAt.add(const Duration(minutes: 1)),
        deletedAt: live.blob.updatedAt.add(const Duration(minutes: 1)),
        existenceAt: live.blob.existenceAt,
        body: live.blob.body,
      );
      final store = _FakeStore(
        snapshotBuilder: (snapshotNumber) {
          final epoch = snapshotNumber >= 3 ? 'epoch-1' : null;
          return SyncCoordinatorSnapshot(
            epoch: epoch,
            previouslyUsed: false,
            local: snapshotNumber >= 3 ? const {} : {live.address: live},
            baseline: const {},
            publication: snapshotNumber >= 3
                ? {live.address: SyncMergeCandidate.fromBlob(tombstoneBlob)}
                : {live.address: live},
            pendingLive: snapshotNumber >= 3 ? {live.address: live} : const {},
            pending: snapshotNumber >= 3 ? {live.address} : const {},
          );
        },
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: _FakeTransport(),
      );

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(store.baselineReplacements, 1);
      expect(store.replacedEntries, isEmpty);
    },
  );

  test(
    'fresh attach compares pending live downloads with the concurrency view',
    () async {
      final live = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'live'),
      );
      final tombstoneStamp = live.blob.updatedAt.add(
        const Duration(minutes: -1),
      );
      final tombstone = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: live.blob.kind,
          id: live.blob.id,
          updatedAt: tombstoneStamp,
          deletedAt: tombstoneStamp,
          existenceAt: live.blob.existenceAt.subtract(
            const Duration(minutes: 1),
          ),
          body: live.blob.body,
        ),
      );
      final address = live.address;
      final store = _FakeStore(
        epoch: null,
        snapshotBuilder: (snapshotNumber) {
          final pending = snapshotNumber >= 2;
          return SyncCoordinatorSnapshot(
            epoch: snapshotNumber >= 3 ? 'epoch-1' : null,
            previouslyUsed: false,
            local: const {},
            baseline: const {},
            publication: pending ? {address: tombstone} : const {},
            pendingLive: pending ? {address: live} : const {},
            pending: pending ? {address} : const {},
          );
        },
        currentCandidatesBuilder: () => {address: live},
      );
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.setting: {live.blob.id: live.wireHash},
          },
        ),
        blobResponses: {
          live.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(live.blob)),
          ),
        },
        missingResponses: [const [], const []],
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(
        result.reports.map((report) => report.code),
        isNot(contains(SyncReportCode.concurrentLocalChange)),
      );
    },
  );

  test(
    'continuation stops without publishing when the epoch changes and retries fresh attach',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final store = _FakeStore(
        local: {candidate.address: candidate},
        snapshotEpochs: [
          null,
          null,
          'epoch-1',
          'epoch-1',
          'epoch-1',
          'epoch-2',
        ],
      );
      final transport = _FakeTransport(
        storeEpochs: ['epoch-1', 'epoch-2', 'epoch-2', 'epoch-2'],
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final staleContinuation = await coordinator.syncNow();
      expect(staleContinuation.status, SyncPassStatus.staleEpoch);
      expect(transport.manifestPuts, 0);
      expect(store.baselineReplacements, 0);

      final retried = await coordinator.syncNow();
      expect(retried.status, SyncPassStatus.completed);
      expect(transport.manifestPuts, 1);
      expect(store.baselineReplacements, 1);
    },
  );

  test(
    'propagates fresh-attach duplicate counts through the coordinator result',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final store = _FakeStore(
        local: {candidate.address: candidate},
        snapshotEpochs: [null, null, 'epoch-1'],
        freshAttachDedupeResult: const SyncFreshAttachDedupeResult(
          duplicateCount: 2,
          reports: [],
        ),
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: _FakeTransport(),
      );

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(result.duplicateCount, 2);
      expect(
        result.appliedKinds,
        containsAll([SyncRecordKind.dance, SyncRecordKind.program]),
      );
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
          epoch: 'epoch-1',
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
        missingResponses: [
          [repaired.wireHash],
        ],
      );
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
      expect(transport.postMissingCalls, 1);
      expect(transport.putBlobHashes, [repaired.wireHash]);
    },
  );

  test(
    'publishes a cited pending tombstone without removing the local live row',
    () async {
      final stamp = DateTime.utc(2026, 7, 15, 12);
      final tombstone = SyncRecordBlob(
        kind: SyncRecordKind.tag,
        id: 'pending-tag',
        updatedAt: stamp,
        deletedAt: stamp,
        existenceAt: stamp,
        body: const {'id': 'pending-tag', 'name': 'Pending tag'},
      );
      final candidate = SyncMergeCandidate.fromBlob(tombstone);
      final store = _FakeStore(
        snapshotBuilder: (_) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: const {},
          publication: {candidate.address: candidate},
          pending: {candidate.address},
          baseline: const {},
        ),
      );
      final transport = _FakeTransport(
        onPostMissing: (_) async {
          expect(store.publishedRecords, [candidate.address]);
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
      final manifest = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.single),
      );
      expect(
        manifest.records[SyncRecordKind.tag]!['pending-tag'],
        candidate.wireHash,
      );
      expect(store.publishedRecords, [candidate.address]);
      expect(store.publishedBatches.first, _manifestAddresses(manifest));
      expect(store.writes, isEmpty);
    },
  );

  test('uploads only blobs retained by the final manifest', () async {
    final local = SyncMergeCandidate.fromBlob(
      _setting('custom_dialects', 'local'),
    );
    final remote = SyncMergeCandidate.fromBlob(
      _setting('custom_dialects', 'remote', seconds: 1),
    );
    final store = _FakeStore(
      snapshotBuilder: (snapshotNumber) => SyncCoordinatorSnapshot(
        epoch: 'epoch-1',
        previouslyUsed: false,
        local: {local.address: snapshotNumber == 1 ? local : remote},
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
      missingResponses: [
        [remote.wireHash],
      ],
    );
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: transport,
    );

    final result = await coordinator.syncNow();

    expect(result.status, SyncPassStatus.completed);
    expect(transport.postMissingBatches, [
      [remote.wireHash],
    ]);
    expect(transport.putBlobHashes, [remote.wireHash]);
  });

  test(
    'skips a remote winner when its local address changed mid-pass',
    () async {
      final local = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final concurrent = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'concurrent', seconds: 1),
      );
      final remote = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'remote', seconds: 2),
      );
      final store = _FakeStore(
        local: {local.address: local},
        currentCandidatesBuilder: () => {concurrent.address: concurrent},
        snapshotBuilder: (snapshotNumber) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: {concurrent.address: snapshotNumber == 1 ? local : concurrent},
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
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(result.reports.single.code, SyncReportCode.concurrentLocalChange);
      expect(store.writes, isEmpty);
      final manifest = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.single),
      );
      expect(
        manifest.records[SyncRecordKind.setting]!['custom_dialects'],
        concurrent.wireHash,
      );
    },
  );

  test('guards aliased downloads against pending survivor changes', () async {
    for (final changeSurvivor in [true, false]) {
      final repositories = openTestRepositories(closeOnTearDown: false);
      final stamp = DateTime.utc(2026, 7, 15, 12);
      const survivorId = 'canonical-pending-tag';
      const losingId = 'legacy-pending-tag';
      final survivor = Tag(id: survivorId, name: 'Shared tag');
      // ignore: unused_result
      await repositories.tags.upsert(survivor, at: stamp);
      await repositories.dances.create(
        Dance(
          id: 'pending-tag-owner',
          title: 'Pending tag owner',
          tagIds: [survivorId],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      final tombstone = SyncRecordBlob(
        kind: SyncRecordKind.tag,
        id: survivorId,
        updatedAt: stamp.add(const Duration(minutes: 1)),
        deletedAt: stamp.add(const Duration(minutes: 1)),
        existenceAt: stamp.add(const Duration(minutes: 1)),
        body: syncBodyForEntity(SyncRecordKind.tag, survivor),
      );
      await repositories.syncLocal.upsertPendingDeletion(
        kind: tombstone.kind,
        recordId: tombstone.id,
        tombstonedAt: tombstone.deletedAt!,
        tombstoneHash: SyncMergeCandidate.fromBlob(tombstone).wireHash,
        tombstoneBlob: encodeSyncRecordBlob(tombstone),
      );
      await repositories.syncLocal.resetEpoch(epoch: 'epoch-1');
      await repositories.syncLocal.upsertAlias(
        kind: SyncRecordKind.tag,
        losingId: losingId,
        survivingId: survivorId,
      );
      final beforePass = await CompendiumSyncCoordinatorStore(
        repositories,
      ).snapshot();
      expect(
        beforePass.pending,
        contains((kind: SyncRecordKind.tag, recordId: survivorId)),
      );
      expect(
        beforePass.pendingLive[(
          kind: SyncRecordKind.tag,
          recordId: survivorId,
        )],
        isNotNull,
      );
      final concurrencyCandidates = await CompendiumSyncCoordinatorStore(
        repositories,
      ).snapshotCandidates();
      expect(
        concurrencyCandidates[(kind: SyncRecordKind.tag, recordId: survivorId)]!
            .wireHash,
        beforePass
            .pendingLive[(kind: SyncRecordKind.tag, recordId: survivorId)]!
            .wireHash,
      );

      final inbound = SyncMergeCandidate.fromBlob(
        _tag(losingId, 'Shared tag', seconds: 1),
      );
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.tag: {losingId: inbound.wireHash},
          },
        ),
        blobResponses: {
          inbound.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(inbound.blob)),
          ),
        },
        onManifestGet: changeSurvivor
            ? (_) async {
                // ignore: unused_result
                await repositories.tags.upsert(
                  Tag(id: survivorId, name: 'Changed locally'),
                  at: stamp.add(const Duration(minutes: 2)),
                );
              }
            : null,
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: CompendiumSyncCoordinatorStore(repositories),
        transport: transport,
      );

      final result = await coordinator.syncNow();
      final reportCodes = result.reports.map((report) => report.code);

      if (changeSurvivor) {
        expect(reportCodes, contains(SyncReportCode.concurrentLocalChange));
        expect(
          (await repositories.tags.getById(survivorId))!.name,
          'Changed locally',
        );
      } else {
        expect(
          reportCodes,
          isNot(contains(SyncReportCode.concurrentLocalChange)),
        );
      }
      await repositories.db.close();
    }
  });

  test(
    'chunks final-manifest missing-blob negotiation at the protocol limit',
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
          epoch: 'epoch-1',
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

  test(
    'an unresolved address does not advance from another peer observation',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final missingHash = _hash('a');
      final address = candidate.address;
      final store = _FakeStore(
        local: {address: candidate},
        baseline: {
          address: SyncBaselineEntry(
            kind: address.kind,
            recordId: address.recordId,
            wireHash: candidate.wireHash,
          ),
        },
      );
      final transport = _FakeTransport(
        devices: ['peer-a', 'peer-b'],
        peerManifests: {
          'peer-a': _manifest(
            deviceId: 'peer-a',
            records: {
              SyncRecordKind.setting: {address.recordId: missingHash},
            },
          ),
          'peer-b': _manifest(
            deviceId: 'peer-b',
            records: {
              SyncRecordKind.setting: {address.recordId: candidate.wireHash},
            },
          ),
        },
        blobResponses: {
          candidate.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(candidate.blob)),
          ),
          missingHash: _FakeTransport.response(404),
        },
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
    },
  );

  test('an equal-time peer tie does not advance the baseline', () async {
    final local = SyncMergeCandidate.fromBlob(
      _setting('custom_dialects', 'local'),
    );
    final remote = SyncMergeCandidate.fromBlob(
      _setting('custom_dialects', 'remote'),
    );
    final store = _FakeStore(
      local: {local.address: local},
      baseline: {
        local.address: SyncBaselineEntry(
          kind: local.address.kind,
          recordId: local.address.recordId,
          wireHash: local.wireHash,
        ),
      },
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
    );
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: transport,
    );

    final result = await coordinator.syncNow();

    expect(
      result.reports.map((report) => report.code),
      contains(SyncReportCode.equalUpdatedAt),
    );
    expect(store.freshAttachDedupeCalls, 0);
    expect(store.steadyStateReviewRefreshCalls, 1);
    expect(store.advancedEntries, isEmpty);
  });

  test('filters noncanonical peer candidates before merge planning', () async {
    final noncanonical = SyncRecordBlob(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      updatedAt: DateTime.utc(2026, 7, 15, 12),
      deletedAt: DateTime.utc(2026, 7, 15, 12),
      existenceAt: DateTime.utc(2026, 7, 15, 12, 0, 2),
      body: {'value': 'e\u0301'},
    );
    final canonical = SyncRecordBlob(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      updatedAt: DateTime.utc(2026, 7, 15, 12, 0, 1),
      deletedAt: DateTime.utc(2026, 7, 15, 12, 0, 1),
      existenceAt: DateTime.utc(2026, 7, 15, 12, 0, 1),
      body: {'value': 'canonical'},
    );
    final noncanonicalCandidate = SyncMergeCandidate.fromBlob(noncanonical);
    final canonicalCandidate = SyncMergeCandidate.fromBlob(canonical);
    final store = _FakeStore(previouslyUsed: true);
    final transport = _FakeTransport(
      devices: ['peer-bad', 'peer-good'],
      peerManifests: {
        'peer-bad': _manifest(
          deviceId: 'peer-bad',
          records: {
            SyncRecordKind.setting: {
              noncanonical.id: noncanonicalCandidate.wireHash,
            },
          },
        ),
        'peer-good': _manifest(
          deviceId: 'peer-good',
          records: {
            SyncRecordKind.setting: {canonical.id: canonicalCandidate.wireHash},
          },
        ),
      },
      blobResponses: {
        noncanonicalCandidate.wireHash: _FakeTransport.response(
          200,
          body: utf8.encode(encodeSyncRecordBlob(noncanonical)),
        ),
        canonicalCandidate.wireHash: _FakeTransport.response(
          200,
          body: utf8.encode(encodeSyncRecordBlob(canonical)),
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
    final rejectionReports = result.reports
        .where((report) => report.code == SyncReportCode.nonCanonicalWireBody)
        .toList();
    expect(rejectionReports, hasLength(1));
    expect(rejectionReports.single.peerId, 'peer-bad');
    expect(store.writes, hasLength(1));
    final write = store.writes.single;
    expect(write.body, canonical.body);
    expect(write.updatedAt, canonical.updatedAt);
    expect(write.deletedAt, canonical.deletedAt);
    expect(write.existenceAt, canonical.existenceAt);
    expect(write.sourceBlob?.body, canonical.body);
  });

  test(
    'filters noncanonical cached peer candidates before merge planning',
    () async {
      final noncanonical = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        updatedAt: DateTime.utc(2026, 7, 15, 12),
        deletedAt: DateTime.utc(2026, 7, 15, 12),
        existenceAt: DateTime.utc(2026, 7, 15, 12, 0, 2),
        body: {'value': 'e\u0301'},
      );
      final canonical = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        updatedAt: DateTime.utc(2026, 7, 15, 12, 0, 1),
        deletedAt: DateTime.utc(2026, 7, 15, 12, 0, 1),
        existenceAt: DateTime.utc(2026, 7, 15, 12, 0, 1),
        body: {'value': 'canonical'},
      );
      final noncanonicalCandidate = SyncMergeCandidate.fromBlob(noncanonical);
      final canonicalCandidate = SyncMergeCandidate.fromBlob(canonical);
      final store = _FakeStore(
        previouslyUsed: true,
        snapshotBuilder: (_) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: true,
          local: const {},
          baseline: const {},
          publication: {noncanonicalCandidate.address: noncanonicalCandidate},
        ),
      );
      final transport = _FakeTransport(
        devices: ['peer-bad', 'peer-good'],
        peerManifests: {
          'peer-bad': _manifest(
            deviceId: 'peer-bad',
            records: {
              SyncRecordKind.setting: {
                noncanonical.id: noncanonicalCandidate.wireHash,
              },
            },
          ),
          'peer-good': _manifest(
            deviceId: 'peer-good',
            records: {
              SyncRecordKind.setting: {
                canonical.id: canonicalCandidate.wireHash,
              },
            },
          ),
        },
        blobResponses: {
          canonicalCandidate.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(canonical)),
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
      final rejectionReports = result.reports
          .where((report) => report.code == SyncReportCode.nonCanonicalWireBody)
          .toList();
      expect(rejectionReports, hasLength(1));
      expect(rejectionReports.single.peerId, 'peer-bad');
      expect(transport.blobCalls, 1);
      expect(store.writes, hasLength(1));
      final write = store.writes.single;
      expect(write.body, canonical.body);
      expect(write.updatedAt, canonical.updatedAt);
      expect(write.deletedAt, canonical.deletedAt);
      expect(write.existenceAt, canonical.existenceAt);
      expect(write.sourceBlob?.body, canonical.body);
    },
  );

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

  test('a cached aliased blob with the wrong envelope is rejected', () async {
    final cached = SyncMergeCandidate.fromBlob(
      _tag('canonical-cached', 'Shared tag'),
    );
    final manifestAddress = (
      kind: SyncRecordKind.tag,
      recordId: 'legacy-cached',
    );
    final store = _FakeStore(
      local: {cached.address: cached},
      baseline: {
        cached.address: SyncBaselineEntry(
          kind: cached.address.kind,
          recordId: cached.address.recordId,
          wireHash: cached.wireHash,
        ),
      },
      aliases: {manifestAddress: cached.address},
    );
    final transport = _FakeTransport(
      devices: ['peer'],
      peerManifest: _manifest(
        deviceId: 'peer',
        records: {
          SyncRecordKind.tag: {manifestAddress.recordId: cached.wireHash},
        },
      ),
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
    expect(transport.blobCalls, 0);
  });
}

final class _SnapshotInterleavingStore
    implements SyncCoordinatorStore, SyncApplyReconciliationStorage {
  _SnapshotInterleavingStore(
    this._delegate, {
    required this.afterFinalSnapshot,
    required this.afterTransaction,
  });

  final CompendiumSyncCoordinatorStore _delegate;
  final Future<void> Function() afterFinalSnapshot;
  final Future<void> Function() afterTransaction;
  int snapshotCalls = 0;
  bool _interleavingStarted = false;
  int _activeTransactions = 0;
  bool _publicationTransactionPending = false;

  @override
  Future<SyncCoordinatorSnapshot> snapshot() async {
    final snapshot = await _delegate.snapshot();
    snapshotCalls++;
    if (snapshotCalls == 2 && !_interleavingStarted) {
      _interleavingStarted = true;
      final publicationTransactionActive = _activeTransactions > 0;
      if (publicationTransactionActive) {
        _publicationTransactionPending = true;
      }
      await afterFinalSnapshot();
      if (!publicationTransactionActive) {
        await afterTransaction();
      }
    }
    return snapshot;
  }

  @override
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> snapshotCandidates() =>
      _delegate.snapshotCandidates();

  @override
  Future<SyncRecordAddress> resolveAlias(SyncRecordAddress address) =>
      _delegate.resolveAlias(address);

  @override
  Future<void> markSyncUsed(String syncId) => _delegate.markSyncUsed(syncId);

  @override
  Future<void> retireAliases({required Set<SyncRecordAddress> peerAddresses}) =>
      _delegate.retireAliases(peerAddresses: peerAddresses);

  @override
  Future<void> markPublished(Iterable<SyncRecordAddress> records) =>
      _delegate.markPublished(records);

  @override
  Future<void> markPublicationAttempt({
    required String syncId,
    required Iterable<SyncRecordAddress> records,
  }) => _delegate.markPublicationAttempt(syncId: syncId, records: records);

  @override
  Future<SyncFreshAttachDedupeResult> deduplicateFreshAttach() =>
      _delegate.deduplicateFreshAttach();

  @override
  Future<SyncFreshAttachDedupeResult> refreshDanceAmbiguityReviews() =>
      _delegate.refreshDanceAmbiguityReviews();

  @override
  Future<void> replaceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
  }) => _delegate.replaceBaseline(epoch: epoch, entries: entries);

  @override
  Future<void> clearEpochState() => _delegate.clearEpochState();

  @override
  Future<void> advanceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
    required Iterable<SyncRecordAddress> drop,
  }) => _delegate.advanceBaseline(epoch: epoch, entries: entries, drop: drop);

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    _activeTransactions++;
    var ownsPublicationInterleave = false;
    try {
      final result = await _delegate.transaction(action);
      ownsPublicationInterleave = _publicationTransactionPending;
      _publicationTransactionPending = false;
      if (ownsPublicationInterleave) {
        await afterTransaction();
      }
      return result;
    } finally {
      _activeTransactions--;
    }
  }

  @override
  Future<Map<String, Object?>?> read(SyncRecordAddress address) =>
      _delegate.read(address);

  @override
  Future<void> write(SyncApplyRecord record) => _delegate.write(record);

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
  Future<void> rebuildDerivedIndexes() => _delegate.rebuildDerivedIndexes();

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
}

final class _TransactionStartGate extends QueryInterceptor {
  Completer<void>? _started;
  Completer<void>? _release;
  bool _armed = false;

  Future<void> get started => _started!.future;

  void arm() {
    _started = Completer<void>();
    _release = Completer<void>();
    _armed = true;
  }

  void release() {
    final release = _release;
    if (release != null && !release.isCompleted) {
      release.complete();
    }
  }

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    if (_armed) {
      _armed = false;
      _started!.complete();
    }
    return parent.beginTransaction();
  }

  @override
  Future<bool> ensureOpen(
    QueryExecutor executor,
    QueryExecutorUser user,
  ) async {
    final release = _release;
    if (release != null && executor is TransactionExecutor) {
      await release.future;
      _release = null;
    }
    return executor.ensureOpen(user);
  }
}

final class _FakeStore implements SyncCoordinatorStore {
  _FakeStore({
    this.previouslyUsed = false,
    String? epoch = 'epoch-1',
    Map<SyncRecordAddress, SyncMergeCandidate?>? local,
    Map<SyncRecordAddress, SyncBaselineEntry>? baseline,
    Map<SyncRecordAddress, SyncRecordAddress>? aliases,
    List<String?>? snapshotEpochs,
    this.freshAttachDedupeResult,
    this.failFreshAttachDedupeOnce = false,
    this.snapshotBuilder,
    this.currentCandidatesBuilder,
    List<String>? lifecycle,
  }) : _storedEpoch = epoch,
       local = {...?local},
       baseline = {...?baseline},
       aliases = {...?aliases},
       snapshotEpochs = [...?snapshotEpochs],
       lifecycle = lifecycle ?? <String>[];

  final bool previouslyUsed;
  String? _storedEpoch;
  final Map<SyncRecordAddress, SyncMergeCandidate?> local;
  final Map<SyncRecordAddress, SyncBaselineEntry> baseline;
  final Map<SyncRecordAddress, SyncRecordAddress> aliases;
  final List<String?> snapshotEpochs;
  final SyncFreshAttachDedupeResult? freshAttachDedupeResult;
  bool failFreshAttachDedupeOnce;
  final SyncCoordinatorSnapshot Function(int snapshotNumber)? snapshotBuilder;
  final Map<SyncRecordAddress, SyncMergeCandidate?> Function()?
  currentCandidatesBuilder;
  final List<String> lifecycle;
  final List<SyncRecordAddress> publishedRecords = [];
  final List<List<SyncRecordAddress>> publishedBatches = [];
  final List<int> publishedTransactionDepths = [];
  final List<SyncRecordAddress> advancedEntries = [];
  final List<SyncRecordAddress> droppedRecords = [];
  final List<SyncApplyRecord> writes = [];
  final List<Set<SyncRecordAddress>> retiredPeerAddresses = [];
  int snapshotCalls = 0;
  int baselineAdvances = 0;
  int baselineReplacements = 0;
  int epochStateClears = 0;
  int freshAttachDedupeCalls = 0;
  int steadyStateReviewRefreshCalls = 0;
  final List<SyncRecordAddress> replacedEntries = [];
  int _transactionDepth = 0;

  @override
  Future<SyncCoordinatorSnapshot> snapshot() async {
    snapshotCalls++;
    final snapshotIndex = snapshotCalls - 1;
    final epoch = snapshotEpochs.isEmpty
        ? _storedEpoch
        : snapshotEpochs[snapshotIndex < snapshotEpochs.length
              ? snapshotIndex
              : snapshotEpochs.length - 1];
    return snapshotBuilder?.call(snapshotCalls) ??
        SyncCoordinatorSnapshot(
          epoch: epoch,
          previouslyUsed: previouslyUsed,
          local: local,
          baseline: baseline,
        );
  }

  @override
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>>
  snapshotCandidates() async => currentCandidatesBuilder?.call() ?? local;

  @override
  Future<SyncRecordAddress> resolveAlias(SyncRecordAddress address) async {
    final visited = <SyncRecordAddress>{};
    var current = address;
    while (visited.add(current)) {
      final next = aliases[current];
      if (next == null) return current;
      current = next;
    }
    return current;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    lifecycle.add('transaction');
    _transactionDepth++;
    try {
      return await action();
    } finally {
      _transactionDepth--;
    }
  }

  @override
  Future<void> markSyncUsed(String syncId) async {
    lifecycle.add('markSyncUsed');
  }

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
    publishedTransactionDepths.add(_transactionDepth);
    final batch = records.toList(growable: false);
    publishedBatches.add(batch);
    for (final address in batch) {
      if (!publishedRecords.contains(address)) {
        publishedRecords.add(address);
      }
    }
  }

  @override
  Future<void> retireAliases({
    required Set<SyncRecordAddress> peerAddresses,
  }) async {
    lifecycle.add('retireAliases');
    retiredPeerAddresses.add(peerAddresses);
  }

  @override
  Future<void> markPublicationAttempt({
    required String syncId,
    required Iterable<SyncRecordAddress> records,
  }) async {
    await transaction(() async {
      await markPublished(records);
      await markSyncUsed(syncId);
    });
  }

  @override
  Future<SyncFreshAttachDedupeResult> deduplicateFreshAttach() async {
    freshAttachDedupeCalls++;
    if (failFreshAttachDedupeOnce) {
      failFreshAttachDedupeOnce = false;
      throw StateError('scripted fresh-attach failure');
    }
    return freshAttachDedupeResult ??
        const SyncFreshAttachDedupeResult(duplicateCount: 0, reports: []);
  }

  @override
  Future<SyncFreshAttachDedupeResult> refreshDanceAmbiguityReviews() async {
    steadyStateReviewRefreshCalls++;
    return const SyncFreshAttachDedupeResult(duplicateCount: 0, reports: []);
  }

  @override
  Future<void> replaceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
  }) async {
    _storedEpoch = epoch;
    baselineReplacements++;
    final addresses = entries.map(
      (entry) => (kind: entry.kind, recordId: entry.recordId),
    );
    replacedEntries.addAll(addresses);
    advancedEntries.addAll(addresses);
  }

  @override
  Future<void> clearEpochState() async {
    _storedEpoch = null;
    baseline.clear();
    epochStateClears++;
    lifecycle.add('clearEpochState');
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
    List<String>? storeEpochs,
    this.peerManifest,
    this.peerManifests = const {},
    List<SyncHttpResponse>? createResponses,
    Map<String, List<SyncHttpResponse>>? manifestResponses,
    this.blobResponses = const {},
    List<List<String>>? missingResponses,
    this.putManifestStatus = 200,
    List<int>? putManifestStatuses,
    this.onManifestPut,
    this.onManifestGet,
    this.onPostMissing,
    List<int>? postMissingStatuses,
  }) : createResponses = [...createResponses ?? const []],
       storeEpochs = [
         ...storeEpochs ?? const ['epoch-1'],
       ],
       missingResponses = [
         for (final response in missingResponses ?? const <List<String>>[[]])
           [...response],
       ],
       putManifestStatuses = [...putManifestStatuses ?? const []],
       postMissingStatuses = [...postMissingStatuses ?? const []],
       manifestResponses = {
         for (final entry
             in (manifestResponses ?? const <String, List<SyncHttpResponse>>{})
                 .entries)
           entry.key: [...entry.value],
       };

  final SyncStoreMissingKind? missingKind;
  final Completer<void>? _storeReadGate;
  final List<String> devices;
  final List<String> storeEpochs;
  final SyncManifest? peerManifest;
  final Map<String, SyncManifest> peerManifests;
  final List<SyncHttpResponse> createResponses;
  final Map<String, List<SyncHttpResponse>> manifestResponses;
  final Map<String, SyncHttpResponse> blobResponses;
  final List<List<String>> missingResponses;
  final int putManifestStatus;
  final List<int> putManifestStatuses;
  final List<int> postMissingStatuses;
  final void Function(List<int> body)? onManifestPut;
  final Future<void> Function(String deviceId)? onManifestGet;
  final Future<void> Function(List<String> hashes)? onPostMissing;
  final firstStoreStarted = Completer<void>();
  final requestLog = <String>[];
  final manifestBodies = <List<int>>[];
  int storeCalls = 0;
  int createCalls = 0;
  int manifestCalls = 0;
  final manifestEtags = <String?>[];
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
    final epoch =
        storeEpochs[(storeCalls - 1) < storeEpochs.length
            ? storeCalls - 1
            : storeEpochs.length - 1];
    final response = _response(
      missingKind == null || storeCalls > 1 ? 200 : 404,
      body: jsonEncode({'epoch': epoch, 'devices': devices}),
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
    if (createResponses.isNotEmpty) return createResponses.removeAt(0);
    return _response(201);
  }

  @override
  Future<SyncHttpResponse> getManifest(String deviceId, {String? etag}) async {
    manifestCalls++;
    requestLog.add('manifest');
    manifestEtags.add(etag);
    await onManifestGet?.call(deviceId);
    final scripted = manifestResponses[deviceId];
    if (scripted != null && scripted.isNotEmpty) {
      return scripted.removeAt(0);
    }
    final manifest = peerManifests[deviceId] ?? peerManifest;
    return _response(
      200,
      body: manifest == null
          ? null
          : utf8.decode(encodeSyncManifestUtf8(manifest)),
    );
  }

  @override
  Future<SyncHttpResponse> putManifest(String deviceId, List<int> body) async {
    manifestPuts++;
    requestLog.add('manifest-put');
    manifestBodies.add(body);
    onManifestPut?.call(body);
    final status = putManifestStatuses.isNotEmpty
        ? putManifestStatuses.removeAt(0)
        : putManifestStatus;
    return _response(status);
  }

  @override
  Future<SyncHttpResponse> postMissing(Iterable<String> hashes) async {
    final batch = hashes.toList(growable: false);
    postMissingBatches.add(batch);
    postMissingCalls++;
    requestLog.add('missing');
    await onPostMissing?.call(batch);
    final response = missingResponses.length >= postMissingCalls
        ? missingResponses[postMissingCalls - 1]
        : const <String>[];
    final status = postMissingStatuses.isNotEmpty
        ? postMissingStatuses.removeAt(0)
        : 200;
    return _response(status, body: jsonEncode({'missing': response}));
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

  static SyncHttpResponse _response(
    int status, {
    String? body,
    Map<String, String> headers = const {},
  }) => SyncHttpResponse(
    statusCode: status,
    kind: switch (status) {
      200 => SyncResponseKind.success,
      201 => SyncResponseKind.created,
      404 => SyncResponseKind.notFound,
      409 => SyncResponseKind.conflict,
      500 => SyncResponseKind.serverError,
      _ => SyncResponseKind.unexpectedStatus,
    },
    headers: headers,
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

List<SyncRecordAddress> _manifestAddresses(SyncManifest manifest) => [
  for (final kindEntry in manifest.records.entries)
    for (final recordId in kindEntry.value.keys)
      (kind: kindEntry.key, recordId: recordId),
];

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

SyncRecordBlob _dance(String id, {required DateTime updatedAt}) =>
    SyncRecordBlob(
      kind: SyncRecordKind.dance,
      id: id,
      updatedAt: updatedAt,
      deletedAt: null,
      existenceAt: updatedAt,
      body: {
        'id': id,
        'title': 'Dance',
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': null,
      },
    );

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
