import 'dart:async';
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';

import '../diagnostics/error_log.dart';
import 'sync_http_client.dart';

/// The event sources that share the single-flight sync scheduler.
enum SyncTrigger { appStart, debouncedChange, manual }

/// The terminal state of one coordinator pass.
enum SyncPassStatus {
  completed,
  skippedUnconfigured,
  paused,
  replacementRequired,
  firstTimeStoreRequired,
  freshAttachRequired,
  staleEpoch,
  failed,
}

/// The result returned by a coordinator pass or explicit replacement action.
class SyncPassResult {
  const SyncPassResult(
    this.status, {
    this.reports = const [],
    this.message,
    this.duplicateCount = 0,
  });

  final SyncPassStatus status;
  final List<SyncReport> reports;
  final String? message;
  final int duplicateCount;
}

/// The data needed to construct a local manifest and calculate a pass.
class SyncCoordinatorSnapshot {
  SyncCoordinatorSnapshot({
    required this.epoch,
    required this.previouslyUsed,
    required Map<SyncRecordAddress, SyncMergeCandidate?> local,
    required Map<SyncRecordAddress, SyncBaselineEntry> baseline,
    Map<SyncRecordAddress, SyncMergeCandidate?>? publication,
    Map<SyncRecordAddress, SyncMergeCandidate?>? pendingLive,
    Set<SyncRecordAddress> pending = const {},
  }) : local = Map.unmodifiable(local),
       baseline = Map.unmodifiable(baseline),
       publication = Map.unmodifiable(publication ?? local),
       pendingLive = Map.unmodifiable(pendingLive ?? const {}),
       pending = Set.unmodifiable(pending);

  final String? epoch;
  final bool previouslyUsed;
  final Map<SyncRecordAddress, SyncMergeCandidate?> local;
  final Map<SyncRecordAddress, SyncBaselineEntry> baseline;
  final Map<SyncRecordAddress, SyncMergeCandidate?> publication;
  final Map<SyncRecordAddress, SyncMergeCandidate?> pendingLive;
  final Set<SyncRecordAddress> pending;
}

/// Storage operations that the coordinator must compose with inbound apply.
///
/// The implementation owns the real database transaction. In particular,
/// [SyncApplyStorage.transaction] must cover the whole inbound apply rather
/// than only an individual record.
abstract interface class SyncCoordinatorStore
    implements SyncApplyConcurrencyStorage {
  Future<SyncCoordinatorSnapshot> snapshot();

  @override
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> snapshotCandidates();

  Future<SyncRecordAddress> resolveAlias(SyncRecordAddress address);

  Future<void> markSyncUsed(String syncId);

  Future<void> markPublished(Iterable<SyncRecordAddress> records);

  /// Drops aliases whose losing IDs no longer appear in any verified peer
  /// manifest. The coordinator only invokes this when every current peer
  /// manifest was available for the epoch.
  Future<void> retireAliases({required Set<SyncRecordAddress> peerAddresses});

  /// Records publication intent before the network PUT, so a crash after the
  /// server accepts the manifest cannot lose the previously-used marker.
  Future<void> markPublicationAttempt({
    required String syncId,
    required Iterable<SyncRecordAddress> records,
  });

  Future<SyncFreshAttachDedupeResult> deduplicateFreshAttach({
    required bool apply,
  });

  Future<void> replaceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
  });

  Future<void> advanceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
    required Iterable<SyncRecordAddress> drop,
  });
}

