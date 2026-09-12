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
  const SyncPassResult(this.status, {this.reports = const [], this.message});

  final SyncPassStatus status;
  final List<SyncReport> reports;
  final String? message;
}

/// The data needed to construct a local manifest and calculate a pass.
class SyncCoordinatorSnapshot {
  SyncCoordinatorSnapshot({
    required this.epoch,
    required this.previouslyUsed,
    required Map<SyncRecordAddress, SyncMergeCandidate?> local,
    required Map<SyncRecordAddress, SyncBaselineEntry> baseline,
  }) : local = Map.unmodifiable(local),
       baseline = Map.unmodifiable(baseline);

  final String? epoch;
  final bool previouslyUsed;
  final Map<SyncRecordAddress, SyncMergeCandidate?> local;
  final Map<SyncRecordAddress, SyncBaselineEntry> baseline;
}

/// Storage operations that the coordinator must compose with inbound apply.
///
/// The implementation owns the real database transaction. In particular,
/// [SyncApplyStorage.transaction] must cover the whole inbound apply rather
/// than only an individual record.
abstract interface class SyncCoordinatorStore implements SyncApplyStorage {
  Future<SyncCoordinatorSnapshot> snapshot();

  Future<void> markSyncUsed(String syncId);

  Future<void> markPublished(Iterable<SyncRecordAddress> records);

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
    implements SyncCoordinatorStore, SyncApplyBatchStorage {
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
    );
  }

  @override
  Future<void> markSyncUsed(String syncId) => storage.markSyncUsed(syncId);

  @override
  Future<void> markPublished(Iterable<SyncRecordAddress> records) =>
      storage.repositories.syncLocal.markPublishedAll(records);

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

final class _PeerManifestCache {
  const _PeerManifestCache({
    required this.epoch,
    required this.etag,
    required this.manifest,
  });

