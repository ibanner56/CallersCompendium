import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  // Passes that reach a real `CompendiumSyncCoordinatorStore` mark identities
  // used; run the PBKDF2 derivation at a lowered count (the real one is pinned
  // in compendium_core's sync_identity_kdf_test.dart).
  final productionKdfIterations = syncIdentityKdfIterations;
  setUpAll(() => syncIdentityKdfIterations = 1000);
  tearDownAll(() => syncIdentityKdfIterations = productionKdfIterations);

  test('isolated peer cache namespaces peer ids from diagnostic fields', () {
    final peerManifest = _manifest(deviceId: 'peer', records: const {});
    final diagnosticAddress = (
      kind: SyncRecordKind.setting,
      recordId: 'custom_dialects',
    );
    final publication = (hash: _hash('c'), pass: 3);
    final seen = [(writtenAt: DateTime.utc(2026, 7, 15, 13), pass: 4)];
    final cache = SyncPeerManifestCache(
      entries: {
        '_rejectedHashes': SyncPeerManifestCacheEntry(
          epoch: 'epoch-1',
          etag: '"peer"',
          manifest: peerManifest,
        ),
        '_publications': SyncPeerManifestCacheEntry(
          epoch: 'epoch-1',
          etag: '"diagnostic"',
          manifest: peerManifest,
        ),
      },
      rejectedHashes: {'rejected-hash'},
      publications: {diagnosticAddress: publication},
      peerPublications: {'_publications': seen},
      passSequence: 4,
      publicationEpoch: 'epoch-1',
    );

    final restored = SyncPeerManifestCache.fromMessage(cache.toMessage());

    expect(restored['_rejectedHashes']?.etag, '"peer"');
    expect(restored['_publications']?.etag, '"diagnostic"');
    expect(restored.rejectedHashes, {'rejected-hash'});
    expect(restored.publications, {diagnosticAddress: publication});
    expect(restored.peerPublications, {'_publications': seen});
    expect(restored.passSequence, 4);
    expect(restored.publicationEpoch, 'epoch-1');

    restored.beginPublicationEpoch('epoch-1');
    expect(restored.publications, {diagnosticAddress: publication});
    restored.beginPublicationEpoch('epoch-2');
    expect(restored.publications, isEmpty);
    expect(restored.peerPublications, isEmpty);
  });

  test('restarts the unreflected-publication evidence when the store epoch '
      'changes', () async {
    final candidate = SyncMergeCandidate.fromBlob(
      _setting('custom_dialects', 'local'),
    );
    final cache = SyncPeerManifestCache(
      publications: {candidate.address: (hash: candidate.wireHash, pass: 1)},
      peerPublications: {
        'peer': [
          (writtenAt: DateTime.utc(2026, 7, 15, 11, 30), pass: 2),
          (writtenAt: DateTime.utc(2026, 7, 15, 11, 45), pass: 3),
        ],
      },
      passSequence: 3,
      publicationEpoch: 'epoch-old',
    );
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(local: {candidate.address: candidate}),
      transport: _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(deviceId: 'peer', records: const {}),
      ),
      peerManifestCache: cache,
      now: () => DateTime.utc(2026, 7, 15, 12, 30),
    );
    addTearDown(coordinator.dispose);

    final result = await coordinator.syncNow();

    expect(
      result.reports.map((report) => report.code),
      isNot(contains(SyncReportCode.unreflectedPublication)),
      reason:
          'the two later publications were seen in another epoch, so they '
          'say nothing about this one',
    );
    expect(cache.publications[candidate.address]?.pass, 4);
    expect(cache.peerPublications['peer'], [
      (writtenAt: DateTime.utc(2026, 7, 15, 12), pass: 4),
    ]);
  });

  group('per-peer reflection (spec §6.9)', () {
    final t0 = DateTime.utc(2026, 7, 15, 12);
    late SyncMergeCandidate candidate;
    late SyncMergeCandidate other;

    setUp(() {
      candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      other = SyncMergeCandidate.fromBlob(
        _setting('shorthand_mappings', 'local'),
      );
    });

    SyncManifest peerAt(
      DateTime writtenAt, {
      Map<SyncRecordKind, Map<String, String>> records = const {},
    }) => SyncManifest(
      deviceId: 'peer',
      epoch: 'epoch-1',
      writtenAt: writtenAt,
      records: records,
    );

    /// Runs one pass per step: the peer's manifest as written at
    /// `step.peerWrittenAt`, with this device's clock at `step.clock`.
    Future<List<SyncPassResult>> passes(
      List<({DateTime peerWrittenAt, DateTime clock})> steps, {
      Map<SyncRecordKind, Map<String, String>> peerRecords = const {},
      Map<String, SyncHttpResponse> blobResponses = const {},
    }) async {
      final local = {candidate.address: candidate, other.address: other};
      final peers = <String, SyncManifest>{};
      var clock = t0;
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(
          local: local,
          snapshotBuilder: (_) => SyncCoordinatorSnapshot(
            epoch: 'epoch-1',
            previouslyUsed: false,
            local: local,
            publication: local,
            baseline: const {},
          ),
        ),
        transport: _FakeTransport(
          devices: ['device-a', 'peer'],
          peerManifests: peers,
          blobResponses: blobResponses,
        ),
        now: () => clock,
      );
      addTearDown(coordinator.dispose);
      final results = <SyncPassResult>[];
      for (final step in steps) {
        peers['peer'] = peerAt(step.peerWrittenAt, records: peerRecords);
        clock = step.clock;
        final result = await coordinator.syncNow();
        expect(result.status, SyncPassStatus.completed);
        results.add(result);
      }
      return results;
    }

    Iterable<SyncReport> unreflected(SyncPassResult result) =>
        result.reports.where(
          (report) => report.code == SyncReportCode.unreflectedPublication,
        );

    test('a peer that has not published since is asleep: never a notice, '
        'and the summary counts what is waiting for it', () async {
      final asleepAt = t0.subtract(const Duration(hours: 1));
      final results = await passes(
        [
          for (var minute = 0; minute < 5; minute++)
            (peerWrittenAt: asleepAt, clock: t0.add(Duration(minutes: minute))),
        ],
        peerRecords: {
          SyncRecordKind.setting: {'shorthand_mappings': other.wireHash},
        },
      );

      for (final result in results) {
        expect(unreflected(result), isEmpty);
      }
      final summary = results.last.peers!.single;
      expect(summary.peerId, 'peer');
      expect(summary.writtenAt, asleepAt);
      expect(
        summary.waitingCount,
        1,
        reason: 'the peer carries one of the two records at this hash',
      );
    });

    test('a peer that published twice since without the record is named as '
        'not taking it', () async {
      final results = await passes([
        (peerWrittenAt: t0.subtract(const Duration(hours: 1)), clock: t0),
        (
          peerWrittenAt: t0.add(const Duration(minutes: 1)),
          clock: t0.add(const Duration(minutes: 2)),
        ),
        (
          peerWrittenAt: t0.add(const Duration(minutes: 3)),
          clock: t0.add(const Duration(minutes: 4)),
        ),
      ]);

      expect(unreflected(results[0]), isEmpty);
      expect(
        unreflected(results[1]),
        isEmpty,
        reason:
            'one publication since can be a pass that started before this '
            'device published and never read its manifest',
      );
      final reports = unreflected(results[2]).toList();
      expect(
        {for (final report in reports) report.recordId},
        {'custom_dialects', 'shorthand_mappings'},
      );
      expect(reports.map((report) => report.peerId).toSet(), {
        'peer',
      }, reason: 'the notice names the device by its tag, so it needs the id');
      expect(results[2].peers!.single.waitingCount, 2);
    });

    test('a peer whose clock runs fast is not judged on what it wrote before '
        'this device published', () async {
      final results = await passes([
        (peerWrittenAt: t0.add(const Duration(hours: 1)), clock: t0),
        (
          peerWrittenAt: t0.add(const Duration(hours: 2)),
          clock: t0.add(const Duration(minutes: 1)),
        ),
        (
          peerWrittenAt: t0.add(const Duration(hours: 3)),
          clock: t0.add(const Duration(minutes: 2)),
        ),
      ]);

      expect(
        unreflected(results[1]),
        isEmpty,
        reason:
            'the first manifest was fetched before this device published, '
            'however late its clock says it was written',
      );
      expect(unreflected(results[2]), isNotEmpty);
    });

    test('a device whose own clock runs fast is still told its changes are '
        'not being taken', () async {
      // The case §6.9 introduced this signal for: peers refuse this device's
      // records as future-dated, and every `writtenAt` they write is earlier
      // than this device's idea of now. A judgement that compared the two
      // clocks would never fire here.
      final fast = t0.add(const Duration(days: 3));
      final results = await passes([
        (peerWrittenAt: t0.subtract(const Duration(hours: 1)), clock: fast),
        (
          peerWrittenAt: t0.add(const Duration(minutes: 1)),
          clock: fast.add(const Duration(minutes: 2)),
        ),
        (
          peerWrittenAt: t0.add(const Duration(minutes: 3)),
          clock: fast.add(const Duration(minutes: 4)),
        ),
      ]);

      expect(unreflected(results[1]), isEmpty);
      expect(unreflected(results[2]), isNotEmpty);
    });

    test('a peer holding a newer version of the record is not refusing '
        'it', () async {
      final newer = _setting('custom_dialects', 'theirs', seconds: 30);
      final newerCandidate = SyncMergeCandidate.fromBlob(newer);
      final results = await passes(
        [
          (peerWrittenAt: t0.subtract(const Duration(hours: 1)), clock: t0),
          (
            peerWrittenAt: t0.add(const Duration(minutes: 1)),
            clock: t0.add(const Duration(minutes: 2)),
          ),
          (
            peerWrittenAt: t0.add(const Duration(minutes: 3)),
            clock: t0.add(const Duration(minutes: 4)),
          ),
        ],
        peerRecords: {
          SyncRecordKind.setting: {
            'custom_dialects': newerCandidate.wireHash,
            'shorthand_mappings': other.wireHash,
          },
        },
        blobResponses: {
          newerCandidate.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(newer)),
          ),
        },
      );

      expect(
        unreflected(results[2]),
        isEmpty,
        reason:
            'a disagreement is resolving towards the peer, or has a notice '
            'of its own; "it may need an app update" would be false',
      );
    });

    test('a peer holding an older edit of the record is refusing it, though '
        'an edit leaves existenceAt where it was', () async {
      // An ordinary content edit advances `updatedAt` and leaves
      // `existenceAt` alone, so the peer's stale copy shares this device's
      // `existenceAt`. Equal is not newer. A choreographer, not a setting:
      // a whole-collection setting that differs is a queued conflict choice,
      // which is judged neither asleep nor refusing.
      final edited = _choreographer(
        'author-1',
        'Edited name',
        updatedAt: t0.add(const Duration(seconds: 30)),
        existenceAt: t0,
      );
      candidate = SyncMergeCandidate.fromBlob(edited);
      final stale = _choreographer('author-1', 'Old name', updatedAt: t0);
      final staleCandidate = SyncMergeCandidate.fromBlob(stale);
      expect(staleCandidate.existenceAt, candidate.existenceAt);
      final results = await passes(
        [
          (peerWrittenAt: t0.subtract(const Duration(hours: 1)), clock: t0),
          (
            peerWrittenAt: t0.add(const Duration(minutes: 1)),
            clock: t0.add(const Duration(minutes: 2)),
          ),
          (
            peerWrittenAt: t0.add(const Duration(minutes: 3)),
            clock: t0.add(const Duration(minutes: 4)),
          ),
        ],
        peerRecords: {
          SyncRecordKind.choreographer: {'author-1': staleCandidate.wireHash},
          SyncRecordKind.setting: {'shorthand_mappings': other.wireHash},
        },
        blobResponses: {
          staleCandidate.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(stale)),
          ),
        },
      );

      expect(unreflected(results[2]).map((report) => report.recordId), [
        'author-1',
      ]);
    });

    test('zero observed peers judges nothing and is an empty survey, not '
        'a missing one', () async {
      var clock = t0;
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(local: {candidate.address: candidate}),
        transport: _FakeTransport(devices: ['device-a']),
        now: () => clock,
      );
      addTearDown(coordinator.dispose);

      for (var minute = 0; minute < 4; minute++) {
        clock = t0.add(Duration(minutes: minute));
        final result = await coordinator.syncNow();
        expect(unreflected(result), isEmpty);
        expect(result.peers, isEmpty);
        expect(result.peers, isNotNull);
      }
    });
  });

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

  test('normalisation resolves aliases from one aliasMap per step', () async {
    Future<int> aliasMapLoads(int aliased) async {
      final locals = <SyncRecordAddress, SyncMergeCandidate?>{};
      final baseline = <SyncRecordAddress, SyncBaselineEntry>{};
      final aliases = <SyncRecordAddress, SyncRecordAddress>{};
      for (var i = 0; i < aliased; i++) {
        final candidate = SyncMergeCandidate.fromBlob(
          _tag('canonical-$i', 'Tag $i'),
        );
        final legacy = (kind: SyncRecordKind.tag, recordId: 'legacy-$i');
        locals[candidate.address] = candidate;
        baseline[legacy] = SyncBaselineEntry(
          kind: legacy.kind,
          recordId: legacy.recordId,
          wireHash: candidate.wireHash,
          bodyHash: candidate.bodyHash,
        );
        aliases[legacy] = candidate.address;
      }
      final store = _FakeStore(
        local: locals,
        baseline: baseline,
        aliases: aliases,
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: _FakeTransport(
          devices: ['peer'],
          peerManifest: _manifest(deviceId: 'peer', records: const {}),
        ),
      );
      addTearDown(coordinator.dispose);

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      return store.aliasMapCalls;
    }

    final few = await aliasMapLoads(3);
    final many = await aliasMapLoads(30);

    expect(few, greaterThan(0));
    // One load per normalisation call, however many addresses it resolves:
    // a per-item load would grow with the library.
    expect(many, few);
    // Independence from N cannot see a helper that loads twice per call, which
    // is still a constant. The count for this pass is exactly one load per
    // `_normalize*` / `_resolveReferenceAliases` call it makes, plus the one
    // the merge plan reads to compare references by the records they name
    // (15 on an empty peer manifest). A pass that gains or loses a
    // normalisation step changes it deliberately; update the number with the
    // step, never to absorb an extra load inside a helper.
    expect(few, 15);
  });

  group('a pass with nothing new to share (spec §6.3 steps 7 and 8)', () {
    late SyncMergeCandidate first;
    late SyncMergeCandidate second;
    late DateTime clock;

    setUp(() {
      first = SyncMergeCandidate.fromBlob(_setting('first', 'one'));
      second = SyncMergeCandidate.fromBlob(_setting('second', 'two'));
      clock = DateTime.utc(2026, 7, 15, 12, 30);
    });

    _FakeTransport transportFor(
      Iterable<SyncMergeCandidate> peerHolds, {
      List<String> devices = const ['device-a', 'peer'],
      List<int>? putManifestStatuses,
    }) => _FakeTransport(
      devices: devices,
      peerManifest: _manifest(
        deviceId: 'peer',
        records: {
          SyncRecordKind.setting: {
            for (final candidate in peerHolds)
              candidate.blob.id: candidate.wireHash,
          },
        },
      ),
      putManifestStatuses: putManifestStatuses,
    );

    SyncCoordinator coordinatorFor(
      _FakeStore store,
      _FakeTransport transport, {
      SyncPeerManifestCache? cache,
    }) {
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
        peerManifestCache: cache,
        now: () => clock,
      );
      addTearDown(coordinator.dispose);
      return coordinator;
    }

    test('sends neither the blob check nor the manifest again', () async {
      final store = _FakeStore(
        local: {first.address: first, second.address: second},
      );
      final transport = transportFor([first, second]);
      final coordinator = coordinatorFor(store, transport);

      expect((await coordinator.syncNow()).status, SyncPassStatus.completed);
      expect(transport.postMissingCalls, 1);
      expect(transport.manifestPuts, 1);
      expect(store.published?.record.verifiedAt, clock);

      clock = clock.add(const Duration(hours: 1));
      final again = await coordinator.syncNow();

      expect(again.status, SyncPassStatus.completed);
      expect(transport.postMissingCalls, 1, reason: 'nothing new to check');
      expect(transport.manifestPuts, 1, reason: 'nothing new to publish');
      expect(
        store.published?.record.verifiedAt,
        DateTime.utc(2026, 7, 15, 12, 30),
        reason: 'a pass that sends nothing confirms nothing',
      );
    });

    test('asks only about the blobs the last manifest did not name', () async {
      final store = _FakeStore(local: {first.address: first});
      final transport = transportFor([first]);
      final coordinator = coordinatorFor(store, transport);
      await coordinator.syncNow();
      final firstPublished = store.published!.record;

      store.local[second.address] = second;
      clock = clock.add(const Duration(hours: 1));
      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(transport.postMissingBatches, [
        [first.wireHash],
        [second.wireHash],
      ]);
      expect(transport.manifestPuts, 2);
      final manifest = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.last),
      );
      expect(manifest.records[SyncRecordKind.setting]!.keys, {
        'first',
        'second',
      });
      expect(store.published!.record.hash, isNot(firstPublished.hash));
      expect(
        store.published!.record.verifiedAt,
        firstPublished.verifiedAt,
        reason: 'the first blob was last confirmed by the first pass',
      );
    });

    test('checks and publishes everything once the interval passes', () async {
      final store = _FakeStore(local: {first.address: first});
      final transport = transportFor([first]);
      final coordinator = coordinatorFor(store, transport);
      await coordinator.syncNow();

      clock = clock.add(kSyncPublicationRefreshInterval);
      await coordinator.syncNow();

      expect(transport.postMissingBatches, [
        [first.wireHash],
        [first.wireHash],
      ]);
      expect(transport.manifestPuts, 2);
      expect(store.published!.record.verifiedAt, clock);
    });

    test('a clock set back does not stretch the interval', () async {
      final store = _FakeStore(local: {first.address: first});
      final transport = transportFor([first]);
      final coordinator = coordinatorFor(store, transport);
      await coordinator.syncNow();

      clock = clock.subtract(const Duration(minutes: 1));
      await coordinator.syncNow();

      expect(transport.manifestPuts, 2);
    });

    test('publishes again when the store no longer lists it', () async {
      // Another device removed this one (§5.3): its manifest is gone, and
      // nothing keeps its blobs from collection (§7.3).
      final store = _FakeStore(local: {first.address: first});
      final transport = transportFor([first], devices: const ['peer']);
      final coordinator = coordinatorFor(store, transport);
      await coordinator.syncNow();
      await coordinator.syncNow();

      expect(transport.postMissingCalls, 2);
      expect(transport.manifestPuts, 2);
    });

    test('a manifest whose PUT failed is published again in full', () async {
      final store = _FakeStore(local: {first.address: first});
      final transport = transportFor([first], putManifestStatuses: [200, 500]);
      final coordinator = coordinatorFor(store, transport);
      await coordinator.syncNow();

      store.local[second.address] = second;
      final failed = await coordinator.syncNow();
      expect(failed.status, SyncPassStatus.failed);
      expect(
        store.published,
        isNull,
        reason: 'the failed PUT may still have replaced the manifest',
      );

      store.local.remove(second.address);
      await coordinator.syncNow();

      expect(transport.manifestPuts, 3);
      expect(transport.postMissingBatches.last, [first.wireHash]);
    });

    test('a new session relies on the stored record, not its own', () async {
      final store = _FakeStore(local: {first.address: first});
      final transport = transportFor([first]);
      await coordinatorFor(store, transport).syncNow();

      // The app restarts: a new coordinator, and a cache that knows nothing.
      final restarted = coordinatorFor(
        store,
        transport,
        cache: SyncPeerManifestCache(),
      );
      await restarted.syncNow();
      expect(transport.postMissingCalls, 1);
      expect(transport.manifestPuts, 1);

      // What the unchanged pass learned is enough for the next change.
      store.local[second.address] = second;
      await restarted.syncNow();
      expect(transport.postMissingBatches.last, [second.wireHash]);
      expect(transport.manifestPuts, 2);
    });

    test('a changed manifest after a restart checks every blob', () async {
      final store = _FakeStore(local: {first.address: first});
      final transport = transportFor([first]);
      await coordinatorFor(store, transport).syncNow();
      final verifiedAt = store.published!.record.verifiedAt;

      store.local[second.address] = second;
      clock = clock.add(const Duration(hours: 1));
      await coordinatorFor(
        store,
        transport,
        cache: SyncPeerManifestCache(),
      ).syncNow();

      expect(transport.postMissingBatches.last, [
        first.wireHash,
        second.wireHash,
      ]);
      expect(store.published!.record.verifiedAt, isNot(verifiedAt));
      expect(store.published!.record.verifiedAt, clock);
    });

    test('a pass that cannot take a peer record still publishes', () async {
      // §6.9: a peer is judged to be refusing a record only once it has
      // published twice since, so a device refusing something must not go
      // quiet. Here the peer lists a record whose blob the store lacks.
      final missing = SyncMergeCandidate.fromBlob(_setting('gone', 'x'));
      final store = _FakeStore(local: {first.address: first});
      final transport = transportFor([first, missing]);
      final coordinator = coordinatorFor(store, transport);
      await coordinator.syncNow();
      final again = await coordinator.syncNow();

      expect(
        again.reports.map((report) => report.code),
        contains(SyncReportCode.unresolvedBlob),
      );
      expect(transport.manifestPuts, 2);
      expect(
        transport.postMissingCalls,
        1,
        reason: 'the blobs it already published are still known',
      );
    });

    test(
      'a pass that refused a peer record at apply still publishes',
      () async {
        // The peer's record downloads and is admitted, then storage refuses it
        // (here as an unresolved reference): refused all the same (§6.9).
        final peerOnly = SyncMergeCandidate.fromBlob(
          _setting('peer-only', 'p'),
        );
        final store = _FakeStore(local: {first.address: first})
          ..refuseWrite = (record) => record.address == peerOnly.address;
        final transport = _FakeTransport(
          devices: const ['device-a', 'peer'],
          peerManifest: _manifest(
            deviceId: 'peer',
            records: {
              SyncRecordKind.setting: {
                first.blob.id: first.wireHash,
                peerOnly.blob.id: peerOnly.wireHash,
              },
            },
          ),
          blobResponses: _blobs([peerOnly]),
        );
        final coordinator = coordinatorFor(store, transport);
        await coordinator.syncNow();
        final again = await coordinator.syncNow();

        expect(
          again.reports.map((report) => report.code),
          contains(SyncReportCode.unresolvedReference),
        );
        expect(store.writes, isEmpty);
        expect(transport.manifestPuts, 2);
      },
    );

    test('a stale-epoch PUT leaves nothing recorded', () async {
      final store = _FakeStore(local: {first.address: first});
      final transport = transportFor([first], putManifestStatuses: [200, 409]);
      final coordinator = coordinatorFor(store, transport);
      await coordinator.syncNow();

      store.local[second.address] = second;
      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.staleEpoch);
      expect(store.published, isNull);
      expect(store.publishedWrites.last, isNull);
    });

    test('a PUT that throws leaves nothing recorded', () async {
      final store = _FakeStore(local: {first.address: first});
      var puts = 0;
      final transport = _FakeTransport(
        devices: const ['device-a', 'peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.setting: {first.blob.id: first.wireHash},
          },
        ),
        onManifestPut: (_) {
          if (++puts == 2) throw const SocketException('reset');
        },
      );
      final coordinator = coordinatorFor(store, transport);
      await coordinator.syncNow();

      store.local[second.address] = second;
      await expectLater(coordinator.syncNow(), throwsA(isA<SocketException>()));

      expect(puts, 2);
      expect(store.published, isNull);
    });

    test('a fresh attach records what its continuation published', () async {
      final store = _FakeStore(epoch: null, local: {first.address: first});
      final transport = transportFor([first]);
      final coordinator = coordinatorFor(store, transport);

      expect((await coordinator.syncNow()).status, SyncPassStatus.completed);
      expect(store.baselineReplacements, 1);
      expect(
        store.published,
        isNotNull,
        reason: 'recorded after the baseline that starts the epoch',
      );

      final puts = transport.manifestPuts;
      await coordinator.syncNow();
      expect(transport.manifestPuts, puts);
    });

    test('what it knows crosses the isolate boundary', () {
      final cache = SyncPeerManifestCache(
        ownManifest: (hash: 'manifest', blobHashes: {first.wireHash}),
      );

      final copy = SyncPeerManifestCache.fromMessage(cache.toMessage());

      expect(copy.ownManifest?.hash, 'manifest');
      expect(copy.ownManifest?.blobHashes, {first.wireHash});
      expect(
        SyncPeerManifestCache.fromMessage(
          SyncPeerManifestCache().toMessage(),
        ).ownManifest,
        isNull,
      );
    });
  });

  group('records this device already holds (spec §6.3 step 5)', () {
    test(
      'an imported dance kept back from publication is not downloaded',
      () async {
        final imported = SyncMergeCandidate.fromBlob(
          _dance('imported', updatedAt: DateTime.utc(2026, 7, 15, 12)),
        );
        final store = _FakeStore(
          snapshotBuilder: (_) => SyncCoordinatorSnapshot(
            epoch: 'epoch-1',
            previouslyUsed: false,
            local: {imported.address: imported},
            baseline: const {},
            // `sync_exclude_imports` withholds it from publication only.
            publication: {imported.address: null},
          ),
        );
        final transport = _FakeTransport(
          devices: ['peer'],
          peerManifest: _manifest(
            deviceId: 'peer',
            records: {
              SyncRecordKind.dance: {'imported': imported.wireHash},
            },
          ),
          blobResponses: _blobs([imported]),
        );
        final coordinator = SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device-a',
          store: store,
          transport: transport,
        );
        addTearDown(coordinator.dispose);

        final result = await coordinator.syncNow();

        expect(result.status, SyncPassStatus.completed);
        expect(transport.blobHashes, isEmpty);
        expect(transport.batchRequests, isEmpty);
      },
    );

    test('the live row behind a pending tombstone is not downloaded', () async {
      final updatedAt = DateTime.utc(2026, 7, 15, 12);
      final live = SyncMergeCandidate.fromBlob(
        _dance('deleted', updatedAt: updatedAt),
      );
      final tombstone = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: SyncRecordKind.dance,
          id: 'deleted',
          updatedAt: updatedAt,
          deletedAt: updatedAt.add(const Duration(minutes: 5)),
          existenceAt: updatedAt.add(const Duration(minutes: 5)),
          body: live.blob.body,
        ),
      );
      final store = _FakeStore(
        snapshotBuilder: (_) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: const {},
          baseline: const {},
          publication: {tombstone.address: tombstone},
          pendingLive: {live.address: live},
          pending: {live.address},
        ),
      );
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.dance: {'deleted': live.wireHash},
          },
        ),
        blobResponses: _blobs([live]),
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );
      addTearDown(coordinator.dispose);

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(transport.blobHashes, isEmpty);
      expect(transport.batchRequests, isEmpty);
    });
  });

  group('SyncAliasMap resolves as the repository does', () {
    const kind = SyncRecordKind.dance;

    Future<SyncAliasMap> loaded(
      CompendiumRepositories repositories,
      List<(String, String)> links,
    ) async {
      for (final (losing, surviving) in links) {
        await repositories.syncLocal.upsertAlias(
          kind: kind,
          losingId: losing,
          survivingId: surviving,
        );
      }
      return CompendiumSyncCoordinatorStore(repositories).aliasMap();
    }

    test('follows a chain to the surviving id', () async {
      final repositories = openTestRepositories();
      final aliases = await loaded(repositories, [('a', 'b'), ('b', 'c')]);

      for (final id in ['a', 'b', 'c', 'unaliased']) {
        expect(
          aliases.resolve((kind: kind, recordId: id)).recordId,
          await repositories.syncLocal.resolveAlias(kind: kind, recordId: id),
          reason: id,
        );
      }
      expect(aliases.resolve((kind: kind, recordId: 'a')).recordId, 'c');
    });

    test('does not resolve across record kinds', () async {
      final repositories = openTestRepositories();
      final aliases = await loaded(repositories, [('a', 'b')]);

      expect(aliases.resolve((kind: SyncRecordKind.tag, recordId: 'a')), (
        kind: SyncRecordKind.tag,
        recordId: 'a',
      ));
    });

    test('throws a StateError on a cycle, like resolveAlias', () async {
      final repositories = openTestRepositories();
      final aliases = await loaded(repositories, [('a', 'b'), ('b', 'a')]);

      await expectLater(
        repositories.syncLocal.resolveAlias(kind: kind, recordId: 'a'),
        throwsStateError,
      );
      expect(
        () => aliases.resolve((kind: kind, recordId: 'a')),
        throwsStateError,
      );
    });

    test('a cycle only fails the addresses whose chain reaches it', () async {
      final repositories = openTestRepositories();
      final aliases = await loaded(repositories, [
        ('a', 'b'),
        ('b', 'a'),
        ('x', 'y'),
      ]);

      expect(
        await repositories.syncLocal.resolveAlias(kind: kind, recordId: 'x'),
        'y',
      );
      expect(aliases.resolve((kind: kind, recordId: 'x')).recordId, 'y');
    });
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

      // Quarantine, not malformation: the peer blob is well formed, its clock
      // is implausible. The "once" coalescing is what this test is about.
      expect(
        first.reports.where((r) => r.code == SyncReportCode.quarantinedRecord),
        [isNotNull],
      );
      expect(
        second.reports.where((r) => r.code == SyncReportCode.quarantinedRecord),
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
        dependent.wireHash,
      );
    },
  );

  test('does not report a quarantined fallback hash as unreflected', () async {
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
    final store = _FakeStore(
      snapshotBuilder: (_) => SyncCoordinatorSnapshot(
        epoch: 'epoch-1',
        previouslyUsed: false,
        local: {root.address: root},
        publication: {root.address: root},
        baseline: {
          root.address: SyncBaselineEntry(
            kind: root.address.kind,
            recordId: root.address.recordId,
            wireHash: _hash('a'),
          ),
        },
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
      now: () => now,
    );
    addTearDown(coordinator.dispose);

    final results = [
      await coordinator.syncNow(),
      await coordinator.syncNow(),
      await coordinator.syncNow(),
    ];

    expect(
      results.expand((result) => result.reports).map((report) => report.code),
      isNot(contains(SyncReportCode.unreflectedPublication)),
    );
  });

  test('surfaces a record the snapshot withheld as unreadable', () async {
    // The core half of #1347 puts the report on the snapshot; this is the half
    // that gets it to the user. Without the drain in `_runPass` the snapshot
    // carries the report and the pass result does not, which is exactly the
    // silence this change removes.
    final now = DateTime.utc(2026, 7, 15, 12);
    const withheld = SyncReport(
      code: SyncReportCode.withheldUnreadableRecord,
      kind: SyncRecordKind.dance,
      recordId: 'd1',
      message: 'Dance withheld from publication.',
    );
    final store = _FakeStore(
      snapshotBuilder: (_) => SyncCoordinatorSnapshot(
        epoch: 'epoch-1',
        previouslyUsed: false,
        local: const {},
        publication: const {},
        baseline: const {},
        withheld: const [withheld],
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
      now: () => now,
    );
    addTearDown(coordinator.dispose);

    final result = await coordinator.syncNow();

    expect(
      result.reports
          .where(
            (report) => report.code == SyncReportCode.withheldUnreadableRecord,
          )
          .map((report) => report.recordId),
      ['d1'],
      reason:
          'reported exactly once: a pass takes the snapshot several times and '
          'the sink coalesces on the record, so re-snapshots must not become '
          'repeats to the user',
    );
  });

  test(
    'uses alias-normalized peer candidates for reflection diagnostics',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _tag('legacy', 'Shared tag'),
      );
      final legacy = candidate.address;
      final canonical = (kind: SyncRecordKind.tag, recordId: 'canonical');
      final store = _FakeStore(
        aliases: {legacy: canonical},
        snapshotBuilder: (_) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: {legacy: candidate},
          publication: {legacy: candidate},
          baseline: const {},
        ),
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: _FakeTransport(
          devices: ['peer'],
          peerManifest: _manifest(
            deviceId: 'peer',
            records: {
              SyncRecordKind.tag: {legacy.recordId: candidate.wireHash},
            },
          ),
        ),
        now: () => DateTime.utc(2026, 7, 15, 12),
      );
      addTearDown(coordinator.dispose);

      final results = [
        await coordinator.syncNow(),
        await coordinator.syncNow(),
        await coordinator.syncNow(),
      ];

      expect(
        results.expand((result) => result.reports).map((report) => report.code),
        isNot(contains(SyncReportCode.unreflectedPublication)),
      );
    },
  );

  test(
    'normalizes aliased dependency references before fallback publication',
    () async {
      final now = DateTime.utc(2026, 7, 15, 12);
      final root = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: SyncRecordKind.choreographer,
          id: 'canonical-author',
          updatedAt: now.add(const Duration(hours: 25)),
          deletedAt: null,
          existenceAt: now,
          body: const {'id': 'canonical-author', 'name': 'Author'},
        ),
      );
      final dependent = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: SyncRecordKind.dance,
          id: 'dance-aliased-author',
          updatedAt: now,
          deletedAt: null,
          existenceAt: now,
          body: const {
            'id': 'dance-aliased-author',
            'title': 'Dance',
            'authorIds': ['legacy-author'],
          },
        ),
      );
      final legacy = (
        kind: SyncRecordKind.choreographer,
        recordId: 'legacy-author',
      );
      final store = _FakeStore(
        aliases: {legacy: root.address},
        snapshotBuilder: (_) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: {root.address: root, dependent.address: dependent},
          publication: {root.address: root, dependent.address: dependent},
          baseline: {
            root.address: SyncBaselineEntry(
              kind: root.address.kind,
              recordId: root.address.recordId,
              wireHash: _hash('a'),
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
      final published = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.single),
      );
      expect(
        published.records[SyncRecordKind.choreographer]?[root.blob.id],
        _hash('a'),
      );
      expect(
        published.records[SyncRecordKind.dance]?[dependent.blob.id],
        dependent.wireHash,
      );
    },
  );

  test(
    'counts dependents held by a quarantined record without a fallback',
    () async {
      final now = DateTime.utc(2026, 7, 15, 12);
      final root = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: SyncRecordKind.choreographer,
          id: 'author-without-baseline',
          updatedAt: now.add(const Duration(hours: 25)),
          deletedAt: null,
          existenceAt: now,
          body: const {'id': 'author-without-baseline', 'name': 'Author'},
        ),
      );
      final dependent = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: SyncRecordKind.dance,
          id: 'dance-withheld',
          updatedAt: now,
          deletedAt: null,
          existenceAt: now,
          body: const {
            'id': 'dance-withheld',
            'title': 'Dance',
            'authorIds': ['author-without-baseline'],
          },
        ),
      );
      final store = _FakeStore(
        snapshotBuilder: (_) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: {root.address: root, dependent.address: dependent},
          publication: {root.address: root, dependent.address: dependent},
          baseline: const {},
        ),
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: _FakeTransport(),
        now: () => now,
      );
      addTearDown(coordinator.dispose);

      final result = await coordinator.syncNow();

      final quarantineReports = result.reports.where(
        (report) => report.code == SyncReportCode.quarantinedRecord,
      );
      expect(quarantineReports, hasLength(1));
      expect(
        quarantineReports.single.message,
        contains('1 database-FK dependent'),
      );
    },
  );

  test(
    'resolves an address from the peers that did not send it out of window',
    () async {
      final now = DateTime.utc(2026, 7, 15, 12);
      final validRoot = SyncMergeCandidate.fromBlob(
        _choreographer('author-r', 'In window', updatedAt: now),
      );
      final futureRoot = SyncMergeCandidate.fromBlob(
        _choreographer(
          'author-r',
          'Out of window',
          updatedAt: now.add(const Duration(hours: 25)),
        ),
      );
      final dependent = SyncMergeCandidate.fromBlob(
        _danceCiting('dance-d', 'author-r', updatedAt: now),
      );
      final transport = _FakeTransport(
        devices: ['peer-b', 'peer-c'],
        peerManifests: {
          'peer-b': _manifest(
            deviceId: 'peer-b',
            records: {
              SyncRecordKind.choreographer: {'author-r': validRoot.wireHash},
              SyncRecordKind.dance: {'dance-d': dependent.wireHash},
            },
          ),
          'peer-c': _manifest(
            deviceId: 'peer-c',
            records: {
              SyncRecordKind.choreographer: {'author-r': futureRoot.wireHash},
              SyncRecordKind.dance: {'dance-d': dependent.wireHash},
            },
          ),
        },
        blobResponses: _blobs([validRoot, futureRoot, dependent]),
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

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      // Peer C's copy is refused; peer B's valid copy still resolves, and so
      // does the dance citing it. §6.9 refuses the blob, not the address.
      final written = {
        for (final write in store.writes) write.address: write.body,
      };
      expect(written.keys, contains(validRoot.address));
      expect(written[validRoot.address]?['name'], 'In window');
      expect(written.keys, contains(dependent.address));
      final quarantined = result.reports
          .where((report) => report.code == SyncReportCode.quarantinedRecord)
          .toList();
      expect(quarantined, hasLength(1));
      expect(quarantined.single.peerId, 'peer-c');
      expect(quarantined.single.recordId, 'author-r');
    },
  );

  test(
    'an address every peer sent out of window is still not downloaded',
    () async {
      final now = DateTime.utc(2026, 7, 15, 12);
      final futureRoot = SyncMergeCandidate.fromBlob(
        _choreographer(
          'author-r',
          'Out of window',
          updatedAt: now.add(const Duration(hours: 25)),
        ),
      );
      final transport = _FakeTransport(
        devices: ['peer-c'],
        peerManifest: _manifest(
          deviceId: 'peer-c',
          records: {
            SyncRecordKind.choreographer: {'author-r': futureRoot.wireHash},
          },
        ),
        blobResponses: _blobs([futureRoot]),
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

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(store.writes, isEmpty);
      final quarantined = result.reports.where(
        (report) => report.code == SyncReportCode.quarantinedRecord,
      );
      expect(quarantined, hasLength(1));
      expect(quarantined.single.peerId, 'peer-c');
    },
  );

  test(
    'a held address still resolves from the peers that sent it in window',
    () async {
      final now = DateTime.utc(2026, 7, 15, 12);
      final held = SyncMergeCandidate.fromBlob(
        _choreographer('author-r', 'Held locally', updatedAt: now),
      );
      final newer = SyncMergeCandidate.fromBlob(
        _choreographer(
          'author-r',
          'Newer on B',
          updatedAt: now.add(const Duration(hours: 1)),
        ),
      );
      final future = SyncMergeCandidate.fromBlob(
        _choreographer(
          'author-r',
          'Out of window',
          updatedAt: now.add(const Duration(hours: 25)),
        ),
      );
      final store = _FakeStore(
        local: {held.address: held},
        baseline: {
          held.address: SyncBaselineEntry(
            kind: held.address.kind,
            recordId: held.address.recordId,
            wireHash: held.wireHash,
          ),
        },
      );
      final transport = _FakeTransport(
        devices: ['peer-b', 'peer-c'],
        peerManifests: {
          'peer-b': _manifest(
            deviceId: 'peer-b',
            records: {
              SyncRecordKind.choreographer: {'author-r': newer.wireHash},
            },
          ),
          'peer-c': _manifest(
            deviceId: 'peer-c',
            records: {
              SyncRecordKind.choreographer: {'author-r': future.wireHash},
            },
          ),
        },
        blobResponses: _blobs([held, newer, future]),
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
      // The mirror of the test above: this path was already correct, and a
      // peer-side exclusion that ignored whether the device holds the record
      // would break it.
      expect(store.writes.map((write) => write.address), [newer.address]);
      expect(store.writes.single.body['name'], 'Newer on B');
    },
  );

  test('applies a peer edit to a dependent of a quarantined root', () async {
    final now = DateTime.utc(2026, 7, 15, 12);
    final root = SyncMergeCandidate.fromBlob(
      _choreographer(
        'author-x',
        'Author',
        updatedAt: now.add(const Duration(hours: 25)),
        existenceAt: now,
      ),
    );
    final dependent = SyncMergeCandidate.fromBlob(
      _danceCiting('dance-d', 'author-x', updatedAt: now),
    );
    final peerDependent = SyncMergeCandidate.fromBlob(
      _danceCiting(
        'dance-d',
        'author-x',
        updatedAt: now.add(const Duration(hours: 1)),
        title: 'Edited on B',
      ),
    );
    final store = _FakeStore(
      local: {root.address: root, dependent.address: dependent},
      baseline: {
        root.address: SyncBaselineEntry(
          kind: root.address.kind,
          recordId: root.address.recordId,
          wireHash: _hash('a'),
        ),
        dependent.address: SyncBaselineEntry(
          kind: dependent.address.kind,
          recordId: dependent.address.recordId,
          wireHash: dependent.wireHash,
        ),
      },
    );
    final transport = _FakeTransport(
      devices: ['peer-b'],
      peerManifest: _manifest(
        deviceId: 'peer-b',
        records: {
          SyncRecordKind.dance: {'dance-d': peerDependent.wireHash},
        },
      ),
      blobResponses: _blobs([peerDependent]),
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
    // §6.3 excludes the quarantined record, not everything citing it: the
    // dance keeps receiving inbound decisions while the root sits out.
    expect(store.writes.map((write) => write.address), [dependent.address]);
    expect(store.writes.single.body['title'], 'Edited on B');
    final published = decodeSyncManifest(
      utf8.decode(transport.manifestBodies.single),
    );
    expect(
      published.records[SyncRecordKind.choreographer]?['author-x'],
      _hash('a'),
    );
  });

  test('keeps a quarantined root out of the merge after repair fails', () async {
    final now = DateTime.utc(2026, 7, 15, 12);
    final root = SyncMergeCandidate.fromBlob(
      _choreographer(
        'author-x',
        'Local body',
        updatedAt: now.add(const Duration(hours: 25)),
        existenceAt: now,
      ),
    );
    // In window, so repair considers it, but a different body under a non-null
    // baseline takes the "do not stamp a different body over it" branch, which
    // leaves the root quarantined for the merge that follows.
    final peerRoot = SyncMergeCandidate.fromBlob(
      _choreographer('author-x', 'Peer body', updatedAt: now),
    );
    final store = _FakeStore(
      local: {root.address: root},
      baseline: {
        root.address: SyncBaselineEntry(
          kind: root.address.kind,
          recordId: root.address.recordId,
          wireHash: _hash('a'),
        ),
      },
    );
    final transport = _FakeTransport(
      devices: ['peer-b'],
      peerManifest: _manifest(
        deviceId: 'peer-b',
        records: {
          SyncRecordKind.choreographer: {'author-x': peerRoot.wireHash},
        },
      ),
      blobResponses: _blobs([peerRoot]),
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
    expect(store.writes, isEmpty);
    final quarantined = result.reports.where(
      (report) =>
          report.code == SyncReportCode.quarantinedRecord &&
          report.peerId == null,
    );
    expect(quarantined, hasLength(1));
    expect(quarantined.single.recordId, 'author-x');
  });

  test(
    'a dependent withheld from publication still receives a peer edit',
    () async {
      final now = DateTime.utc(2026, 7, 15, 12);
      final root = SyncMergeCandidate.fromBlob(
        _choreographer(
          'author-x',
          'Author',
          updatedAt: now.add(const Duration(hours: 25)),
          existenceAt: now,
        ),
      );
      final dependent = SyncMergeCandidate.fromBlob(
        _danceCiting('dance-d', 'author-x', updatedAt: now),
      );
      final peerDependent = SyncMergeCandidate.fromBlob(
        _danceCiting(
          'dance-d',
          'author-x',
          updatedAt: now.add(const Duration(hours: 1)),
          title: 'Edited on B',
        ),
      );
      final store = _FakeStore(
        local: {root.address: root, dependent.address: dependent},
        baseline: {
          dependent.address: SyncBaselineEntry(
            kind: dependent.address.kind,
            recordId: dependent.address.recordId,
            wireHash: dependent.wireHash,
          ),
        },
      );
      final transport = _FakeTransport(
        devices: ['peer-b'],
        peerManifest: _manifest(
          deviceId: 'peer-b',
          records: {
            SyncRecordKind.dance: {'dance-d': peerDependent.wireHash},
          },
        ),
        blobResponses: _blobs([peerDependent]),
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
      // Publication is unchanged: the root has no fallback, so the dance is
      // still withheld from the manifest.
      final published = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.single),
      );
      expect(published.records[SyncRecordKind.dance] ?? const {}, isEmpty);
      expect(
        published.records[SyncRecordKind.choreographer] ?? const {},
        isEmpty,
      );
      final quarantined = result.reports.where(
        (report) =>
            report.code == SyncReportCode.quarantinedRecord &&
            report.peerId == null,
      );
      expect(quarantined, hasLength(1));
      expect(quarantined.single.message, contains('1 database-FK dependent'));
      // Withheld from publication is not withheld from the merge.
      expect(store.writes.map((write) => write.address), [dependent.address]);
      expect(store.writes.single.body['title'], 'Edited on B');
    },
  );

  test(
    'does not report an uploaded publication as unreflected when its peer blob is unavailable',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _tag('legacy', 'Shared tag'),
      );
      final legacy = candidate.address;
      final canonical = (kind: SyncRecordKind.tag, recordId: 'canonical');
      final store = _FakeStore(
        aliases: {legacy: canonical},
        snapshotBuilder: (_) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: {legacy: candidate},
          publication: {legacy: candidate},
          baseline: const {},
        ),
      );
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.tag: {canonical.recordId: candidate.wireHash},
          },
        ),
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
        now: () => DateTime.utc(2026, 7, 15, 12),
      );
      addTearDown(coordinator.dispose);

      final results = [
        await coordinator.syncNow(),
        await coordinator.syncNow(),
        await coordinator.syncNow(),
      ];

      expect(
        results.expand((result) => result.reports).map((report) => report.code),
        isNot(contains(SyncReportCode.unreflectedPublication)),
      );
    },
  );

  test(
    'omits a fallback and its dependents when the fallback blob is unavailable',
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
      final transport = _FakeTransport(
        missingResponses: [
          [fallbackHash],
        ],
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
      final published = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.single),
      );
      expect(published.records[SyncRecordKind.choreographer], isNull);
      expect(published.records[SyncRecordKind.dance], isNull);
      expect(
        result.reports.map((report) => report.code),
        contains(SyncReportCode.unresolvedBlob),
      );
      expect(transport.postMissingBatches.single, contains(fallbackHash));
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

  // A `409` on the replacement `POST` means only that a store exists for this
  // `id_key` (spec §5.2, §5.3), and the sole way that can be true is that
  // another holder of this device's own phrase recreated it — or that this
  // device's own `201` was lost. So the device adopts it and continues into
  // the ordinary fresh attach. Reporting it as a failure left the decision
  // pending and re-POSTed into the same conflict on every confirm, forever.
  test(
    'create conflict adopts the existing store and fresh-attaches',
    () async {
      final transport = _FakeTransport(
        missingKind: SyncStoreMissingKind.replacementRequired,
        createResponses: [_FakeTransport.response(409)],
      );
      final store = _FakeStore(
        previouslyUsed: true,
        snapshotEpochs: [null, null, 'epoch-1'],
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );
      addTearDown(coordinator.dispose);

      await coordinator.onAppStart();
      final result = await coordinator.confirmReplacement();

      expect(result.status, SyncPassStatus.completed);
      expect(
        transport.createCalls,
        1,
        reason: 'adopting must not send a second POST',
      );
      expect(transport.requestLog, [
        'store', // §6.3 step 1 found the store gone
        'create', // the one POST — answered 409
        'store', // the adopted store, read exactly as after a 201
        'store', // the fresh-attach pass's own lookup
        'manifest-put',
      ]);

      // And the decision is resolved: a later trigger runs an ordinary pass
      // instead of re-raising the dialog.
      expect(
        (await coordinator.syncNow()).status,
        SyncPassStatus.completed,
        reason: 'no re-prompt — the replacement decision is done',
      );
      expect(transport.createCalls, 1);
    },
  );

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
    // The automatic retry and the resume trigger are automatic too: neither
    // may lift a pause the user chose.
    for (final trigger in [SyncTrigger.retry, SyncTrigger.resume]) {
      expect(
        (await coordinator.trigger(trigger)).status,
        SyncPassStatus.paused,
        reason: trigger.name,
      );
    }
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

  group('peer manifests kept across restarts (spec §5.2)', () {
    final peerManifest = _manifest(deviceId: 'peer', records: const {});
    final encodedManifest = encodeSyncManifestUtf8(peerManifest);
    SyncHttpResponse full(String etag) => SyncHttpResponse(
      statusCode: 200,
      kind: SyncResponseKind.success,
      headers: {'etag': etag},
      body: encodedManifest,
    );
    const notModified = SyncHttpResponse(
      statusCode: 304,
      kind: SyncResponseKind.notModified,
      headers: {},
      body: [],
    );

    SyncCoordinator restarted(_FakeStore store, _FakeTransport transport) {
      // A new coordinator with a cache of its own: what the app has after a
      // restart.
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
        peerManifestCache: SyncPeerManifestCache(),
      );
      addTearDown(coordinator.dispose);
      return coordinator;
    }

    test('a restart asks with the kept ETag and takes the 304', () async {
      final store = _FakeStore();
      final transport = _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          'peer': [full('"peer-v1"'), notModified],
        },
      );
      await restarted(store, transport).syncNow();
      expect(store.peerManifests['peer'], (
        epoch: 'epoch-1',
        etag: '"peer-v1"',
        body: utf8.decode(encodedManifest),
      ));

      final result = await restarted(store, transport).syncNow();

      expect(transport.manifestEtags, [null, '"peer-v1"']);
      expect(result.status, SyncPassStatus.completed);
      expect(
        result.reports.map((report) => report.code),
        isNot(contains(SyncReportCode.malformedRecord)),
        reason: 'the 304 is answered from the kept manifest',
      );
      expect(result.peers?.map((peer) => peer.peerId), ['peer']);
    });

    test('a 304 leaves the kept copy as it was', () async {
      final store = _FakeStore();
      final transport = _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          'peer': [full('"peer-v1"'), notModified],
        },
      );
      final coordinator = restarted(store, transport);
      await coordinator.syncNow();
      store.peerManifests['peer'] = (
        epoch: 'epoch-1',
        etag: '"peer-v1"',
        body: 'left alone',
      );

      await coordinator.syncNow();

      expect(store.peerManifests['peer']!.body, 'left alone');
    });

    test('a kept copy that does not decode is dropped and refetched', () async {
      final store = _FakeStore()
        ..peerManifests['peer'] = (
          epoch: 'epoch-1',
          etag: '"peer-v1"',
          body: '{not a manifest',
        );
      final transport = _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          'peer': [full('"peer-v2"')],
        },
      );

      final result = await restarted(store, transport).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(transport.manifestEtags, [null]);
      expect(store.peerManifests['peer']!.etag, '"peer-v2"');
    });

    test(
      'an undecodable kept copy is dropped even when the refetch fails',
      () async {
        final store = _FakeStore()
          ..peerManifests['peer'] = (
            epoch: 'epoch-1',
            etag: '"peer-v1"',
            body: '{not a manifest',
          );
        final transport = _FakeTransport(
          devices: ['peer'],
          manifestResponses: {
            'peer': [_FakeTransport.response(500)],
          },
        );

        await restarted(store, transport).syncNow();

        expect(store.peerManifests, isEmpty);
      },
    );

    String bodyFor({required String deviceId, required String epoch}) =>
        encodeSyncManifest(
          SyncManifest(
            deviceId: deviceId,
            epoch: epoch,
            writtenAt: DateTime.utc(2026, 7, 15, 12),
            records: const {},
          ),
        );

    test('a kept copy that names another device is not used', () async {
      final store = _FakeStore()
        ..peerManifests['peer'] = (
          epoch: 'epoch-1',
          etag: '"other-v1"',
          body: bodyFor(deviceId: 'other', epoch: 'epoch-1'),
        );
      final transport = _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          'peer': [full('"peer-v1"')],
        },
      );

      await restarted(store, transport).syncNow();

      expect(transport.manifestEtags, [null]);
      expect(store.peerManifests['peer']!.etag, '"peer-v1"');
    });

    test('a kept copy whose epoch disagrees with its row is not used', () {
      final store = _FakeStore()
        ..peerManifests['peer'] = (
          epoch: 'epoch-1',
          etag: '"peer-old"',
          body: bodyFor(deviceId: 'peer', epoch: 'epoch-0'),
        );
      final transport = _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          'peer': [full('"peer-v1"')],
        },
      );

      return restarted(store, transport).syncNow().then((_) {
        expect(transport.manifestEtags, [null]);
        expect(store.peerManifests['peer']!.etag, '"peer-v1"');
      });
    });

    test('a 304 puts back a kept copy a restore cleared', () async {
      final store = _FakeStore();
      final transport = _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          // The first pass, then a fresh attach and its continuation.
          'peer': [full('"peer-v1"'), notModified, notModified],
        },
      );
      final coordinator = restarted(store, transport);
      await coordinator.syncNow();
      // A restore clears the baseline, and the kept manifests with it, while
      // this session still holds them in memory.
      await store.clearEpochState();
      expect(store.peerManifests, isEmpty);

      await coordinator.syncNow();

      expect(transport.manifestEtags, [null, '"peer-v1"', '"peer-v1"']);
      expect(store.peerManifests['peer']?.etag, '"peer-v1"');
    });

    test('a device that leaves the list and returns is kept again', () async {
      final store = _FakeStore();
      final devices = ['peer'];
      final transport = _FakeTransport(
        devices: devices,
        manifestResponses: {
          'peer': [full('"peer-v1"'), notModified],
        },
      );
      final coordinator = restarted(store, transport);
      await coordinator.syncNow();
      devices.clear();
      await coordinator.syncNow();
      expect(store.peerManifests, isEmpty);

      devices.add('peer');
      await coordinator.syncNow();

      expect(transport.manifestEtags, [null, '"peer-v1"']);
      expect(store.peerManifests['peer']?.etag, '"peer-v1"');
    });

    test('a malformed answer forgets the kept copy', () async {
      final store = _FakeStore()
        ..peerManifests['peer'] = (
          epoch: 'epoch-1',
          etag: '"peer-v1"',
          body: utf8.decode(encodedManifest),
        );
      final transport = _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          'peer': [
            SyncHttpResponse(
              statusCode: 200,
              kind: SyncResponseKind.success,
              headers: const {'etag': '"peer-v2"'},
              body: utf8.encode('{not a manifest'),
            ),
          ],
        },
      );

      await restarted(store, transport).syncNow();

      expect(transport.manifestEtags, ['"peer-v1"']);
      expect(store.peerManifests, isEmpty);
    });

    test('whether a manifest is kept crosses the isolate boundary', () {
      final cache = SyncPeerManifestCache(
        entries: {
          'peer': SyncPeerManifestCacheEntry(
            epoch: 'epoch-1',
            etag: '"peer-v1"',
            manifest: peerManifest,
            stored: true,
          ),
        },
      );

      final copy = SyncPeerManifestCache.fromMessage(cache.toMessage());

      expect(copy['peer']?.stored, isTrue);
      copy.markUnstored();
      expect(copy['peer']?.stored, isFalse);
      expect(copy['peer']?.etag, '"peer-v1"');
    });

    test('a copy kept in another epoch is not used', () async {
      final store = _FakeStore()
        ..peerManifests['peer'] = (
          epoch: 'epoch-0',
          etag: '"peer-old"',
          body: utf8.decode(
            encodeSyncManifestUtf8(
              SyncManifest(
                deviceId: 'peer',
                epoch: 'epoch-0',
                writtenAt: DateTime.utc(2026, 7, 15, 12),
                records: const {},
              ),
            ),
          ),
        );
      final transport = _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          'peer': [full('"peer-v1"')],
        },
      );

      await restarted(store, transport).syncNow();

      expect(transport.manifestEtags, [null]);
      expect(store.peerManifests['peer']!.epoch, 'epoch-1');
    });

    test('a device the store no longer lists is forgotten', () async {
      final store = _FakeStore()
        ..peerManifests['gone'] = (
          epoch: 'epoch-1',
          etag: '"gone-v1"',
          body: '{}',
        );
      final transport = _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          'peer': [full('"peer-v1"')],
        },
      );

      await restarted(store, transport).syncNow();

      expect(store.peerManifests.keys, ['peer']);
    });

    test('a manifest that stops being usable is forgotten', () async {
      final store = _FakeStore();
      final transport = _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          'peer': [
            full('"peer-v1"'),
            // A full answer with no validator: nothing to ask with next time.
            SyncHttpResponse(
              statusCode: 200,
              kind: SyncResponseKind.success,
              headers: const {},
              body: encodedManifest,
            ),
          ],
        },
      );
      final coordinator = restarted(store, transport);
      await coordinator.syncNow();
      expect(store.peerManifests, contains('peer'));

      await coordinator.syncNow();

      expect(store.peerManifests, isEmpty);
    });
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
      // One download in all: peer-b's duplicate entry reuses peer-a's blob
      // within the first pass, and the second pass reuses the body the
      // session already verified (`SyncPeerManifestCache.fetchedBlob`).
      expect(transport.blobCalls, 1);
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
          NativeDatabase(databaseFile, setup: applyCompendiumSqliteSetup),
          closeStreamsSynchronously: true,
        );
        final deleteTransactionGate = _TransactionStartGate();
        final deletingDatabase = CompendiumDatabase(
          NativeDatabase.createInBackground(
            databaseFile,
            setup: applyCompendiumSqliteSetup,
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
    'protects a fallback root and FK dependent from hard-delete during probing',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fallback-publication-marker-race-',
      );
      final databaseFile = File('${directory.path}/test.sqlite');
      final writerDatabase = CompendiumDatabase(
        NativeDatabase(databaseFile, setup: applyCompendiumSqliteSetup),
        closeStreamsSynchronously: true,
      );
      final deleteTransactionGate = _TransactionStartGate();
      final deletingDatabase = CompendiumDatabase(
        NativeDatabase.createInBackground(
          databaseFile,
          setup: applyCompendiumSqliteSetup,
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
      final rootId = 'fallback-publication-race-dance';
      final dependentId = 'fallback-publication-race-program';
      final fallbackHash = _hash('a');
      await repositories.dances.create(
        Dance(
          id: rootId,
          title: 'Fallback publication race dance',
          createdAt: stamp,
          updatedAt: stamp.add(const Duration(hours: 25)),
        ),
      );
      await repositories.programs.create(
        Program(
          id: dependentId,
          title: 'Fallback publication race program',
          slots: [
            ProgramSlot(id: 'fallback-race-slot', position: 0, danceId: rootId),
          ],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await repositories.syncLocal.resetEpoch(
        epoch: 'epoch-1',
        entries: [
          SyncBaselineEntry(
            kind: SyncRecordKind.dance,
            recordId: rootId,
            wireHash: fallbackHash,
          ),
        ],
      );
      expect(
        await deletingRepositories.programs.getById(dependentId),
        isNotNull,
      );
      deleteTransactionGate.arm();

      late Future<void> deleteFuture;
      final store = _SnapshotInterleavingStore(
        CompendiumSyncCoordinatorStore(repositories),
        afterFinalSnapshot: () async {
          deleteFuture = deletingRepositories.programs.hardDelete([
            dependentId,
          ]);
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
        now: () => stamp,
      );

      final result = await coordinator.syncNow();
      await deleteFuture;

      expect(result.status, SyncPassStatus.completed);
      final retained = await deletingRepositories.programs.getById(
        dependentId,
        includeDeleted: true,
      );
      expect(retained, isNotNull);
      expect(retained?.deletedAt, isNotNull);
      expect(store.snapshotCalls, 2);
      final manifest = decodeSyncManifest(
        utf8.decode(transport.manifestBodies.single),
      );
      expect(manifest.records[SyncRecordKind.dance]?[rootId], fallbackHash);
      expect(manifest.records[SyncRecordKind.program]?[dependentId], isNotNull);
    },
  );

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

  test('does not retire aliases when the store lists no peer', () async {
    // Zero observed peers is not evidence that an alias has nothing left to
    // resolve. `allPeerManifestsAvailable` is vacuously true when the loop over
    // `devices` never runs, so retirement used to be called with an empty
    // address set — which retains nothing and deletes every `id_aliases` row.
    // A peer that later returns then re-raises every collision this device had
    // already reconciled. Reachable on a solo install, after peers age out
    // under §7.3, and on the attach continuation.
    final store = _FakeStore();
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: _FakeTransport(devices: ['device-a']),
    );

    final result = await coordinator.syncNow();

    expect(result.status, SyncPassStatus.completed);
    expect(store.retiredPeerAddresses, isEmpty);
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
          // A 404, which still completes the pass. A 5xx, which ends it as a
          // temporary failure, is covered with the other server faults.
          'peer': [_FakeTransport.response(404)],
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
    'a fresh attach reports what its steady continuation saw of each peer',
    () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final store = _FakeStore(
        epoch: null,
        local: {candidate.address: candidate},
        snapshotEpochs: [null, null, 'epoch-1'],
      );
      final peerWrittenAt = DateTime.utc(2026, 7, 14, 9);
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: _FakeTransport(
          devices: ['device-a', 'peer'],
          peerManifest: SyncManifest(
            deviceId: 'peer',
            epoch: 'epoch-1',
            writtenAt: peerWrittenAt,
            records: const {},
          ),
        ),
      );
      addTearDown(coordinator.dispose);

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(store.epochStateClears, 1, reason: 'this was a fresh attach');
      final summary = result.peers!.single;
      expect(summary.peerId, 'peer');
      expect(summary.writtenAt, peerWrittenAt);
      expect(summary.waitingCount, 1);
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
    'fresh attach skips a listed peer blob that is unavailable and completes',
    () async {
      final shared = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'shared'),
      );
      final missing = SyncMergeCandidate.fromBlob(
        _setting('default_program_band', 'remote-only'),
      );
      final store = _FakeStore(epoch: null, local: {shared.address: shared});
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.setting: {
              shared.blob.id: shared.wireHash,
              missing.blob.id: missing.wireHash,
            },
          },
        ),
        blobResponses: {
          shared.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(shared.blob)),
          ),
        },
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final first = await coordinator.syncNow();

      // §6.3 step 5: the unfetchable blob skips one record and reports it; the
      // batch stays intact, so the attach persists its epoch and publishes.
      expect(first.status, SyncPassStatus.completed);
      expect(
        first.reports.map((report) => report.code),
        contains(SyncReportCode.unresolvedBlob),
      );
      expect(store.freshAttachDedupeCalls, 1);
      expect(store.baselineReplacements, 1);
      expect(transport.manifestPuts, 1);
      // The skipped record gets no baseline entry, so a later pass retries it.
      expect(store.replacedEntries, [shared.address]);
      expect(store.advancedEntries, isNot(contains(missing.address)));

      transport.blobResponses[missing.wireHash] = _FakeTransport.response(
        200,
        body: utf8.encode(encodeSyncRecordBlob(missing.blob)),
      );
      final second = await coordinator.syncNow();

      expect(second.status, SyncPassStatus.completed);
      expect(store.epochStateClears, 1);
      expect(
        second.reports.map((report) => report.code),
        isNot(contains(SyncReportCode.unresolvedBlob)),
      );
      expect(
        store.writes.map((write) => write.address),
        contains(missing.address),
      );
    },
  );

  test(
    'fresh attach withholds a baseline entry for an address unresolved from one peer',
    () async {
      final shared = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'shared'),
      );
      final clean = SyncMergeCandidate.fromBlob(
        _setting('default_program_band', 'clean'),
      );
      final missingHash = _hash('a');
      final store = _FakeStore(
        epoch: null,
        local: {shared.address: shared, clean.address: clean},
      );
      final transport = _FakeTransport(
        devices: ['peer-a', 'peer-b'],
        peerManifests: {
          // Advertises a body for `shared` that the store no longer holds.
          'peer-a': _manifest(
            deviceId: 'peer-a',
            records: {
              SyncRecordKind.setting: {shared.blob.id: missingHash},
            },
          ),
          'peer-b': _manifest(
            deviceId: 'peer-b',
            records: {
              SyncRecordKind.setting: {
                shared.blob.id: shared.wireHash,
                clean.blob.id: clean.wireHash,
              },
            },
          ),
        },
        blobResponses: {
          shared.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(shared.blob)),
          ),
          clean.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(clean.blob)),
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

      expect(result.status, SyncPassStatus.completed);
      expect(
        result.reports.map((report) => report.code),
        contains(SyncReportCode.unresolvedBlob),
      );
      expect(store.baselineReplacements, 1);
      // `shared` is unresolved from peer-a, so the merge never decided it — a
      // second peer carrying this device's own hash is not evidence that the
      // record is agreed, exactly as steady state treats it.
      expect(store.replacedEntries, [clean.address]);
    },
  );

  test(
    'fresh attach reports a refused peer record and applies the rest',
    () async {
      final noncanonical = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        updatedAt: DateTime.utc(2026, 7, 15, 12),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 7, 15, 12),
        body: {'value': 'é'},
      );
      final refused = SyncMergeCandidate.fromBlob(noncanonical);
      final accepted = SyncMergeCandidate.fromBlob(
        _setting('default_program_band', 'canonical'),
      );
      final store = _FakeStore(epoch: null);
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.setting: {
              noncanonical.id: refused.wireHash,
              accepted.blob.id: accepted.wireHash,
            },
          },
        ),
        blobResponses: {
          refused.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(noncanonical)),
          ),
          accepted.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(accepted.blob)),
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

      // A peer on an older build whose body this device refuses must not stop the
      // attach: §6.5 skips only that record and does not gate the rest.
      expect(result.status, SyncPassStatus.completed);
      expect(
        result.reports.map((report) => report.code),
        contains(SyncReportCode.nonCanonicalWireBody),
      );
      expect(
        store.writes.map((write) => write.address),
        contains(accepted.address),
      );
      expect(
        store.writes.map((write) => write.address),
        isNot(contains(refused.address)),
      );
      expect(transport.manifestPuts, 1);
      expect(store.baselineReplacements, 1);
    },
  );

  test(
    'incomplete fresh attach retries when a peer manifest carries a stale epoch',
    () async {
      final local = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final store = _FakeStore(epoch: null, local: {local.address: local});
      final staleManifest = SyncManifest(
        deviceId: 'peer',
        epoch: 'epoch-0',
        writtenAt: DateTime.utc(2026, 7, 15, 12),
        records: const {},
      );
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(deviceId: 'peer', records: const {}),
        manifestResponses: {
          'peer': [
            _FakeTransport.response(
              200,
              body: encodeSyncManifestUtf8(staleManifest),
            ),
          ],
        },
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final first = await coordinator.syncNow();

      // The manifest itself is unusable, so the union is incomplete for every
      // record that peer holds and the attach still persists nothing.
      expect(first.status, SyncPassStatus.failed);
      expect(
        first.reports.map((report) => report.code),
        contains(SyncReportCode.malformedRecord),
      );
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

  test('a stale peer copy does not outrank a pending tombstone', () async {
    // §6.4 decides existence by the greater `existenceAt` "on every path that
    // can decide existence". `snapshot.local` strips pending addresses out,
    // so the merge used to see no local candidate and the peer's live copy
    // won by default — even this one, stamped three days *before* the
    // deletion it is competing with. The stale body was applied and the local
    // row's `existence_at` was lowered below the tombstone superseding it.
    final deleted = DateTime.utc(2026, 7, 15, 12);
    final stale = DateTime.utc(2026, 7, 12, 12);
    final tombstone = SyncMergeCandidate.fromBlob(
      SyncRecordBlob(
        kind: SyncRecordKind.tag,
        id: 'pending-tag',
        updatedAt: deleted,
        deletedAt: deleted,
        existenceAt: deleted,
        body: const {'id': 'pending-tag', 'name': 'Pending tag'},
      ),
    );
    final stalePeerCopy = SyncMergeCandidate.fromBlob(
      SyncRecordBlob(
        kind: SyncRecordKind.tag,
        id: 'pending-tag',
        updatedAt: stale,
        deletedAt: null,
        existenceAt: stale,
        body: const {'id': 'pending-tag', 'name': 'Renamed by a stale peer'},
      ),
    );
    final store = _FakeStore(
      snapshotBuilder: (_) => SyncCoordinatorSnapshot(
        epoch: 'epoch-1',
        previouslyUsed: false,
        local: const {},
        publication: {tombstone.address: tombstone},
        pending: {tombstone.address},
        baseline: const {},
      ),
    );
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.tag: {'pending-tag': stalePeerCopy.wireHash},
          },
        ),
        blobResponses: {
          stalePeerCopy.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(stalePeerCopy.blob)),
          ),
        },
      ),
    );

    final result = await coordinator.syncNow();

    expect(result.status, SyncPassStatus.completed);
    // Nothing is written: the tombstone wins the existence comparison, so the
    // winner is this device's own candidate and the live row it names is left
    // alone (§6.8).
    expect(store.writes, isEmpty);
  });

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

  test(
    'repairs a future-dated pending tombstone without dropping its live guard',
    () async {
      final now = DateTime.utc(2026, 7, 15, 12);
      final address = (
        kind: SyncRecordKind.setting,
        recordId: 'custom_dialects',
      );
      final localTombstone = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: address.kind,
          id: address.recordId,
          updatedAt: now.add(const Duration(hours: 25)),
          deletedAt: now,
          existenceAt: now,
          body: const {'value': 'pending'},
        ),
      );
      final peerTombstone = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: address.kind,
          id: address.recordId,
          updatedAt: now.add(const Duration(hours: 1)),
          deletedAt: now,
          existenceAt: now,
          body: const {'value': 'peer'},
        ),
      );
      final pendingLive = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: address.kind,
          id: address.recordId,
          updatedAt: now,
          deletedAt: null,
          existenceAt: now,
          body: const {'value': 'pending'},
        ),
      );
      final store = _FakeStore(
        snapshotBuilder: (_) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: const {},
          publication: {address: localTombstone},
          pendingLive: {address: pendingLive},
          pending: {address},
          baseline: const {},
        ),
        currentCandidatesBuilder: () => {address: pendingLive},
      );
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.setting: {address.recordId: peerTombstone.wireHash},
          },
        ),
        blobResponses: {
          peerTombstone.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(peerTombstone.blob)),
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
      // One write: the repair. This fake's snapshot is constant, so the merge
      // that follows still sees the *pre-repair*, out-of-window tombstone, and
      // §6.3 excludes a quarantined record from the merge table entirely. It
      // used to be dropped from the local side only, which left the engine
      // deciding the address with no local candidate and applying the peer's
      // copy on top — the second write this test once asserted. A real store
      // never produced it either: there the post-repair snapshot carries the
      // repaired tombstone, whose `updatedAt` outranks the peer's, so the
      // decision is upload.
      expect(store.writes, hasLength(1));
      expect(store.writes.map((write) => write.address), [address]);
      expect(store.writes.first.sourceBlob?.body['value'], 'pending');
      expect(
        store.writes.first.sourceBlob!.updatedAt.isAfter(
          peerTombstone.updatedAt,
        ),
        isTrue,
      );
      expect(
        result.reports.map((report) => report.code),
        isNot(contains(SyncReportCode.concurrentLocalChange)),
      );
    },
  );

  test(
    'a stale peer live copy does not reverse an unrepairable pending tombstone',
    () async {
      final now = DateTime.utc(2026, 7, 15, 12);
      final address = (
        kind: SyncRecordKind.setting,
        recordId: 'custom_dialects',
      );
      // Out of window on `updatedAt` only, so repair is attempted and the
      // existence half is left alone.
      final localTombstone = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: address.kind,
          id: address.recordId,
          updatedAt: now.add(const Duration(hours: 25)),
          deletedAt: now,
          existenceAt: now,
          body: const {'value': 'pending'},
        ),
      );
      // In window, so `repairSyncCandidate` considers it, but a different body
      // under a non-null baseline takes the "do not stamp a different body over
      // it" branch. The tombstone therefore reaches the merge still
      // quarantined, which is the path this test exists for. Its `existenceAt`
      // is older than the tombstone's, so it must lose on §6.4 even if it were
      // considered at all.
      final peerLive = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: address.kind,
          id: address.recordId,
          updatedAt: now,
          deletedAt: null,
          existenceAt: now.subtract(const Duration(minutes: 1)),
          body: const {'value': 'peer'},
        ),
      );
      final pendingLive = SyncMergeCandidate.fromBlob(
        SyncRecordBlob(
          kind: address.kind,
          id: address.recordId,
          updatedAt: now,
          deletedAt: null,
          existenceAt: now,
          body: const {'value': 'pending'},
        ),
      );
      final store = _FakeStore(
        snapshotBuilder: (_) => SyncCoordinatorSnapshot(
          epoch: 'epoch-1',
          previouslyUsed: false,
          local: const {},
          publication: {address: localTombstone},
          pendingLive: {address: pendingLive},
          pending: {address},
          baseline: {
            address: SyncBaselineEntry(
              kind: address.kind,
              recordId: address.recordId,
              wireHash: _hash('a'),
            ),
          },
        ),
        currentCandidatesBuilder: () => {address: pendingLive},
      );
      final transport = _FakeTransport(
        devices: ['peer'],
        peerManifest: _manifest(
          deviceId: 'peer',
          records: {
            SyncRecordKind.setting: {address.recordId: peerLive.wireHash},
          },
        ),
        blobResponses: _blobs([peerLive]),
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
      // A quarantined pending tombstone is a quarantined record, so §6.3
      // excludes it from the merge table entirely. Dropping it from the local
      // side alone would leave the engine deciding the address with no local
      // candidate, where the peer's live copy wins unconditionally and the
      // deferred deletion is silently reversed.
      expect(
        store.writes.where((write) => write.address == address),
        isEmpty,
        reason:
            'a stale peer live copy must not be applied over a pending deletion',
      );
      expect(store.writes, isEmpty);
      // Nothing was applied, so the pending deletion still stands.
      expect(result.appliedKinds, isNot(contains(SyncRecordKind.setting)));
      final quarantined = result.reports.where(
        (report) =>
            report.code == SyncReportCode.quarantinedRecord &&
            report.peerId == null,
      );
      expect(quarantined, hasLength(1));
      expect(quarantined.single.recordId, address.recordId);
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
      // An ordinary preference: a whole-collection key changed on both
      // sides would go to review, never reaching the apply this test guards.
      final local = SyncMergeCandidate.fromBlob(
        _setting('theme_mode', 'local'),
      );
      final concurrent = SyncMergeCandidate.fromBlob(
        _setting('theme_mode', 'concurrent', seconds: 1),
      );
      final remote = SyncMergeCandidate.fromBlob(
        _setting('theme_mode', 'remote', seconds: 2),
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
        manifest.records[SyncRecordKind.setting]!['theme_mode'],
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
      ).currentCandidates({(kind: SyncRecordKind.tag, recordId: survivorId)});
      expect(
        concurrencyCandidates[(kind: SyncRecordKind.tag, recordId: survivorId)]!
            .wireHash,
        beforePass
            .pendingLive[(kind: SyncRecordKind.tag, recordId: survivorId)]!
            .wireHash,
      );

      // Stamped *after* the pending tombstone (12:01:00) on purpose. The
      // tombstone is this device's existence claim for the survivor, and §6.4
      // decides existence by the greater `existenceAt`, so an inbound copy
      // older than it does not reach the apply at all — there would be no
      // download for this guard to guard. The subject here is the concurrency
      // check on an aliased download, which needs a download that legitimately
      // wins.
      final inbound = SyncMergeCandidate.fromBlob(
        _tag(losingId, 'Shared tag', seconds: 120),
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

  test('an equal-time peer tie is queued for the user and does not advance '
      'the baseline', () async {
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
      isNot(contains(SyncReportCode.equalUpdatedAt)),
      reason: 'a queued choice replaces the report raised every pass',
    );
    final queued = store.conflictReviewCalls.single;
    expect(queued.single.address, local.address);
    expect(queued.single.conflict!.candidates.single.wireHash, remote.wireHash);
    expect(store.freshAttachDedupeCalls, 0);
    expect(store.steadyStateReviewRefreshCalls, 1);
    expect(store.advancedEntries, isEmpty);
  });

  test('a choice queued in an earlier pass is not reported as unreflected '
      'even when this pass raises no conflict for it', () async {
    // The peer never carries this device's version; what keeps the record
    // out of the count is the queued choice alone, as when its peer blob was
    // unreadable this pass and the merge skipped it.
    final local = SyncMergeCandidate.fromBlob(_setting('theme_mode', 'local'));
    final other = SyncMergeCandidate.fromBlob(
      _setting('reduce_motion', 'other'),
    );
    final store = _FakeStore(local: {local.address: local})
      ..queuedConflicts = {local.address};
    final transport = _FakeTransport(
      devices: ['peer'],
      peerManifest: _manifest(
        deviceId: 'peer',
        records: {
          SyncRecordKind.setting: {other.blob.id: other.wireHash},
        },
      ),
      blobResponses: {
        other.wireHash: _FakeTransport.response(
          200,
          body: utf8.encode(encodeSyncRecordBlob(other.blob)),
        ),
      },
    );
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: transport,
    );

    final codes = <SyncReportCode>[];
    for (var pass = 0; pass < 4; pass++) {
      final result = await coordinator.syncNow();
      codes.addAll(result.reports.map((report) => report.code));
    }

    expect(codes, isNot(contains(SyncReportCode.unreflectedPublication)));
  });

  test(
    "a record awaiting the user's choice is not reported as unreflected",
    () async {
      final local = SyncMergeCandidate.fromBlob(
        _setting('theme_mode', 'local'),
      );
      final remote = SyncMergeCandidate.fromBlob(
        _setting('theme_mode', 'remote'),
      );
      final store = _FakeStore(local: {local.address: local});
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

      final codes = <SyncReportCode>[];
      for (var pass = 0; pass < 4; pass++) {
        final result = await coordinator.syncNow();
        codes.addAll(result.reports.map((report) => report.code));
      }

      expect(store.conflictReviewCalls, hasLength(4));
      expect(codes, isNot(contains(SyncReportCode.unreflectedPublication)));
    },
  );

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

  // A failed pass says why, at the step it stopped, so the status surface can
  // explain it instead of saying only that it failed.
  group('failure causes', () {
    SyncCoordinator coordinatorFor(
      _FakeStore store,
      _FakeTransport transport,
    ) => SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: transport,
    );

    test(
      'a refused manifest publication names the publish step and status',
      () async {
        final result = await coordinatorFor(
          _FakeStore(),
          _FakeTransport(putManifestStatus: 500),
        ).syncNow();

        expect(result.status, SyncPassStatus.failed);
        expect(result.failure?.cause, SyncFailureCause.serverError);
        expect(result.failure?.step, SyncFailureStep.publish);
        expect(result.failure?.statusCode, 500);
      },
    );

    test('a refused upload names the upload step and status', () async {
      final candidate = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'local'),
      );
      final result = await coordinatorFor(
        _FakeStore(local: {candidate.address: candidate}),
        _FakeTransport(postMissingStatuses: [500]),
      ).syncNow();

      expect(result.status, SyncPassStatus.failed);
      expect(result.failure?.cause, SyncFailureCause.serverError);
      expect(result.failure?.step, SyncFailureStep.upload);
      expect(result.failure?.statusCode, 500);
    });

    test(
      'a fresh attach missing a peer manifest blames the peer, not the server',
      () async {
        // A `404` is the store saying it has no list for that device: the
        // peer's to fix, and the user's to chase. A `5xx` is the server's
        // own fault and retries quietly instead (spec §6.3 step 3).
        final result = await coordinatorFor(
          _FakeStore(epoch: null),
          _FakeTransport(
            devices: ['peer'],
            peerManifest: _manifest(deviceId: 'peer', records: const {}),
            manifestResponses: {
              'peer': [_FakeTransport.response(404)],
            },
          ),
        ).syncNow();

        expect(result.status, SyncPassStatus.failed);
        expect(result.failure?.cause, SyncFailureCause.peerUnavailable);
        expect(result.failure?.step, SyncFailureStep.download);
        expect(result.failure?.statusCode, 404);
      },
    );

    test('a fresh attach with an unreadable peer manifest downloads no blobs, '
        'however many the readable peers hold', () async {
      // The attach cannot finish without every peer's list (spec §6.2), so
      // anything fetched before the check was thrown away, and was fetched
      // again on every re-run.
      final peerCandidate = SyncMergeCandidate.fromBlob(
        _setting('default_program_band', 'peer'),
      );
      final transport = _FakeTransport(
        devices: ['peer-a', 'peer-b'],
        manifestResponses: {
          'peer-a': [_FakeTransport.response(404)],
          'peer-b': [
            SyncHttpResponse(
              statusCode: 200,
              kind: SyncResponseKind.success,
              headers: const {'etag': '"peer-b-v1"'},
              body: encodeSyncManifestUtf8(
                _manifest(
                  deviceId: 'peer-b',
                  records: {
                    SyncRecordKind.setting: {
                      peerCandidate.blob.id: peerCandidate.wireHash,
                    },
                  },
                ),
              ),
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

      final result = await coordinatorFor(
        _FakeStore(epoch: null),
        transport,
      ).syncNow();

      expect(result.status, SyncPassStatus.failed);
      expect(result.failure?.cause, SyncFailureCause.peerUnavailable);
      expect(result.failure?.statusCode, 404);
      expect(transport.blobCalls, 0);
    });

    test('a completed pass carries no failure', () async {
      final result = await coordinatorFor(
        _FakeStore(),
        _FakeTransport(),
      ).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(result.failure, isNull);
    });
  });

  test('a fresh attach whose continuation fails keeps the continuation\'s '
      'failure', () async {
    // The fresh-attach branch rebuilds its result from the continuation's,
    // and once rebuilt it without `failure`: the status line then had a
    // failed pass and nothing to explain it with.
    final result = await SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(epoch: null),
      transport: _FakeTransport(putManifestStatus: 500),
    ).syncNow();

    expect(result.status, SyncPassStatus.failed);
    expect(result.failure?.cause, SyncFailureCause.serverError);
    expect(result.failure?.step, SyncFailureStep.publish);
    expect(result.failure?.statusCode, 500);
  });

  group('store quota (spec §5.2)', () {
    const quota = {
      'blobs': 900,
      'bytes': 1000,
      'maxBlobs': 1000,
      'maxBytes': 100000,
    };
    SyncCoordinator coordinatorFor(_FakeTransport transport) => SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(),
      transport: transport,
    );

    test('a completed pass carries the quota its store lookup read', () async {
      final result = await coordinatorFor(
        _FakeTransport(storeQuota: quota),
      ).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(result.quota?.blobs, 900);
      expect(result.quota?.maxBlobs, 1000);
      expect(result.quota?.bytes, 1000);
      expect(result.quota?.maxBytes, 100000);
      expect(result.quota?.nearlyFull, isTrue);
    });

    test(
      'a pass that fails after its lookup still carries the quota',
      () async {
        final result = await coordinatorFor(
          _FakeTransport(storeQuota: quota, putManifestStatus: 500),
        ).syncNow();

        expect(result.status, SyncPassStatus.failed);
        expect(result.quota?.blobs, 900);
      },
    );

    test('a fresh attach carries the quota', () async {
      final result = await SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(epoch: null),
        transport: _FakeTransport(storeQuota: quota),
      ).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(result.quota?.blobs, 900);
    });

    for (final (name, value) in <(String, Object)>[
      ('a quota with a missing member', {'blobs': 1, 'bytes': 1}),
      ('a quota with a zero cap', {...quota, 'maxBytes': 0}),
      ('a quota with a negative count', {...quota, 'blobs': -1}),
      ('a quota that is not an object', 'full'),
    ]) {
      test('$name costs only the warning, never the pass', () async {
        final result = await coordinatorFor(
          _FakeTransport(storeQuota: value),
        ).syncNow();

        expect(result.status, SyncPassStatus.completed);
        expect(result.quota, isNull);
      });
    }

    test('a server that sends no quota leaves it null', () async {
      final result = await coordinatorFor(_FakeTransport()).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(result.quota, isNull);
    });
  });

  test('the warning threshold is at 80% of either limit, not before', () {
    SyncStoreQuota q(int blobs, int bytes) => SyncStoreQuota(
      blobs: blobs,
      bytes: bytes,
      maxBlobs: 100,
      maxBytes: 1000,
    );
    expect(q(79, 799).nearlyFull, isFalse);
    expect(q(80, 0).nearlyFull, isTrue);
    expect(q(0, 800).nearlyFull, isTrue);
  });

  // sync-1: a choice on a whole-collection setting must stop the deciding
  // device asking, even though the other version is still published (by a
  // peer that has not synced yet, or by a leftover manifest that never will).
  // Another device that changed the set too is asked once more; that is the
  // documented limit of a choice recorded only on this device (sync-spec §6.6).
  group('a whole-collection conflict choice (spec §6.6)', () {
    const dialects = (
      kind: SyncRecordKind.setting,
      recordId: 'custom_dialects',
    );
    final t0 = DateTime.utc(2026, 7, 15, 12);

    Future<SyncMergeCandidate> current(CompendiumRepositories repos) async =>
        (await CompendiumSyncStorage(repos).snapshot()).local[dialects]!;

    /// The wire hash of each version this device is asking about.
    Future<List<String>> choices(CompendiumRepositories repos) async => [
      for (final row in await repos.syncLocal.listReviewQueue())
        if (row.reason == syncConflictChoiceReason) row.candidateHash,
    ];

    /// One pass on [repos] (as `deviceId`) against [peers], each of which
    /// publishes exactly the given copy of the dialects setting.
    Future<void> pass(
      CompendiumRepositories repos, {
      required String deviceId,
      required Map<String, SyncMergeCandidate> peers,
    }) async {
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: deviceId,
        store: CompendiumSyncCoordinatorStore(repos),
        transport: _FakeTransport(
          devices: [deviceId, ...peers.keys],
          peerManifests: {
            for (final entry in peers.entries)
              entry.key: _manifest(
                deviceId: entry.key,
                records: {
                  SyncRecordKind.setting: {
                    dialects.recordId: entry.value.wireHash,
                  },
                },
              ),
          },
          blobResponses: {
            for (final peer in peers.values)
              peer.wireHash: _FakeTransport.response(
                200,
                body: utf8.encode(encodeSyncRecordBlob(peer.blob)),
              ),
          },
        ),
      );
      addTearDown(coordinator.dispose);
      final result = await coordinator.syncNow();
      expect(result.status, SyncPassStatus.completed);
    }

    /// A device attached to `epoch-1`, holding [value] set at [at], with
    /// [agreed] (if any) as the last version every device carried.
    Future<CompendiumRepositories> device(
      Object value, {
      required DateTime at,
      SyncMergeCandidate? agreed,
    }) async {
      final repos = openTestRepositories();
      await repos.settings.set(dialects.recordId, value, at: at);
      await repos.syncLocal.resetEpoch(
        epoch: 'epoch-1',
        entries: [
          if (agreed != null)
            SyncBaselineEntry(
              kind: dialects.kind,
              recordId: dialects.recordId,
              wireHash: agreed.wireHash,
            ),
        ],
      );
      return repos;
    }

    Future<SyncMergeCandidate> agreedSet() async => current(
      await device(const [
        {'name': 'Agreed'},
      ], at: t0),
    );

    test('the deciding device is not asked again while the other device '
        'still publishes the version it chose against', () async {
      final agreed = await agreedSet();
      final a = await device(
        const [
          {'name': 'Mine'},
        ],
        at: t0.add(const Duration(seconds: 1)),
        agreed: agreed,
      );
      final b = await device(
        const [
          {'name': 'Theirs'},
        ],
        at: t0.add(const Duration(seconds: 2)),
        agreed: agreed,
      );
      final bVersion = await current(b);

      await pass(a, deviceId: 'device-a', peers: {'device-b': bVersion});
      expect(await choices(a), hasLength(1));

      await CompendiumSyncStorage(a).resolveConflicts(const [
        SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'custom_dialects',
        ),
      ]);
      expect(await choices(a), isEmpty);

      await pass(a, deviceId: 'device-a', peers: {'device-b': bVersion});
      expect(
        await choices(a),
        isEmpty,
        reason:
            'device B has not synced since, so it still publishes the set '
            'the user chose against; that must not raise the choice again',
      );
      expect(await a.settings.get(dialects.recordId), [
        {'name': 'Mine'},
      ]);
    });

    test('every copy of a version chosen against counts as chosen against, '
        'not only the copy that was shown', () async {
      // Two other devices hold the same set under different stamps, so two
      // wire hashes. The choice shows that body once, as its newest copy; the
      // older copy must not raise the choice again.
      final agreed = await agreedSet();
      final a = await device(
        const [
          {'name': 'Mine'},
        ],
        at: t0.add(const Duration(seconds: 1)),
        agreed: agreed,
      );
      const theirs = [
        {'name': 'Theirs'},
      ];
      final older = await current(
        await device(theirs, at: t0.add(const Duration(seconds: 2))),
      );
      final newer = await current(
        await device(theirs, at: t0.add(const Duration(seconds: 3))),
      );
      expect(older.wireHash, isNot(newer.wireHash));
      final peers = {'device-b': older, 'device-c': newer};

      await pass(a, deviceId: 'device-a', peers: peers);
      expect(await choices(a), [newer.wireHash]);

      await CompendiumSyncStorage(a).resolveConflicts(const [
        SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'custom_dialects',
        ),
      ]);

      await pass(a, deviceId: 'device-a', peers: peers);
      expect(await choices(a), isEmpty);
    });

    test('a leftover manifest re-offering the version chosen against asks '
        'nothing, on every later pass', () async {
      // A detach and re-attach leaves the earlier attachment's manifest on
      // the server. It never republishes, and with no baseline after the
      // fresh attach its old set counts as changed.
      final ghost = await current(
        await device(const [
          {'name': 'Before detach'},
        ], at: t0),
      );
      final a = await device(const [
        {'name': 'After re-attach'},
      ], at: t0.add(const Duration(seconds: 1)));

      await pass(a, deviceId: 'device-a', peers: {'device-a-old': ghost});
      expect(await choices(a), hasLength(1));

      await CompendiumSyncStorage(a).resolveConflicts(const [
        SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'custom_dialects',
        ),
      ]);

      for (var later = 0; later < 3; later++) {
        await pass(a, deviceId: 'device-a', peers: {'device-a-old': ghost});
        expect(await choices(a), isEmpty, reason: 'pass ${later + 1}');
      }
    });

    test('another device that also changed the set is asked once more, and '
        'taking the chosen version settles both', () async {
      final agreed = await agreedSet();
      final a = await device(
        const [
          {'name': 'Mine'},
        ],
        at: t0.add(const Duration(seconds: 1)),
        agreed: agreed,
      );
      final b = await device(
        const [
          {'name': 'Theirs'},
        ],
        at: t0.add(const Duration(seconds: 2)),
        agreed: agreed,
      );
      await pass(
        a,
        deviceId: 'device-a',
        peers: {'device-b': await current(b)},
      );
      await CompendiumSyncStorage(a).resolveConflicts(const [
        SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'custom_dialects',
        ),
      ]);
      final decided = await current(a);

      // The choice is recorded only on device A, so device B — whose own
      // change the choice went against — cannot tell it from a concurrent
      // edit, and asks (sync-spec §6.6, docs/user/settings.md).
      await pass(b, deviceId: 'device-b', peers: {'device-a': decided});
      final asked = await choices(b);
      expect(asked, hasLength(1));
      expect(asked.single, decided.wireHash);

      await CompendiumSyncStorage(b).resolveConflicts([
        SyncConflictDecision(
          kind: SyncRecordKind.setting,
          recordId: 'custom_dialects',
          keepCandidateHash: decided.wireHash,
        ),
      ]);
      final taken = await current(b);
      await pass(b, deviceId: 'device-b', peers: {'device-a': decided});
      await pass(a, deviceId: 'device-a', peers: {'device-b': taken});
      expect(await choices(b), isEmpty);
      expect(await choices(a), isEmpty);
      expect(await b.settings.get(dialects.recordId), [
        {'name': 'Mine'},
      ]);
    });
  });

  // A `429` or `5xx` on a record download is about the server, not the record:
  // every request after a `429` fails the same way until the limit refills. It
  // ends the pass's downloads as a temporary failure, and the records not yet
  // fetched are waiting rather than skipped (spec §6.3 step 5). Reported per
  // record, as they were, a large first download raised a skipped-records
  // notice listing most of the library and re-fetched it into the same limit
  // on every later pass.
  group('a record download the server refuses for now (spec §6.3 step 5)', () {
    final at = DateTime.utc(2026, 7, 15, 12);

    /// What a peer publishes for three tags and three dances that cite them,
    /// in apply order: every tag before any dance. With [linkAcross],
    /// dance-0 also links to dance-2, a citation within one kind that no kind
    /// order can put first.
    Future<List<SyncMergeCandidate>> peerLibrary({
      bool linkAcross = false,
    }) async {
      final peer = openTestRepositories();
      for (var i = 0; i < 3; i++) {
        final _ = await peer.tags.upsert(
          Tag(id: 'tag-$i', name: 'Tag $i'),
          at: at,
        );
      }
      // Created last-first, so a linked dance exists before its link.
      for (var i = 2; i >= 0; i--) {
        await peer.dances.create(
          Dance(
            id: 'dance-$i',
            title: 'Dance $i',
            tagIds: ['tag-$i'],
            links: [
              if (linkAcross && i == 0)
                DanceLink(
                  id: 'link-0',
                  kind: LinkKind.relatedDance,
                  targetDanceId: 'dance-2',
                ),
            ],
            createdAt: at,
            updatedAt: at,
          ),
        );
      }
      final publication = (await CompendiumSyncStorage(
        peer,
      ).snapshot()).publication;
      final candidates = [
        for (final candidate in publication.values)
          if (candidate != null &&
              (candidate.address.kind == SyncRecordKind.tag ||
                  candidate.address.kind == SyncRecordKind.dance))
            candidate,
      ];
      expect(candidates, hasLength(6));
      return candidates;
    }

    String hashOf(List<SyncMergeCandidate> library, String recordId) =>
        library.singleWhere((c) => c.address.recordId == recordId).wireHash;

    _FakeTransport transportFor(List<SyncMergeCandidate> library) =>
        _FakeTransport(
          devices: ['peer'],
          peerManifest: _manifest(
            deviceId: 'peer',
            records: {
              for (final kind in {for (final c in library) c.address.kind})
                kind: {
                  for (final c in library)
                    if (c.address.kind == kind) c.address.recordId: c.wireHash,
                },
            },
          ),
          blobResponses: _blobs(library),
        );

    for (final freshAttach in [false, true]) {
      final label = freshAttach ? 'a fresh attach' : 'a steady-state pass';
      test('$label stops at a 429, applies what it fetched, reports nothing, '
          'and the next pass fetches only the rest', () async {
        final repositories = openTestRepositories();
        if (!freshAttach) {
          await repositories.syncLocal.resetEpoch(epoch: 'epoch-1');
        }
        final library = await peerLibrary();
        final transport = transportFor(library);
        // The fifth download meets the limit, and so would every one after.
        var limited = true;
        transport.onBlob = (call, _) =>
            limited && call >= 5 ? _FakeTransport.rateLimited : null;
        final store = CompendiumSyncCoordinatorStore(repositories);
        final coordinator = SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device-a',
          store: store,
          transport: transport,
        );
        addTearDown(coordinator.dispose);

        final first = await coordinator.syncNow();

        expect(first.status, SyncPassStatus.failed);
        expect(first.failure?.cause, SyncFailureCause.rateLimited);
        expect(first.failure?.cause.isTransient, isTrue);
        expect(first.failure?.step, SyncFailureStep.download);
        expect(first.failure?.statusCode, 429);
        expect(first.failure?.retryAfter, const Duration(seconds: 60));
        expect(first.failure?.progressed, isTrue);
        expect(
          first.reports,
          isEmpty,
          reason:
              'nothing was skipped: no unresolvedBlob for the records not '
              'fetched, and no unresolvedReference for a fetched dance whose '
              'tag was not fetched yet',
        );
        // Every tag first, then dances: the stop came at dance-1.
        expect(transport.blobHashes, [
          for (final id in ['tag-0', 'tag-1', 'tag-2', 'dance-0', 'dance-1'])
            hashOf(library, id),
        ]);
        for (var i = 0; i < 3; i++) {
          expect(await repositories.tags.getById('tag-$i'), isNotNull);
        }
        expect(await repositories.dances.getById('dance-0'), isNotNull);
        expect(await repositories.dances.getById('dance-1'), isNull);
        expect(await repositories.dances.getById('dance-2'), isNull);
        // Nothing was published, so nothing can have been baselined: the
        // records not fetched were decided by nothing.
        expect(transport.manifestPuts, 0);
        final afterFirst = await store.snapshot();
        expect(afterFirst.baseline, isEmpty);
        expect(afterFirst.epoch, freshAttach ? isNull : 'epoch-1');

        limited = false;
        transport.blobHashes.clear();
        final second = await coordinator.syncNow();

        expect(second.status, SyncPassStatus.completed);
        expect(second.reports, isEmpty);
        expect(transport.blobHashes, [
          hashOf(library, 'dance-1'),
          hashOf(library, 'dance-2'),
        ], reason: 'the next pass resumes where downloads stopped');
        expect(await repositories.dances.getById('dance-2'), isNotNull);
        final afterSecond = await store.snapshot();
        expect(afterSecond.epoch, 'epoch-1');
        expect(afterSecond.baseline.keys.toSet(), {
          for (final c in library) c.address,
        });
      });
    }

    test('a fetched dance linking to one not fetched yet waits with it, '
        'unreported', () async {
      // Kind order cannot help here: the link is dance to dance. Applied
      // alone, dance-0 would be refused as citing an unavailable related
      // dance — a skipped-record notice about a record merely not fetched.
      final repositories = openTestRepositories();
      await repositories.syncLocal.resetEpoch(epoch: 'epoch-1');
      final library = await peerLibrary(linkAcross: true);
      final transport = transportFor(library);
      var limited = true;
      transport.onBlob = (call, _) =>
          limited && call >= 5 ? _FakeTransport.rateLimited : null;
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: CompendiumSyncCoordinatorStore(repositories),
        transport: transport,
      );
      addTearDown(coordinator.dispose);

      final first = await coordinator.syncNow();

      expect(first.failure?.cause, SyncFailureCause.rateLimited);
      expect(first.reports, isEmpty);
      expect(await repositories.dances.getById('dance-0'), isNull);
      expect(await repositories.tags.getById('tag-0'), isNotNull);

      limited = false;
      transport.blobHashes.clear();
      final second = await coordinator.syncNow();

      expect(second.status, SyncPassStatus.completed);
      expect(second.reports, isEmpty);
      expect(transport.blobHashes, [
        hashOf(library, 'dance-1'),
        hashOf(library, 'dance-2'),
      ], reason: 'dance-0 waited in the session cache, not on the server');
      final linked = await repositories.dances.getById('dance-0');
      expect(linked?.links.single.targetDanceId, 'dance-2');
    });

    test('a 503 stops downloads as a server fault, not a skip', () async {
      final library = await peerLibrary();
      final transport = transportFor(library)
        ..onBlob = (call, _) => call >= 2 ? _FakeTransport.response(503) : null;
      final result = await SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(),
        transport: transport,
      ).syncNow();

      expect(result.status, SyncPassStatus.failed);
      expect(result.failure?.cause, SyncFailureCause.serverError);
      expect(result.failure?.step, SyncFailureStep.download);
      expect(result.failure?.statusCode, 503);
      expect(result.reports, isEmpty);
      expect(transport.blobCalls, 2, reason: 'no request after the 503');
      expect(transport.manifestPuts, 0);
    });

    for (final error in <Object>[
      const SyncTransportException('request timed out'),
      const SocketException('connection reset'),
    ]) {
      test('a ${error.runtimeType} mid-download keeps what was fetched and '
          'fails as temporary', () async {
        final library = await peerLibrary();
        final store = _FakeStore();
        final transport = transportFor(library)
          ..onBlob = (call, _) => call == 4 ? throw error : null;
        final result = await SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device-a',
          store: store,
          transport: transport,
        ).syncNow();

        expect(result.status, SyncPassStatus.failed);
        expect(result.failure?.cause.isTransient, isTrue);
        expect(result.failure?.step, SyncFailureStep.download);
        expect(result.failure?.progressed, isTrue);
        expect(result.reports, isEmpty);
        expect(transport.blobCalls, 4);
        expect(store.writes.map((w) => w.address.recordId).toSet(), {
          'tag-0',
          'tag-1',
          'tag-2',
        });
        expect(store.baselineAdvances, 0);
      });
    }

    test('a 404 is still a skipped record, and carries its status', () async {
      final library = await peerLibrary();
      final missing = hashOf(library, 'dance-2');
      final transport = transportFor(library)
        ..onBlob = (_, hash) =>
            hash == missing ? _FakeTransport.response(404) : null;
      final result = await SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(),
        transport: transport,
      ).syncNow();

      expect(result.status, SyncPassStatus.completed);
      final report = result.reports.singleWhere(
        (r) => r.code == SyncReportCode.unresolvedBlob,
      );
      expect(report.recordId, 'dance-2');
      expect(report.httpStatus, 404);
    });

    // A `5xx` on a peer's manifest is the server failing, not the peer
    // (spec §6.3 step 3). On a fresh attach, which cannot finish without every
    // peer's list, it is a temporary failure that retries by itself; it was
    // `peerUnavailable`, a needs-you warning sending the user to their other
    // devices. In steady state the pass carries on as before — baselined
    // records wait, and only records new to this device arrive from the
    // readable peers — but without the skipped-records notice, whose advice
    // (check the other device's app version) is false here.
    for (final status in [500, 503]) {
      test('a $status on a peer manifest during a fresh attach is a '
          'temporary failure', () async {
        final transport = _FakeTransport(
          devices: ['peer'],
          manifestResponses: {
            'peer': [_FakeTransport.response(status)],
          },
        );
        final result = await SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device-a',
          store: _FakeStore(epoch: null),
          transport: transport,
        ).syncNow();

        expect(result.status, SyncPassStatus.failed);
        expect(result.failure?.cause, SyncFailureCause.serverError);
        expect(result.failure?.cause.isTransient, isTrue);
        expect(result.failure?.step, SyncFailureStep.download);
        expect(result.failure?.statusCode, status);
        expect(result.reports, isEmpty);
        expect(transport.manifestPuts, 0);
      });

      test('a $status on one peer manifest in steady state finishes the pass '
          'quietly, then ends it as a temporary failure', () async {
        final other = SyncMergeCandidate.fromBlob(
          _setting('default_program_band', 'from other'),
        );
        final transport = _FakeTransport(
          devices: ['broken', 'other'],
          manifestResponses: {
            'broken': [_FakeTransport.response(status)],
          },
          peerManifests: {
            'other': _manifest(
              deviceId: 'other',
              records: {
                SyncRecordKind.setting: {other.blob.id: other.wireHash},
              },
            ),
          },
          blobResponses: _blobs([other]),
        );
        final store = _FakeStore();
        final result = await SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device-a',
          store: store,
          transport: transport,
        ).syncNow();

        expect(
          result.status,
          SyncPassStatus.failed,
          reason:
              'reported as completed, the pass cancels the retry and advances '
              'the last-success clock while shared edits are held back',
        );
        expect(result.failure?.cause, SyncFailureCause.serverError);
        expect(result.failure?.cause.isTransient, isTrue);
        expect(result.failure?.step, SyncFailureStep.download);
        expect(result.failure?.statusCode, status);
        expect(
          result.failure?.progressed,
          isFalse,
          reason:
              'a persistent fault backs off rather than retrying each minute',
        );
        expect(
          result.reports,
          isEmpty,
          reason: 'no skipped-records notice for a server fault',
        );
        expect(
          transport.manifestPuts,
          1,
          reason: 'the pass still publishes before it reports the fault',
        );
        expect(store.baselineAdvances, 1);
        expect(
          store.writes.map((w) => w.address.recordId),
          contains('default_program_band'),
          reason:
              'a record new to this device still arrives from the readable '
              'peer; baselined records wait, since none is decidable without '
              'every peer list',
        );
        expect(
          store.retiredPeerAddresses,
          isEmpty,
          reason: 'an unread peer list still blocks alias retirement',
        );
      });
    }

    test('with several peer manifests failing in steady state, the pass '
        'keeps the longest Retry-After', () async {
      SyncHttpResponse serverError(int status, int? seconds) =>
          SyncHttpResponse(
            statusCode: status,
            kind: SyncResponseKind.serverError,
            headers: {if (seconds != null) 'retry-after': '$seconds'},
            body: const [],
            retryAfter: seconds == null ? null : Duration(seconds: seconds),
          );
      final result = await SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(),
        transport: _FakeTransport(
          devices: ['none', 'short', 'long', 'later-short'],
          manifestResponses: {
            'none': [serverError(503, null)],
            'short': [serverError(503, 30)],
            'long': [serverError(500, 120)],
            'later-short': [serverError(503, 60)],
          },
        ),
      ).syncNow();

      expect(result.status, SyncPassStatus.failed);
      expect(
        result.failure?.retryAfter,
        const Duration(seconds: 120),
        reason: 'the retry must not come sooner than any answer allowed',
      );
      expect(result.failure?.statusCode, 500);
      expect(result.reports, isEmpty);
    });

    test(
      'a 404 on one peer manifest in steady state is still reported',
      () async {
        final result = await SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device-a',
          store: _FakeStore(),
          transport: _FakeTransport(
            devices: ['peer'],
            manifestResponses: {
              'peer': [_FakeTransport.response(404)],
            },
          ),
        ).syncNow();

        expect(result.status, SyncPassStatus.completed);
        final report = result.reports.single;
        expect(report.code, SyncReportCode.malformedRecord);
        expect(report.peerId, 'peer');
        expect(report.httpStatus, 404);
      },
    );

    test('a 429 on a peer manifest is a temporary failure, not an '
        'unreadable peer', () async {
      for (final epoch in ['epoch-1', null]) {
        final transport = _FakeTransport(
          devices: ['peer'],
          manifestResponses: {
            'peer': [_FakeTransport.rateLimited],
          },
        );
        final result = await SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device-a',
          store: _FakeStore(epoch: epoch),
          transport: transport,
        ).syncNow();

        expect(result.status, SyncPassStatus.failed, reason: '$epoch');
        expect(result.failure?.cause, SyncFailureCause.rateLimited);
        expect(result.failure?.retryAfter, const Duration(seconds: 60));
        expect(result.reports, isEmpty, reason: '$epoch');
        expect(transport.manifestPuts, 0);
      }
    });

    test('downloads are kind-major across peers, so a tag only another peer '
        'lists is fetched before the dance that cites it', () async {
      final library = await peerLibrary();
      final tags = [
        for (final c in library)
          if (c.address.kind == SyncRecordKind.tag) c,
      ];
      final dances = [
        for (final c in library)
          if (c.address.kind == SyncRecordKind.dance) c,
      ];
      SyncManifest manifestOf(String id, List<SyncMergeCandidate> records) =>
          _manifest(
            deviceId: id,
            records: {
              records.first.address.kind: {
                for (final c in records) c.address.recordId: c.wireHash,
              },
            },
          );
      final transport = _FakeTransport(
        devices: ['peer-a', 'peer-b'],
        peerManifests: {
          'peer-a': manifestOf('peer-a', dances),
          'peer-b': manifestOf('peer-b', tags),
        },
        blobResponses: _blobs(library),
      );
      await SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(),
        transport: transport,
      ).syncNow();

      expect(transport.blobHashes, [
        for (final c in [...tags, ...dances]) c.wireHash,
      ]);
    });
  });

  group('batched record downloads (spec §6.3 step 5)', () {
    final at = DateTime.utc(2026, 7, 15, 12);

    // Zero-padded, so a manifest's canonical (sorted) order is numeric order.
    String tagId(int i) => 'tag-${i.toString().padLeft(4, '0')}';
    String danceId(int i) => 'dance-${i.toString().padLeft(4, '0')}';

    SyncManifest manifestOf(List<SyncMergeCandidate> library) => _manifest(
      deviceId: 'peer',
      records: {
        for (final kind in {for (final c in library) c.address.kind})
          kind: {
            for (final c in library)
              if (c.address.kind == kind) c.address.recordId: c.wireHash,
          },
      },
    );

    /// A peer's [tags] tags and [dances] dances, each dance citing a tag, in
    /// apply order: every tag before any dance.
    Future<List<SyncMergeCandidate>> peerLibrary({
      required int tags,
      required int dances,
    }) async {
      final peer = openTestRepositories();
      for (var i = 0; i < tags; i++) {
        final _ = await peer.tags.upsert(
          Tag(id: tagId(i), name: 'Tag $i'),
          at: at,
        );
      }
      for (var i = 0; i < dances; i++) {
        await peer.dances.create(
          Dance(
            id: danceId(i),
            title: 'Dance $i',
            tagIds: [tagId(i % tags)],
            createdAt: at,
            updatedAt: at,
          ),
        );
      }
      final publication = (await CompendiumSyncStorage(
        peer,
      ).snapshot()).publication;
      final library = [
        for (final candidate in publication.values)
          if (candidate != null &&
              (candidate.address.kind == SyncRecordKind.tag ||
                  candidate.address.kind == SyncRecordKind.dance))
            candidate,
      ];
      expect(library, hasLength(tags + dances));
      return library;
    }

    /// The order a pass needs the library's hashes in: tags, then dances,
    /// each in manifest order.
    List<String> fetchOrder(List<SyncMergeCandidate> library) {
      // As the client reads it: decoded from its canonical encoding.
      final manifest = decodeSyncManifest(
        encodeSyncManifest(manifestOf(library)),
      );
      return [
        for (final kind in [SyncRecordKind.tag, SyncRecordKind.dance])
          ...?manifest.records[kind]?.values,
      ];
    }

    _FakeTransport transportFor(
      List<SyncMergeCandidate> library, {
      Map<String, SyncHttpResponse>? blobs,
    }) => _FakeTransport(
      devices: ['peer'],
      peerManifest: manifestOf(library),
      blobResponses: blobs ?? _blobs(library),
      batchSupported: true,
    );

    SyncCoordinator coordinatorFor(
      CompendiumRepositories repositories,
      _FakeTransport transport, {
      SyncPeerManifestCache? cache,
    }) {
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: CompendiumSyncCoordinatorStore(repositories),
        transport: transport,
        peerManifestCache: cache,
      );
      addTearDown(coordinator.dispose);
      return coordinator;
    }

    test('a 1,000-record fresh attach completes in one pass, '
        'one batch per $syncBlobBatchMaxHashes records', () async {
      final library = await peerLibrary(tags: 400, dances: 600);
      final transport = transportFor(library);
      final repositories = openTestRepositories();

      final result = await coordinatorFor(repositories, transport).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(result.reports, isEmpty);
      expect(
        transport.batchCalls,
        (library.length / syncBlobBatchMaxHashes).ceil(),
      );
      expect(transport.blobCalls, 0, reason: 'no single-blob request');
      for (final batch in transport.batchRequests) {
        expect(batch.length, lessThanOrEqualTo(syncBlobBatchMaxHashes));
      }
      // Every tag a dance cites is asked for before the dance.
      expect([
        for (final batch in transport.batchRequests) ...batch,
      ], fetchOrder(library));
      final snapshot = await CompendiumSyncCoordinatorStore(
        repositories,
      ).snapshot();
      expect(snapshot.epoch, 'epoch-1');
      expect(snapshot.baseline.keys.toSet(), {
        for (final c in library) c.address,
      });
    });

    for (final (status, refusal) in [
      (429, _FakeTransport.rateLimited),
      (503, _FakeTransport.response(503)),
    ]) {
      test('a $status on the second batch stops downloads with no reports, '
          'and the next pass fetches only the rest', () async {
        final library = await peerLibrary(tags: 300, dances: 200);
        final order = fetchOrder(library);
        final transport = transportFor(library);
        var refusing = true;
        transport.onBatch = (call, _) => refusing && call == 2 ? refusal : null;
        final repositories = openTestRepositories();
        final coordinator = coordinatorFor(repositories, transport);

        final first = await coordinator.syncNow();

        expect(first.status, SyncPassStatus.failed);
        expect(first.failure?.cause.isTransient, isTrue);
        expect(first.failure?.step, SyncFailureStep.download);
        expect(first.failure?.statusCode, status);
        expect(first.failure?.progressed, isTrue);
        expect(first.reports, isEmpty, reason: 'nothing was skipped');
        expect(transport.batchCalls, 2, reason: 'no request after the stop');
        expect(transport.blobCalls, 0);
        expect(transport.manifestPuts, 0);
        // The first batch was applied; nothing after it was.
        expect(await repositories.tags.getById(tagId(199)), isNotNull);
        expect(await repositories.tags.getById(tagId(200)), isNull);

        refusing = false;
        transport.batchRequests.clear();
        final second = await coordinator.syncNow();

        expect(second.status, SyncPassStatus.completed);
        expect(second.reports, isEmpty);
        expect([
          for (final batch in transport.batchRequests) ...batch,
        ], order.sublist(syncBlobBatchMaxHashes));
        expect(await repositories.dances.getById(danceId(199)), isNotNull);
      });
    }

    test('a hash the batch lists as missing is reported as a 404', () async {
      final library = await peerLibrary(tags: 3, dances: 0);
      final gone = library[1];
      final transport = transportFor(
        library,
        blobs: _blobs([library[0], library[2]]),
      );
      final repositories = openTestRepositories();
      await repositories.syncLocal.resetEpoch(epoch: 'epoch-1');

      final result = await coordinatorFor(repositories, transport).syncNow();

      expect(result.status, SyncPassStatus.completed);
      final report = result.reports.single;
      expect(report.code, SyncReportCode.unresolvedBlob);
      expect(report.recordId, gone.address.recordId);
      expect(report.httpStatus, 404);
      expect(transport.batchCalls, 1);
      expect(transport.blobCalls, 0);
      expect(
        await repositories.tags.getById(library[0].address.recordId),
        isNotNull,
      );
    });

    // `400` is what an Athenaeum from before the route answers; `413` stands
    // for any refusal a proxy in front of the server gives a POST that a
    // single GET would not meet; `501` is a 5xx that says "no such route".
    for (final status in [400, 404, 405, 413, 501]) {
      test('a $status on the batch route falls back to single requests for '
          'the rest of the session, with no notice', () async {
        final library = await peerLibrary(tags: 4, dances: 0);
        final transport = transportFor(library)
          // As `SyncHttpClient` reads it: a 501 is a `serverError`.
          ..onBatch = (_, _) => status == 501
              ? const SyncHttpResponse(
                  statusCode: 501,
                  kind: SyncResponseKind.serverError,
                  headers: {},
                  body: [],
                )
              : _FakeTransport.response(status);
        // The third single request meets the limit, so the session needs a
        // second pass, which must not ask for a batch again.
        var limited = true;
        transport.onBlob = (call, _) =>
            limited && call == 3 ? _FakeTransport.rateLimited : null;
        final cache = SyncPeerManifestCache();
        final repositories = openTestRepositories();
        final coordinator = coordinatorFor(
          repositories,
          transport,
          cache: cache,
        );

        final first = await coordinator.syncNow();

        expect(first.status, SyncPassStatus.failed);
        expect(first.failure?.cause, SyncFailureCause.rateLimited);
        expect(first.reports, isEmpty, reason: 'the fallback raises nothing');
        expect(transport.batchCalls, 1);
        expect(transport.blobCalls, 3);
        expect(cache.blobBatchUnsupported, isTrue);

        limited = false;
        final second = await coordinator.syncNow();

        expect(second.status, SyncPassStatus.completed);
        expect(second.reports, isEmpty);
        expect(transport.batchCalls, 1, reason: 'not asked again');
        expect(
          transport.blobHashes,
          fetchOrder(library).sublist(0, 3) + fetchOrder(library).sublist(2),
        );
      });
    }

    test('a 200 that is not a batch falls back too', () async {
      final library = await peerLibrary(tags: 2, dances: 0);
      final transport = transportFor(library)
        ..onBatch = (_, _) => const SyncHttpResponse(
          statusCode: 200,
          kind: SyncResponseKind.unexpectedStatus,
          headers: {},
          body: [],
        );

      final result = await coordinatorFor(
        openTestRepositories(),
        transport,
      ).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(transport.blobCalls, 2);
    });

    test('a malformed batch keeps the blobs that arrived and falls back to '
        'single requests for the rest, with no notice', () async {
      final library = await peerLibrary(tags: 5, dances: 0);
      final order = fetchOrder(library);
      final transport = transportFor(library)
        ..cutBatch = (_, index) => index == 2
            ? const SyncEndpointException('malformed blob batch response')
            : null;
      final repositories = openTestRepositories();
      final cache = SyncPeerManifestCache();

      final result = await coordinatorFor(
        repositories,
        transport,
        cache: cache,
      ).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(result.reports, isEmpty);
      expect(transport.batchCalls, 1);
      expect(transport.blobHashes, order.sublist(2));
      expect(cache.blobBatchUnsupported, isTrue);
      for (final candidate in library) {
        expect(
          await repositories.tags.getById(candidate.address.recordId),
          isNotNull,
        );
      }
    });

    test('a new store epoch asks for batches again', () {
      final cache = SyncPeerManifestCache()
        ..beginPublicationEpoch('epoch-1')
        ..blobBatchUnsupported = true
        ..beginPublicationEpoch('epoch-1');
      expect(cache.blobBatchUnsupported, isTrue, reason: 'same epoch');
      cache.beginPublicationEpoch('epoch-2');
      expect(cache.blobBatchUnsupported, isFalse);
    });

    test('a stream cut mid-batch keeps and applies the blobs that arrived, '
        'and the next pass fetches only the rest', () async {
      final library = await peerLibrary(tags: 5, dances: 0);
      final order = fetchOrder(library);
      final transport = transportFor(library);
      var cutting = true;
      transport.cutBatch = (call, index) => cutting && index == 3
          ? const SocketException('connection reset')
          : null;
      final repositories = openTestRepositories();
      final coordinator = coordinatorFor(repositories, transport);

      final first = await coordinator.syncNow();

      expect(first.status, SyncPassStatus.failed);
      expect(first.failure?.cause, SyncFailureCause.unreachable);
      expect(first.failure?.step, SyncFailureStep.download);
      expect(first.failure?.progressed, isTrue);
      expect(first.reports, isEmpty);
      for (final candidate in library) {
        final present = await repositories.tags.getById(
          candidate.address.recordId,
        );
        expect(
          present,
          order.indexOf(candidate.wireHash) < 3 ? isNotNull : isNull,
          reason: candidate.address.recordId,
        );
      }

      cutting = false;
      transport.batchRequests.clear();
      final second = await coordinator.syncNow();

      expect(second.status, SyncPassStatus.completed);
      expect(transport.batchRequests, [order.sublist(3)]);
    });
  });

  group('batched uploads (spec §6.3 step 7)', () {
    List<SyncMergeCandidate> localLibrary(int count) => [
      for (var i = 0; i < count; i++)
        SyncMergeCandidate.fromBlob(
          _dance(
            'dance-${i.toString().padLeft(4, '0')}',
            updatedAt: DateTime.utc(2026, 7, 15, 12),
          ),
        ),
    ];

    _FakeTransport transportFor(List<SyncMergeCandidate> local) =>
        _FakeTransport(
          missingResponses: [
            [for (final c in local) c.wireHash],
          ],
          uploadBatchSupported: true,
        );

    SyncCoordinator coordinatorFor(
      List<SyncMergeCandidate> local,
      _FakeTransport transport, {
      SyncPeerManifestCache? cache,
    }) {
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(local: {for (final c in local) c.address: c}),
        transport: transport,
        peerManifestCache: cache,
      );
      addTearDown(coordinator.dispose);
      return coordinator;
    }

    test('uploads what the store is missing $syncBlobBatchMaxUploadBlobs to a '
        'request, and publishes', () async {
      final local = localLibrary(120);
      final transport = transportFor(local);

      final result = await coordinatorFor(local, transport).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(
        [for (final batch in transport.putBatchRequests) batch.length],
        [50, 50, 20],
      );
      expect(
        {for (final batch in transport.putBatchRequests) ...batch},
        {for (final c in local) c.wireHash},
      );
      expect(transport.putBlobHashes, isEmpty, reason: 'no single upload');
      expect(transport.manifestPuts, 1);
    });

    for (final (status, refusal) in [
      (429, _FakeTransport.rateLimited),
      (503, _FakeTransport.response(503)),
    ]) {
      test('a $status on the second batch is a temporary failure that made '
          'progress', () async {
        final local = localLibrary(120);
        final transport = transportFor(local)
          ..onPutBatch = (call, _) => call == 2 ? refusal : null;

        final result = await coordinatorFor(local, transport).syncNow();

        expect(result.status, SyncPassStatus.failed);
        expect(result.failure?.cause.isTransient, isTrue);
        expect(result.failure?.step, SyncFailureStep.upload);
        expect(result.failure?.statusCode, status);
        expect(result.failure?.progressed, isTrue);
        expect(transport.putBatchCalls, 2);
        expect(transport.manifestPuts, 0);
      });
    }

    for (final (status, cause) in [
      (507, SyncFailureCause.storeFull),
      (422, SyncFailureCause.rejected),
    ]) {
      test(
        'a blob the store refuses with $status fails the pass as that '
        'single upload would, keeping the progress of the ones it stored',
        () async {
          final local = localLibrary(10);
          final refusedHash = local[4].wireHash;
          final transport = transportFor(local)
            ..putBatchStatus = (hash) => hash == refusedHash ? status : null;

          final result = await coordinatorFor(local, transport).syncNow();

          expect(result.status, SyncPassStatus.failed);
          expect(result.failure?.cause, cause);
          expect(result.failure?.step, SyncFailureStep.upload);
          expect(result.failure?.statusCode, status);
          expect(result.failure?.progressed, isTrue);
          expect(transport.manifestPuts, 0);
        },
      );
    }

    for (final status in [400, 404, 405, 413, 501]) {
      test('a $status on the batch route falls back to single uploads for the '
          'rest of the session', () async {
        final local = localLibrary(3);
        final transport = transportFor(local)
          ..onPutBatch = (_, _) => status == 501
              ? const SyncHttpResponse(
                  statusCode: 501,
                  kind: SyncResponseKind.serverError,
                  headers: {},
                  body: [],
                )
              : _FakeTransport.response(status);
        final cache = SyncPeerManifestCache();

        final result = await coordinatorFor(
          local,
          transport,
          cache: cache,
        ).syncNow();

        expect(result.status, SyncPassStatus.completed);
        expect(result.reports, isEmpty);
        expect(transport.putBatchCalls, 1);
        expect(transport.putBlobHashes, {for (final c in local) c.wireHash});
        expect(cache.blobUploadBatchUnsupported, isTrue);
      });
    }

    test('a 200 that is not the route\'s answer falls back too', () async {
      final local = localLibrary(3);
      final transport = transportFor(local)
        ..onPutBatch = (_, _) =>
            _FakeTransport.response(200, body: utf8.encode('<html></html>'));

      final result = await coordinatorFor(local, transport).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(transport.putBlobHashes, hasLength(3));
    });

    test('a blob over the size cap goes alone, and batches carry on', () async {
      final local = localLibrary(3);
      final big = SyncMergeCandidate.fromBlob(
        _tag('big-tag', 'x' * (syncMaxBlobResponseBytes + 1)),
      );
      final all = [...local, big];
      final transport = transportFor(all);
      final cache = SyncPeerManifestCache();

      final result = await coordinatorFor(
        all,
        transport,
        cache: cache,
      ).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(transport.putBlobHashes, [big.wireHash]);
      expect(
        {for (final batch in transport.putBatchRequests) ...batch},
        {for (final c in local) c.wireHash},
      );
      expect(cache.blobUploadBatchUnsupported, isFalse);
    });

    test('a batch carries at most 2 MB of blobs', () async {
      final large = [
        for (var i = 0; i < 3; i++)
          SyncMergeCandidate.fromBlob(_tag('large-$i', '$i' * 800000)),
      ];
      final transport = transportFor(large);

      final result = await coordinatorFor(large, transport).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(transport.putBlobHashes, isEmpty);
      expect(
        [for (final batch in transport.putBatchRequests) batch.length],
        [2, 1],
      );
    });

    test('a new store epoch asks for upload batches again', () {
      final cache = SyncPeerManifestCache()
        ..beginPublicationEpoch('epoch-1')
        ..blobUploadBatchUnsupported = true;
      expect(
        SyncPeerManifestCache.fromMessage(
          cache.toMessage(),
        ).blobUploadBatchUnsupported,
        isTrue,
      );
      cache.beginPublicationEpoch('epoch-2');
      expect(cache.blobUploadBatchUnsupported, isFalse);
    });
  });

  // The upload side of the same problem: against a server without
  // `PUT /v1/blobs/batch` (the fake's default), a device with a large library
  // of its own uploads one blob a request, so its first publication meets the
  // per-IP limit too; the batched equivalents are in `batched uploads (spec
  // §6.3 step 7)`. That already failed as a temporary `rateLimited`, never
  // as skipped records; what it lacked was saying it had moved on, so every
  // such pass doubled the wait before the next (spec §6.12).
  group('an upload the server refuses for now (spec §6.12)', () {
    final local = [
      for (final key in [
        'default_program_band',
        'default_program_caller',
        'default_import_tag_names',
        'custom_dialects',
      ])
        SyncMergeCandidate.fromBlob(_setting(key, 'local $key')),
    ];

    _FakeTransport transportMissingAll() => _FakeTransport(
      missingResponses: [
        [for (final c in local) c.wireHash],
      ],
    );

    Future<SyncPassResult> pass(_FakeTransport transport) => SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(local: {for (final c in local) c.address: c}),
      transport: transport,
    ).syncNow();

    test('a 429 after some uploads is a temporary failure that made '
        'progress', () async {
      final transport = transportMissingAll()
        ..onPutBlob = (call, _) =>
            call >= 3 ? _FakeTransport.rateLimited : null;

      final result = await pass(transport);

      expect(result.status, SyncPassStatus.failed);
      expect(result.failure?.cause, SyncFailureCause.rateLimited);
      expect(result.failure?.step, SyncFailureStep.upload);
      expect(result.failure?.retryAfter, const Duration(seconds: 60));
      expect(result.failure?.progressed, isTrue);
      expect(result.reports, isEmpty);
      expect(transport.putBlobHashes, hasLength(3));
      expect(transport.manifestPuts, 0);
    });

    test('a 429 on the first upload made no progress, so the wait still '
        'grows', () async {
      final transport = transportMissingAll()
        ..onPutBlob = (_, _) => _FakeTransport.rateLimited;

      final result = await pass(transport);

      expect(result.failure?.cause, SyncFailureCause.rateLimited);
      expect(result.failure?.progressed, isFalse);
    });

    test('a network failure mid-upload is a temporary result, not a throw, '
        'and says how far it got', () async {
      final transport = transportMissingAll()
        ..onPutBlob = (call, _) =>
            call == 2 ? throw const SocketException('connection reset') : null;

      final result = await pass(transport);

      expect(result.status, SyncPassStatus.failed);
      expect(result.failure?.cause, SyncFailureCause.unreachable);
      expect(result.failure?.step, SyncFailureStep.upload);
      expect(result.failure?.progressed, isTrue);
      expect(transport.manifestPuts, 0);
    });

    test('a network failure asking which blobs are missing is a temporary '
        'result at the upload step, not a throw', () async {
      final transport = transportMissingAll();
      final result = await SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(local: {for (final c in local) c.address: c}),
        transport: _FakeTransport(
          missingResponses: transport.missingResponses,
          onPostMissing: (_) async =>
              throw const SyncTransportException('request timed out'),
        ),
      ).syncNow();

      expect(result.status, SyncPassStatus.failed);
      expect(result.failure?.cause, SyncFailureCause.timedOut);
      expect(result.failure?.step, SyncFailureStep.upload);
      expect(result.failure?.progressed, isFalse);
    });

    test('a later missing-blob batch that fails keeps the progress of the '
        'batches before it', () async {
      // `POST /v1/blobs/missing` takes at most 10,000 hashes, so a library
      // this size asks twice. The first batch's uploads all land; the second
      // request drops. Those uploads are still progress.
      final many = [
        for (var i = 0; i <= 10000; i++)
          SyncMergeCandidate.fromBlob(
            _dance('dance-$i', updatedAt: DateTime.utc(2026, 7, 15, 12)),
          ),
      ];
      var asks = 0;
      final transport = _FakeTransport(
        missingResponses: [
          [for (final c in many) c.wireHash],
        ],
        onPostMissing: (_) async {
          if (++asks == 2) throw const SocketException('connection reset');
        },
      );
      final result = await SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: _FakeStore(local: {for (final c in many) c.address: c}),
        transport: transport,
      ).syncNow();

      expect(asks, 2);
      expect(transport.putBlobHashes, isNotEmpty);
      expect(result.status, SyncPassStatus.failed);
      expect(result.failure?.cause, SyncFailureCause.unreachable);
      expect(result.failure?.step, SyncFailureStep.upload);
      expect(result.failure?.progressed, isTrue);
    });
  });

  group('the capability gate (#709)', () {
    const policy = SyncCapabilityPolicy(
      advertised: {'test.v1'},
      gatedSettingKeys: {'custom_dialects': 'test.v1'},
    );
    final stamp = DateTime.utc(2026, 7, 15, 12);
    SyncMergeCandidate capabilityOf(String device, Set<String> caps) =>
        SyncMergeCandidate.fromBlob(
          SyncRecordBlob(
            kind: SyncRecordKind.setting,
            id: syncCapabilityRecordKey(device),
            updatedAt: stamp,
            deletedAt: null,
            existenceAt: stamp,
            body: {'value': syncCapabilityRecordValue(caps)},
          ),
        );
    final gated = SyncMergeCandidate.fromBlob(
      _setting('custom_dialects', 'mine', seconds: 10),
    );
    final plain = SyncMergeCandidate.fromBlob(_setting('theme_mode', 'dark'));

    SyncCoordinator coordinatorFor(
      _FakeStore store,
      _FakeTransport transport, {
      SyncCapabilityPolicy capabilities = policy,
    }) => SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: store,
      transport: transport,
      capabilityPolicy: capabilities,
    );
    _FakeTransport transportFor(
      List<String> peers, {
      Map<SyncRecordKind, Map<String, String>> peerRecords = const {},
      Map<String, SyncHttpResponse> blobs = const {},
      Set<String> missing = const {},
    }) => _FakeTransport(
      devices: ['device-a', ...peers],
      peerManifests: {
        for (final peer in peers)
          peer: _manifest(deviceId: peer, records: peerRecords),
      },
      blobResponses: blobs,
      missing: missing,
      // The fake answers its first question from `missingResponses`, whose
      // default is one empty answer, whatever `missing` says. A pass that
      // asks only once (a steady one) then uploads nothing, and no upload
      // assertion here could fail.
      missingResponses: missing.isEmpty ? null : const [],
    );
    Set<String> publishedSettings(_FakeTransport transport) =>
        (decodeSyncManifest(
                  utf8.decode(transport.manifestBodies.last),
                ).records[SyncRecordKind.setting] ??
                const <String, String>{})
            .keys
            .toSet();
    List<SyncReport> awaiting(SyncPassResult result) => [
      for (final report in result.reports)
        if (report.code == SyncReportCode.withheldAwaitingDevices) report,
    ];
    Set<String> uploaded(_FakeTransport transport) => {
      ...transport.putBlobHashes,
      for (final batch in transport.putBatchRequests) ...batch,
    };
    SyncMergeCandidate tombstoneOf(SyncMergeCandidate live) =>
        SyncMergeCandidate.fromBlob(
          SyncRecordBlob(
            kind: live.blob.kind,
            id: live.blob.id,
            updatedAt: stamp.add(const Duration(minutes: 1)),
            deletedAt: stamp.add(const Duration(minutes: 1)),
            existenceAt: stamp.add(const Duration(minutes: 1)),
            body: live.blob.body,
          ),
        );

    test('(a) a device with no capability record holds gated data back, and '
        'only that', () async {
      final store = _FakeStore(
        local: {gated.address: gated, plain.address: plain},
      );
      // Both blobs are missing from the store, so only the gate keeps the
      // gated one from uploading.
      final transport = transportFor(
        ['peer'],
        missing: {gated.wireHash, plain.wireHash},
      );
      final result = await coordinatorFor(store, transport).syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(publishedSettings(transport), {'theme_mode'});
      expect(uploaded(transport), contains(plain.wireHash));
      expect(uploaded(transport), isNot(contains(gated.wireHash)));
      expect(awaiting(result).map((r) => r.peerId), ['peer']);
      expect(awaiting(result).single.message, contains('device peer'));
    });

    test('(a\') a held-back row is marked published, which is what keeps a '
        'later delete\'s tombstone (a never-published row may be '
        'hard-deleted)', () async {
      // A row never named by a publication may be hard-deleted without a
      // tombstone; a held-back row is only waiting, so it is protected too.
      final store = _FakeStore(
        local: {gated.address: gated, plain.address: plain},
      );
      final transport = transportFor(['peer']);
      await coordinatorFor(store, transport).syncNow();

      expect(publishedSettings(transport), isNot(contains('custom_dialects')));
      expect(store.publishedRecords, contains(gated.address));
    });

    test('(a\'\') a gated tombstone is held back as a live row is', () async {
      final deleted = tombstoneOf(gated);
      final store = _FakeStore(
        local: {deleted.address: deleted, plain.address: plain},
      );
      final transport = transportFor(
        ['peer'],
        missing: {deleted.wireHash, plain.wireHash},
      );
      final result = await coordinatorFor(store, transport).syncNow();

      expect(publishedSettings(transport), {'theme_mode'});
      expect(uploaded(transport), contains(plain.wireHash));
      expect(uploaded(transport), isNot(contains(deleted.wireHash)));
      expect(awaiting(result).map((r) => r.peerId), ['peer']);
      expect(store.publishedRecords, contains(deleted.address));
    });

    test(
      'one report per device names every capability it holds back',
      () async {
        // Reports coalesce per device, so a report per capability would keep
        // only the first.
        final dialects = SyncMergeCandidate.fromBlob(
          _setting('custom_dialects', 'mine'),
        );
        final shorthands = SyncMergeCandidate.fromBlob(
          _setting('shorthand_mappings', 'mine'),
        );
        final store = _FakeStore(
          local: {dialects.address: dialects, shorthands.address: shorthands},
        );
        final result = await coordinatorFor(
          store,
          transportFor(['peer']),
          capabilities: const SyncCapabilityPolicy(
            advertised: {'a.v1', 'b.v1'},
            gatedSettingKeys: {
              'custom_dialects': 'a.v1',
              'shorthand_mappings': 'b.v1',
            },
          ),
        ).syncNow();

        final report = awaiting(result).single;
        expect(report.peerId, 'peer');
        expect(report.message, contains('a.v1, b.v1'));
      },
    );

    test('a tombstoned capability record counts as no record', () async {
      final peerCaps = tombstoneOf(capabilityOf('peer', {'test.v1'}));
      final store = _FakeStore(
        local: {gated.address: gated, peerCaps.address: peerCaps},
      );
      final transport = transportFor(['peer']);
      final result = await coordinatorFor(store, transport).syncNow();

      expect(publishedSettings(transport), isNot(contains('custom_dialects')));
      expect(awaiting(result).map((r) => r.peerId), ['peer']);
    });

    test('a store that can write a capability record writes one only while '
        'this build advertises something', () async {
      final quiet = _CapabilityRecordingStore(local: {plain.address: plain});
      await coordinatorFor(
        quiet,
        transportFor(['peer']),
        capabilities: const SyncCapabilityPolicy(
          gatedSettingKeys: {'custom_dialects': 'test.v1'},
        ),
      ).syncNow();
      expect(quiet.ensured, isEmpty);

      final advertising = _CapabilityRecordingStore(
        local: {plain.address: plain},
      );
      await coordinatorFor(advertising, transportFor(['peer'])).syncNow();
      expect(advertising.ensured.single.$1, 'device-a');
      expect(advertising.ensured.single.$2, {'test.v1'});
    });

    test('(b) once every other device advertises it, the next pass '
        'publishes it', () async {
      final peerCaps = capabilityOf('peer', {'test.v1'});
      final store = _FakeStore(
        local: {
          gated.address: gated,
          plain.address: plain,
          peerCaps.address: peerCaps,
        },
      );
      final transport = transportFor(['peer']);
      final result = await coordinatorFor(store, transport).syncNow();

      expect(
        publishedSettings(transport),
        containsAll(['custom_dialects', 'theme_mode']),
      );
      expect(awaiting(result), isEmpty);
    });

    test('(c) a device attaching without the capability closes it again, '
        'and nothing is deleted', () async {
      final peerCaps = capabilityOf('peer', {'test.v1'});
      final store = _FakeStore(
        local: {gated.address: gated, peerCaps.address: peerCaps},
      );
      // One coordinator across both passes, so a gate decided once and kept
      // would be caught; the store's device list grows between them.
      final transport = transportFor(['peer']);
      final coordinator = coordinatorFor(store, transport);
      await coordinator.syncNow();
      expect(publishedSettings(transport), contains('custom_dialects'));

      transport.devices.add('peer2');
      final result = await coordinator.syncNow();

      expect(publishedSettings(transport), isNot(contains('custom_dialects')));
      expect(awaiting(result).map((r) => r.peerId), ['peer2']);
      expect(store.local[gated.address], gated, reason: 'kept here');
      expect(store.droppedRecords, isNot(contains(gated.address)));
      expect(store.writes.where((w) => w.address == gated.address), isEmpty);
    });

    test('(d) receiving is never gated', () async {
      final theirs = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'theirs', seconds: 20),
      );
      final store = _FakeStore(local: {plain.address: plain});
      final transport = transportFor(
        ['peer'],
        peerRecords: {
          SyncRecordKind.setting: {'custom_dialects': theirs.wireHash},
        },
        blobs: {
          theirs.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(theirs.blob)),
          ),
        },
      );
      final result = await coordinatorFor(store, transport).syncNow();

      expect(result.appliedKinds, contains(SyncRecordKind.setting));
      expect(store.writes.map((w) => w.address), contains(gated.address));
    });

    test('(e) a capability record itself is never held back', () async {
      final own = capabilityOf('device-a', {'test.v1'});
      final store = _FakeStore(local: {gated.address: gated, own.address: own});
      final transport = transportFor(['peer']);
      await coordinatorFor(store, transport).syncNow();

      expect(publishedSettings(transport), {own.address.recordId});
    });

    test(
      '(g) an edit held back is not overwritten by a peer\'s older copy',
      () async {
        final older = SyncMergeCandidate.fromBlob(
          _setting('custom_dialects', 'older'),
        );
        final store = _FakeStore(local: {gated.address: gated});
        final transport = transportFor(
          ['peer'],
          peerRecords: {
            SyncRecordKind.setting: {'custom_dialects': older.wireHash},
          },
          blobs: {
            older.wireHash: _FakeTransport.response(
              200,
              body: utf8.encode(encodeSyncRecordBlob(older.blob)),
            ),
          },
        );
        final result = await coordinatorFor(store, transport).syncNow();

        expect(awaiting(result), isNotEmpty, reason: 'the gate is closed');
        expect(store.writes.where((w) => w.address == gated.address), isEmpty);
        // Filtering the merge's view instead would make the row look absent:
        // the peer's older copy is then chosen for download, and only the
        // apply step's concurrency check stops it, as a deferred change raised
        // again on every pass.
        expect(
          result.reports.where((r) => r.recordId == 'custom_dialects'),
          isEmpty,
        );
      },
    );

    test('(g\') the same holds through a fresh attach', () async {
      final older = SyncMergeCandidate.fromBlob(
        _setting('custom_dialects', 'older'),
      );
      final store = _FakeStore(
        epoch: null,
        snapshotEpochs: [null, null, 'epoch-1'],
        local: {gated.address: gated},
      );
      final transport = transportFor(
        ['peer'],
        // The store lacks the gated blob, so the attach would upload it were
        // it not held back: without this the upload assertion below cannot
        // fail, whether or not the attach path holds anything back.
        missing: {gated.wireHash},
        peerRecords: {
          SyncRecordKind.setting: {'custom_dialects': older.wireHash},
        },
        blobs: {
          older.wireHash: _FakeTransport.response(
            200,
            body: utf8.encode(encodeSyncRecordBlob(older.blob)),
          ),
        },
      );
      final result = await coordinatorFor(store, transport).syncNow();

      expect(store.writes.where((w) => w.address == gated.address), isEmpty);
      expect(
        result.reports.where((r) => r.recordId == 'custom_dialects'),
        isEmpty,
      );
      expect(publishedSettings(transport), isNot(contains('custom_dialects')));
      expect(
        transport.postMissingBatches.expand((batch) => batch),
        isNot(contains(gated.wireHash)),
        reason: 'the attach asked the store about a blob it must not publish',
      );
      expect(uploaded(transport), isNot(contains(gated.wireHash)));
    });

    test('(g\'\') a fresh attach whose blob upload fails still protects a '
        'held-back row, so deleting it leaves a tombstone', () async {
      // The attach protects held-back rows itself (§6.15) rather than leaving
      // it to the continuation pass, which a failed upload never reaches.
      final repositories = openTestRepositories();
      await repositories.settings.set('custom_dialects', 'mine'); // gated
      await repositories.settings.set('theme_mode', 'dark'); // uploaded
      final store = CompendiumSyncCoordinatorStore(repositories);
      final transport = _FakeTransport(
        devices: ['device-a', 'peer'],
        peerManifest: _manifest(deviceId: 'peer', records: const {}),
        onPostMissing: (_) async =>
            throw const SyncTransportException('request timed out'),
      );

      final result = await SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
        capabilityPolicy: policy,
      ).syncNow();

      // The attach failed at its own upload, before the continuation pass.
      expect(result.status, SyncPassStatus.failed);
      expect(result.failure?.step, SyncFailureStep.upload);
      expect(transport.manifestPuts, 0);
      expect(awaiting(result), isNotEmpty, reason: 'the gate held it back');

      // The user deletes the held-back row the way a hard-delete path does.
      await repositories.settings.remove('custom_dialects', permanent: true);

      final row = (await store.snapshot())
          .local[(kind: SyncRecordKind.setting, recordId: 'custom_dialects')];
      expect(row, isNotNull, reason: 'erased without a tombstone');
      expect(row!.blob.deletedAt, isNotNull);
    });

    test('(h) a build that does not advertise the capability never opens '
        'it, even alone in its store', () async {
      final store = _FakeStore(local: {gated.address: gated});
      final transport = transportFor(const []);
      final result = await coordinatorFor(
        store,
        transport,
        capabilities: const SyncCapabilityPolicy(
          gatedSettingKeys: {'custom_dialects': 'test.v1'},
        ),
      ).syncNow();

      expect(publishedSettings(transport), isEmpty);
      expect(awaiting(result), isEmpty, reason: 'no other device to name');
    });

    test('this build advertises glossary.v1 and glossary.v2 and gates the '
        'glossary\'s kinds and settings on them (#709, #1023)', () async {
      expect(SyncCapabilityPolicy.build.advertised, {
        SyncCapabilities.glossaryV1,
        SyncCapabilities.glossaryV2,
      });
      expect(SyncCapabilityPolicy.build.gatedRecordKinds, {
        SyncRecordKind.glossaryEntry: SyncCapabilities.glossaryV1,
        SyncRecordKind.figureNote: SyncCapabilities.glossaryV1,
      });
      expect(SyncCapabilityPolicy.build.gatedSettingKeys, {
        'show_custom_figures': SyncCapabilities.glossaryV1,
        'compound_shorthands': SyncCapabilities.glossaryV1,
        'user_figure_shorthands': SyncCapabilities.glossaryV2,
      });
      expect(SyncCapabilityPolicy.build.gatedGlossaryEntryKinds, {
        'term': SyncCapabilities.glossaryV2,
        'customFigure': SyncCapabilities.glossaryV2,
      });
      final toggle = SyncMergeCandidate.fromBlob(
        _setting('show_custom_figures', 'true'),
      );
      final shorthands = SyncMergeCandidate.fromBlob(
        _setting('compound_shorthands', '[]'),
      );
      // The shorthands for the user's new figures wait on glossary.v2, with
      // the figures themselves (#1023).
      final newFigureShorthands = SyncMergeCandidate.fromBlob(
        _setting('user_figure_shorthands', '[]'),
      );
      final local = {
        toggle.address: toggle,
        shorthands.address: shorthands,
        newFigureShorthands.address: newFigureShorthands,
        plain.address: plain,
      };

      // A peer that has not said it can read them holds them back...
      final waiting = transportFor(['peer']);
      await coordinatorFor(
        _FakeStore(local: local),
        waiting,
        capabilities: SyncCapabilityPolicy.build,
      ).syncNow();
      expect(publishedSettings(waiting), {'theme_mode'});

      // ...and alone in its store, this build publishes them all, the
      // shorthands for new figures included: it advertises glossary.v2.
      final alone = transportFor(const []);
      await coordinatorFor(
        _FakeStore(local: local),
        alone,
        capabilities: SyncCapabilityPolicy.build,
      ).syncNow();
      expect(publishedSettings(alone), {
        'show_custom_figures',
        'compound_shorthands',
        'user_figure_shorthands',
        'theme_mode',
      });
    });

    test('rollout: beside peers that have not written a capability record '
        'yet, this build holds all of the glossary back and names every '
        'peer; beside peers on the previous build, it holds back only '
        'glossary.v2 and names each; once every device advertises it, it '
        'all publishes (#709, #1023)', () async {
      // The shipped policy, not a hand-built one: this is what an update
      // that first advertises a capability meets (sync-spec §6.15). Every
      // existing peer is on a build that has written no record, so each
      // reads as closed until it updates.
      const build = SyncCapabilityPolicy.build;
      SyncMergeCandidate entryOf(String id, String kind) =>
          SyncMergeCandidate.fromBlob(
            syncRecordBlobForEntity(
              SyncRecordKind.glossaryEntry,
              StoredUserGlossaryEntry(
                id: id,
                kind: kind,
                name: id,
                definition: 'A definition.',
                description: 'A description.',
                createdAt: stamp,
              ),
              updatedAt: stamp,
              existenceAt: stamp,
            )!,
          );
      final onV1 = [
        SyncMergeCandidate.fromBlob(_setting('show_custom_figures', 'true')),
        SyncMergeCandidate.fromBlob(_setting('compound_shorthands', '[]')),
        entryOf('a-compound', 'compound'),
        SyncMergeCandidate.fromBlob(
          SyncRecordBlob(
            kind: SyncRecordKind.figureNote,
            id: 'swing',
            updatedAt: stamp,
            deletedAt: null,
            existenceAt: stamp,
            body: const {'id': 'swing', 'notes': 'Smooth.'},
          ),
        ),
      ];
      final onV2 = [
        SyncMergeCandidate.fromBlob(_setting('user_figure_shorthands', '[]')),
        entryOf('a-figure', 'customFigure'),
      ];
      for (final candidate in [...onV1, ...onV2]) {
        expect(
          build.capabilityFor(
            candidate.blob.kind,
            candidate.blob.id,
            body: candidate.blob.body,
          ),
          isNotNull,
          reason: '${candidate.blob.id} is gated by the shipped policy',
        );
      }
      final everyDevice = ['p1', 'p2', 'p3'];

      // What the build before this one advertised: glossary.v1 alone.
      const previous = {SyncCapabilities.glossaryV1};

      Future<(SyncPassResult, _FakeTransport, _FakeStore)> pass(
        Map<String, Set<String>> recorded,
      ) async {
        final records = [
          for (final MapEntry(key: peer, value: advertised) in recorded.entries)
            capabilityOf(peer, advertised),
        ];
        final local = {
          for (final c in [...onV1, ...onV2, plain, ...records]) c.address: c,
        };
        final store = _FakeStore(local: local);
        // The store holds none of these blobs, so a pass that published one
        // would upload it: without this, an upload assertion cannot fail.
        final transport = transportFor(
          everyDevice,
          missing: {
            for (final c in [...onV1, ...onV2, plain]) c.wireHash,
          },
        );
        final result = await coordinatorFor(
          store,
          transport,
          capabilities: build,
        ).syncNow();
        expect(result.status, SyncPassStatus.completed);
        expect(
          uploaded(transport),
          contains(plain.wireHash),
          reason: 'an ungated record uploads, so the checks below can fail',
        );
        return (result, transport, store);
      }

      Set<String> manifestIds(_FakeTransport transport, SyncRecordKind kind) =>
          (decodeSyncManifest(
                    utf8.decode(transport.manifestBodies.last),
                  ).records[kind] ??
                  const <String, String>{})
              .keys
              .toSet();

      // 1. No peer has a record: all of the glossary waits, every peer is
      // named, once, for both capabilities.
      var (result, transport, store) = await pass(const {});
      expect(publishedSettings(transport), {'theme_mode'});
      expect(manifestIds(transport, SyncRecordKind.glossaryEntry), isEmpty);
      expect(manifestIds(transport, SyncRecordKind.figureNote), isEmpty);
      for (final c in [...onV1, ...onV2]) {
        expect(uploaded(transport), isNot(contains(c.wireHash)));
        expect(store.publishedRecords, contains(c.address));
      }
      expect(awaiting(result).map((r) => r.peerId).toSet(), {'p1', 'p2', 'p3'});
      expect(awaiting(result), hasLength(3), reason: 'one report per peer');
      for (final report in awaiting(result)) {
        expect(report.message, contains(SyncCapabilities.glossaryV1));
        expect(report.message, contains(SyncCapabilities.glossaryV2));
      }

      // 2. Some have updated: only the ones that have not are named.
      (result, transport, store) = await pass({'p1': build.advertised});
      expect(
        publishedSettings(transport),
        isNot(contains('show_custom_figures')),
      );
      expect(awaiting(result).map((r) => r.peerId).toSet(), {'p2', 'p3'});

      // 3. Every peer is on the previous build: glossary.v1 publishes, and
      // glossary.v2 waits, each peer named once for it alone.
      (result, transport, store) = await pass({
        for (final peer in everyDevice) peer: previous,
      });
      expect(
        publishedSettings(transport),
        containsAll([
          'show_custom_figures',
          'compound_shorthands',
          'theme_mode',
        ]),
      );
      expect(manifestIds(transport, SyncRecordKind.glossaryEntry), {
        'a-compound',
      });
      expect(manifestIds(transport, SyncRecordKind.figureNote), {'swing'});
      for (final c in onV1) {
        expect(uploaded(transport), contains(c.wireHash));
      }
      expect(
        publishedSettings(transport),
        isNot(contains('user_figure_shorthands')),
      );
      for (final c in onV2) {
        expect(uploaded(transport), isNot(contains(c.wireHash)));
        expect(store.publishedRecords, contains(c.address));
      }
      expect(awaiting(result).map((r) => r.peerId).toSet(), {'p1', 'p2', 'p3'});
      expect(awaiting(result), hasLength(3), reason: 'one report per peer');
      for (final report in awaiting(result)) {
        expect(report.message, contains(SyncCapabilities.glossaryV2));
        expect(
          report.message,
          isNot(contains(SyncCapabilities.glossaryV1)),
          reason: 'nothing gated on glossary.v1 was held back',
        );
      }

      // 4. Some have updated: glossary.v2 still waits, and only the peers
      // still on the previous build are named.
      (result, transport, store) = await pass({
        'p1': build.advertised,
        'p2': previous,
        'p3': previous,
      });
      expect(manifestIds(transport, SyncRecordKind.glossaryEntry), {
        'a-compound',
      });
      expect(awaiting(result).map((r) => r.peerId).toSet(), {'p2', 'p3'});

      // 5. Every device advertises what this build does: it all publishes,
      // and no one is named.
      (result, transport, store) = await pass({
        for (final peer in everyDevice) peer: build.advertised,
      });
      expect(
        publishedSettings(transport),
        containsAll(['show_custom_figures', 'user_figure_shorthands']),
      );
      expect(manifestIds(transport, SyncRecordKind.glossaryEntry), {
        'a-compound',
        'a-figure',
      });
      for (final c in [...onV1, ...onV2]) {
        expect(uploaded(transport), contains(c.wireHash));
      }
      expect(awaiting(result), isEmpty);
    });

    test('glossary entries wait on the capability of their own kind: terms '
        'and figures of your own on glossary.v2, compounds and unknown kinds '
        'on glossary.v1, tombstones included (#1023)', () async {
      SyncMergeCandidate entryOf(String id, String kind) =>
          SyncMergeCandidate.fromBlob(
            syncRecordBlobForEntity(
              SyncRecordKind.glossaryEntry,
              StoredUserGlossaryEntry(
                id: id,
                kind: kind,
                name: id,
                definition: 'A definition.',
                description: 'A description.',
                createdAt: stamp,
              ),
              updatedAt: stamp,
              existenceAt: stamp,
            )!,
          );
      final compound = entryOf('a-compound', 'compound');
      final term = entryOf('a-term', 'term');
      final figure = entryOf('a-figure', 'customFigure');
      final gone = tombstoneOf(entryOf('a-gone-figure', 'customFigure'));
      final future = entryOf('a-future', 'someLaterKind');
      final local = {
        for (final c in [compound, term, figure, gone, future]) c.address: c,
      };
      Set<String> publishedEntries(_FakeTransport transport) =>
          (decodeSyncManifest(
                    utf8.decode(transport.manifestBodies.last),
                  ).records[SyncRecordKind.glossaryEntry] ??
                  const <String, String>{})
              .keys
              .toSet();
      // The shipped policy, which advertises both.
      const both = SyncCapabilityPolicy.build;

      // Alone in its store, this build publishes every entry.
      final alone = transportFor(const []);
      var result = await coordinatorFor(
        _FakeStore(local: local),
        alone,
        capabilities: both,
      ).syncNow();
      expect(result.status, SyncPassStatus.completed);
      expect(publishedEntries(alone), {
        'a-compound',
        'a-term',
        'a-figure',
        'a-gone-figure',
        'a-future',
      });

      // Beside a peer that only reads glossary.v1, the peer holds back only
      // the new kinds, and is named.
      final v1Peer = capabilityOf('peer', {SyncCapabilities.glossaryV1});
      final olderPeer = transportFor(['peer']);
      result = await coordinatorFor(
        _FakeStore(local: {...local, v1Peer.address: v1Peer}),
        olderPeer,
        capabilities: both,
      ).syncNow();
      expect(result.status, SyncPassStatus.completed);
      expect(publishedEntries(olderPeer), {'a-compound', 'a-future'});
      expect(awaiting(result).map((r) => r.peerId), ['peer']);
      expect(awaiting(result).single.message, contains('glossary.v2'));
      expect(
        awaiting(result).single.message,
        isNot(contains('glossary.v1')),
        reason: 'nothing gated on glossary.v1 was held back',
      );

      // Once the peer reads glossary.v2 too, everything publishes.
      final v2Peer = capabilityOf('peer', {
        SyncCapabilities.glossaryV1,
        SyncCapabilities.glossaryV2,
      });
      final updatedPeer = transportFor(['peer']);
      result = await coordinatorFor(
        _FakeStore(local: {...local, v2Peer.address: v2Peer}),
        updatedPeer,
        capabilities: both,
      ).syncNow();
      expect(result.status, SyncPassStatus.completed);
      expect(awaiting(result), isEmpty);
      expect(publishedEntries(updatedPeer), {
        'a-compound',
        'a-term',
        'a-figure',
        'a-gone-figure',
        'a-future',
      });
    });

    test('end to end: two capable devices publish their glossaries; a third '
        'with no capability record closes the gate, holding them back and '
        'deleting nothing (#709)', () async {
      // Device A, on the real store, and its own entry and note.
      final repos = openTestRepositories();
      final created = DateTime.utc(2026, 9, 1);
      await repos.userGlossary.upsert(
        UserGlossaryEntry(
          id: 'mine',
          kindName: 'compound',
          name: 'role1s spiral',
          definition: 'A spiral.',
          description: 'Round.',
          payload: const {
            'params': <Object?>[],
            'figures': <Object?>[],
            'bindings': <Object?>[],
          },
          createdAt: created,
        ),
        at: created,
      );
      await repos.figureNotes.set('swing', 'Smooth.', at: created);
      const entry = (kind: SyncRecordKind.glossaryEntry, recordId: 'mine');
      const note = (kind: SyncRecordKind.figureNote, recordId: 'swing');

      // Device B advertises glossary.v1 and publishes an entry of its own.
      final peerCaps = capabilityOf('peer', {SyncCapabilities.glossaryV1});
      final theirs = SyncMergeCandidate.fromBlob(
        syncRecordBlobForEntity(
          SyncRecordKind.glossaryEntry,
          StoredUserGlossaryEntry(
            id: 'theirs',
            kind: 'compound',
            name: 'Grand spin',
            definition: 'A spin.',
            description: 'Once round.',
            payloadJson: '{"params":[],"figures":[],"bindings":[]}',
            createdAt: created,
          ),
          updatedAt: created,
          existenceAt: created,
        )!,
      );
      final transport = _FakeTransport(
        devices: ['device-a', 'peer'],
        peerManifests: {
          'peer': _manifest(
            deviceId: 'peer',
            records: {
              SyncRecordKind.setting: {
                peerCaps.address.recordId: peerCaps.wireHash,
              },
              SyncRecordKind.glossaryEntry: {'theirs': theirs.wireHash},
            },
          ),
        },
        blobResponses: {
          for (final c in [peerCaps, theirs])
            c.wireHash: _FakeTransport.response(
              200,
              body: utf8.encode(encodeSyncRecordBlob(c.blob)),
            ),
        },
      );
      await repos.syncLocal.resetEpoch(epoch: 'epoch-1');
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: CompendiumSyncCoordinatorStore(repos),
        transport: transport,
      );
      addTearDown(coordinator.dispose);
      Map<SyncRecordKind, Map<String, String>> manifest() => decodeSyncManifest(
        utf8.decode(transport.manifestBodies.last),
      ).records;

      var result = await coordinator.syncNow();
      expect(result.status, SyncPassStatus.completed);
      expect(awaiting(result), isEmpty, reason: 'every device can read them');
      expect(manifest()[SyncRecordKind.glossaryEntry]?.keys, contains('mine'));
      expect(manifest()[SyncRecordKind.figureNote]?.keys, contains('swing'));
      expect(
        (await repos.userGlossary.getById('theirs'))?.name,
        'Grand spin',
        reason: "the peer's entry arrived",
      );
      expect(await repos.settings.get(syncCapabilityRecordKey('device-a')), {
        'capabilities': [
          SyncCapabilities.glossaryV1,
          SyncCapabilities.glossaryV2,
        ],
      }, reason: 'this build advertises the capabilities');

      // Device C attaches, on a build that advertises nothing.
      transport.devices.add('older');
      result = await coordinator.syncNow();
      expect(result.status, SyncPassStatus.completed);
      expect(awaiting(result).map((r) => r.peerId), ['older']);
      expect(manifest()[SyncRecordKind.glossaryEntry] ?? const {}, isEmpty);
      expect(manifest()[SyncRecordKind.figureNote] ?? const {}, isEmpty);
      // Held back, not deleted: every row is still here and live.
      expect((await repos.userGlossary.getById('mine'))?.name, 'role1s spiral');
      expect((await repos.userGlossary.getById('theirs'))?.name, 'Grand spin');
      expect((await repos.figureNotes.get('swing'))?.notes, 'Smooth.');
      final snapshot = await CompendiumSyncStorage(repos).snapshot();
      expect(
        snapshot.local[entry],
        isNotNull,
        reason: 'kept in the merge view',
      );
      expect(snapshot.local[note], isNotNull, reason: 'kept in the merge view');
      expect(snapshot.local[entry]!.blob.deletedAt, isNull);
      expect(snapshot.local[note]!.blob.deletedAt, isNull);

      // Device B holds its own glossary back too now: absence from its
      // manifest is not a deletion (spec §4.5), so its entry stays live here.
      transport.peerManifests['peer'] = _manifest(
        deviceId: 'peer',
        records: {
          SyncRecordKind.setting: {
            peerCaps.address.recordId: peerCaps.wireHash,
          },
        },
      );
      result = await coordinator.syncNow();
      expect(result.status, SyncPassStatus.completed);
      expect((await repos.userGlossary.getById('theirs'))?.name, 'Grand spin');

      // Device C is updated and advertises glossary.v1: the gate opens again
      // and the next pass publishes what it held back.
      final olderCaps = capabilityOf('older', {SyncCapabilities.glossaryV1});
      transport.peerManifests['older'] = _manifest(
        deviceId: 'older',
        records: {
          SyncRecordKind.setting: {
            olderCaps.address.recordId: olderCaps.wireHash,
          },
        },
      );
      transport.blobResponses[olderCaps.wireHash] = _FakeTransport.response(
        200,
        body: utf8.encode(encodeSyncRecordBlob(olderCaps.blob)),
      );
      result = await coordinator.syncNow();
      expect(result.status, SyncPassStatus.completed);
      expect(awaiting(result), isEmpty);
      expect(manifest()[SyncRecordKind.glossaryEntry]?.keys, contains('mine'));
      expect(manifest()[SyncRecordKind.figureNote]?.keys, contains('swing'));
    });

    test('the real store writes its own record only when it changes', () async {
      final repositories = openTestRepositories();
      final store = CompendiumSyncCoordinatorStore(repositories);
      final key = syncCapabilityRecordKey('device-a');

      await store.ensureCapabilityRecord('device-a', {'b.v1', 'a.v1'});
      expect(await repositories.settings.get(key), {
        'capabilities': ['a.v1', 'b.v1'],
      });
      Future<DateTime?> stampOf() async => (await store.snapshot())
          .local[(kind: SyncRecordKind.setting, recordId: key)]
          ?.blob
          .updatedAt;
      final first = await stampOf();
      expect(first, isNotNull, reason: 'the record is a synced setting');
      await store.ensureCapabilityRecord('device-a', {'a.v1', 'b.v1'});
      expect(await stampOf(), first, reason: 'unchanged: not re-stamped');
      await store.ensureCapabilityRecord('device-a', {'a.v1'});
      expect(await repositories.settings.get(key), {
        'capabilities': ['a.v1'],
      });
    });
  });

  group('a peer running a newer app version (spec §6.9)', () {
    SyncCoordinator coordinatorFor(_FakeTransport transport) => SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device-a',
      store: _FakeStore(),
      transport: transport,
    );

    test('a newer blob is reported as newerWireVersion, naming its record, '
        'not as a malformed record', () async {
      final newer = utf8.encode(
        jsonEncode({
          ..._tag('t-new', 'Newer').toJson(),
          'v': syncWireVersion + 1,
          'addedInV2': true,
        }),
      );
      final hash = sha256Hex(newer);
      final result = await coordinatorFor(
        _FakeTransport(
          devices: ['peer'],
          peerManifest: _manifest(
            deviceId: 'peer',
            records: {
              SyncRecordKind.tag: {'t-new': hash},
            },
          ),
          blobResponses: {hash: _FakeTransport.response(200, body: newer)},
        ),
      ).syncNow();

      final report = result.reports.singleWhere(
        (report) => report.recordId == 't-new',
      );
      expect(report.code, SyncReportCode.newerWireVersion);
      expect(report.kind, SyncRecordKind.tag);
      expect(report.peerId, 'peer');
    });

    test('a blob carrying a field this build does not sync is applied, not '
        'reported (spec §6.7)', () async {
      // The envelope `v` is unchanged: a newer build added a body field, as
      // #1714 added a program's pay. This build keeps it rather than refusing
      // the record.
      final tag = _tag('t-new', 'Newer').toJson();
      final newer = utf8.encode(
        jsonEncode({
          ...tag,
          'body': {...(tag['body']! as Map<String, Object?>), 'addedLater': 1},
        }),
      );
      final hash = sha256Hex(newer);
      final result = await coordinatorFor(
        _FakeTransport(
          devices: ['peer'],
          peerManifest: _manifest(
            deviceId: 'peer',
            records: {
              SyncRecordKind.tag: {'t-new': hash},
            },
          ),
          blobResponses: {hash: _FakeTransport.response(200, body: newer)},
        ),
      ).syncNow();

      expect(
        result.reports.where((report) => report.recordId == 't-new'),
        isEmpty,
      );
    });

    test('a dance whose figures a newer build extended is reported as '
        'newerFigures, naming its record', () async {
      final dance = SyncRecordBlob(
        kind: SyncRecordKind.dance,
        id: 'd-new',
        updatedAt: DateTime.utc(2026, 7, 15, 12),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 7, 15, 12),
        body: const {'id': 'd-new', 'title': 'Newer'},
      ).toJson();
      final newer = utf8.encode(
        jsonEncode({
          ...dance,
          'body': {
            ...(dance['body']! as Map<String, Object?>),
            'figures': [
              {'schemaVersion': 1, 'move': 'swing', 'handHold': 'cross'},
            ],
          },
        }),
      );
      final hash = sha256Hex(newer);
      final result = await coordinatorFor(
        _FakeTransport(
          devices: ['peer'],
          peerManifest: _manifest(
            deviceId: 'peer',
            records: {
              SyncRecordKind.dance: {'d-new': hash},
            },
          ),
          blobResponses: {hash: _FakeTransport.response(200, body: newer)},
        ),
      ).syncNow();

      final report = result.reports.singleWhere(
        (report) => report.recordId == 'd-new',
      );
      expect(report.code, SyncReportCode.newerFigures);
      expect(report.kind, SyncRecordKind.dance);
      expect(report.peerId, 'peer');
    });

    test('a newer manifest is reported as newerWireVersion for the peer, '
        'naming no record', () async {
      final newer = utf8.encode(
        jsonEncode({
          ..._manifest(deviceId: 'peer', records: const {}).toJson(),
          'v': syncWireVersion + 1,
          'addedInV2': true,
        }),
      );
      final result = await coordinatorFor(
        _FakeTransport(
          devices: ['peer'],
          manifestResponses: {
            'peer': [_FakeTransport.response(200, body: newer)],
          },
        ),
      ).syncNow();

      final report = result.reports.singleWhere(
        (report) => report.peerId == 'peer',
      );
      expect(report.code, SyncReportCode.newerWireVersion);
      expect(report.kind, isNull);
      expect(report.recordId, isNull);
    });

    test('a manifest listing a record kind this build does not know still '
        'delivers the known records, is reported as newerRecordKind, and is '
        'never kept (#709)', () async {
      final tagBlob = utf8.encode(encodeSyncRecordBlob(_tag('t-1', 'Known')));
      final tagHash = sha256Hex(tagBlob);
      final known = _manifest(
        deviceId: 'peer',
        records: {
          SyncRecordKind.tag: {'t-1': tagHash},
        },
      ).toJson();
      final manifestBody = utf8.encode(
        jsonEncode({
          ...known,
          'records': {
            ...(known['records']! as Map<String, Object?>),
            'futureKind': {'future-1': 'b' * 64},
          },
        }),
      );
      SyncHttpResponse full() => SyncHttpResponse(
        statusCode: 200,
        kind: SyncResponseKind.success,
        headers: const {'etag': '"peer-v1"'},
        body: manifestBody,
      );
      final store = _FakeStore();
      final transport = _FakeTransport(
        devices: ['peer'],
        manifestResponses: {
          'peer': [full(), full()],
        },
        blobResponses: {tagHash: _FakeTransport.response(200, body: tagBlob)},
      );
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );

      final result = await coordinator.syncNow();

      expect(result.status, SyncPassStatus.completed);
      expect(result.appliedKinds, contains(SyncRecordKind.tag));
      final report = result.reports.singleWhere(
        (report) => report.peerId == 'peer',
      );
      expect(report.code, SyncReportCode.newerRecordKind);
      expect(report.kind, isNull);
      expect(report.message, contains('futureKind'));
      // Neither cache keeps the copy, which has lost the unknown kind: the
      // next pass asks in full, with no ETag a `304` could answer.
      expect(store.peerManifests, isNot(contains('peer')));
      await coordinator.syncNow();
      expect(transport.manifestEtags, [null, null]);
    });

    test('a genuinely malformed blob is still malformedRecord', () async {
      final broken = utf8.encode(jsonEncode({'v': syncWireVersion}));
      final hash = sha256Hex(broken);
      final result = await coordinatorFor(
        _FakeTransport(
          devices: ['peer'],
          peerManifest: _manifest(
            deviceId: 'peer',
            records: {
              SyncRecordKind.tag: {'t-bad': hash},
            },
          ),
          blobResponses: {hash: _FakeTransport.response(200, body: broken)},
        ),
      ).syncNow();

      expect(
        result.reports.singleWhere((r) => r.recordId == 't-bad').code,
        SyncReportCode.malformedRecord,
      );
    });
  });
  group('a pass that throws still knows what it committed (#1913)', () {
    // The worker isolate reads `passAppliedKinds` after a throw, because a
    // throw carries no `SyncPassResult` to hold them; see sync_isolate.dart.
    final theirs = SyncMergeCandidate.fromBlob(
      _setting('theme_mode', 'theirs', seconds: 20),
    );

    _FakeTransport inbound({void Function(List<int> body)? onManifestPut}) =>
        _FakeTransport(
          devices: const ['device-a', 'peer'],
          peerManifest: _manifest(
            deviceId: 'peer',
            records: {
              SyncRecordKind.setting: {theirs.blob.id: theirs.wireHash},
            },
          ),
          blobResponses: _blobs([theirs]),
          onManifestPut: onManifestPut,
        );

    SyncCoordinator coordinatorFor(_FakeStore store, _FakeTransport transport) {
      final coordinator = SyncCoordinator(
        syncId: 'configured',
        deviceId: 'device-a',
        store: store,
        transport: transport,
      );
      addTearDown(coordinator.dispose);
      return coordinator;
    }

    test('an apply that committed before the throw is recorded', () async {
      final store = _FakeStore();
      final coordinator = coordinatorFor(
        store,
        inbound(onManifestPut: (_) => throw const SocketException('reset')),
      );

      await expectLater(coordinator.syncNow(), throwsA(isA<SocketException>()));

      expect(store.writes.map((write) => write.address), [theirs.address]);
      expect(coordinator.passAppliedKinds, {SyncRecordKind.setting});
    });

    test('an apply that rolled back records nothing', () async {
      // The rebuild runs inside the apply transaction, so its throw rolls the
      // writes back and escapes the engine: nothing was committed, and a kind
      // recorded before the commit would make the main isolate reload rows
      // that never changed.
      final store = _FakeStore()
        ..failRebuildDerivedIndexes = StateError('rebuild failed');
      final coordinator = coordinatorFor(store, inbound());

      await expectLater(coordinator.syncNow(), throwsA(isA<StateError>()));

      expect(coordinator.passAppliedKinds, isEmpty);
    });

    test('the success path returns the kinds it always did, and each pass '
        'starts empty', () async {
      final store = _FakeStore();
      final coordinator = coordinatorFor(store, inbound());

      final first = await coordinator.syncNow();
      expect(first.appliedKinds, [SyncRecordKind.setting]);
      expect(coordinator.passAppliedKinds, {SyncRecordKind.setting});

      store.local[theirs.address] = theirs;
      final second = await coordinator.syncNow();
      expect(second.appliedKinds, isEmpty);
      expect(coordinator.passAppliedKinds, isEmpty);
    });
  });
}