/// Adapts the core repository/database sync boundary to the app coordinator.
///
/// The adapter is intentionally small: all entity mapping and transaction
/// semantics live in [CompendiumSyncStorage], while this layer owns only the
/// coordinator's baseline/publication lifecycle.
final class CompendiumSyncCoordinatorStore
    implements SyncCoordinatorStore, SyncApplyReconciliationStorage {
  CompendiumSyncCoordinatorStore(
    CompendiumRepositories repositories, {
    this.syncId,
  }) : storage = CompendiumSyncStorage(repositories);

  final CompendiumSyncStorage storage;
  final String? syncId;

  @override
  Future<SyncCoordinatorSnapshot> snapshot() async {
    final snapshot = await storage.snapshot(syncId: syncId);
    return SyncCoordinatorSnapshot(
      epoch: snapshot.epoch,
      previouslyUsed: snapshot.previouslyUsed,
      local: snapshot.local,
      baseline: snapshot.baseline,
      publication: snapshot.publication,
      pendingLive: snapshot.pendingLive,
      pending: snapshot.pending,
    );
  }

  @override
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> snapshotCandidates() =>
      storage.snapshot().then((snapshot) => snapshot.local);

  @override
  Future<SyncRecordAddress> resolveAlias(SyncRecordAddress address) async {
    final recordId = await storage.repositories.syncLocal.resolveAlias(
      kind: address.kind,
      recordId: address.recordId,
    );
    return (kind: address.kind, recordId: recordId);
  }

  @override
  Future<SyncApplyPreparation> reconcileInbound(
    List<SyncMergeCandidate> candidates, {
    Map<SyncRecordAddress, String?>? expectedWireHashes,
  }) => storage.reconcileInbound(
    candidates,
    expectedWireHashes: expectedWireHashes,
  );

  @override
  Future<void> setInboundTombstoneContext(
    Set<SyncRecordAddress> tombstonedAddresses,
  ) => storage.setInboundTombstoneContext(tombstonedAddresses);

  @override
  Future<void> clearReconciliationContext() =>
      storage.clearReconciliationContext();

  @override
  Future<void> markSyncUsed(String syncId) => storage.markSyncUsed(syncId);

  @override
  Future<void> markPublished(Iterable<SyncRecordAddress> records) =>
      storage.repositories.syncLocal.markPublishedAll(records);

  @override
  Future<void> retireAliases({required Set<SyncRecordAddress> peerAddresses}) =>
      storage.repositories.syncLocal.retireAliases(
        peerAddresses: peerAddresses,
      );

  @override
  Future<void> markPublicationAttempt({
    required String syncId,
    required Iterable<SyncRecordAddress> records,
  }) => storage.markPublicationAttempt(syncId: syncId, records: records);

  @override
  Future<SyncFreshAttachDedupeResult> deduplicateFreshAttach({
    required bool apply,
  }) => storage.deduplicateFreshAttach(apply: apply);

  @override
  Future<void> replaceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
  }) => storage.repositories.syncLocal.replaceBaseline(
    epoch: epoch,
    entries: entries,
  );

  @override
  Future<void> advanceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
    required Iterable<SyncRecordAddress> drop,
  }) => storage.repositories.syncLocal.advanceBaseline(
    epoch: epoch,
    entries: entries,
    drop: drop,
  );

  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      storage.transaction(action);

  @override
  Future<Map<String, Object?>?> read(SyncRecordAddress address) =>
      storage.read(address);

  @override
  Future<void> write(SyncApplyRecord record) => storage.write(record);

  @override
  Future<SyncReport?> validateInboundReferences(
    SyncApplyRecord record, {
    Set<SyncRecordAddress> inboundLiveAddresses = const {},
    Set<SyncRecordAddress> inboundAddresses = const {},
    Map<SyncRecordAddress, SyncApplyRecord> inboundRecords = const {},
  }) => storage.validateInboundReferences(
    record,
    inboundLiveAddresses: inboundLiveAddresses,
    inboundAddresses: inboundAddresses,
    inboundRecords: inboundRecords,
  );

  @override
  Future<SyncReport?> writeWithReport(SyncApplyRecord record) =>
      storage.writeWithReport(record);

  @override
  Future<SyncReport?> writeParentWithReport(SyncApplyRecord record) =>
      storage.writeParentWithReport(record);

  @override
  Future<SyncReport?> writeJoinsWithReport(SyncApplyRecord record) =>
      storage.writeJoinsWithReport(record);

  @override
  Future<void> rebuildDerivedIndexes() => storage.rebuildDerivedIndexes();
}

/// The transport surface consumed by [SyncCoordinator].
abstract interface class SyncCoordinatorTransport {
  Future<SyncStoreResult> getStore({required bool previouslyUsed});

  Future<SyncHttpResponse> createStore();

  Future<SyncHttpResponse> getManifest(String deviceId, {String? etag});

  Future<SyncHttpResponse> putManifest(String deviceId, List<int> body);

  Future<SyncHttpResponse> postMissing(Iterable<String> hashes);

  Future<SyncHttpResponse> getBlob(String hash);

  Future<SyncHttpResponse> putBlob(String hash, List<int> body);
}

/// Adapts the authenticated HTTP client to the coordinator transport seam.
final class SyncHttpCoordinatorTransport implements SyncCoordinatorTransport {
  const SyncHttpCoordinatorTransport(this.client);

  final SyncHttpClient client;

  @override
  Future<SyncStoreResult> getStore({required bool previouslyUsed}) =>
      client.getStore(previouslyUsed: previouslyUsed);

  @override
  Future<SyncHttpResponse> createStore() => client.createStore();

  @override
  Future<SyncHttpResponse> getManifest(String deviceId, {String? etag}) =>
      client.getManifest(deviceId, etag: etag);

  @override
  Future<SyncHttpResponse> putManifest(String deviceId, List<int> body) =>
      client.putManifest(deviceId, body);

  @override
  Future<SyncHttpResponse> postMissing(Iterable<String> hashes) =>
      client.postMissing(hashes);

  @override
  Future<SyncHttpResponse> getBlob(String hash) => client.getBlob(hash);

  @override
  Future<SyncHttpResponse> putBlob(String hash, List<int> body) =>
      client.putBlob(hash, body);
}

/// An injectable boundary for the pass operation.
///
/// The inline runner is retained for callers that already own the database and
/// transport. Production passes use [SyncPassOperation] to open those
/// resources inside a background isolate.
abstract interface class SyncPassRunner {
  Future<T> run<T>(Future<T> Function() action);
}

/// Runs a complete pass through an externally-owned execution boundary.
///
/// Production uses this to open the database and transport inside a background
/// isolate. Tests can inject a deterministic operation without depending on
/// isolate or native-database setup.
typedef SyncPassOperation = Future<SyncPassResult> Function();

/// Runs a pass against resources that are already owned by the calling
/// isolate. The transaction-bound apply still provides atomic interruption
/// semantics for the database portion of the pass.
final class TransactionBoundSyncPassRunner implements SyncPassRunner {
  const TransactionBoundSyncPassRunner();

