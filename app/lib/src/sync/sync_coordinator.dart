import 'dart:async';
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';

import '../diagnostics/error_log.dart';
import 'sync_http_client.dart';

DateTime _syncNowUtc() => DateTime.now().toUtc();

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
    this.appliedKinds = const [],
  });

  final SyncPassStatus status;
  final List<SyncReport> reports;
  final String? message;
  final int duplicateCount;

  /// Sync record kinds whose tables were mutated by this pass.
  ///
  /// This includes inbound apply records and fresh-attach dedupe rewrites. It
  /// crosses the worker boundary so the owning Drift connection can invalidate
  /// its live queries after the worker has closed its connection.
  final List<SyncRecordKind> appliedKinds;
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

  /// Drops aliases whose losing IDs no longer appear in any verified peer
  /// manifest. The coordinator only invokes this when every current peer
  /// manifest was available for the epoch.
  Future<void> retireAliases({required Set<SyncRecordAddress> peerAddresses});

  /// Records a manifest-producing snapshot's addresses before blob
  /// publication, so a concurrent hard delete retains tombstone evidence.
  Future<void> markPublished(Iterable<SyncRecordAddress> records);

  /// Atomically records the manifest attempt and marks the sync identity
  /// immediately before the manifest request. Keep this after blob
  /// publication so a failed upload does not mark the sync identity used.
  Future<void> markPublicationAttempt({
    required String syncId,
    required Iterable<SyncRecordAddress> records,
  });

  Future<SyncFreshAttachDedupeResult> deduplicateFreshAttach();

  /// Refreshes only the already-queued dance ambiguity pairs.
  ///
  /// Ordinary passes must not scan the complete dance library. Fresh attach
  /// owns discovery and merging; this path only revalidates pending review
  /// candidates after inbound writes.
  Future<SyncFreshAttachDedupeResult> refreshDanceAmbiguityReviews();

  Future<void> replaceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
  });

  /// Clears old epoch-scoped conclusions without persisting the new epoch.
  ///
  /// A fresh attach persists its epoch only with [replaceBaseline] after the
  /// union, dedupe, blob publication, and resulting manifest are complete.
  Future<void> clearEpochState();

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
    implements
        SyncCoordinatorStore,
        SyncApplyReconciliationStorage,
        SyncApplyRestorableStorage {
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
      storage.snapshot().then(
        (snapshot) => {...snapshot.local, ...snapshot.pendingLive},
      );

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
  Future<SyncFreshAttachDedupeResult> deduplicateFreshAttach() =>
      storage.deduplicateFreshAttach();

  @override
  Future<SyncFreshAttachDedupeResult> refreshDanceAmbiguityReviews() =>
      storage.refreshDanceAmbiguityReviews();

  @override
  Future<void> replaceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
  }) => storage.repositories.syncLocal.replaceBaseline(
    epoch: epoch,
    entries: entries,
  );

  @override
  Future<void> clearEpochState() =>
      storage.repositories.syncLocal.clearBaseline();

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

  // Forwarded so the engine can make a record's parent and join writes atomic.
  // The engine type-tests for this capability, so an adapter that did not
  // forward it would silently lose the protection in production while every
  // core-level test kept it.
  @override
  Future<Object?> capturePreImage(SyncRecordAddress address) =>
      storage.capturePreImage(address);

  @override
  Future<void> restorePreImage(SyncRecordAddress address, Object? preImage) =>
      storage.restorePreImage(address, preImage);

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
typedef SyncPassOperation =
    Future<SyncPassResult> Function({SyncStoreResult? initialStore});

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
  SyncPeerManifestCache({
    Map<String, SyncPeerManifestCacheEntry>? entries,
    Set<String>? rejectedHashes,
    Map<SyncRecordAddress, int>? unreflectedPasses,
    this.unreflectedEpoch,
  }) : _entries = {...?entries},
       rejectedHashes = {...?rejectedHashes},
       unreflectedPasses = {...?unreflectedPasses};

  final Map<String, SyncPeerManifestCacheEntry> _entries;
  final Set<String> rejectedHashes;
  final Map<SyncRecordAddress, int> unreflectedPasses;
  String? unreflectedEpoch;

  void beginUnreflectedEpoch(String epoch) {
    if (unreflectedEpoch == epoch) return;
    unreflectedPasses.clear();
    unreflectedEpoch = epoch;
  }

  SyncPeerManifestCacheEntry? operator [](String peerId) => _entries[peerId];

  void operator []=(String peerId, SyncPeerManifestCacheEntry entry) {
    _entries[peerId] = entry;
  }

  void remove(String peerId) {
    _entries.remove(peerId);
  }

  void clear() {
    _entries.clear();
    rejectedHashes.clear();
    unreflectedPasses.clear();
    unreflectedEpoch = null;
  }

  void replaceFrom(SyncPeerManifestCache source) {
    _entries
      ..clear()
      ..addAll(source._entries);
    rejectedHashes
      ..clear()
      ..addAll(source.rejectedHashes);
    unreflectedPasses
      ..clear()
      ..addAll(source.unreflectedPasses);
    unreflectedEpoch = source.unreflectedEpoch;
  }

  Map<String, Object?> toMessage() => {
    '_entries': {
      for (final entry in _entries.entries)
        entry.key: {
          'epoch': entry.value.epoch,
          'etag': entry.value.etag,
          'manifest': utf8.decode(encodeSyncManifestUtf8(entry.value.manifest)),
        },
    },
    '_rejectedHashes': rejectedHashes.toList(growable: false),
    '_unreflectedPasses': [
      for (final entry in unreflectedPasses.entries)
        {
          'kind': entry.key.kind.name,
          'recordId': entry.key.recordId,
          'count': entry.value,
        },
    ],
    '_unreflectedEpoch': unreflectedEpoch,
  };

  static SyncPeerManifestCache fromMessage(Object? message) {
    if (message == null) return SyncPeerManifestCache();
    if (message is! Map<Object?, Object?>) {
      throw const FormatException('sync isolate returned a malformed cache');
    }
    final entries = <String, SyncPeerManifestCacheEntry>{};
    final rejectedHashes = <String>{};
    final unreflectedPasses = <SyncRecordAddress, int>{};
    final rawEntries = message['_entries'];
    if (rawEntries is! Map<Object?, Object?>) {
      throw const FormatException('sync isolate returned a malformed cache');
    }
    for (final rawEntry in rawEntries.entries) {
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
    final rawHashes = message['_rejectedHashes'];
    if (rawHashes is! List<Object?> ||
        rawHashes.any((hash) => hash is! String)) {
      throw const FormatException(
        'sync isolate returned a malformed rejected hash set',
      );
    }
    rejectedHashes.addAll(rawHashes.cast<String>());

    final rawPasses = message['_unreflectedPasses'];
    if (rawPasses is! List<Object?>) {
      throw const FormatException(
        'sync isolate returned malformed unreflected diagnostics',
      );
    }
    for (final rawPass in rawPasses) {
      if (rawPass is! Map<Object?, Object?> ||
          rawPass['kind'] is! String ||
          rawPass['recordId'] is! String ||
          rawPass['count'] is! int ||
          (rawPass['count']! as int) < 1) {
        throw const FormatException(
          'sync isolate returned malformed unreflected diagnostic',
        );
      }
      final address = (
        kind: SyncRecordKind.values.byName(rawPass['kind']! as String),
        recordId: rawPass['recordId']! as String,
      );
      unreflectedPasses[address] = rawPass['count']! as int;
    }
    final rawUnreflectedEpoch = message['_unreflectedEpoch'];
    if (rawUnreflectedEpoch != null && rawUnreflectedEpoch is! String) {
      throw const FormatException(
        'sync isolate returned malformed unreflected epoch',
      );
    }
    return SyncPeerManifestCache(
      entries: entries,
      rejectedHashes: rejectedHashes,
      unreflectedPasses: unreflectedPasses,
      unreflectedEpoch: rawUnreflectedEpoch as String?,
    );
  }
}