/// A [_FakeStore] that can write a capability record, recording each call.
final class _CapabilityRecordingStore extends _FakeStore
    implements SyncCapabilityRecordStore {
  _CapabilityRecordingStore({super.local});

  final List<(String, Set<String>)> ensured = [];

  @override
  Future<void> ensureCapabilityRecord(
    String deviceId,
    Set<String> capabilities,
  ) async => ensured.add((deviceId, {...capabilities}));
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
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> currentCandidates(
    Set<SyncRecordAddress> addresses,
  ) => _delegate.currentCandidates(addresses);

  @override
  Future<SyncAliasMap> aliasMap() => _delegate.aliasMap();

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
  Future<int> refreshConflictReviews(
    Iterable<SyncMergeDecision> reviews, {
    Set<SyncRecordAddress> unevaluated = const {},
  }) => _delegate.refreshConflictReviews(reviews, unevaluated: unevaluated);

  @override
  Future<Set<SyncRecordAddress>> queuedConflictAddresses() =>
      _delegate.queuedConflictAddresses();

  @override
  Future<Map<SyncRecordAddress, Set<String>>> decidedAgainstHashes() =>
      _delegate.decidedAgainstHashes();

  @override
  Future<void> replaceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
  }) => _delegate.replaceBaseline(epoch: epoch, entries: entries);

  @override
  Future<void> clearEpochState() => _delegate.clearEpochState();

  @override
  Future<SyncPublishedManifest?> publishedManifest({required String epoch}) =>
      _delegate.publishedManifest(epoch: epoch);

  @override
  Future<void> setPublishedManifest({
    required String epoch,
    required SyncPublishedManifest? published,
  }) => _delegate.setPublishedManifest(epoch: epoch, published: published);

  @override
  Future<SyncStoredPeerManifest?> storedPeerManifest(String peerId) =>
      _delegate.storedPeerManifest(peerId);

  @override
  Future<void> storePeerManifest(
    String peerId,
    SyncStoredPeerManifest manifest,
  ) => _delegate.storePeerManifest(peerId, manifest);

  @override
  Future<void> forgetPeerManifest(String peerId) =>
      _delegate.forgetPeerManifest(peerId);

  @override
  Future<void> retainPeerManifests({
    required String epoch,
    required Set<String> peerIds,
  }) => _delegate.retainPeerManifests(epoch: epoch, peerIds: peerIds);

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
  Future<void> reindexDerivedAfterApply(Set<SyncRecordAddress> applied) =>
      _delegate.reindexDerivedAfterApply(applied);

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
  int aliasMapCalls = 0;
  int baselineAdvances = 0;
  int baselineReplacements = 0;
  int epochStateClears = 0;

  /// What this device last published, as storage records it, and the epoch
  /// it was recorded for.
  ({String epoch, SyncPublishedManifest record})? published;

  /// Every [setPublishedManifest] call, in order; null for a clear.
  final List<SyncPublishedManifest?> publishedWrites = [];
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
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> currentCandidates(
    Set<SyncRecordAddress> addresses,
  ) async {
    final current = currentCandidatesBuilder?.call() ?? local;
    return {
      for (final address in addresses)
        if (current.containsKey(address)) address: current[address],
    };
  }

  @override
  Future<SyncAliasMap> aliasMap() async {
    aliasMapCalls++;
    final byKind = <SyncRecordKind, Map<String, String>>{};
    for (final entry in aliases.entries) {
      byKind.putIfAbsent(entry.key.kind, () => {})[entry.key.recordId] =
          entry.value.recordId;
    }
    return SyncAliasMap(byKind);
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

  /// Refuses, as storage does for a reference to data this device lacks, the
  /// records for which it returns true.
  bool Function(SyncApplyRecord record)? refuseWrite;

  @override
  Future<void> write(SyncApplyRecord record) async {
    if (refuseWrite?.call(record) ?? false) {
      throw StateError('scripted refusal');
    }
    writes.add(record);
  }

  /// Thrown from [reindexDerivedAfterApply] when set: the apply engine runs it
  /// inside its transaction, so this is an apply that rolls back and throws.
  Object? failRebuildDerivedIndexes;

  @override
  Future<void> reindexDerivedAfterApply(Set<SyncRecordAddress> applied) async {
    if (failRebuildDerivedIndexes case final error?) throw error;
  }

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

  /// Every pass's conflict reviews, in call order.
  final List<List<SyncMergeDecision>> conflictReviewCalls = [];

  @override
  Future<int> refreshConflictReviews(
    Iterable<SyncMergeDecision> reviews, {
    Set<SyncRecordAddress> unevaluated = const {},
  }) async {
    conflictReviewCalls.add(reviews.toList());
    return 0;
  }

  /// Conflict choices already queued, as storage would return them.
  Set<SyncRecordAddress> queuedConflicts = {};

  @override
  Future<Set<SyncRecordAddress>> queuedConflictAddresses() async =>
      queuedConflicts;

  @override
  Future<Map<SyncRecordAddress, Set<String>>> decidedAgainstHashes() async =>
      const {};

  @override
  Future<void> replaceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
  }) async {
    _storedEpoch = epoch;
    published = null;
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
    published = null;
    peerManifests.clear();
    epochStateClears++;
    lifecycle.add('clearEpochState');
  }

  /// Peer manifests kept on disk (spec §5.2), as storage would hold them.
  final Map<String, SyncStoredPeerManifest> peerManifests = {};

  @override
  Future<SyncStoredPeerManifest?> storedPeerManifest(String peerId) async =>
      peerManifests[peerId];

  @override
  Future<void> storePeerManifest(
    String peerId,
    SyncStoredPeerManifest manifest,
  ) async {
    peerManifests[peerId] = manifest;
  }

  @override
  Future<void> forgetPeerManifest(String peerId) async {
    peerManifests.remove(peerId);
  }

  @override
  Future<void> retainPeerManifests({
    required String epoch,
    required Set<String> peerIds,
  }) async {
    peerManifests.removeWhere(
      (peerId, kept) => kept.epoch != epoch || !peerIds.contains(peerId),
    );
  }

  @override
  Future<SyncPublishedManifest?> publishedManifest({
    required String epoch,
  }) async => published?.epoch == epoch ? published!.record : null;

  @override
  Future<void> setPublishedManifest({
    required String epoch,
    required SyncPublishedManifest? published,
  }) async {
    lifecycle.add('setPublishedManifest');
    publishedWrites.add(published);
    this.published = published == null
        ? null
        : (epoch: epoch, record: published);
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
    this.missing = const {},
    this.putManifestStatus = 200,
    List<int>? putManifestStatuses,
    this.onManifestPut,
    this.onManifestGet,
    this.onPostMissing,
    List<int>? postMissingStatuses,
    this.storeQuota,
    this.batchSupported = false,
    this.uploadBatchSupported = false,
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

  /// The `quota` member of every store answer, verbatim; omitted when null.
  final Object? storeQuota;
  final Completer<void>? _storeReadGate;
  final List<String> devices;
  final List<String> storeEpochs;
  final SyncManifest? peerManifest;
  final Map<String, SyncManifest> peerManifests;
  final List<SyncHttpResponse> createResponses;
  final Map<String, List<SyncHttpResponse>> manifestResponses;
  final Map<String, SyncHttpResponse> blobResponses;

  /// Hashes the store does not hold: [postMissing] reports each one of these
  /// that it is asked about, so the pass uploads it. Without it the default
  /// answer is empty, and a test asserting that a blob was *not* uploaded
  /// passes whether or not the code under test would have uploaded it.
  /// [missingResponses] takes precedence for the calls it scripts.
  final Set<String> missing;

  /// Answers the [call]th blob request (1-based) for [hash] in place of
  /// [blobResponses] when it returns non-null; may throw, as a transport does.
  /// Assigned after construction, so a test can lift a limit between passes.
  SyncHttpResponse? Function(int call, String hash)? onBlob;

  /// Whether [postBlobBatch] is a route this server has. Off by default, as
  /// for an Athenaeum from before it: a test written against single requests
  /// then exercises the fallback that keeps them, and sees only `getBlob`.
  final bool batchSupported;

  /// Answers the [call]th batch request (1-based) in place of the frames it
  /// would otherwise serve, when it returns non-null.
  SyncHttpResponse? Function(int call, List<String> hashes)? onBatch;

  /// Throws, before the frame at [index] of the [call]th batch, what it
  /// returns when non-null: the stream breaking with earlier frames sent.
  Object? Function(int call, int index)? cutBatch;
  int batchCalls = 0;
  final batchRequests = <List<String>>[];

  /// Whether [putBlobBatch] is a route this server has; off by default, for
  /// the same reason as [batchSupported].
  final bool uploadBatchSupported;

  /// Answers the [call]th batch upload (1-based) in place of storing it, when
  /// it returns non-null.
  SyncHttpResponse? Function(int call, List<String> hashes)? onPutBatch;

  /// The status the store gives one blob of a batch upload; `201` when null.
  int? Function(String hash)? putBatchStatus;
  int putBatchCalls = 0;
  final putBatchRequests = <List<String>>[];

  /// Answers the [call]th blob upload (1-based) in place of a `201` when it
  /// returns non-null; may throw, as a transport does.
  SyncHttpResponse? Function(int call, String hash)? onPutBlob;
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
  final blobHashes = <String>[];
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
      body: jsonEncode({
        'epoch': epoch,
        'devices': devices,
        'quota': ?storeQuota,
      }),
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
        : [
            for (final hash in batch)
              if (missing.contains(hash)) hash,
          ];
    final status = postMissingStatuses.isNotEmpty
        ? postMissingStatuses.removeAt(0)
        : 200;
    return _response(status, body: jsonEncode({'missing': response}));
  }

  @override
  Future<SyncHttpResponse> getBlob(String hash) async {
    blobCalls++;
    blobHashes.add(hash);
    requestLog.add('blob');
    return onBlob?.call(blobCalls, hash) ??
        blobResponses[hash] ??
        _response(404);
  }

  /// Serves a batch from [blobResponses]: a `200` there is the blob, anything
  /// else is `missing`, as the server answers a hash it cannot serve.
  @override
  Future<SyncHttpResponse> postBlobBatch(
    List<String> hashes, {
    required void Function(SyncBlobBatchFrame frame) onFrame,
  }) async {
    batchCalls++;
    batchRequests.add([...hashes]);
    if (!batchSupported) return _response(404);
    requestLog.add('batch');
    final scripted = onBatch?.call(batchCalls, hashes);
    if (scripted != null) return scripted;
    for (final (index, hash) in hashes.indexed) {
      final cut = cutBatch?.call(batchCalls, index);
      if (cut != null) throw cut;
      final blob = blobResponses[hash];
      onFrame(
        blob != null && blob.isSuccess
            ? SyncBlobBatchFrame(
                SyncBlobBatchFrameStatus.blob,
                hash,
                Uint8List.fromList(blob.body),
              )
            : SyncBlobBatchFrame(SyncBlobBatchFrameStatus.missing, hash),
      );
    }
    return _response(200);
  }

  @override
  Future<SyncHttpResponse> putBlob(String hash, List<int> body) async {
    putBlobHashes.add(hash);
    return onPutBlob?.call(putBlobHashes.length, hash) ?? _response(201);
  }

  @override
  Future<SyncHttpResponse> putBlobBatch(
    List<({String hash, List<int> body})> blobs,
  ) async {
    putBatchCalls++;
    final hashes = [for (final blob in blobs) blob.hash];
    putBatchRequests.add(hashes);
    if (!uploadBatchSupported) return _response(404);
    requestLog.add('put-batch');
    final scripted = onPutBatch?.call(putBatchCalls, hashes);
    if (scripted != null) return scripted;
    return _response(
      200,
      body: jsonEncode({
        'results': [
          for (final hash in hashes)
            {'hash': hash, 'status': putBatchStatus?.call(hash) ?? 201},
        ],
      }),
    );
  }

  static SyncHttpResponse response(int status, {List<int>? body}) =>
      _response(status, body: body == null ? null : utf8.decode(body));

  /// The server's `429`, exactly as `SyncHttpClient` reads it.
  static const rateLimited = SyncHttpResponse(
    statusCode: 429,
    kind: SyncResponseKind.rateLimited,
    headers: {'retry-after': '60'},
    body: [],
    retryAfter: Duration(seconds: 60),
  );

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
      403 => SyncResponseKind.invalidSyncId,
      500 || 503 => SyncResponseKind.serverError,
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

SyncRecordBlob _choreographer(
  String id,
  String name, {
  required DateTime updatedAt,
  DateTime? existenceAt,
}) => SyncRecordBlob(
  kind: SyncRecordKind.choreographer,
  id: id,
  updatedAt: updatedAt,
  deletedAt: null,
  existenceAt: existenceAt ?? updatedAt,
  body: {'id': id, 'name': name},
);

SyncRecordBlob _danceCiting(
  String id,
  String authorId, {
  required DateTime updatedAt,
  String title = 'Dance',
}) => SyncRecordBlob(
  kind: SyncRecordKind.dance,
  id: id,
  updatedAt: updatedAt,
  deletedAt: null,
  existenceAt: updatedAt,
  body: {
    'id': id,
    'title': title,
    'authorIds': [authorId],
  },
);

Map<String, SyncHttpResponse> _blobs(Iterable<SyncMergeCandidate> candidates) =>
    {
      for (final candidate in candidates)
        candidate.wireHash: _FakeTransport.response(
          200,
          body: utf8.encode(encodeSyncRecordBlob(candidate.blob)),
        ),
    };

String _hash(String character) => List.filled(64, character).join();