  @override
  Future<T> run<T>(Future<T> Function() action) => action();
}

final class SyncPeerManifestCacheEntry {
  const SyncPeerManifestCacheEntry({
    required this.epoch,
    required this.etag,
    required this.manifest,
  });

  final String epoch;
  final String etag;
  final SyncManifest manifest;
}

/// Keeps verified peer manifests across isolated production passes.
///
/// Isolate boundaries cannot retain the coordinator instance, so this cache
/// has an explicit message representation that the pass operation can return
/// to its owner after each worker finishes.
final class SyncPeerManifestCache {
  SyncPeerManifestCache({Map<String, SyncPeerManifestCacheEntry>? entries})
    : _entries = {...?entries};

  final Map<String, SyncPeerManifestCacheEntry> _entries;

  SyncPeerManifestCacheEntry? operator [](String peerId) => _entries[peerId];

  void operator []=(String peerId, SyncPeerManifestCacheEntry entry) {
    _entries[peerId] = entry;
  }

  void remove(String peerId) {
    _entries.remove(peerId);
  }

  void clear() {
    _entries.clear();
  }

  void replaceFrom(SyncPeerManifestCache source) {
    _entries
      ..clear()
      ..addAll(source._entries);
  }

  Map<String, Object?> toMessage() => {
    for (final entry in _entries.entries)
      entry.key: {
        'epoch': entry.value.epoch,
        'etag': entry.value.etag,
        'manifest': utf8.decode(encodeSyncManifestUtf8(entry.value.manifest)),
      },
  };

  static SyncPeerManifestCache fromMessage(Object? message) {
    if (message == null) return SyncPeerManifestCache();
    if (message is! Map<Object?, Object?>) {
      throw const FormatException('sync isolate returned a malformed cache');
    }
    final entries = <String, SyncPeerManifestCacheEntry>{};
    for (final rawEntry in message.entries) {
      final peerId = rawEntry.key;
      final value = rawEntry.value;
      if (peerId is! String || value is! Map<Object?, Object?>) {
        throw const FormatException('sync isolate returned a malformed cache');
      }
      final epoch = value['epoch'];
      final etag = value['etag'];
      final manifestBody = value['manifest'];
      if (epoch is! String || etag is! String || manifestBody is! String) {
        throw const FormatException('sync isolate returned a malformed cache');
      }
      entries[peerId] = SyncPeerManifestCacheEntry(
        epoch: epoch,
        etag: etag,
        manifest: decodeSyncManifest(manifestBody),
      );
    }
    return SyncPeerManifestCache(entries: entries);
  }
}

/// A coalesced notification that a previously-used remote store is missing.
class SyncReplacementRequiredEvent {
  const SyncReplacementRequiredEvent();
}

/// Coordinates one steady-state pass and its explicit replacement decision.
class SyncCoordinator {
  SyncCoordinator({
    required this.syncId,
    required this.deviceId,
    required this.store,
    required this.transport,
    this.passRunner = const TransactionBoundSyncPassRunner(),
    this.passOperation,
    this.onFreshAttach,
    SyncMergeEngine? mergeEngine,
    SyncApplyEngine? applyEngine,
    SyncPeerManifestCache? peerManifestCache,
  }) : _mergeEngine = mergeEngine ?? const SyncMergeEngine(),
       _applyEngine = applyEngine ?? const SyncApplyEngine(),
       _peerManifestCache = peerManifestCache ?? SyncPeerManifestCache(),
       _ownsPeerManifestCache = peerManifestCache == null;

  final String deviceId;
  final SyncCoordinatorStore store;
  final SyncCoordinatorTransport transport;
  final SyncPassRunner passRunner;
  final SyncPassOperation? passOperation;
  final Future<void> Function(SyncHttpResponse response)? onFreshAttach;
  final SyncMergeEngine _mergeEngine;
  final SyncApplyEngine _applyEngine;
  final String? syncId;
  final SyncPeerManifestCache _peerManifestCache;
  final bool _ownsPeerManifestCache;
  final _replacementEvents =
      StreamController<SyncReplacementRequiredEvent>.broadcast();

  Future<SyncPassResult>? _inFlight;
  Completer<SyncPassResult>? _queuedResult;
  var _queued = false;
  var _replacementPending = false;
  var _paused = false;
  Future<SyncPassResult>? _confirmation;
  var _replacementCreated = false;
  var _disposed = false;

  static const _maxMissingHashesPerRequest = 10000;

  /// Emits at most one event while the same replacement decision is pending.
  Stream<SyncReplacementRequiredEvent> get replacementRequired =>
      _replacementEvents.stream;

  /// Requests a pass from any of the §6.12 trigger paths.
  Future<SyncPassResult> trigger(SyncTrigger trigger) {
    if (_disposed) {
      return Future.value(
        const SyncPassResult(
          SyncPassStatus.failed,
          message: 'sync coordinator is closed', // i18n-ignore: internal status
        ),
      );
    }
    if (syncId == null) {
      return Future.value(
        const SyncPassResult(SyncPassStatus.skippedUnconfigured),
      );
    }
    if (_replacementPending) {
      return Future.value(
        const SyncPassResult(SyncPassStatus.replacementRequired),
      );
    }
    if (_paused) {
      if (trigger != SyncTrigger.manual) {
        return Future.value(const SyncPassResult(SyncPassStatus.paused));
      }
      _paused = false;
    }

    final inFlight = _inFlight;
    if (inFlight != null) {
      _queued = true;
      return (_queuedResult ??= Completer<SyncPassResult>()).future;
    }

    final pass = _startPass();
    _inFlight = pass;
    _watch(pass);
    return pass;
  }