/// A coalesced notification that a previously-used remote store is missing.
class SyncReplacementRequiredEvent {
  const SyncReplacementRequiredEvent();
}

final class _MissingBlobUploadResult {
  const _MissingBlobUploadResult({
    required this.succeeded,
    required this.unavailableFallbackHashes,
  });

  final bool succeeded;
  final Set<String> unavailableFallbackHashes;
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
    this.now = _syncNowUtc,
  }) : _mergeEngine = mergeEngine ?? const SyncMergeEngine(),
       _applyEngine = applyEngine ?? SyncApplyEngine(now: now),
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
  final DateTime Function() now;
  final _replacementEvents =
      StreamController<SyncReplacementRequiredEvent>.broadcast();

  Future<SyncPassResult>? _inFlight;
  Completer<SyncPassResult>? _queuedResult;
  var _queued = false;
  var _replacementPending = false;
  var _paused = false;
  Future<SyncPassResult>? _confirmation;

  /// Set when the user declines while a confirmation is already running.
  bool _replacementDeclined = false;
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

  /// Runs one pass with an optional already-validated store lookup.
  ///
  /// The isolate worker uses this entry point after a replacement decision so
  /// the parent lookup is consumed rather than repeated inside the worker.
  Future<SyncPassResult> runPass({SyncStoreResult? initialStore}) {
    if (_disposed) {
      return Future.value(
        const SyncPassResult(
          SyncPassStatus.failed,
          message: 'sync coordinator is closed', // i18n-ignore: internal status
        ),
      );
    }
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final pass = _startPass(initialStore: initialStore);
    _inFlight = pass;
    _watch(pass);
    return pass;
  }

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
    if (!_replacementPending && _confirmation == null) return;
    _replacementPending = false;
    // A confirmation already in flight cannot be recalled — its `POST
    // /v1/store` may already have created the store — but the user's decision
    // to pause must still hold. Without this the confirmation went on to clear
    // `_paused` on success, so declining silently left sync running against a
    // store the user had just declined.
    _replacementDeclined = true;
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

  Future<SyncPassResult> _startPass({SyncStoreResult? initialStore}) =>
      _runStartedPass(initialStore: initialStore);

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
        await (passOperation?.call(initialStore: initialStore) ??
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
    String? continuationEpoch,
    List<SyncBaselineEntry>? deferredBaseline,
  }) async {
    var snapshot = await store.snapshot();
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
    _peerManifestCache.beginUnreflectedEpoch(metadata.epoch);
    final attachContinuation =
        continuation && continuationEpoch != null && deferredBaseline != null;
    if (attachContinuation && metadata.epoch != continuationEpoch) {
      return const SyncPassResult(SyncPassStatus.staleEpoch);
    }
    final epochMismatch =
        snapshot.epoch == null || snapshot.epoch != metadata.epoch;
    if (continuation && epochMismatch && !attachContinuation) {
      return const SyncPassResult(SyncPassStatus.staleEpoch);
    }
    var freshAttach = epochMismatch && !attachContinuation;
    if (freshAttach) {
      await store.clearEpochState();
      snapshot = await store.snapshot();
    }
    if (!freshAttach &&
        deferredBaseline == null &&
        _hasLegacyBaselineBodyHashes(snapshot.baseline)) {
      await store.clearEpochState();
      snapshot = await store.snapshot();
      freshAttach = true;
    }

    final localNow = now().toUtc();
    final windowEnd = syncQuarantineWindowEnd(localNow);
    var normalizedLocal = await _normalizeCandidates(
      freshAttach ? snapshot.publication : snapshot.local,
    );
    var normalizedPendingLive = await _normalizeCandidates(
      snapshot.pendingLive,
    );
    final normalizedBaseline = await _normalizeBaseline(
      deferredBaseline == null
          ? snapshot.baseline
          : {
              for (final entry in deferredBaseline)
                (kind: entry.kind, recordId: entry.recordId): entry,
            },
    );
    var normalizedPending = await _normalizeAddresses(snapshot.pending);
    var normalizedPendingTombstones = <SyncRecordAddress, SyncMergeCandidate>{};
    Future<void> rebuildPendingViews() async {
      normalizedPending = await _normalizeAddresses(snapshot.pending);
      normalizedPendingTombstones = <SyncRecordAddress, SyncMergeCandidate>{};
      if (freshAttach) return;
      final normalizedPublication = await _normalizeCandidates(
        snapshot.publication,
      );
      for (final address in normalizedPending) {
        final candidate = normalizedPublication[address];
        if (candidate != null) {
          normalizedPendingTombstones[address] = candidate;
        }
      }
    }

    await rebuildPendingViews();
    final reports = SyncReportSink();
    final peerMaps = <Map<SyncRecordAddress, SyncMergeCandidate?>>[];
    final peerManifestHashes = <Map<SyncRecordAddress, String>>[];
    final peerReferenceAliases = <Map<SyncRecordAddress, SyncRecordAddress>>[];
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
      peerManifestHashes.add(await _normalizeManifestHashes(manifest));
    }
    // Zero observed peers is not evidence that an alias has nothing left to
    // resolve — it is the absence of evidence, the same distinction §6.9 draws
    // twice for clock-suspect and for unreflected publications. Without the
    // emptiness check `allPeerManifestsAvailable` is vacuously true whenever
    // the store lists no other device (a solo install, peers aged out by §7.3,
    // or the attach continuation before this device has published), and
    // `retireAliases` with an empty set retains nothing and deletes every row.
    // A peer returning afterwards then re-raises every collision this device
    // had already reconciled.
    if (allPeerManifestsAvailable && peerManifests.isNotEmpty) {
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
    final rejectedPeerAddresses = <SyncRecordAddress>{};

    final rawPeerMaps = <Map<SyncRecordAddress, SyncMergeCandidate?>>[];
    for (final peer in peerManifests) {
      final downloaded = await _downloadPeerRecords(
        peer.manifest,
        peerId: peer.peerId,
        reports: reports,
        unresolved: unresolved,
        candidateByHash: availableByHash,
        rejectedAddresses: rejectedPeerAddresses,
      );
      final normalized = await _normalizeCandidates(downloaded);
      final referenceAliases = await _resolveReferenceAliases([normalized]);
      rawPeerMaps.add(normalized);
      peerReferenceAliases.add(referenceAliases);
      _addPeerQuarantineReports(
        normalized,
        peerId: peer.peerId,
        windowEnd: windowEnd,
        reports: reports,
      );
      peerMaps.add(
        filterSyncQuarantinedCandidates(
          normalized,
          windowEnd: windowEnd,
          resolveAlias: (address) => referenceAliases[address] ?? address,
        ),
      );
    }

    _recordClockSuspect(rawPeerMaps, windowEnd: windowEnd, reports: reports);

    final normalizedUnresolved = await _normalizeAddresses(unresolved);
    final normalizedPeerAddresses = <SyncRecordAddress>{
      for (final peer in peerMaps) ...peer.keys,
    };
    final normalizedRejectedPeerAddresses = await _normalizeAddresses(
      rejectedPeerAddresses,
    );
    normalizedUnresolved.addAll(
      normalizedRejectedPeerAddresses.difference(normalizedPeerAddresses),
    );
    // Only a missing peer *manifest* aborts the attach. There the union is
    // incomplete for every record that peer holds, and nothing downstream can
    // tell which those are, so persisting an epoch would baseline a library
    // whose shape this device has never seen.
    //
    // A per-record failure is not that. §6.2 step 4 says inbound rejection
    // "applies here as in steady state", and §6.3 step 5, §6.5 and §6.9 all
    // specify one record skipped with the batch left intact. Failing the whole
    // pass instead was unrecoverable rather than merely strict: the epoch is
    // persisted only at the end, so every later trigger repeated the attach and
    // failed identically until the condition cleared on the *other* device. One
    // blob its manifest outlived (§7.3), or one peer on an older build whose
    // body this device refuses as non-canonical, could keep a new device from
    // ever attaching. `normalizedUnresolved` still flows into the merge's
    // `unresolved` set, which skips exactly those addresses and leaves their
    // reports standing.
    if (freshAttach && !allPeerManifestsAvailable) {
      return SyncPassResult(
        SyncPassStatus.failed,
        reports: reports.reports,
        message:
            'fresh attach requires every peer manifest', // i18n-ignore: internal status
      );
    }

    final repairCandidates = <SyncMergeCandidate>[];
    final quarantinedLocal = <SyncRecordAddress>{};
    final repairLocal = <SyncRecordAddress, SyncMergeCandidate?>{
      ...normalizedLocal,
      ...normalizedPendingTombstones,
    };
    for (final entry in repairLocal.entries) {
      final local = entry.value;
      if (local == null) continue;
      final repair = repairSyncCandidate(
        local: local,
        baseline: normalizedBaseline[entry.key],
        peers: [for (final peer in rawPeerMaps) ?peer[entry.key]],
        windowEnd: windowEnd,
      );
      if (repair.completed && repair.repaired!.wireHash != local.wireHash) {
        repairCandidates.add(repair.repaired!);
      } else if (repair.before.isQuarantined) {
        quarantinedLocal.add(entry.key);
      }
    }
    final repairedKinds = <SyncRecordKind>{};
    if (repairCandidates.isNotEmpty) {
      final repairExpected = <SyncRecordAddress, String?>{
        for (final entry in repairLocal.entries)
          entry.key: normalizedPending.contains(entry.key)
              ? normalizedPendingLive[entry.key]?.wireHash
              : entry.value?.wireHash,
      };
      final repairResult = await _applyEngine.apply(
        candidates: repairCandidates,
        storage: store,
        expectedWireHashes: repairExpected,
      );
      reports.addAll(repairResult.reports);
      // A repair is a durable local write like any other, so the kinds it
      // touched have to reach the owning connection. Dropping
      // `repairResult.applied` meant a pass whose only writes were §6.9
      // timestamp repairs reported no applied kinds at all, and neither the
      // derived-index rebuild nor the live-query invalidation ran for them.
      repairedKinds.addAll(repairResult.applied.map((address) => address.kind));
      snapshot = await store.snapshot();
      normalizedLocal = await _normalizeCandidates(
        freshAttach ? snapshot.publication : snapshot.local,
      );
      normalizedPendingLive = await _normalizeCandidates(snapshot.pendingLive);
      // The pending views are derived from the same snapshot, so they go stale
      // with it. A repaired tombstone left behind as its pre-repair copy stays
      // filtered out as quarantined, and a stale peer live copy then wins the
      // merge the repair was supposed to make it lose.
      await rebuildPendingViews();
    }

    // Both maps, because both are about to be merged. Resolving only
    // `normalizedLocal` left a pending tombstone's references unaliased, so a
    // reference to a losing ID could not be connected to its survivor and the
    // quarantine closure could not reach the dependent.
    final localReferenceAliases = await _resolveReferenceAliases([
      normalizedLocal,
      normalizedPendingTombstones,
    ]);
    // A pending tombstone is this device's copy for the merge's purposes, even
    // though the row it names is still live locally. `snapshot.local` strips
    // those addresses out — the row must not be offered as live — so without
    // the overlay the merge saw no local candidate at all and §6.4's existence
    // comparison never ran for them. A peer still advertising the record live
    // therefore won by default, including when its `existenceAt` was *older*
    // than the tombstone's: the stale body was applied and `_restoreTimestamps`
    // lowered the local row's `existence_at` below the deletion that supersedes
    // it. §6.4 requires the comparison "on every path that can decide
    // existence".
    //
    // Feeding the tombstone in resolves it the way §6.4 specifies without
    // changing what is stored: when the tombstone wins, the winner is this
    // device's own candidate, so the pass uploads rather than downloads and the
    // live row stays untouched (§6.8). A peer revival stamped above the
    // tombstone still wins and still downloads, exactly as before.
    final mergeLocal = filterSyncQuarantinedCandidates(
      {...normalizedLocal, ...normalizedPendingTombstones},
      windowEnd: windowEnd,
      resolveAlias: (address) => localReferenceAliases[address] ?? address,
    );
    final mergePeers = [
      for (var index = 0; index < rawPeerMaps.length; index++)
        filterSyncQuarantinedCandidates(
          rawPeerMaps[index],
          windowEnd: windowEnd,
          resolveAlias: (address) =>
              peerReferenceAliases[index][address] ?? address,
        ),
    ];
    final localQuarantined = syncQuarantineClosure(
      candidates: normalizedLocal,
      quarantined: syncQuarantinedAddresses(
        normalizedLocal,
        windowEnd: windowEnd,
      ),
      resolveAlias: (address) => localReferenceAliases[address] ?? address,
    );
    final peerQuarantined = <SyncRecordAddress>{};
    for (var index = 0; index < rawPeerMaps.length; index++) {
      final peer = rawPeerMaps[index];
      peerQuarantined.addAll(
        syncQuarantineClosure(
          candidates: peer,
          quarantined: syncQuarantinedAddresses(peer, windowEnd: windowEnd),
          resolveAlias: (address) =>
              peerReferenceAliases[index][address] ?? address,
        ),
      );
    }
    final mergeQuarantined = {
      ...localQuarantined,
      for (final address in peerQuarantined)
        if (normalizedLocal[address] == null) address,
    };
    final mergeBaseline =
        freshAttach
              ? <SyncRecordAddress, SyncBaselineEntry>{}
              : <SyncRecordAddress, SyncBaselineEntry>{...normalizedBaseline}
          ..removeWhere(
            (address, _) =>
                normalizedPending.contains(address) ||
                mergeQuarantined.contains(address),
          );
    final plan = _mergeEngine.plan(
      local: mergeLocal,
      baseline: mergeBaseline,
      peers: mergePeers,
      freshAttach: freshAttach,
      unresolved: {...normalizedUnresolved, ...mergeQuarantined},
    );
    reports.addAll(plan.reports);
    final downloads = [
      for (final decision in plan.downloads)
        if (decision.winner != null) decision.winner!,
    ];
    final expectedCandidates = <SyncRecordAddress, SyncMergeCandidate?>{
      ...normalizedLocal,
      ...normalizedPendingLive,
    };
    final expectedWireHashes = <SyncRecordAddress, String?>{
      for (final entry in expectedCandidates.entries)
        entry.key: entry.value?.wireHash,
      for (final decision in plan.downloads)
        if (decision.winner != null)
          decision.address: expectedCandidates[decision.address]?.wireHash,
    };
    final applyResult = await _applyEngine.apply(
      candidates: downloads,
      storage: store,
      expectedWireHashes: expectedWireHashes,
    );
    reports.addAll(applyResult.reports);
    final appliedKinds = {
      ...repairedKinds,
      for (final address in applyResult.applied) address.kind,
    };

    final dedupe = freshAttach
        ? await store.deduplicateFreshAttach()
        : await store.refreshDanceAmbiguityReviews();
    reports.addAll(dedupe.reports);
    if (freshAttach && dedupe.duplicateCount > 0) {
      appliedKinds.addAll({SyncRecordKind.dance, SyncRecordKind.program});
    }
    if (freshAttach) {
      final attachedSnapshot = await store.snapshot();
      final attachedLocal = await _normalizeCandidates(attachedSnapshot.local);
      final attachedPublication = await _normalizeCandidates(
        attachedSnapshot.publication,
      );
      final attachedReferenceAliases = await _resolveReferenceAliases([
        attachedPublication,
      ]);
      final attachPlan = planSyncPublication(
        publication: attachedPublication,
        baseline: const {},
        windowEnd: windowEnd,
        resolveAlias: (address) => attachedReferenceAliases[address] ?? address,
      );
      // An address unresolved from *any* peer is skipped by the merge
      // (`SyncMergeEngine.plan`), so it was never decided and must not be
      // baselined — §6.3 step 5 leaves the baseline unadvanced precisely so the
      // next pass retries it. The peer-observation test below is not enough on
      // its own: with two peers, one peer's blob can be unfetchable while
      // another supplies the same address at this device's hash, which is the
      // steady-state case `normalizedUnresolved` is excluded for at the
      // `observed` builder further down. Until fresh attach stopped aborting on
      // any unresolved address this branch could not be reached with a
      // non-empty set at all, so the asymmetry was latent rather than benign.
      final baselineEntries = <SyncBaselineEntry>[
        for (final entry in attachedLocal.entries)
          if (entry.value != null &&
              !normalizedUnresolved.contains(entry.key) &&
              attachPlan.manifestHashes[entry.key] == entry.value!.wireHash &&
              peerMaps.any(
                (peer) => peer[entry.key]?.wireHash == entry.value!.wireHash,
              ))
            SyncBaselineEntry(
              kind: entry.key.kind,
              recordId: entry.key.recordId,
              wireHash: entry.value!.wireHash,
              bodyHash: entry.value!.comparisonBodyHash,
            ),
      ];
      final uploadResult = await _uploadMissingLocalBlobs(
        attachPlan.uploadCandidates,
        reports: reports,
      );
      if (!uploadResult.succeeded) {
        return SyncPassResult(
          SyncPassStatus.failed,
          reports: reports.reports,
          message:
              'fresh-attach blob publication failed', // i18n-ignore: internal status
          duplicateCount: dedupe.duplicateCount,
          appliedKinds: appliedKinds.toList(),
        );
      }
      final continuationResult = await _runPass(
        continuation: true,
        continuationEpoch: metadata.epoch,
        deferredBaseline: baselineEntries,
      );
      if (continuationResult.status == SyncPassStatus.completed) {
        await store.markSyncUsed(syncId!);
      }
      return SyncPassResult(
        continuationResult.status,
        reports: [...reports.reports, ...continuationResult.reports],
        message: continuationResult.message,
        duplicateCount:
            dedupe.duplicateCount + continuationResult.duplicateCount,
        appliedKinds: {
          ...appliedKinds,
          ...continuationResult.appliedKinds,
        }.toList(),
      );
    }
    Future<
      ({
        Map<SyncRecordAddress, SyncMergeCandidate?> current,
        Map<SyncRecordAddress, SyncMergeCandidate?> publication,
        SyncPublicationPlan publicationPlan,
        SyncManifest manifest,
        List<SyncRecordAddress> addresses,
      })
    >
    buildPublicationState({
      Set<String> unavailableFallbackHashes = const {},
      Map<SyncRecordAddress, SyncMergeCandidate?>? publicationOverride,
    }) async => store.transaction(() async {
      final currentSnapshot = await store.snapshot();
      final current = await _normalizeCandidates(currentSnapshot.local);
      final publication =
          publicationOverride ??
          await _normalizeCandidates(currentSnapshot.publication);
      final referenceAliases = await _resolveReferenceAliases([publication]);
      final publicationPlan = planSyncPublication(
        publication: publication,
        baseline: normalizedBaseline,
        windowEnd: windowEnd,
        resolveAlias: (address) => referenceAliases[address] ?? address,
        unavailableFallbackHashes: unavailableFallbackHashes,
      );
      final manifest = SyncManifest(
        deviceId: deviceId,
        epoch: metadata.epoch,
        writtenAt: DateTime.now().toUtc(),
        records: _manifestRecords(publicationPlan.manifestHashes),
      );
      final addresses = _manifestAddresses(manifest);
      // The initial plan is a conservative superset of any replan that omits
      // unavailable fallback hashes, so protect it before probing the store.
      await store.markPublished(addresses);
      return (
        current: current,
        publication: publication,
        publicationPlan: publicationPlan,
        manifest: manifest,
        addresses: addresses,
      );
    });

    var publicationState = await buildPublicationState();
    // Availability-only: a fallback hash is a baseline hash for a withheld
    // address, which by construction differs from that address's current wire
    // hash — and a wire blob embeds its own kind and id, so no other address
    // can be carrying it either. There is therefore never a local candidate to
    // re-upload; the probe exists to learn which agreed fallbacks the store has
    // lost, so the replan can drop them.
    final fallbackProbe = await _uploadMissingLocalBlobs(
      const {},
      fallbackHashes: publicationState.publicationPlan.fallbackHashes,
      reports: reports,
    );
    if (!fallbackProbe.succeeded) {
      return SyncPassResult(
        SyncPassStatus.failed,
        reports: reports.reports,
        message:
            'fallback blob availability probe failed', // i18n-ignore: internal status
        appliedKinds: appliedKinds.toList(),
      );
    }
    if (fallbackProbe.unavailableFallbackHashes.isNotEmpty) {
      publicationState = await buildPublicationState(
        publicationOverride: publicationState.publication,
        unavailableFallbackHashes: fallbackProbe.unavailableFallbackHashes,
      );
    }
    for (final address in quarantinedLocal) {
      final count =
          publicationState.publicationPlan.withheldDependentCounts[address] ??
          0;
      final dependentLabel = count == 1 ? 'dependent' : 'dependents';
      reports.add(
        SyncReport(
          code: SyncReportCode.quarantinedRecord,
          kind: address.kind,
          recordId: address.recordId,
          message:
              'Record remained quarantined after peer-only timestamp repair; ' // i18n-ignore: internal status
              '$count database-FK $dependentLabel withheld.', // i18n-ignore: internal status
        ),
      );
    }
    final current = publicationState.current;
    final publicationPlan = publicationState.publicationPlan;
    final manifest = publicationState.manifest;
    final addresses = publicationState.addresses;
    final finalUploadResult = await _uploadMissingLocalBlobs(
      publicationPlan.uploadCandidates,
      reports: reports,
    );
    if (!finalUploadResult.succeeded) {
      return SyncPassResult(
        SyncPassStatus.failed,
        reports: reports.reports,
        message:
            'post-apply blob publication failed', // i18n-ignore: internal status
        appliedKinds: appliedKinds.toList(),
      );
    }
    final manifestBody = encodeSyncManifestUtf8(manifest);
    await store.markPublicationAttempt(syncId: syncId!, records: addresses);
    final published = await transport.putManifest(deviceId, manifestBody);
    if (published.kind == SyncResponseKind.conflict) {
      return SyncPassResult(
        SyncPassStatus.staleEpoch,
        reports: reports.reports,
        message:
            'manifest publication observed a stale epoch', // i18n-ignore: internal status
        appliedKinds: appliedKinds.toList(),
      );
    }
    if (!published.isSuccess) {
      return SyncPassResult(
        SyncPassStatus.failed,
        reports: reports.reports,
        message:
            'manifest publication returned ${published.statusCode}', // i18n-ignore: internal status
        appliedKinds: appliedKinds.toList(),
      );
    }
    final observed = <SyncBaselineEntry>[];
    for (final entry in current.entries) {
      if (normalizedUnresolved.contains(entry.key)) continue;
      final candidate = entry.value;
      if (candidate == null) continue;
      if (publicationPlan.manifestHashes[entry.key] != candidate.wireHash) {
        continue;
      }
      final seenByPeer = peerMaps.any(
        (peer) => peer[entry.key]?.wireHash == candidate.wireHash,
      );
      if (!seenByPeer) continue;
      observed.add(
        SyncBaselineEntry(
          kind: entry.key.kind,
          recordId: entry.key.recordId,
          wireHash: candidate.wireHash,
          bodyHash: candidate.comparisonBodyHash,
        ),
      );
    }
    final uploadManifestHashes = <SyncRecordAddress, String>{
      for (final address in publicationPlan.uploadAddresses)
        address: publicationPlan.manifestHashes[address]!,
    };
    _recordUnreflectedPublications(
      uploadManifestHashes,
      peerManifestHashes: peerManifestHashes,
      reports: reports,
    );
    final dropped = {
      for (final decision in plan.decisions)
        if (decision.action == SyncMergeAction.dropBaseline) decision.address,
    };
    if (deferredBaseline == null) {
      await store.advanceBaseline(
        epoch: metadata.epoch,
        entries: observed,
        drop: dropped,
      );
    } else {
      final completedBaseline = <SyncRecordAddress, SyncBaselineEntry>{
        for (final entry in deferredBaseline)
          (kind: entry.kind, recordId: entry.recordId): entry,
      }..removeWhere((address, _) => dropped.contains(address));
      for (final entry in observed) {
        completedBaseline[(kind: entry.kind, recordId: entry.recordId)] = entry;
      }
      await store.replaceBaseline(
        epoch: metadata.epoch,
        entries: completedBaseline.values,
      );
    }

    return SyncPassResult(
      SyncPassStatus.completed,
      reports: reports.reports,
      duplicateCount: dedupe.duplicateCount,
      appliedKinds: appliedKinds.toList(),
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

  bool _hasLegacyBaselineBodyHashes(
    Map<SyncRecordAddress, SyncBaselineEntry> baseline,
  ) => baseline.values.any(
    (entry) =>
        entry.bodyHash != null &&
        entry.bodyHashVersion == SyncBaselineBodyHashVersion.legacyFullBody,
  );

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
          bodyHashVersion: entry.value.bodyHashVersion,
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

  Future<Map<SyncRecordAddress, String>> _normalizeManifestHashes(
    SyncManifest manifest,
  ) async {
    final normalized = <SyncRecordAddress, String>{};
    final sources = <SyncRecordAddress, SyncRecordAddress>{};
    for (final kindEntry in manifest.records.entries) {
      for (final entry in kindEntry.value.entries) {
        final source = (kind: kindEntry.key, recordId: entry.key);
        final address = await store.resolveAlias(source);
        if (_shouldReplaceNormalizedAddress(
          sources[address],
          source,
          address,
        )) {
          normalized[address] = entry.value;
          sources[address] = source;
        }
      }
    }
    return normalized;
  }

  Future<Map<SyncRecordAddress, SyncRecordAddress>> _resolveReferenceAliases(
    Iterable<Map<SyncRecordAddress, SyncMergeCandidate?>> candidateMaps,
  ) async {
    final references = <SyncRecordAddress>{};
    for (final candidates in candidateMaps) {
      for (final candidate in candidates.values) {
        if (candidate != null) {
          references.addAll(syncRecordReferences(candidate));
        }
      }
    }
    final resolved = <SyncRecordAddress, SyncRecordAddress>{};
    for (final reference in references) {
      final address = await store.resolveAlias(reference);
      if (address != reference) resolved[reference] = address;
    }
    return resolved;
  }

  void _addPeerQuarantineReports(
    Map<SyncRecordAddress, SyncMergeCandidate?> candidates, {
    required String peerId,
    required DateTime windowEnd,
    required SyncReportSink reports,
  }) {
    const classifier = SyncQuarantineClassifier();
    for (final entry in candidates.entries) {
      final candidate = entry.value;
      if (candidate == null ||
          !classifier.assess(candidate, windowEnd: windowEnd).isQuarantined) {
        continue;
      }
      if (!_peerManifestCache.rejectedHashes.add(candidate.wireHash)) {
        continue;
      }
      reports.add(
        SyncReport(
          // See SyncApplyEngine.apply: a quarantined record is well-formed
          // with an implausible clock, which is not the same finding as a
          // malformed one.
          code: SyncReportCode.quarantinedRecord,
          kind: entry.key.kind,
          recordId: entry.key.recordId,
          peerId: peerId,
          message:
              'Inbound record timestamp exceeded the local clock window.', // i18n-ignore: internal status
        ),
      );
    }
  }

  void _recordClockSuspect(
    Iterable<Map<SyncRecordAddress, SyncMergeCandidate?>> peerMaps, {
    required DateTime windowEnd,
    required SyncReportSink reports,
  }) {
    final observed = <DateTime>[];
    for (final peer in peerMaps) {
      for (final candidate in peer.values) {
        if (candidate == null) continue;
        observed
          ..add(candidate.updatedAt)
          ..add(candidate.existenceAt);
      }
    }
    if (observed.isEmpty ||
        !observed.every((value) => value.isAfter(windowEnd))) {
      return;
    }
    reports.add(
      const SyncReport(
        code: SyncReportCode.clockSuspect,
        message:
            'Every peer timestamp observed in this pass exceeded the local ' // i18n-ignore: internal status
            'clock window.', // i18n-ignore: internal status
      ),
    );
  }

  void _recordUnreflectedPublications(
    Map<SyncRecordAddress, String> publishableHashes, {
    required Iterable<Map<SyncRecordAddress, String>> peerManifestHashes,
    required SyncReportSink reports,
  }) {
    final peers = peerManifestHashes.toList(growable: false);
    if (peers.isEmpty) {
      _peerManifestCache.unreflectedPasses.clear();
      return;
    }
    final publishedAddresses = publishableHashes.keys.toSet();
    _peerManifestCache.unreflectedPasses.removeWhere(
      (address, _) => !publishedAddresses.contains(address),
    );
    for (final entry in publishableHashes.entries) {
      final reflected = peers.any((peer) => peer[entry.key] == entry.value);
      if (reflected) {
        _peerManifestCache.unreflectedPasses.remove(entry.key);
        continue;
      }
      final count = (_peerManifestCache.unreflectedPasses[entry.key] ?? 0) + 1;
      _peerManifestCache.unreflectedPasses[entry.key] = count;
      if (count < 3) continue;
      reports.add(
        SyncReport(
          code: SyncReportCode.unreflectedPublication,
          kind: entry.key.kind,
          recordId: entry.key.recordId,
          message:
              'A published record was not reflected by any observed peer ' // i18n-ignore: internal status
              'for three consecutive passes.', // i18n-ignore: internal status
        ),
      );
    }
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
    _replacementDeclined = false;
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
      if (!_replacementDeclined) _paused = false;
    } else if (result.status == SyncPassStatus.replacementRequired) {
      _replacementCreated = false;
    }
    _replacementDeclined = false;
    return result;
  }

  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> _downloadPeerRecords(
    SyncManifest manifest, {
    required String peerId,
    required SyncReportSink reports,
    required Set<SyncRecordAddress> unresolved,
    required Map<String, SyncMergeCandidate> candidateByHash,
    required Set<SyncRecordAddress> rejectedAddresses,
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
          final admitted = _admitPeerCandidate(
            SyncMergeCandidate(
              blob: cachedCandidate.blob,
              wireHash: cachedCandidate.wireHash,
              peerId: peerId,
            ),
            reports: reports,
            rejectedAddresses: rejectedAddresses,
          );
          if (admitted != null) result[address] = admitted;
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
          peerId: peerId,
        );
        final admitted = _admitPeerCandidate(
          candidate,
          reports: reports,
          rejectedAddresses: rejectedAddresses,
        );
        if (admitted == null) continue;
        candidateByHash[recordEntry.value] = admitted;
        result[address] = admitted;
      }
    }
    return result;
  }

  SyncMergeCandidate? _admitPeerCandidate(
    SyncMergeCandidate candidate, {
    required SyncReportSink reports,
    required Set<SyncRecordAddress> rejectedAddresses,
  }) {
    final admission = admitSyncInboundCandidate(candidate);
    final report = admission.report;
    if (report != null) {
      rejectedAddresses.add(candidate.address);
      reports.add(report);
      return null;
    }
    return admission.candidate!;
  }

  Future<_MissingBlobUploadResult> _uploadMissingLocalBlobs(
    Map<String, SyncMergeCandidate> localByHash, {
    Set<String> fallbackHashes = const {},
    required SyncReportSink reports,
  }) async {
    final requestedHashes = {
      ...localByHash.keys,
      ...fallbackHashes,
    }.toList(growable: false);
    final unavailableFallbackHashes = <String>{};
    for (
      var offset = 0;
      offset < requestedHashes.length;
      offset += _maxMissingHashesPerRequest
    ) {
      final end = (offset + _maxMissingHashesPerRequest).clamp(
        0,
        requestedHashes.length,
      );
      final response = await transport.postMissing(
        requestedHashes.sublist(offset, end),
      );
      if (!response.isSuccess) {
        return const _MissingBlobUploadResult(
          succeeded: false,
          unavailableFallbackHashes: {},
        );
      }
      final missing = _decodeMissing(response.body);
      if (missing == null) {
        return const _MissingBlobUploadResult(
          succeeded: false,
          unavailableFallbackHashes: {},
        );
      }
      for (final hash in missing) {
        final candidate = localByHash[hash];
        if (candidate == null) {
          if (fallbackHashes.contains(hash)) {
            unavailableFallbackHashes.add(hash);
            reports.add(
              SyncReport(
                code: SyncReportCode.unresolvedBlob,
                message:
                    'An agreed fallback blob was unavailable locally and at the ' // i18n-ignore: internal report
                    'store.', // i18n-ignore: internal report
              ),
            );
            continue;
          }
          reports.add(
            SyncReport(
              code: SyncReportCode.unresolvedBlob,
              message:
                  'The store requested an unknown local blob.', // i18n-ignore: internal report
            ),
          );
          return const _MissingBlobUploadResult(
            succeeded: false,
            unavailableFallbackHashes: {},
          );
        }
        final uploaded = await transport.putBlob(
          hash,
          encodeSyncRecordBlobUtf8(candidate.blob),
        );
        if (!uploaded.isSuccess) {
          return const _MissingBlobUploadResult(
            succeeded: false,
            unavailableFallbackHashes: {},
          );
        }
      }
    }
    return _MissingBlobUploadResult(
      succeeded: true,
      unavailableFallbackHashes: Set.unmodifiable(unavailableFallbackHashes),
    );
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
    Map<SyncRecordAddress, String> hashes,
  ) {
    final records = <SyncRecordKind, Map<String, String>>{};
    for (final entry in hashes.entries) {
      records.putIfAbsent(entry.key.kind, () => {})[entry.key.recordId] =
          entry.value;
    }
    return records;
  }

  static List<SyncRecordAddress> _manifestAddresses(SyncManifest manifest) => [
    for (final kindEntry in manifest.records.entries)
      for (final recordId in kindEntry.value.keys)
        (kind: kindEntry.key, recordId: recordId),
  ];
}

class _StoreMetadata {
  const _StoreMetadata({required this.epoch, required this.devices});

  final String epoch;
  final List<String> devices;
}