  final String epoch;
  final String etag;
  final SyncManifest manifest;
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
  }) : _mergeEngine = mergeEngine ?? const SyncMergeEngine(),
       _applyEngine = applyEngine ?? const SyncApplyEngine();

  final String deviceId;
  final SyncCoordinatorStore store;
  final SyncCoordinatorTransport transport;
  final SyncPassRunner passRunner;
  final SyncPassOperation? passOperation;
  final Future<void> Function(SyncHttpResponse response)? onFreshAttach;
  final SyncMergeEngine _mergeEngine;
  final SyncApplyEngine _applyEngine;
  final String? syncId;
  final _replacementEvents =
      StreamController<SyncReplacementRequiredEvent>.broadcast();

  Future<SyncPassResult>? _inFlight;
  Completer<SyncPassResult>? _queuedResult;
  var _queued = false;
  var _replacementPending = false;
  var _paused = false;
  Future<SyncPassResult>? _confirmation;
  var _disposed = false;
  final _peerManifestCache = <String, _PeerManifestCache>{};

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

  /// Confirms replacement exactly once, then stops at the fresh-attach
  /// boundary. Attach/dedupe orchestration remains owned by W8.
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
    if (!_replacementPending) {
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
    _peerManifestCache.clear();
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
    if (transport case final SyncHttpCoordinatorTransport httpTransport) {
      httpTransport.client.close();
    }
    if (inFlight != null) {
      try {
        await inFlight;
      } on Object catch (error, stack) {
        logCaughtErrorTypeOnly(
          error,
          stack,
          source: 'sync_coordinator.dispose',
        );
      }
      if (identical(_inFlight, inFlight)) _inFlight = null;
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

  Future<SyncPassResult> _runStartedPass() async {
    final result = await (passOperation?.call() ?? passRunner.run(_runPass));
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

  Future<SyncPassResult> _runPass() async {
    final snapshot = await store.snapshot();
    final storeResult = await transport.getStore(
      previouslyUsed: snapshot.previouslyUsed,
    );
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
    if (snapshot.epoch != null && snapshot.epoch != metadata.epoch) {
      return const SyncPassResult(SyncPassStatus.staleEpoch);
    }

    final reports = SyncReportSink();
    final peerMaps = <Map<SyncRecordAddress, SyncMergeCandidate?>>[];
    final peerManifests = <({String peerId, SyncManifest manifest})>[];
    final unresolved = <SyncRecordAddress>{};
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
        unresolved.addAll(snapshot.baseline.keys);
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
        _peerManifestCache.remove(peerId);
        unresolved.addAll(snapshot.baseline.keys);
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
          _peerManifestCache[peerId] = _PeerManifestCache(
            epoch: metadata.epoch,
            etag: etag,
            manifest: manifest,
          );
        }
      } else if (etag == null || etag.isEmpty) {
        _peerManifestCache.remove(peerId);
      } else {
        _peerManifestCache[peerId] = _PeerManifestCache(
          epoch: metadata.epoch,
          etag: etag,
          manifest: manifest,
        );
      }
      peerManifests.add((peerId: peerId, manifest: manifest));
    }

    final localByHash = <String, SyncMergeCandidate>{};
    for (final candidate in snapshot.local.values) {
      if (candidate != null) localByHash[candidate.wireHash] = candidate;
    }
    final availableByHash = <String, SyncMergeCandidate>{...localByHash};
    final uploadResult = await _uploadMissingLocalBlobs(
      localByHash,
      reports: reports,
    );
    if (!uploadResult) {
      return SyncPassResult(SyncPassStatus.failed, reports: reports.reports);
    }

    for (final peer in peerManifests) {
      peerMaps.add(
        await _downloadPeerRecords(
          peer.manifest,
          peerId: peer.peerId,
          reports: reports,
          unresolved: unresolved,
          candidateByHash: availableByHash,
        ),
      );
    }

    final plan = _mergeEngine.plan(
      local: snapshot.local,
      baseline: snapshot.baseline,
      peers: peerMaps,
      unresolved: unresolved,
    );
    reports.addAll(plan.reports);
    final downloads = [
      for (final decision in plan.downloads)
        if (decision.winner != null) decision.winner!,
    ];
    final applyResult = await _applyEngine.apply(
      candidates: downloads,
      storage: store,
    );
    reports.addAll(applyResult.reports);

    final appliedAddresses = applyResult.applied.toSet();
    final current = appliedAddresses.isEmpty
        ? <SyncRecordAddress, SyncMergeCandidate?>{...snapshot.local}
        : <SyncRecordAddress, SyncMergeCandidate?>{
            ...(await store.snapshot()).local,
          };
    for (final decision in plan.decisions) {
      if (decision.action == SyncMergeAction.dropBaseline) {
        current.remove(decision.address);
      }
    }
    if (appliedAddresses.isNotEmpty) {
      final finalByHash = <String, SyncMergeCandidate>{};
      for (final candidate in current.values) {
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
    }
    final manifest = SyncManifest(
      deviceId: deviceId,
      epoch: metadata.epoch,
      writtenAt: DateTime.now().toUtc(),
      records: _manifestRecords(current),
    );
    final manifestBody = encodeSyncManifestUtf8(manifest);
    final addresses = [
      for (final kindEntry in manifest.records.entries)
        for (final recordId in kindEntry.value.keys)
          (kind: kindEntry.key, recordId: recordId),
    ];
    await store.markPublished(addresses);
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
    await store.markSyncUsed(syncId!);

    final observed = <SyncBaselineEntry>[];
    for (final entry in current.entries) {
      if (unresolved.contains(entry.key)) continue;
      final candidate = entry.value;
      if (candidate == null) continue;
      final seenByPeer = peerMaps.any(
        (peer) => peer[entry.key]?.wireHash == candidate.wireHash,
      );
      if (!seenByPeer) continue;
      observed.add(
        SyncBaselineEntry(
          kind: candidate.blob.kind,
          recordId: candidate.blob.id,
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

    return SyncPassResult(SyncPassStatus.completed, reports: reports.reports);
  }

  Future<SyncPassResult> _confirmReplacement() async {
    final created = await transport.createStore();
    if (!created.isSuccess) {
      return SyncPassResult(
        SyncPassStatus.failed,
        message:
            'store creation returned ${created.statusCode}', // i18n-ignore: internal status
      );
    }
    final attached = await transport.getStore(previouslyUsed: false);
    if (attached.missingKind != null || !attached.response.isSuccess) {
      return const SyncPassResult(
        SyncPassStatus.failed,
        message:
            'fresh attach did not produce a store', // i18n-ignore: internal status
      );
    }
    if (onFreshAttach != null) await onFreshAttach!(attached.response);
    _replacementPending = false;
    _paused = false;
    return const SyncPassResult(SyncPassStatus.freshAttachRequired);
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