  Future<SyncPassResult> onAppStart() => trigger(SyncTrigger.appStart);

  Future<SyncPassResult> onDebouncedChange() =>
      trigger(SyncTrigger.debouncedChange);

  Future<SyncPassResult> syncNow() => trigger(SyncTrigger.manual);

  /// Confirms replacement exactly once, then runs the W8 fresh-attach
  /// lifecycle, including its single steady-state continuation.
  Future<SyncPassResult> confirmReplacement() {
    if (_disposed) {
      return Future.value(
        const SyncPassResult(
          SyncPassStatus.failed,
          message: 'sync coordinator is closed', // i18n-ignore: internal status
        ),
      );
    }
    if (syncId == null) {
      return Future.value(
        const SyncPassResult(SyncPassStatus.skippedUnconfigured),
      );
    }
    final existing = _confirmation;
    if (existing != null) return existing;
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight.then((_) => confirmReplacement());
    }
    if (!_replacementPending && !_replacementCreated) {
      return Future.value(
        const SyncPassResult(
          SyncPassStatus.failed,
          message:
              'no replacement decision is pending', // i18n-ignore: internal status
        ),
      );
    }
    final confirmation = _confirmReplacement();
    _confirmation = confirmation;
    _inFlight = confirmation;
    _watch(confirmation);
    confirmation.then<void>(
      (result) {
        if (result.status != SyncPassStatus.freshAttachRequired &&
            identical(_confirmation, confirmation)) {
          _confirmation = null;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        logCaughtErrorTypeOnly(
          error,
          stackTrace,
          source: 'sync_coordinator.confirmReplacement',
        );
        if (identical(_confirmation, confirmation)) {
          _confirmation = null;
        }
      },
    );
    return confirmation;
  }

  /// Declines replacement without detaching or clearing the configured sync
  /// identity. A later explicit manual action can reconsider the decision.
  void declineReplacement() {
    if (!_replacementPending) return;
    _replacementPending = false;
    _confirmation = null;
    _paused = true;
  }

  /// Releases the event stream and the owned HTTP client, if any.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_ownsPeerManifestCache) _peerManifestCache.clear();
    _queued = false;
    final queuedResult = _queuedResult;
    _queuedResult = null;
    queuedResult?.complete(
      const SyncPassResult(
        SyncPassStatus.failed,
        message: 'sync coordinator is closed', // i18n-ignore: internal status
      ),
    );
    final inFlight = _inFlight;
    final confirmation = _confirmation;
    Future<void> settle(Future<SyncPassResult>? operation) async {
      if (operation == null) return;
      try {
        await operation;
      } on Object catch (error, stack) {
        logCaughtErrorTypeOnly(
          error,
          stack,
          source: 'sync_coordinator.dispose',
        );
      }
    }

    await settle(inFlight);
    if (!identical(confirmation, inFlight)) {
      await settle(confirmation);
    }
    if (transport case final SyncHttpCoordinatorTransport httpTransport) {
      httpTransport.client.close();
    }
    if (inFlight != null && identical(_inFlight, inFlight)) {
      _inFlight = null;
    }
    await _replacementEvents.close();
  }

  Future<SyncPassResult> _startPass() => _runStartedPass();

  void _watch(Future<SyncPassResult> pass) {
    pass.then<void>(
      (_) => _finish(pass),
      onError: (Object error, StackTrace stack) {
        logCaughtErrorTypeOnly(error, stack, source: 'sync_coordinator._watch');
        _finish(pass);
      },
    );
  }

  Future<SyncPassResult> _runStartedPass({
    SyncStoreResult? initialStore,
  }) async {
    final result =
        await (passOperation?.call() ??
            passRunner.run(() => _runPass(initialStore: initialStore)));
    if (result.status == SyncPassStatus.replacementRequired) {
      _emitReplacementRequired();
    }
    return result;
  }

  void _finish(Future<SyncPassResult> pass) {
    if (!identical(_inFlight, pass)) return;
    _inFlight = null;
    if (_disposed) {
      _queued = false;
      final queuedResult = _queuedResult;
      _queuedResult = null;
      queuedResult?.complete(
        const SyncPassResult(
          SyncPassStatus.failed,
          message: 'sync coordinator is closed', // i18n-ignore: internal status
        ),
      );
      return;
    }
    if (!_queued) return;

    _queued = false;
    final queuedResult = _queuedResult!;
    _queuedResult = null;
    if (syncId == null) {
      queuedResult.complete(
        const SyncPassResult(SyncPassStatus.skippedUnconfigured),
      );
      return;
    }
    if (_replacementPending) {
      queuedResult.complete(
        const SyncPassResult(SyncPassStatus.replacementRequired),
      );
      return;
    }
    if (_paused) {
      queuedResult.complete(const SyncPassResult(SyncPassStatus.paused));
      return;
    }

    final next = _startPass();
    _inFlight = next;
    _watch(next);
    next.then<void>(queuedResult.complete, onError: queuedResult.completeError);
  }

  Future<SyncPassResult> _runPass({
    SyncStoreResult? initialStore,
    bool continuation = false,
  }) async {
    final snapshot = await store.snapshot();
    final storeResult =
        initialStore ??
        await transport.getStore(previouslyUsed: snapshot.previouslyUsed);
    if (storeResult.missingKind == SyncStoreMissingKind.replacementRequired) {
      _emitReplacementRequired();
      return const SyncPassResult(SyncPassStatus.replacementRequired);
    }
    if (storeResult.missingKind == SyncStoreMissingKind.firstTime) {
      return const SyncPassResult(SyncPassStatus.firstTimeStoreRequired);
    }
    if (!storeResult.response.isSuccess) {
      return SyncPassResult(
        SyncPassStatus.failed,
        message:
            'store lookup returned ${storeResult.response.statusCode}', // i18n-ignore: internal status
      );
    }

    final metadata = _decodeStoreMetadata(storeResult.response.body);
    if (metadata == null) {
      return const SyncPassResult(
        SyncPassStatus.failed,
        message: 'store metadata was malformed', // i18n-ignore: internal status
      );
    }
    final freshAttach =
        snapshot.epoch == null || snapshot.epoch != metadata.epoch;
    if (continuation && freshAttach) {
      return const SyncPassResult(SyncPassStatus.staleEpoch);
    }

    final normalizedLocal = await _normalizeCandidates(
      freshAttach ? snapshot.publication : snapshot.local,
    );
    final normalizedPendingLive = await _normalizeCandidates(
      snapshot.pendingLive,
    );
    final normalizedBaseline = await _normalizeBaseline(snapshot.baseline);
    final normalizedPending = await _normalizeAddresses(snapshot.pending);
    final reports = SyncReportSink();
    final peerMaps = <Map<SyncRecordAddress, SyncMergeCandidate?>>[];
    final peerManifests = <({String peerId, SyncManifest manifest})>[];
    final unresolved = <SyncRecordAddress>{};
    var allPeerManifestsAvailable = true;
    for (final peerId in metadata.devices) {
      if (peerId == deviceId) continue;
      final cached = _peerManifestCache[peerId];
      final epochCached = cached?.epoch == metadata.epoch ? cached : null;
      final response = await transport.getManifest(
        peerId,
        etag: epochCached?.etag,
      );
      final manifest = response.kind == SyncResponseKind.notModified
          ? epochCached?.manifest
          : response.isSuccess
          ? _decodeManifest(response.body)
          : null;
      if (response.kind == SyncResponseKind.notModified && manifest == null) {
        _peerManifestCache.remove(peerId);
      }
      if (!response.isSuccess) {
        allPeerManifestsAvailable = false;
        unresolved.addAll(normalizedBaseline.keys);
        reports.add(
          SyncReport(
            code: SyncReportCode.malformedRecord,
            peerId: peerId,
            message:
                'Peer manifest returned ${response.statusCode}.', // i18n-ignore: internal report
          ),
        );
        continue;
      }
      if (manifest == null || manifest.epoch != metadata.epoch) {
        allPeerManifestsAvailable = false;
        _peerManifestCache.remove(peerId);
        unresolved.addAll(normalizedBaseline.keys);
        reports.add(
          SyncReport(
            code: SyncReportCode.malformedRecord,
            peerId: peerId,
            message:
                'Peer manifest was malformed or used a stale epoch.', // i18n-ignore: internal report
          ),
        );
        continue;
      }
      final etag = _header(response.headers, 'etag');
      if (response.kind == SyncResponseKind.notModified) {
        if (etag != null && etag.isNotEmpty) {
          _peerManifestCache[peerId] = SyncPeerManifestCacheEntry(
            epoch: metadata.epoch,
            etag: etag,
            manifest: manifest,
          );
        }
      } else if (etag == null || etag.isEmpty) {
        _peerManifestCache.remove(peerId);
      } else {
        _peerManifestCache[peerId] = SyncPeerManifestCacheEntry(
          epoch: metadata.epoch,
          etag: etag,
          manifest: manifest,
        );
      }
      peerManifests.add((peerId: peerId, manifest: manifest));
    }
    if (allPeerManifestsAvailable) {
      final peerAddresses = <SyncRecordAddress>{
        for (final peer in peerManifests)
          for (final kindEntry in peer.manifest.records.entries)
            for (final recordId in kindEntry.value.keys)
              (kind: kindEntry.key, recordId: recordId),
      };
      await store.retireAliases(peerAddresses: peerAddresses);
    }

    final localByHash = <String, SyncMergeCandidate>{};
    for (final candidate in snapshot.publication.values) {
      if (candidate != null) localByHash[candidate.wireHash] = candidate;
    }
    final availableByHash = <String, SyncMergeCandidate>{...localByHash};

    for (final peer in peerManifests) {
      peerMaps.add(
        await _normalizeCandidates(
          await _downloadPeerRecords(
            peer.manifest,
            peerId: peer.peerId,
            reports: reports,
            unresolved: unresolved,
            candidateByHash: availableByHash,
          ),
        ),
      );
    }

    final normalizedUnresolved = await _normalizeAddresses(unresolved);
    final mergeBaseline =
        freshAttach
              ? <SyncRecordAddress, SyncBaselineEntry>{}
              : <SyncRecordAddress, SyncBaselineEntry>{...normalizedBaseline}
          ..removeWhere((address, _) => normalizedPending.contains(address));
    final plan = _mergeEngine.plan(
      local: normalizedLocal,
      baseline: mergeBaseline,
      peers: peerMaps,
      freshAttach: freshAttach,
      unresolved: normalizedUnresolved,
    );
    reports.addAll(plan.reports);
    final downloads = [
      for (final decision in plan.downloads)
        if (decision.winner != null) decision.winner!,
    ];
    final expectedWireHashes = <SyncRecordAddress, String?>{
      for (final entry in normalizedLocal.entries)
        entry.key: entry.value?.wireHash,
      for (final entry in normalizedPendingLive.entries)
        entry.key: entry.value?.wireHash,
      for (final decision in plan.downloads)
        if (decision.winner != null)
          decision.address:
              (normalizedLocal[decision.address] ??
                      normalizedPendingLive[decision.address])
                  ?.wireHash,
    };
    final applyResult = await _applyEngine.apply(
      candidates: downloads,
      storage: store,
      expectedWireHashes: expectedWireHashes,
    );
    reports.addAll(applyResult.reports);

    final dedupe = await store.deduplicateFreshAttach(apply: freshAttach);
    reports.addAll(dedupe.reports);
    if (freshAttach) {
      final attachedSnapshot = await store.snapshot();
      final attachedLocal = await _normalizeCandidates(attachedSnapshot.local);
      final attachedPendingLive = await _normalizeCandidates(
        attachedSnapshot.pendingLive,
      );
      final baselineEntries = <SyncBaselineEntry>[
        for (final entry in {...attachedLocal, ...attachedPendingLive}.entries)
          if (entry.value != null)
            SyncBaselineEntry(
              kind: entry.key.kind,
              recordId: entry.key.recordId,
              wireHash: entry.value!.wireHash,
              bodyHash: entry.value!.bodyHash,
            ),
      ];
      final attachByHash = <String, SyncMergeCandidate>{};
      for (final candidate in attachedSnapshot.publication.values) {
        if (candidate != null) attachByHash[candidate.wireHash] = candidate;
      }
      if (!await _uploadMissingLocalBlobs(attachByHash, reports: reports)) {
        return SyncPassResult(
          SyncPassStatus.failed,
          reports: reports.reports,
          message:
              'fresh-attach blob publication failed', // i18n-ignore: internal status
          duplicateCount: dedupe.duplicateCount,
        );
      }
      await store.replaceBaseline(
        epoch: metadata.epoch,
        entries: baselineEntries,
      );
      await store.markSyncUsed(syncId!);
      final continuationResult = await _runPass(continuation: true);
      return SyncPassResult(
        continuationResult.status,
        reports: [...reports.reports, ...continuationResult.reports],
        message: continuationResult.message,
        duplicateCount:
            dedupe.duplicateCount + continuationResult.duplicateCount,
      );
    }

    final currentSnapshot = await store.snapshot();
    final current = await _normalizeCandidates(currentSnapshot.local);
    final publication = <SyncRecordAddress, SyncMergeCandidate?>{
      ...currentSnapshot.publication,
    };
    final finalByHash = <String, SyncMergeCandidate>{};
    for (final candidate in publication.values) {
      if (candidate != null) finalByHash[candidate.wireHash] = candidate;
    }
    final finalUploadSucceeded = await _uploadMissingLocalBlobs(
      finalByHash,
      reports: reports,
    );
    if (!finalUploadSucceeded) {
      return SyncPassResult(
        SyncPassStatus.failed,
        reports: reports.reports,
        message:
            'post-apply blob publication failed', // i18n-ignore: internal status
      );
    }
    final manifest = SyncManifest(
      deviceId: deviceId,
      epoch: metadata.epoch,
      writtenAt: DateTime.now().toUtc(),
      records: _manifestRecords(publication),
    );
    final manifestBody = encodeSyncManifestUtf8(manifest);
    final addresses = [
      for (final kindEntry in manifest.records.entries)
        for (final recordId in kindEntry.value.keys)
          (kind: kindEntry.key, recordId: recordId),
    ];
    await store.markPublicationAttempt(syncId: syncId!, records: addresses);
    final published = await transport.putManifest(deviceId, manifestBody);
    if (published.kind == SyncResponseKind.conflict) {
      return SyncPassResult(
        SyncPassStatus.staleEpoch,
        reports: reports.reports,
        message:
            'manifest publication observed a stale epoch', // i18n-ignore: internal status
      );
    }
    if (!published.isSuccess) {
      return SyncPassResult(
        SyncPassStatus.failed,
        reports: reports.reports,
        message:
            'manifest publication returned ${published.statusCode}', // i18n-ignore: internal status
      );
    }
    final observed = <SyncBaselineEntry>[];
    for (final entry in current.entries) {
      if (normalizedUnresolved.contains(entry.key)) continue;
      final candidate = entry.value;
      if (candidate == null) continue;
      final seenByPeer = peerMaps.any(
        (peer) => peer[entry.key]?.wireHash == candidate.wireHash,
      );
      if (!seenByPeer) continue;
      observed.add(
        SyncBaselineEntry(
          kind: entry.key.kind,
          recordId: entry.key.recordId,
          wireHash: candidate.wireHash,
          bodyHash: candidate.bodyHash,
        ),
      );
    }
    await store.advanceBaseline(
      epoch: metadata.epoch,
      entries: observed,
      drop: [
        for (final decision in plan.decisions)
          if (decision.action == SyncMergeAction.dropBaseline) decision.address,
      ],
    );

    return SyncPassResult(
      SyncPassStatus.completed,
      reports: reports.reports,
      duplicateCount: dedupe.duplicateCount,
    );
  }

  Future<Set<SyncRecordAddress>> _normalizeAddresses(
    Iterable<SyncRecordAddress> addresses,
  ) async {
    final normalized = <SyncRecordAddress>{};
    for (final address in addresses) {
      normalized.add(await store.resolveAlias(address));
    }
    return normalized;
  }

  Future<Map<SyncRecordAddress, SyncBaselineEntry>> _normalizeBaseline(
    Map<SyncRecordAddress, SyncBaselineEntry> baseline,
  ) async {
    final normalized = <SyncRecordAddress, SyncBaselineEntry>{};
    final sources = <SyncRecordAddress, SyncRecordAddress>{};
    for (final entry in baseline.entries) {
      final address = await store.resolveAlias(entry.key);
      if (_shouldReplaceNormalizedAddress(
        sources[address],
        entry.key,
        address,
      )) {
        normalized[address] = SyncBaselineEntry(
          kind: address.kind,
          recordId: address.recordId,
          wireHash: entry.value.wireHash,
          bodyHash: entry.value.bodyHash,
        );
        sources[address] = entry.key;
      }
    }
    return normalized;
  }

  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> _normalizeCandidates(
    Map<SyncRecordAddress, SyncMergeCandidate?> candidates,
  ) async {
    final normalized = <SyncRecordAddress, SyncMergeCandidate?>{};
    final sources = <SyncRecordAddress, SyncRecordAddress>{};
    for (final entry in candidates.entries) {
      final address = await store.resolveAlias(entry.key);
      if (_shouldReplaceNormalizedAddress(
        sources[address],
        entry.key,
        address,
      )) {
        normalized[address] = entry.value;
        sources[address] = entry.key;
      }
    }
    return normalized;
  }

  static bool _shouldReplaceNormalizedAddress(
    SyncRecordAddress? previousSource,
    SyncRecordAddress source,
    SyncRecordAddress normalized,
  ) {
    if (previousSource == null) return true;
    if (source == normalized && previousSource != normalized) return true;
    if (previousSource == normalized) return false;
    return source.recordId.compareTo(previousSource.recordId) < 0;
  }

  Future<SyncPassResult> _confirmReplacement() async {
    SyncStoreResult? attached;
    if (!_replacementCreated) {
      final created = await transport.createStore();
      if (!created.isSuccess) {
        return SyncPassResult(
          SyncPassStatus.failed,
          message:
              'store creation returned ${created.statusCode}', // i18n-ignore: internal status
        );
      }
      _replacementCreated = true;
      attached = await transport.getStore(previouslyUsed: false);
      if (attached.missingKind != null || !attached.response.isSuccess) {
        return const SyncPassResult(
          SyncPassStatus.failed,
          message:
              'fresh attach did not produce a store', // i18n-ignore: internal status
        );
      }
      if (onFreshAttach != null) await onFreshAttach!(attached.response);
    }
    _replacementPending = false;
    final result = await _runStartedPass(initialStore: attached);
    if (result.status == SyncPassStatus.completed) {
      _replacementCreated = false;
      _paused = false;
    }
    return result;
  }

  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> _downloadPeerRecords(
    SyncManifest manifest, {
    required String peerId,
    required SyncReportSink reports,
    required Set<SyncRecordAddress> unresolved,
    required Map<String, SyncMergeCandidate> candidateByHash,
  }) async {
    final result = <SyncRecordAddress, SyncMergeCandidate?>{};
    for (final kindEntry in manifest.records.entries) {
      for (final recordEntry in kindEntry.value.entries) {
        final address = (kind: kindEntry.key, recordId: recordEntry.key);
        final cachedCandidate = candidateByHash[recordEntry.value];
        if (cachedCandidate != null) {
          if (cachedCandidate.address != address) {
            unresolved.add(address);
            reports.add(
              SyncReport(
                code: SyncReportCode.blobIdentityMismatch,
                kind: address.kind,
                recordId: address.recordId,
                peerId: peerId,
                message:
                    'Cached blob identity did not match its manifest address.', // i18n-ignore: internal report
              ),
            );
            continue;
          }
          result[address] = cachedCandidate;
          continue;
        }
        final response = await transport.getBlob(recordEntry.value);
        if (!response.isSuccess) {
          unresolved.add(address);
          reports.add(
            SyncReport(
              code: SyncReportCode.unresolvedBlob,
              kind: address.kind,
              recordId: address.recordId,
              peerId: peerId,
              message:
                  'Blob returned ${response.statusCode}.', // i18n-ignore: internal report
            ),
          );
          continue;
        }
        if (sha256Hex(response.body) != recordEntry.value) {
          unresolved.add(address);
          reports.add(
            SyncReport(
              code: SyncReportCode.unresolvedBlob,
              kind: address.kind,
              recordId: address.recordId,
              peerId: peerId,
              message:
                  'Blob hash did not match its manifest reference.', // i18n-ignore: internal report
            ),
          );
          continue;
        }
        final blob = _decodeBlob(response.body);
        if (blob == null) {
          unresolved.add(address);
          reports.add(
            SyncReport(
              code: SyncReportCode.malformedRecord,
              kind: address.kind,
              recordId: address.recordId,
              peerId: peerId,
              message:
                  'Blob did not decode as a record.', // i18n-ignore: internal report
            ),
          );
          continue;
        }
        if (blob.kind != address.kind || blob.id != address.recordId) {
          unresolved.add(address);
          reports.add(
            SyncReport(
              code: SyncReportCode.blobIdentityMismatch,
              kind: address.kind,
              recordId: address.recordId,
              peerId: peerId,
              message:
                  'Blob identity did not match its manifest address.', // i18n-ignore: internal report
            ),
          );
          continue;
        }
        final candidate = SyncMergeCandidate(
          blob: blob,
          wireHash: recordEntry.value,
        );
        candidateByHash[recordEntry.value] = candidate;
        result[address] = candidate;
      }
    }
    return result;
  }

  Future<bool> _uploadMissingLocalBlobs(
    Map<String, SyncMergeCandidate> localByHash, {
    required SyncReportSink reports,
  }) async {
    final entries = localByHash.entries.toList(growable: false);
    for (
      var offset = 0;
      offset < entries.length;
      offset += _maxMissingHashesPerRequest
    ) {
      final end = (offset + _maxMissingHashesPerRequest).clamp(
        0,
        entries.length,
      );
      final response = await transport.postMissing(
        entries.sublist(offset, end).map((entry) => entry.key),
      );
      if (!response.isSuccess) return false;
      final missing = _decodeMissing(response.body);
      if (missing == null) return false;
      for (final hash in missing) {
        final candidate = localByHash[hash];
        if (candidate == null) {
          reports.add(
            SyncReport(
              code: SyncReportCode.unresolvedBlob,
              message:
                  'The store requested an unknown local blob.', // i18n-ignore: internal report
            ),
          );
          return false;
        }
        final uploaded = await transport.putBlob(
          hash,
          encodeSyncRecordBlobUtf8(candidate.blob),
        );
        if (!uploaded.isSuccess) return false;
      }
    }
    return true;
  }

  void _emitReplacementRequired() {
    if (_disposed) return;
    if (_replacementPending) return;
    _replacementPending = true;
    _confirmation = null;
    _replacementEvents.add(const SyncReplacementRequiredEvent());
  }

  static SyncManifest? _decodeManifest(List<int> body) {
    try {
      return decodeSyncManifest(utf8.decode(body, allowMalformed: false));
    } on FormatException {
      // diagnostics: silent — malformed peer manifests are reported by the
      // caller as per-record failures.
      return null;
    }
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
    }
    return null;
  }

  static SyncRecordBlob? _decodeBlob(List<int> body) {
    try {
      return decodeSyncRecordBlob(utf8.decode(body, allowMalformed: false));
    } on FormatException {
      // diagnostics: silent — malformed peer blobs are reported by the caller
      // and do not advance the baseline.
      return null;
    }
  }

  static _StoreMetadata? _decodeStoreMetadata(List<int> body) {
    try {
      final decoded = jsonDecode(utf8.decode(body, allowMalformed: false));
      if (decoded is! Map || decoded['epoch'] is! String) {
        return null;
      }
      final devices = decoded['devices'];
      if (devices is! List || devices.any((device) => device is! String)) {
        return null;
      }
      return _StoreMetadata(
        epoch: decoded['epoch'] as String,
        devices: [for (final device in devices) device as String],
      );
    } on FormatException {
      // diagnostics: silent — malformed store metadata is surfaced as a
      // failed pass.
      return null;
    }
  }

  static List<String>? _decodeMissing(List<int> body) {
    try {
      final decoded = jsonDecode(utf8.decode(body, allowMalformed: false));
      if (decoded is! Map || decoded['missing'] is! List) return null;
      final values = decoded['missing'] as List;
      if (values.any(
        (value) =>
            value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value),
      )) {
        return null;
      }
      return [for (final value in values) value as String];
    } on FormatException {
      // diagnostics: silent — malformed missing-blob responses fail the
      // upload step.
      return null;
    }
  }

  static Map<SyncRecordKind, Map<String, String>> _manifestRecords(
    Map<SyncRecordAddress, SyncMergeCandidate?> local,
  ) {
    final records = <SyncRecordKind, Map<String, String>>{};
    for (final candidate in local.values) {
      if (candidate == null) continue;
      records.putIfAbsent(candidate.blob.kind, () => {})[candidate.blob.id] =
          candidate.wireHash;
    }
    return records;
  }
}

class _StoreMetadata {
  const _StoreMetadata({required this.epoch, required this.devices});

  final String epoch;
  final List<String> devices;
}
