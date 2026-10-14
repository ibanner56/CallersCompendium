import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';

import '../diagnostics/error_log.dart';
import 'sync_failure.dart';
import 'sync_http_client.dart';

export 'sync_failure.dart'
    show SyncFailure, SyncFailureCause, SyncFailureCauseTier, SyncFailureStep;

DateTime _syncNowUtc() => DateTime.now().toUtc();

/// The event sources that share the single-flight sync scheduler (spec
/// §6.12).
///
/// Only [manual] is treated differently by the coordinator: it is the one
/// trigger that resumes a paused coordinator. Every other value is automatic.
enum SyncTrigger {
  appStart,
  debouncedChange,
  manual,

  /// The automatic retry `SyncController` schedules after a transient failure.
  retry,

  /// The app returning to the foreground.
  resume,
}

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

/// The share of either store limit at which the status surface warns that the
/// store is almost full (spec §5.2: the caps are echoed "so a client can warn
/// before hitting them rather than discovering a `507`").
const double kSyncQuotaWarningFraction = 0.8;

/// What the store has used of its §5.4 allowance, as `GET /v1/store` reports
/// it under `quota` (spec §5.2).
class SyncStoreQuota {
  const SyncStoreQuota({
    required this.blobs,
    required this.bytes,
    required this.maxBlobs,
    required this.maxBytes,
  });

  final int blobs;
  final int bytes;
  final int maxBlobs;
  final int maxBytes;

  /// The larger of the two shares used, from 0; either cap reached is full.
  double get usedFraction {
    final byBlobs = blobs / maxBlobs;
    final byBytes = bytes / maxBytes;
    return byBlobs > byBytes ? byBlobs : byBytes;
  }

  /// Whether either limit is at or past [kSyncQuotaWarningFraction].
  bool get nearlyFull => usedFraction >= kSyncQuotaWarningFraction;

  /// Reads the `quota` object of a store answer, or null when it is absent or
  /// not the documented shape.
  ///
  /// Lenient where the rest of the store answer is strict, deliberately: the
  /// quota is advice for a warning, and nothing in a pass depends on it, so a
  /// server that omits it (or a malformed one) costs the warning and nothing
  /// else, rather than failing every pass.
  static SyncStoreQuota? tryParse(Object? value) {
    if (value is! Map) return null;
    final blobs = value['blobs'];
    final bytes = value['bytes'];
    final maxBlobs = value['maxBlobs'];
    final maxBytes = value['maxBytes'];
    if (blobs is! int ||
        bytes is! int ||
        maxBlobs is! int ||
        maxBytes is! int ||
        blobs < 0 ||
        bytes < 0 ||
        maxBlobs <= 0 ||
        maxBytes <= 0) {
      return null;
    }
    return SyncStoreQuota(
      blobs: blobs,
      bytes: bytes,
      maxBlobs: maxBlobs,
      maxBytes: maxBytes,
    );
  }

  /// The isolate-message encoding, in the wire shape [tryParse] reads.
  Map<String, Object?> encode() => {
    'blobs': blobs,
    'bytes': bytes,
    'maxBlobs': maxBlobs,
    'maxBytes': maxBytes,
  };
}

/// The result returned by a coordinator pass or explicit replacement action.
class SyncPassResult {
  const SyncPassResult(
    this.status, {
    this.reports = const [],
    this.message,
    this.failure,
    this.duplicateCount = 0,
    this.appliedKinds = const [],
    this.quota,
    this._storeRead = false,
    this.peers,
  });

  final SyncPassStatus status;
  final List<SyncReport> reports;

  /// An English diagnostic for logs and tests. Never shown to the user: the
  /// status surface explains a failure from [failure].
  final String? message;

  /// Why a [SyncPassStatus.failed] pass failed; null for every other status.
  final SyncFailure? failure;
  final int duplicateCount;

  /// Sync record kinds whose tables were mutated by this pass.
  ///
  /// This includes inbound apply records and fresh-attach dedupe rewrites. It
  /// crosses the worker boundary so the owning Drift connection can invalidate
  /// its live queries after the worker has closed its connection.
  final List<SyncRecordKind> appliedKinds;

  /// The store's usage as the pass's latest store lookup reported it, or null
  /// when the pass never got a usable lookup or the server sent none. Set on
  /// any status, a failed pass included: a pass that stopped at its upload
  /// with a `507` has still read how full the store is.
  final SyncStoreQuota? quota;

  /// Whether the pass read a usable store answer, so that [quota] — null
  /// included — is what the store says now. A null [quota] alone cannot tell
  /// "never reached the store" (keep the last reading) from "the store sent
  /// no usable quota" (spec §5.2: lose the warning). A non-null [quota]
  /// implies a read.
  bool get storeRead => _storeRead || quota != null;
  final bool _storeRead;

  /// This result carrying the store reading the pass took, unless it already
  /// carries one (a result from the worker isolate does) or none was taken.
  SyncPassResult withStoreReading({
    required bool read,
    SyncStoreQuota? quota,
  }) => !read || storeRead
      ? this
      : SyncPassResult(
          status,
          reports: reports,
          message: message,
          failure: failure,
          duplicateCount: duplicateCount,
          appliedKinds: appliedKinds,
          quota: quota,
          storeRead: true,
          peers: peers,
        );

  /// What this pass saw of each other device whose manifest it read, or null
  /// when the pass did not get as far as publishing and so surveyed nothing.
  ///
  /// Null and empty mean different things, and the controller relies on it: an
  /// empty list is a completed survey that found no other device, which
  /// replaces what it held, while null leaves the previous survey standing.
  final List<SyncPeerSummary>? peers;
}

/// One other device as a completed pass saw it, for the *Other devices* list.
///
/// Built from the manifest the pass already fetched, so showing it costs no
/// request of its own.
final class SyncPeerSummary {
  const SyncPeerSummary({
    required this.peerId,
    required this.writtenAt,
    required this.waitingCount,
  });

  final String peerId;

  /// The peer's own manifest `writtenAt`: when it last published, by *its*
  /// clock. Only ever shown rounded to the day.
  final DateTime writtenAt;

  /// How many records this device publishes whose current hash that peer's
  /// manifest does not carry — changes from here that are waiting for it.
  final int waitingCount;
}

/// The pass sequence number on which this device first published one record's
/// current hash in this sync session — or, for a hash an earlier session
/// published, the first pass of this one that found it in the manifest the
/// store holds. That is later than the real publication, so it can only delay
/// a §6.9 refusing judgement, never bring one forward.
typedef SyncOwnPublication = ({String hash, int pass});

/// One distinct manifest `writtenAt` seen for a peer, and the pass sequence
/// number on which it was first seen.
typedef SyncPeerPublication = ({DateTime writtenAt, int pass});

/// The manifest this device last published, as this session knows it: the
/// hash [SyncCoordinator] records for it, and every blob hash it names. Every
/// one of those blobs was in the store when it was published, and stays
/// there while the manifest names it (spec §7.3), so a later pass need not
/// ask about them again.
typedef SyncOwnManifest = ({String hash, Set<String> blobHashes});

/// How long a pass may rely on what an earlier one confirmed about this
/// device's own manifest and blobs (spec §6.3 steps 7 and 8). Past it, a pass
/// asks the store about every blob again and republishes the manifest even when
/// nothing in it changed, which also keeps its `writtenAt` — what peers show as
/// this device's last share, and the evidence §6.9 judges a refusing peer by —
/// from going stale on a device that is in use but has nothing new to share.
///
/// It must stay below §7.3's 24-hour grace for unreferenced uploads, and the
/// confirmation it is measured from is the start of the pass that asked, not
/// the answer. Together they mean a pass that stalled past the grace before
/// its `PUT` — whose blobs the store may then have collected — is never
/// current for the pass after it, which therefore asks about every blob.
const Duration kSyncPublicationRefreshInterval = Duration(hours: 12);

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
    List<SyncReport> withheld = const [],
  }) : local = Map.unmodifiable(local),
       baseline = Map.unmodifiable(baseline),
       publication = Map.unmodifiable(publication ?? local),
       pendingLive = Map.unmodifiable(pendingLive ?? const {}),
       pending = Set.unmodifiable(pending),
       withheld = List.unmodifiable(withheld);

  final String? epoch;
  final bool previouslyUsed;
  final Map<SyncRecordAddress, SyncMergeCandidate?> local;
  final Map<SyncRecordAddress, SyncBaselineEntry> baseline;
  final Map<SyncRecordAddress, SyncMergeCandidate?> publication;
  final Map<SyncRecordAddress, SyncMergeCandidate?> pendingLive;
  final Set<SyncRecordAddress> pending;

  /// Records this snapshot withheld from publication because this device could
  /// not decode their stored content (spec §6.9, #1347).
  ///
  /// Defaulted rather than required so the existing snapshot fakes keep
  /// compiling and keep meaning what they meant: a snapshot that withheld
  /// nothing.
  final List<SyncReport> withheld;
}

/// Persisted ID aliases (`losingId -> survivingId`, per record kind) held in
/// memory, resolving exactly as `SyncLocalRepository.resolveAlias` does.
///
/// Chains are followed on demand rather than collapsed up front, so a cycle
/// throws only for an address whose chain reaches it, as the per-call SQL
/// resolution did. An eager collapse would also throw for a cycle that no
/// queried address touches.
final class SyncAliasMap {
  const SyncAliasMap(this._byKind);

  final Map<SyncRecordKind, Map<String, String>> _byKind;

  /// Each kind's losing id to the id it was merged into, one link at a time.
  Map<SyncRecordKind, Map<String, String>> get links => _byKind;

  SyncRecordAddress resolve(SyncRecordAddress address) {
    final links = _byKind[address.kind];
    if (links == null) return address;
    var current = address.recordId;
    final seen = <String>{current};
    for (var next = links[current]; next != null; next = links[current]) {
      if (!seen.add(next)) {
        throw StateError(
          'Cyclic sync ID alias for ${address.kind.name}: ${address.recordId}',
        );
      }
      current = next;
    }
    return current == address.recordId
        ? address
        : (kind: address.kind, recordId: current);
  }
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

  /// Every persisted ID alias, loaded in one statement.
  ///
  /// The normalisation helpers load this once per call and resolve in memory:
  /// resolving per item through the store is one transaction per record. Do not
  /// hold the result across coordinator steps. Collision adoption writes
  /// aliases between them, so a map kept for a whole pass would go stale.
  Future<SyncAliasMap> aliasMap();

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

  /// Queues this pass's conflict choices and drops those it no longer raises
  /// (sync-spec §6.3, §6.6). [unevaluated] names addresses the merge skipped,
  /// whose queued choices must survive the pass untouched.
  Future<int> refreshConflictReviews(
    Iterable<SyncMergeDecision> reviews, {
    Set<SyncRecordAddress> unevaluated,
  });

  /// Every record with a conflict choice queued, including those a pass kept
  /// untouched because the merge skipped them.
  Future<Set<SyncRecordAddress>> queuedConflictAddresses();

  /// The wire hashes of whole-collection versions the user chose against on
  /// this device, which the merge does not count as a conflict again
  /// (sync-spec §6.6).
  Future<Map<SyncRecordAddress, Set<String>>> decidedAgainstHashes();

  Future<void> replaceBaseline({
    required String epoch,
    required Iterable<SyncBaselineEntry> entries,
  });

  /// Clears old epoch-scoped conclusions without persisting the new epoch.
  ///
  /// A fresh attach persists its epoch only with [replaceBaseline] after the
  /// union, dedupe, blob publication, and resulting manifest are complete.
  Future<void> clearEpochState();

  /// What this device last published in [epoch] (spec §6.3 step 8).
  Future<SyncPublishedManifest?> publishedManifest({required String epoch});

  /// Records, or with null forgets, what this device last published in
  /// [epoch].
  Future<void> setPublishedManifest({
    required String epoch,
    required SyncPublishedManifest? published,
  });

  /// The manifest kept for [peerId] (spec §5.2), or null.
  Future<SyncStoredPeerManifest?> storedPeerManifest(String peerId);

  /// Keeps [manifest] as [peerId]'s.
  Future<void> storePeerManifest(
    String peerId,
    SyncStoredPeerManifest manifest,
  );

  /// Forgets the manifest kept for [peerId].
  Future<void> forgetPeerManifest(String peerId);

  /// Forgets every kept manifest except those of [peerIds] in [epoch].
  Future<void> retainPeerManifests({
    required String epoch,
    required Set<String> peerIds,
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
      withheld: snapshot.withheld,
    );
  }

  @override
  Future<Map<SyncRecordAddress, SyncMergeCandidate?>> snapshotCandidates() =>
      storage.snapshot().then(
        (snapshot) => {...snapshot.local, ...snapshot.pendingLive},
      );

  // Loads the rows the way `CompendiumSyncStorage._aliasMap()` in
  // compendium_core does, but resolves chains lazily (see [SyncAliasMap]) so a
  // cycle fails as `resolveAlias` did. That file belongs to the sync-core lane,
  // so a later change can deduplicate the two.
  @override
  Future<SyncAliasMap> aliasMap() async {
    final byKind = <SyncRecordKind, Map<String, String>>{};
    for (final row in await storage.repositories.syncLocal.listAliases()) {
      byKind.putIfAbsent(row.kind, () => <String, String>{})[row.losingId] =
          row.survivingId;
    }
    return SyncAliasMap(byKind);
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
  Future<int> refreshConflictReviews(
    Iterable<SyncMergeDecision> reviews, {
    Set<SyncRecordAddress> unevaluated = const {},
  }) => storage.refreshConflictReviews(reviews, unevaluated: unevaluated);

  @override
  Future<Map<SyncRecordAddress, Set<String>>> decidedAgainstHashes() =>
      storage.decidedAgainstHashes();

  @override
  Future<Set<SyncRecordAddress>> queuedConflictAddresses() async => {
    for (final row in await storage.repositories.syncLocal.listReviewQueue())
      if (row.reason == syncConflictChoiceReason)
        (kind: row.kind, recordId: row.recordId),
  };

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
  Future<SyncPublishedManifest?> publishedManifest({required String epoch}) =>
      storage.repositories.syncLocal.publishedManifest(epoch: epoch);

  @override
  Future<void> setPublishedManifest({
    required String epoch,
    required SyncPublishedManifest? published,
  }) => storage.repositories.syncLocal.setPublishedManifest(
    epoch: epoch,
    published: published,
  );

  @override
  Future<SyncStoredPeerManifest?> storedPeerManifest(String peerId) =>
      storage.repositories.syncLocal.peerManifest(peerId);

  @override
  Future<void> storePeerManifest(
    String peerId,
    SyncStoredPeerManifest manifest,
  ) => storage.repositories.syncLocal.putPeerManifest(peerId, manifest);

  @override
  Future<void> forgetPeerManifest(String peerId) =>
      storage.repositories.syncLocal.removePeerManifest(peerId);

  @override
  Future<void> retainPeerManifests({
    required String epoch,
    required Set<String> peerIds,
  }) => storage.repositories.syncLocal.retainPeerManifests(
    epoch: epoch,
    peerIds: peerIds,
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

  /// `POST /v1/blobs/batch` (spec §5.2): see [SyncHttpClient.postBlobBatch].
  Future<SyncHttpResponse> postBlobBatch(
    List<String> hashes, {
    required void Function(SyncBlobBatchFrame frame) onFrame,
  });

  Future<SyncHttpResponse> putBlob(String hash, List<int> body);

  /// `PUT /v1/blobs/batch` (spec §5.2): see [SyncHttpClient.putBlobBatch].
  Future<SyncHttpResponse> putBlobBatch(
    List<({String hash, List<int> body})> blobs,
  );
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
  Future<SyncHttpResponse> postBlobBatch(
    List<String> hashes, {
    required void Function(SyncBlobBatchFrame frame) onFrame,
  }) => client.postBlobBatch(hashes, onFrame: onFrame);

  @override
  Future<SyncHttpResponse> putBlob(String hash, List<int> body) =>
      client.putBlob(hash, body);

  @override
  Future<SyncHttpResponse> putBlobBatch(
    List<({String hash, List<int> body})> blobs,
  ) => client.putBlobBatch(blobs);
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
    this.stored = false,
  });

  final String epoch;
  final String etag;
  final SyncManifest manifest;

  /// Whether storage is known to keep this entry (spec §5.2). False until a
  /// pass writes it or reads it back, and again after anything that clears
  /// the kept copies, so a `304` can put back one that went missing.
  final bool stored;

  SyncPeerManifestCacheEntry withStored(bool stored) =>
      SyncPeerManifestCacheEntry(
        epoch: epoch,
        etag: etag,
        manifest: manifest,
        stored: stored,
      );
}

/// Keeps verified peer manifests across isolated production passes.
///
/// For the session only: storage keeps a copy of each across restarts
/// ([SyncCoordinatorStore.storedPeerManifest], spec §5.2), which a pass takes
/// in whenever this cache has none for a peer.
///
/// Isolate boundaries cannot retain the coordinator instance, so this cache
/// has an explicit message representation that the pass operation can return
/// to its owner after each worker finishes.
///
/// It also carries the session-scoped evidence the §6.9 unreflected-publication
/// judgement is made from: when this device first published each record's
/// current hash ([publications]), and the distinct manifest `writtenAt` values
/// seen for each peer since ([peerPublications]), both stamped with
/// [passSequence] so "seen after" never depends on comparing two devices'
/// clocks alone.
///
/// And it keeps the peer blobs this session has already downloaded
/// ([fetchedBlob]), so a pass that stopped part-way through its downloads
/// (spec §6.3 step 5) is resumed by the next one rather than restarted.
final class SyncPeerManifestCache {
  SyncPeerManifestCache({
    Map<String, SyncPeerManifestCacheEntry>? entries,
    Set<String>? rejectedHashes,
    Map<SyncRecordAddress, SyncOwnPublication>? publications,
    Map<String, List<SyncPeerPublication>>? peerPublications,
    Map<String, Uint8List>? fetchedBlobs,
    this.passSequence = 0,
    this.publicationEpoch,
    this.blobBatchUnsupported = false,
    this.blobUploadBatchUnsupported = false,
    this.ownManifest,
  }) : _entries = {...?entries},
       rejectedHashes = {...?rejectedHashes},
       publications = {...?publications},
       peerPublications = {
         for (final entry in (peerPublications ?? const {}).entries)
           entry.key: [...entry.value],
       } {
    for (final entry in (fetchedBlobs ?? const {}).entries) {
      rememberFetchedBlob(entry.key, entry.value);
    }
  }

  /// The most blob bytes [fetchedBlob] holds; the oldest go first past it.
  ///
  /// Records are small — a dance is a few kilobytes — so this keeps several
  /// thousand, more than a first download of a large library needs. It is a
  /// bound on memory, and on what each pass copies across the isolate
  /// boundary, not a target.
  static const fetchedBlobBytesKept = 8 * 1024 * 1024;

  /// How many distinct `writtenAt` values are kept per peer. Two is what the
  /// judgement needs: a peer is taken to be refusing a record only once it has
  /// published twice since this device published it, and the values are kept
  /// in the order they were first seen, so the two newest are the only two
  /// that can both postdate a publication.
  static const peerPublicationsKept = 2;

  final Map<String, SyncPeerManifestCacheEntry> _entries;
  final Set<String> rejectedHashes;
  final Map<SyncRecordAddress, SyncOwnPublication> publications;
  final Map<String, List<SyncPeerPublication>> peerPublications;
  int passSequence;
  String? publicationEpoch;

  /// Whether `POST /v1/blobs/batch` was answered as a route the server — or a
  /// proxy in front of it — does not serve (spec §6.3 step 5), so the rest of
  /// this session fetches one blob per request instead of asking again every
  /// pass. A self-hosted server updates on its own schedule.
  bool blobBatchUnsupported;

  /// The same, for `PUT /v1/blobs/batch`: the rest of this session uploads one
  /// blob per request.
  bool blobUploadBatchUnsupported;

  /// This device's own last published manifest, while this session knows
  /// which blobs it names (spec §6.3 step 7). Trusted only while its hash is
  /// the one storage records as published; a pass that publishes something
  /// else replaces it, and one about to `PUT` clears it first.
  SyncOwnManifest? ownManifest;

  /// Verified peer blob bodies by wire hash, oldest first.
  ///
  /// A blob is addressed by the hash of its bytes, so a body kept here is the
  /// body the store would serve for that hash in any epoch. Without it, the
  /// only thing that spared the next pass a request was the record having
  /// been applied — a blob fetched and then not applied (the local copy won,
  /// or the choice waits for the user) was downloaded again by every pass,
  /// and enough of those ahead of the rest in download order would have
  /// spent every pass's request budget on the same records. In memory only,
  /// and gone when the sync session ends: unlike the manifests, blobs are
  /// never kept on disk.
  final LinkedHashMap<String, Uint8List> _fetchedBlobs =
      LinkedHashMap<String, Uint8List>();
  int _fetchedBlobBytes = 0;

  /// The body of the blob with [hash] if this session has downloaded and
  /// verified it, or null.
  Uint8List? fetchedBlob(String hash) {
    final body = _fetchedBlobs.remove(hash);
    if (body != null) _fetchedBlobs[hash] = body;
    return body;
  }

  /// Whether [fetchedBlob] holds [hash], without counting as a use of it.
  bool hasFetchedBlob(String hash) => _fetchedBlobs.containsKey(hash);

  /// Keeps [body], whose SHA-256 the caller has verified is [hash].
  void rememberFetchedBlob(String hash, List<int> body) {
    final previous = _fetchedBlobs.remove(hash);
    if (previous != null) _fetchedBlobBytes -= previous.length;
    if (body.length > fetchedBlobBytesKept) return;
    final kept = Uint8List.fromList(body);
    _fetchedBlobs[hash] = kept;
    _fetchedBlobBytes += kept.length;
    while (_fetchedBlobBytes > fetchedBlobBytesKept) {
      final oldest = _fetchedBlobs.keys.first;
      _fetchedBlobBytes -= _fetchedBlobs.remove(oldest)!.length;
    }
  }

  /// Starts the unreflected-publication evidence afresh when the store's epoch
  /// has changed: hashes and manifests from another epoch prove nothing here.
  ///
  /// It also forgets that the server lacked the batch route: a new epoch can
  /// follow a store reaped and re-created mid-session, whose `404` the batch
  /// read as a missing route.
  void beginPublicationEpoch(String epoch) {
    if (publicationEpoch == epoch) return;
    publications.clear();
    peerPublications.clear();
    publicationEpoch = epoch;
    blobBatchUnsupported = false;
    blobUploadBatchUnsupported = false;
    ownManifest = null;
  }

  SyncPeerManifestCacheEntry? operator [](String peerId) => _entries[peerId];

  void operator []=(String peerId, SyncPeerManifestCacheEntry entry) {
    _entries[peerId] = entry;
  }

  void remove(String peerId) {
    _entries.remove(peerId);
  }

  /// Marks every entry as no longer kept by storage, except those of
  /// [keptPeerIds]: whatever just cleared the kept manifests left these in
  /// place.
  void markUnstored({Set<String> keptPeerIds = const {}}) {
    for (final entry in _entries.entries.toList()) {
      if (keptPeerIds.contains(entry.key)) continue;
      _entries[entry.key] = entry.value.withStored(false);
    }
  }

  void clear() {
    _entries.clear();
    rejectedHashes.clear();
    publications.clear();
    peerPublications.clear();
    _fetchedBlobs.clear();
    _fetchedBlobBytes = 0;
    passSequence = 0;
    publicationEpoch = null;
    blobBatchUnsupported = false;
    blobUploadBatchUnsupported = false;
    ownManifest = null;
  }

  void replaceFrom(SyncPeerManifestCache source) {
    _entries
      ..clear()
      ..addAll(source._entries);
    rejectedHashes
      ..clear()
      ..addAll(source.rejectedHashes);
    publications
      ..clear()
      ..addAll(source.publications);
    peerPublications
      ..clear()
      ..addAll({
        for (final entry in source.peerPublications.entries)
          entry.key: [...entry.value],
      });
    _fetchedBlobs
      ..clear()
      ..addAll(source._fetchedBlobs);
    _fetchedBlobBytes = source._fetchedBlobBytes;
    passSequence = source.passSequence;
    publicationEpoch = source.publicationEpoch;
    blobBatchUnsupported = source.blobBatchUnsupported;
    blobUploadBatchUnsupported = source.blobUploadBatchUnsupported;
    ownManifest = source.ownManifest;
  }

  Map<String, Object?> toMessage() => {
    '_entries': {
      for (final entry in _entries.entries)
        entry.key: {
          'epoch': entry.value.epoch,
          'etag': entry.value.etag,
          'manifest': utf8.decode(encodeSyncManifestUtf8(entry.value.manifest)),
          'stored': entry.value.stored,
        },
    },
    '_rejectedHashes': rejectedHashes.toList(growable: false),
    '_publications': [
      for (final entry in publications.entries)
        {
          'kind': entry.key.kind.name,
          'recordId': entry.key.recordId,
          'hash': entry.value.hash,
          'pass': entry.value.pass,
        },
    ],
    '_peerPublications': {
      for (final entry in peerPublications.entries)
        entry.key: [
          for (final seen in entry.value)
            {
              'writtenAt': seen.writtenAt.microsecondsSinceEpoch,
              'pass': seen.pass,
            },
        ],
    },
    '_fetchedBlobs': {
      for (final entry in _fetchedBlobs.entries) entry.key: entry.value,
    },
    '_passSequence': passSequence,
    '_publicationEpoch': publicationEpoch,
    '_blobBatchUnsupported': blobBatchUnsupported,
    '_blobUploadBatchUnsupported': blobUploadBatchUnsupported,
    '_ownManifest': switch (ownManifest) {
      null => null,
      final own => {
        'hash': own.hash,
        'blobHashes': own.blobHashes.toList(growable: false),
      },
    },
  };

  static SyncPeerManifestCache fromMessage(Object? message) {
    if (message == null) return SyncPeerManifestCache();
    if (message is! Map<Object?, Object?>) {
      throw const FormatException('sync isolate returned a malformed cache');
    }
    final entries = <String, SyncPeerManifestCacheEntry>{};
    final rejectedHashes = <String>{};
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
      final stored = value['stored'] ?? false;
      if (epoch is! String ||
          etag is! String ||
          manifestBody is! String ||
          stored is! bool) {
        throw const FormatException('sync isolate returned a malformed cache');
      }
      entries[peerId] = SyncPeerManifestCacheEntry(
        epoch: epoch,
        etag: etag,
        manifest: decodeSyncManifest(manifestBody),
        stored: stored,
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

    const malformedPublications = FormatException(
      'sync isolate returned malformed publication evidence',
    );
    final publications = <SyncRecordAddress, SyncOwnPublication>{};
    final rawPublications = message['_publications'];
    if (rawPublications is! List<Object?>) throw malformedPublications;
    for (final raw in rawPublications) {
      if (raw is! Map<Object?, Object?> ||
          raw['kind'] is! String ||
          raw['recordId'] is! String ||
          raw['hash'] is! String ||
          raw['pass'] is! int) {
        throw malformedPublications;
      }
      final kind = SyncRecordKind.values.asNameMap()[raw['kind']];
      if (kind == null) throw malformedPublications;
      publications[(kind: kind, recordId: raw['recordId']! as String)] = (
        hash: raw['hash']! as String,
        pass: raw['pass']! as int,
      );
    }
    final peerPublications = <String, List<SyncPeerPublication>>{};
    final rawPeerPublications = message['_peerPublications'];
    if (rawPeerPublications is! Map<Object?, Object?>) {
      throw malformedPublications;
    }
    for (final entry in rawPeerPublications.entries) {
      final peerId = entry.key;
      final rawSeen = entry.value;
      if (peerId is! String || rawSeen is! List<Object?>) {
        throw malformedPublications;
      }
      peerPublications[peerId] = [
        for (final seen in rawSeen)
          if (seen is Map<Object?, Object?> &&
              seen['writtenAt'] is int &&
              seen['pass'] is int)
            (
              writtenAt: DateTime.fromMicrosecondsSinceEpoch(
                seen['writtenAt']! as int,
                isUtc: true,
              ),
              pass: seen['pass']! as int,
            )
          else
            throw malformedPublications,
      ];
    }
    final fetchedBlobs = <String, Uint8List>{};
    final rawFetchedBlobs = message['_fetchedBlobs'];
    if (rawFetchedBlobs != null) {
      if (rawFetchedBlobs is! Map<Object?, Object?>) {
        throw const FormatException(
          'sync isolate returned malformed fetched blobs',
        );
      }
      for (final entry in rawFetchedBlobs.entries) {
        final hash = entry.key;
        final body = entry.value;
        if (hash is! String || body is! Uint8List) {
          throw const FormatException(
            'sync isolate returned malformed fetched blobs',
          );
        }
        fetchedBlobs[hash] = body;
      }
    }
    final rawPassSequence = message['_passSequence'];
    if (rawPassSequence is! int || rawPassSequence < 0) {
      throw malformedPublications;
    }
    final rawPublicationEpoch = message['_publicationEpoch'];
    if (rawPublicationEpoch != null && rawPublicationEpoch is! String) {
      throw const FormatException(
        'sync isolate returned a malformed publication epoch',
      );
    }
    final rawBlobBatchUnsupported = message['_blobBatchUnsupported'];
    if (rawBlobBatchUnsupported != null && rawBlobBatchUnsupported is! bool) {
      throw const FormatException(
        'sync isolate returned a malformed blob batch flag',
      );
    }
    final rawUploadBatchUnsupported = message['_blobUploadBatchUnsupported'];
    if (rawUploadBatchUnsupported != null &&
        rawUploadBatchUnsupported is! bool) {
      throw const FormatException(
        'sync isolate returned a malformed blob upload batch flag',
      );
    }
    SyncOwnManifest? ownManifest;
    final rawOwnManifest = message['_ownManifest'];
    if (rawOwnManifest != null) {
      const malformedOwnManifest = FormatException(
        'sync isolate returned a malformed own manifest',
      );
      if (rawOwnManifest is! Map<Object?, Object?>) throw malformedOwnManifest;
      final hash = rawOwnManifest['hash'];
      final blobHashes = rawOwnManifest['blobHashes'];
      if (hash is! String ||
          blobHashes is! List<Object?> ||
          blobHashes.any((blobHash) => blobHash is! String)) {
        throw malformedOwnManifest;
      }
      ownManifest = (hash: hash, blobHashes: blobHashes.cast<String>().toSet());
    }
    return SyncPeerManifestCache(
      entries: entries,
      rejectedHashes: rejectedHashes,
      publications: publications,
      peerPublications: peerPublications,
      fetchedBlobs: fetchedBlobs,
      passSequence: rawPassSequence,
      publicationEpoch: rawPublicationEpoch as String?,
      blobBatchUnsupported: rawBlobBatchUnsupported as bool? ?? false,
      blobUploadBatchUnsupported: rawUploadBatchUnsupported as bool? ?? false,
      ownManifest: ownManifest,
    );
  }
}

/// A coalesced notification that a previously-used remote store is missing.
class SyncReplacementRequiredEvent {
  const SyncReplacementRequiredEvent();
}

/// How far one pass's record downloads got (spec §6.3 step 5).
final class _PeerDownloadProgress {
  _PeerDownloadProgress(List<String> fetchOrder)
    : fetchOrder = List.unmodifiable(fetchOrder),
      _position = {
        for (var index = 0; index < fetchOrder.length; index++)
          fetchOrder[index]: index,
      };

  /// Why downloads stopped, or null while they continue.
  SyncFailure? stop;

  /// How many blobs this pass downloaded and verified.
  int fetched = 0;

  /// The records left unfetched once [stop] was set: waiting, not skipped.
  final notFetched = <SyncRecordAddress>{};

  /// Every hash this pass may need from the network, once each, in the order
  /// the records naming them are taken: a batch asks for the next stretch of
  /// it, so batches follow dependency order exactly as single requests did.
  final List<String> fetchOrder;
  final Map<String, int> _position;

  /// Answers a batch brought ahead of the record that needs them: a body
  /// (taken once, then kept by the session cache), or the status that refused
  /// it (kept, so a second peer naming the same hash is not asked for again).
  final Map<String, _BlobOutcome> batched = {};

  /// The hashes the batch for [hash] asks for: [hash] first, then the ones
  /// after it in [fetchOrder] that are still unanswered, up to [limit].
  List<String> batchFrom(
    String hash, {
    required int limit,
    required bool Function(String hash) answered,
  }) {
    final start = _position[hash];
    if (start == null) return [hash];
    final hashes = <String>[hash];
    for (
      var index = start + 1;
      index < fetchOrder.length && hashes.length < limit;
      index++
    ) {
      final next = fetchOrder[index];
      if (!answered(next)) hashes.add(next);
    }
    return hashes;
  }
}

/// What one record download came to.
sealed class _BlobOutcome {
  const _BlobOutcome();
}

/// The blob's bytes. [downloaded] when this pass fetched them, so the hash
/// still has to be verified; false when the session cache already had them.
final class _BlobBody extends _BlobOutcome {
  const _BlobBody(this.body, {required this.downloaded});

  final List<int> body;
  final bool downloaded;
}

/// The server refused the blob with [statusCode]: a report, as for a `404`.
final class _BlobRefused extends _BlobOutcome {
  const _BlobRefused(this.statusCode);

  final int statusCode;
}

/// Not fetched yet: downloads have stopped for this pass (spec §6.3 step 5).
final class _BlobNotFetched extends _BlobOutcome {
  const _BlobNotFetched();
}

final class _MissingBlobUploadResult {
  const _MissingBlobUploadResult({
    required this.succeeded,
    required this.unavailableFallbackHashes,
  }) : failure = null;

  /// A failed upload, recording [failure] for the pass result.
  const _MissingBlobUploadResult.failed(SyncFailure this.failure)
    : succeeded = false,
      unavailableFallbackHashes = const {};

  final bool succeeded;
  final Set<String> unavailableFallbackHashes;

  /// Why the upload did not succeed; null when it did.
  final SyncFailure? failure;
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

  /// The quota the running pass's latest store lookup reported. A field
  /// rather than threaded through every return in [_runPass], because the
  /// pass has many exits and every one past the lookup should carry it;
  /// [_runStartedPass] resets it before a pass and attaches it after.
  SyncStoreQuota? _passQuota;
  bool _passStoreRead = false;
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
          failure: SyncFailure(SyncFailureCause.internal),
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
          failure: SyncFailure(SyncFailureCause.internal),
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
          failure: SyncFailure(SyncFailureCause.internal),
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
          failure: SyncFailure(SyncFailureCause.internal),
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
        failure: SyncFailure(SyncFailureCause.internal),
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
    _passQuota = null;
    _passStoreRead = false;
    // Under `passOperation` the pass ran in the worker isolate, whose own
    // coordinator attached the reading; this one took none and adds nothing.
    final result =
        (await (passOperation?.call(initialStore: initialStore) ??
                passRunner.run(() => _runPass(initialStore: initialStore))))
            .withStoreReading(read: _passStoreRead, quota: _passQuota);
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
          failure: SyncFailure(SyncFailureCause.internal),
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
        failure: SyncFailure.fromResponse(
          storeResult.response,
          SyncFailureStep.lookup,
        ),
      );
    }

    final metadata = _decodeStoreMetadata(storeResult.response.body);
    if (metadata == null) {
      return const SyncPassResult(
        SyncPassStatus.failed,
        message: 'store metadata was malformed', // i18n-ignore: internal status
        failure: SyncFailure(
          SyncFailureCause.unexpectedResponse,
          step: SyncFailureStep.lookup,
        ),
      );
    }
    _passStoreRead = true;
    _passQuota = metadata.quota;
    _peerManifestCache.beginPublicationEpoch(metadata.epoch);
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
      _peerManifestCache.markUnstored();
      snapshot = await store.snapshot();
    }
    if (!freshAttach &&
        deferredBaseline == null &&
        _hasLegacyBaselineBodyHashes(snapshot.baseline)) {
      await store.clearEpochState();
      _peerManifestCache.markUnstored();
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
    // A record this device holds but cannot read is withheld from publication
    // (spec §6.9). Draining it here is what stops that being silent (#1347):
    // without it the dance is simply absent from every peer, which looks
    // exactly like a dance that synced.
    //
    // Drained from the snapshot rather than emitted through a sink threaded
    // into storage, and drained again after each later re-snapshot below,
    // because the earlier ones are taken before this sink exists. Repeats cost
    // nothing: `SyncReportSink` coalesces on code, kind, record and peer, so
    // one record raises one notice however many paths withheld it.
    reports.addAll(snapshot.withheld);
    final peerMaps = <Map<SyncRecordAddress, SyncMergeCandidate?>>[];
    final peerManifestHashes = <Map<SyncRecordAddress, String>>[];
    final peerReferenceAliases = <Map<SyncRecordAddress, SyncRecordAddress>>[];
    final peerManifests = <({String peerId, SyncManifest manifest})>[];
    final unresolved = <SyncRecordAddress>{};
    var allPeerManifestsAvailable = true;
    // The status of the first peer manifest the server refused, kept for the
    // failure a fresh attach reports: the user can quote it, and it is what
    // separates a server fault from a peer whose list is merely unreadable.
    int? unavailableManifestStatus;
    // The steady-state peer manifest the server failed to serve with the
    // longest `Retry-After` (else the first). The pass still finishes, but it
    // ends as that temporary failure rather than `completed`: see the `5xx`
    // rule below. Keeping the longest wait means the retry never comes sooner
    // than any of those answers allowed.
    SyncHttpResponse? deferredServerFault;
    for (final peerId in metadata.devices) {
      if (peerId == deviceId) continue;
      final cached =
          _peerManifestCache[peerId] ?? await _storedPeerManifest(peerId);
      final epochCached = cached?.epoch == metadata.epoch ? cached : null;
      final response = await transport.getManifest(
        peerId,
        etag: epochCached?.etag,
      );
      final decoded =
          response.kind != SyncResponseKind.notModified && response.isSuccess
          ? _decodeManifest(response.body)
          : null;
      final manifest = response.kind == SyncResponseKind.notModified
          ? epochCached?.manifest
          : decoded?.manifest;
      if (response.kind == SyncResponseKind.notModified && manifest == null) {
        await _forgetPeerManifest(peerId);
      }
      // A `429` is about this device's request rate, not the peer, so it ends
      // the pass as a temporary failure (spec §6.3 step 3). Reported as an
      // unreadable peer list, it raised the skipped-records notice — and on a
      // fresh attach failed the pass as `peerUnavailable`, which waits for the
      // user — over a limit that refills by itself in a minute. Nothing has
      // been applied yet. A `5xx` here is handled just below.
      if (response.kind == SyncResponseKind.rateLimited) {
        return SyncPassResult(
          SyncPassStatus.failed,
          reports: reports.reports,
          message:
              'peer manifest returned ${response.statusCode}', // i18n-ignore: internal status
          failure: SyncFailure.fromResponse(response, SyncFailureStep.download),
        );
      }
      // A `5xx` is the server failing, not the peer (spec §6.3 step 3). A
      // fresh attach cannot finish without every peer's list, so there it is
      // the temporary failure it is, retried by itself; reported as an
      // unreadable peer it failed as `peerUnavailable`, which waits for the
      // user and sends them to their other devices. In steady state the pass
      // carries on as before — every baselined address is left undecided for
      // it (`unresolved` below), so only records new to this device can arrive
      // from the readable peers, and edits to shared records wait — but
      // without a report: the skipped-records notice it raised tells the user
      // to check their other device's app version, which is false advice for
      // a server fault. Instead the finished pass ends as this failure
      // ([deferredServerFault]): reported as `completed`, it cancelled the
      // retry and advanced the last-success clock, so a persistent fault held
      // shared edits back indefinitely while every surface said synced, and
      // the §6.14 expiry warning that clock drives never came. Anything else —
      // a `404`, an unexpected status — is still about that peer's list, and
      // is still reported.
      final serverFault = response.kind == SyncResponseKind.serverError;
      if (serverFault && freshAttach) {
        return SyncPassResult(
          SyncPassStatus.failed,
          reports: reports.reports,
          message:
              'peer manifest returned ${response.statusCode}', // i18n-ignore: internal status
          failure: SyncFailure.fromResponse(response, SyncFailureStep.download),
        );
      }
      if (!response.isSuccess) {
        allPeerManifestsAvailable = false;
        unavailableManifestStatus ??= response.statusCode;
        unresolved.addAll(normalizedBaseline.keys);
        if (serverFault) {
          final kept = deferredServerFault?.retryAfter;
          final wait = response.retryAfter;
          if (deferredServerFault == null ||
              (wait != null && (kept == null || wait > kept))) {
            deferredServerFault = response;
          }
        } else {
          reports.add(
            SyncReport(
              code: SyncReportCode.malformedRecord,
              peerId: peerId,
              httpStatus: response.statusCode,
              message:
                  'Peer manifest returned ${response.statusCode}.', // i18n-ignore: internal report
            ),
          );
        }
        continue;
      }
      if (manifest == null || manifest.epoch != metadata.epoch) {
        allPeerManifestsAvailable = false;
        await _forgetPeerManifest(peerId);
        unresolved.addAll(normalizedBaseline.keys);
        reports.add(
          SyncReport(
            // A manifest this build cannot read because it is newer says
            // nothing about which records it lists, so the report names only
            // the peer (spec §6.9).
            code: decoded?.newer ?? false
                ? SyncReportCode.newerWireVersion
                : SyncReportCode.malformedRecord,
            peerId: peerId,
            message: decoded?.newer ?? false
                ? 'Peer manifest uses a newer wire version.' // i18n-ignore: internal report
                : 'Peer manifest was malformed or used a stale epoch.', // i18n-ignore: internal report
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
            stored: epochCached!.stored && epochCached.etag == etag,
          );
        }
        // A `304` leaves a kept copy as it was, and puts back one storage
        // lost — cleared under a session that kept it in memory, or never
        // written because the write failed.
        final current = _peerManifestCache[peerId];
        if (current != null && !current.stored) {
          await _keepPeerManifest(peerId, current);
        }
      } else if (etag == null || etag.isEmpty) {
        await _forgetPeerManifest(peerId);
      } else {
        // Kept on disk too, so the first pass after a restart can ask with
        // `If-None-Match` rather than download it again (spec §5.2).
        await _keepPeerManifest(
          peerId,
          SyncPeerManifestCacheEntry(
            epoch: metadata.epoch,
            etag: etag,
            manifest: manifest,
          ),
        );
      }
      peerManifests.add((peerId: peerId, manifest: manifest));
      peerManifestHashes.add(await _normalizeManifestHashes(manifest));
    }
    // Kept manifests of devices the store no longer lists, or from another
    // epoch, would never be asked for again. The session keeps its copies, so
    // a device listed again is still asked with its `ETag`, but they are no
    // longer kept, so that `304` writes them back.
    final listedPeers = {
      for (final peerId in metadata.devices)
        if (peerId != deviceId) peerId,
    };
    await store.retainPeerManifests(
      epoch: metadata.epoch,
      peerIds: listedPeers,
    );
    _peerManifestCache.markUnstored(keptPeerIds: listedPeers);
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

    // Every blob this device can build from what it holds needs no download,
    // not only those it publishes: a blob is addressed by the hash of its
    // bytes, so a peer's copy with the same hash is this one. Publication
    // alone left out the imported dances `sync_exclude_imports` keeps back
    // and the live rows behind pending tombstones, so a peer still sharing
    // either had it downloaded again on every pass that missed the session's
    // cache, and on the first pass of every session.
    final localByHash = <String, SyncMergeCandidate>{};
    for (final candidates in [
      snapshot.local,
      snapshot.pendingLive,
      snapshot.publication,
    ]) {
      for (final candidate in candidates.values) {
        if (candidate != null) localByHash[candidate.wireHash] = candidate;
      }
    }
    final availableByHash = <String, SyncMergeCandidate>{...localByHash};
    final rejectedPeerAddresses = <SyncRecordAddress>{};

    // Kind-major across every peer, in apply order, so a pass that stops
    // part-way through its downloads (spec §6.3 step 5) has fetched every
    // record of another kind that the records it did fetch can cite. In
    // manifest order — kinds sorted by name — a dance came before the tags and
    // venues it names, and stopping between them turned every fetched dance
    // into an unresolved-reference report about a record that was merely not
    // fetched yet. Citations within one kind (dance to dance) no order can
    // put first; `_deferCitersOfUnfetched` holds those back instead.
    final downloadedByPeer = [
      for (final _ in peerManifests) <SyncRecordAddress, SyncMergeCandidate?>{},
    ];
    final kindsInApplyOrder = [...SyncRecordKind.values]
      ..sort((a, b) => syncApplyKindOrder(a).compareTo(syncApplyKindOrder(b)));
    final fetchOrder = <String>{
      for (final kind in kindsInApplyOrder)
        for (final peer in peerManifests)
          for (final hash
              in (peer.manifest.records[kind] ?? const <String, String>{})
                  .values)
            if (!availableByHash.containsKey(hash) &&
                !_peerManifestCache.hasFetchedBlob(hash))
              hash,
    };
    final downloadProgress = _PeerDownloadProgress(fetchOrder.toList());
    for (final kind in kindsInApplyOrder) {
      for (var index = 0; index < peerManifests.length; index++) {
        await _downloadPeerRecords(
          peerManifests[index].manifest,
          kind: kind,
          into: downloadedByPeer[index],
          peerId: peerManifests[index].peerId,
          reports: reports,
          unresolved: unresolved,
          candidateByHash: availableByHash,
          rejectedAddresses: rejectedPeerAddresses,
          progress: downloadProgress,
        );
      }
    }

    _deferCitersOfUnfetched(
      downloadedByPeer,
      notFetched: downloadProgress.notFetched,
      unresolved: unresolved,
    );

    final rawPeerMaps = <Map<SyncRecordAddress, SyncMergeCandidate?>>[];
    for (var index = 0; index < peerManifests.length; index++) {
      final peer = peerManifests[index];
      final normalized = await _normalizeCandidates(downloadedByPeer[index]);
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
        failure: SyncFailure(
          SyncFailureCause.peerUnavailable,
          step: SyncFailureStep.download,
          statusCode: unavailableManifestStatus,
        ),
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
      reports.addAll(snapshot.withheld);
      normalizedLocal = await _normalizeCandidates(
        freshAttach ? snapshot.publication : snapshot.local,
      );
      normalizedPendingLive = await _normalizeCandidates(snapshot.pendingLive);
      // The pending views are derived from the same snapshot, so they go stale
      // with it. A repaired tombstone left behind as its pre-repair copy still
      // reads as quarantined, which excludes it from the merge table (§6.3) and
      // so drops the decision the repair was made to win. Rebuilding is what
      // lets the repaired copy stand as this device's candidate.
      await rebuildPendingViews();
    }

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
    final mergeLocalCandidates = {
      ...normalizedLocal,
      ...normalizedPendingTombstones,
    };
    // §6.3 step 4 and §6.9 exclude *a quarantined record* from the merge table,
    // and nothing further: the citation closure is §6.9's publication rule,
    // applied by `planSyncPublication` only to a root with no usable fallback.
    // Excluding a quarantined root's dependents here froze them one way — they
    // kept publishing against the agreed fallback while no peer's edit or
    // tombstone for them was ever applied — on a clock §6.9 says does not
    // self-heal. Inbound dependents stay guarded per record by
    // `validateInboundReferences`, which is where the spec puts that check.
    //
    // The roots are taken over the pending-tombstone overlay too, not just
    // `normalizedLocal`. A quarantined pending tombstone is a quarantined
    // record, and §6.3 states the exclusion without an exception for one; the
    // narrower reading left it filtered out of the local side but still merged,
    // so a peer's stale *live* copy won by default and silently reversed the
    // deletion.
    final mergeQuarantined = syncQuarantinedAddresses(
      mergeLocalCandidates,
      windowEnd: windowEnd,
    );
    // Excluded from the merge table means excluded from `unresolved` as well as
    // from the local side. Dropping a root from `local` alone would leave the
    // engine deciding it with no local candidate, where a peer's copy wins
    // unconditionally (`SyncMergeEngine._resolve`) and, with no peer holding it,
    // its baseline entry is dropped.
    final mergeLocal = {
      for (final entry in mergeLocalCandidates.entries)
        if (!mergeQuarantined.contains(entry.key)) entry.key: entry.value,
    };
    // §6.9's inbound rejection is scoped to the offending blob: "one record
    // skipped, batch intact". Each peer's map is filtered on its own, which
    // drops that peer's refused copies and whatever only those copies let this
    // device reach, so a valid copy of the same address on another peer still
    // resolves. Adding the refused addresses to `unresolved` as well suppressed
    // the address for *every* peer — and only when this device did not already
    // hold it, so the same record merged normally once held. §4.5 and §6.3 say
    // absence from a manifest is not evidence, and a refused copy is absence
    // from that peer.
    final mergePeers = [
      for (var index = 0; index < rawPeerMaps.length; index++)
        filterSyncQuarantinedCandidates(
          rawPeerMaps[index],
          windowEnd: windowEnd,
          resolveAlias: (address) =>
              peerReferenceAliases[index][address] ?? address,
        ),
    ];
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
      decidedAgainst: await store.decidedAgainstHashes(),
      aliases: (await store.aliasMap()).links,
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

    // Ties and whole-collection conflicts wait for the user rather than
    // being reported every pass. Queued after apply, beside the dance
    // review refresh, so one pass leaves the queue matching what it found.
    await store.refreshConflictReviews(
      plan.reviews,
      unevaluated: {...normalizedUnresolved, ...mergeQuarantined},
    );
    final dedupe = freshAttach
        ? await store.deduplicateFreshAttach()
        : await store.refreshDanceAmbiguityReviews();
    reports.addAll(dedupe.reports);
    if (freshAttach && dedupe.duplicateCount > 0) {
      appliedKinds.addAll({SyncRecordKind.dance, SyncRecordKind.program});
    }
    // Downloads stopped part-way (spec §6.3 step 5), so what was fetched is
    // merged and applied above, and the pass ends here as the temporary
    // failure it is: every request from here on — the uploads, the manifest,
    // a fresh attach's continuation — would meet the same limit or fault. The
    // records not fetched are in `normalizedUnresolved`, so nothing was
    // decided for them, and returning before publication leaves the manifest
    // and the baseline unadvanced for everything, as any failure does
    // (§6.12). A fresh attach stays unfinished and is resumed by the next
    // pass, which finds what this one applied already held here.
    if (downloadProgress.stop case final stop?) {
      return SyncPassResult(
        SyncPassStatus.failed,
        reports: reports.reports,
        message:
            'record downloads stopped after ${downloadProgress.fetched} fetched', // i18n-ignore: internal status
        failure: stop.withProgress(downloadProgress.fetched > 0),
        duplicateCount: dedupe.duplicateCount,
        appliedKinds: appliedKinds.toList(),
      );
    }
    if (freshAttach) {
      final attachedSnapshot = await store.snapshot();
      reports.addAll(attachedSnapshot.withheld);
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
          failure: uploadResult.failure,
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
        failure: continuationResult.failure,
        duplicateCount:
            dedupe.duplicateCount + continuationResult.duplicateCount,
        appliedKinds: {
          ...appliedKinds,
          ...continuationResult.appliedKinds,
        }.toList(),
        peers: continuationResult.peers,
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
      reports.addAll(currentSnapshot.withheld);
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
    // What this device last published (spec §6.3 step 8), and whether this
    // pass may rely on it: the store still lists this device — so the
    // manifest it holds is that one, since only this device writes it — and
    // the store confirmed its blobs within the refresh interval. A device
    // removed from the store (§5.3) has lost its manifest, and with it what
    // kept its blobs from §7.3's collection, so it checks and publishes
    // everything again.
    final lastPublished = await store.publishedManifest(epoch: metadata.epoch);
    final lastPublishedCurrent =
        lastPublished != null &&
        metadata.devices.contains(deviceId) &&
        !localNow.isBefore(lastPublished.verifiedAt) &&
        localNow.difference(lastPublished.verifiedAt) <
            kSyncPublicationRefreshInterval;
    // Nothing to share: the manifest is the one the store already holds, and
    // every blob it names was there when it was published. Asking about them
    // again and rewriting it would change only its `writtenAt`, and that alone
    // gives it a new `ETag`, so every peer would download it in full on its
    // next pass. The fallback probe is skipped with the rest: the fallbacks
    // this manifest names were confirmed when it was published, and a
    // replan can only ever drop entries, which would change the hash.
    //
    // Except on a pass that refused or could not take a peer's record: §6.9
    // judges a peer as refusing a record only once it has published twice
    // since, and a peer that skips unchanged publications would otherwise
    // republish only once per refresh interval. Republishing on every such
    // pass keeps that judgement working as it did, and costs nothing while
    // every peer's records are taken.
    //
    // That counts a record the apply step refused (an unkeepable newer field,
    // a reference to data this device lacks, a malformed body) as much as one
    // refused before it: a downloaded winner that was not applied.
    final appliedAddresses = applyResult.applied.toSet();
    final refusedPeerRecords =
        normalizedUnresolved.isNotEmpty ||
        rejectedPeerAddresses.isNotEmpty ||
        downloads.any(
          (candidate) => !appliedAddresses.contains(candidate.address),
        ) ||
        [
          for (var index = 0; index < rawPeerMaps.length; index++)
            peerMaps[index].length < rawPeerMaps[index].length,
        ].any((filtered) => filtered);
    final unchanged =
        lastPublishedCurrent &&
        !refusedPeerRecords &&
        _publishedManifestHash(publicationState.manifest) == lastPublished.hash;
    final ownManifest = _peerManifestCache.ownManifest;
    // Blobs the store is known to hold: those the published manifest names,
    // when this session knows which they are. Only the rest are asked about.
    final knownPresent =
        lastPublishedCurrent && ownManifest?.hash == lastPublished.hash
        ? ownManifest!.blobHashes
        : const <String>{};
    if (!unchanged) {
      // Availability-only: a fallback hash is a baseline hash for a withheld
      // address, which by construction differs from that address's current
      // wire hash — and a wire blob embeds its own kind and id, so no other
      // address can be carrying it either. There is therefore never a local
      // candidate to re-upload; the probe exists to learn which agreed
      // fallbacks the store has lost, so the replan can drop them.
      final fallbackProbe = await _uploadMissingLocalBlobs(
        const {},
        fallbackHashes: publicationState.publicationPlan.fallbackHashes,
        knownPresent: knownPresent,
        reports: reports,
      );
      if (!fallbackProbe.succeeded) {
        return SyncPassResult(
          SyncPassStatus.failed,
          reports: reports.reports,
          message:
              'fallback blob availability probe failed', // i18n-ignore: internal status
          failure: fallbackProbe.failure,
          appliedKinds: appliedKinds.toList(),
        );
      }
      if (fallbackProbe.unavailableFallbackHashes.isNotEmpty) {
        publicationState = await buildPublicationState(
          publicationOverride: publicationState.publication,
          unavailableFallbackHashes: fallbackProbe.unavailableFallbackHashes,
        );
      }
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
    // What to record as published once the baseline is stored, if this pass
    // publishes.
    SyncPublishedManifest? nowPublished;
    if (unchanged) {
      if (ownManifest?.hash != lastPublished.hash) {
        _peerManifestCache.ownManifest = (
          hash: lastPublished.hash,
          blobHashes: _manifestBlobHashes(manifest),
        );
      }
    } else {
      final finalUploadResult = await _uploadMissingLocalBlobs(
        publicationPlan.uploadCandidates,
        knownPresent: knownPresent,
        reports: reports,
      );
      if (!finalUploadResult.succeeded) {
        return SyncPassResult(
          SyncPassStatus.failed,
          reports: reports.reports,
          message:
              'post-apply blob publication failed', // i18n-ignore: internal status
          failure: finalUploadResult.failure,
          appliedKinds: appliedKinds.toList(),
        );
      }
      final manifestBody = encodeSyncManifestUtf8(manifest);
      await store.markPublicationAttempt(syncId: syncId!, records: addresses);
      // Forgotten before the `PUT`, not after it: a `PUT` that fails, or whose
      // answer never arrives, may still have replaced the manifest, so until
      // one is known to have landed nothing about the store's copy is known.
      if (lastPublished != null) {
        await store.setPublishedManifest(
          epoch: metadata.epoch,
          published: null,
        );
      }
      _peerManifestCache.ownManifest = null;
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
          failure: SyncFailure.fromResponse(published, SyncFailureStep.publish),
          appliedKinds: appliedKinds.toList(),
        );
      }
      nowPublished = (
        hash: _publishedManifestHash(manifest),
        // Every blob was asked about unless some were taken as known, in
        // which case the store last confirmed those when they were.
        verifiedAt: knownPresent.isEmpty ? localNow : lastPublished!.verifiedAt,
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
    // A record waiting on the user's choice is unreflected by design until
    // they decide; counting it would raise a second notice for the same
    // record, pointing at the wrong remedy. Every queued choice counts, not
    // only those this pass raised: a choice kept because a peer could not be
    // read this pass is still awaiting the user.
    final awaitingChoice = {
      for (final decision in plan.reviews) decision.address,
      ...await store.queuedConflictAddresses(),
    };
    final uploadManifestHashes = <SyncRecordAddress, String>{
      for (final address in publicationPlan.uploadAddresses)
        if (!awaitingChoice.contains(address))
          address: publicationPlan.manifestHashes[address]!,
    };
    final peerSummaries = _recordUnreflectedPublications(
      uploadManifestHashes,
      ownCandidates: publicationPlan.uploadCandidates,
      peerManifests: peerManifests,
      peerManifestHashes: peerManifestHashes,
      peerCandidates: rawPeerMaps,
      storeDevices: metadata.devices,
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
    // Recorded after the baseline, because replacing the baseline (a fresh
    // attach's continuation) starts its epoch with nothing published.
    if (nowPublished != null) {
      await store.setPublishedManifest(
        epoch: metadata.epoch,
        published: nowPublished,
      );
      _peerManifestCache.ownManifest = (
        hash: nowPublished.hash,
        blobHashes: _manifestBlobHashes(manifest),
      );
    }

    if (deferredServerFault != null) {
      return SyncPassResult(
        SyncPassStatus.failed,
        reports: reports.reports,
        message:
            'peer manifest returned ${deferredServerFault.statusCode}', // i18n-ignore: internal status
        failure: SyncFailure.fromResponse(
          deferredServerFault,
          SyncFailureStep.download,
        ),
        duplicateCount: dedupe.duplicateCount,
        appliedKinds: appliedKinds.toList(),
        peers: peerSummaries,
      );
    }
    return SyncPassResult(
      SyncPassStatus.completed,
      reports: reports.reports,
      duplicateCount: dedupe.duplicateCount,
      appliedKinds: appliedKinds.toList(),
      peers: peerSummaries,
    );
  }

  /// The manifest kept on disk for [peerId], taken into the session cache, or
  /// null when none is kept or the kept copy no longer decodes — in which
  /// case it is dropped and the manifest is fetched in full, as it would be
  /// with nothing kept.
  Future<SyncPeerManifestCacheEntry?> _storedPeerManifest(String peerId) async {
    final stored = await store.storedPeerManifest(peerId);
    if (stored == null) return null;
    final SyncManifest manifest;
    try {
      manifest = decodeSyncManifest(stored.body);
    } on Object catch (error, stack) {
      // A kept copy this build cannot read — damaged, or written in a wire
      // version it does not know — is as good as none. Anything else is a
      // fault and still throws.
      if (error is! FormatException && error is! ArgumentError) rethrow;
      // diagnostics: silent for a FormatException — after an update that
      // bumps the wire version every kept copy fails this way, as expected.
      if (error is ArgumentError) {
        logCaughtErrorTypeOnly(
          error,
          stack,
          source: 'sync_coordinator._storedPeerManifest',
        );
      }
      await store.forgetPeerManifest(peerId);
      return null;
    }
    if (manifest.deviceId != peerId || manifest.epoch != stored.epoch) {
      await store.forgetPeerManifest(peerId);
      return null;
    }
    final entry = SyncPeerManifestCacheEntry(
      epoch: stored.epoch,
      etag: stored.etag,
      manifest: manifest,
      stored: true,
    );
    _peerManifestCache[peerId] = entry;
    return entry;
  }

  /// Puts [entry] in the session cache and keeps it on disk.
  Future<void> _keepPeerManifest(
    String peerId,
    SyncPeerManifestCacheEntry entry,
  ) async {
    // In the session cache first, unmarked: if the write throws, the entry is
    // still used and a later `304` tries the write again.
    _peerManifestCache[peerId] = entry.withStored(false);
    await store.storePeerManifest(peerId, (
      epoch: entry.epoch,
      etag: entry.etag,
      body: encodeSyncManifest(entry.manifest),
    ));
    _peerManifestCache[peerId] = entry.withStored(true);
  }

  /// Forgets [peerId]'s manifest in the session cache and on disk.
  Future<void> _forgetPeerManifest(String peerId) async {
    _peerManifestCache.remove(peerId);
    await store.forgetPeerManifest(peerId);
  }

  /// The hash a published [manifest] is recorded under: its encoding with
  /// `writtenAt` fixed, so it changes exactly when the device id, epoch, wire
  /// version or any record it lists does.
  static String _publishedManifestHash(SyncManifest manifest) => sha256Hex(
    encodeSyncManifestUtf8(
      SyncManifest(
        v: manifest.v,
        deviceId: manifest.deviceId,
        epoch: manifest.epoch,
        writtenAt: DateTime.utc(1970),
        records: manifest.records,
      ),
    ),
  );

  static Set<String> _manifestBlobHashes(SyncManifest manifest) => {
    for (final records in manifest.records.values) ...records.values,
  };

  Future<Set<SyncRecordAddress>> _normalizeAddresses(
    Iterable<SyncRecordAddress> addresses,
  ) async {
    final aliases = await store.aliasMap();
    final normalized = <SyncRecordAddress>{};
    for (final address in addresses) {
      normalized.add(aliases.resolve(address));
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
    final aliases = await store.aliasMap();
    final normalized = <SyncRecordAddress, SyncBaselineEntry>{};
    final sources = <SyncRecordAddress, SyncRecordAddress>{};
    for (final entry in baseline.entries) {
      final address = aliases.resolve(entry.key);
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
    final aliases = await store.aliasMap();
    final normalized = <SyncRecordAddress, SyncMergeCandidate?>{};
    final sources = <SyncRecordAddress, SyncRecordAddress>{};
    for (final entry in candidates.entries) {
      final address = aliases.resolve(entry.key);
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
    final aliases = await store.aliasMap();
    final normalized = <SyncRecordAddress, String>{};
    final sources = <SyncRecordAddress, SyncRecordAddress>{};
    for (final kindEntry in manifest.records.entries) {
      for (final entry in kindEntry.value.entries) {
        final source = (kind: kindEntry.key, recordId: entry.key);
        final address = aliases.resolve(source);
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
    final aliases = await store.aliasMap();
    final resolved = <SyncRecordAddress, SyncRecordAddress>{};
    for (final reference in references) {
      final address = aliases.resolve(reference);
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

  /// Judges, per peer, whether the records this device publishes are reaching
  /// it, and summarises each peer for the *Other devices* list (spec §6.9).
  ///
  /// Called once per pass that reaches publication, with the manifests the
  /// pass already fetched — so it costs no request. That is after this
  /// device's manifest `PUT` has succeeded, or on a pass with nothing new to
  /// share, after the `PUT` was skipped because the store already holds that
  /// manifest (spec §6.3 step 8). Either way, "published" below means named by
  /// the manifest the store holds.
  ///
  /// A peer missing one of this device's hashes is in one of two states, and
  /// only one of them is worth the user's attention:
  ///
  /// * **asleep** — it has not published since this device published the
  ///   record. Its app is simply not running, which is the common case and not
  ///   a fault. Never reported; the device list shows the record as waiting.
  /// * **refusing** — it has published at least twice since, with distinct
  ///   `writtenAt` values, and still does not carry the hash. Twice, not once:
  ///   a pass that was already running when this device published can finish
  ///   afterwards without having read its manifest, but the pass after it
  ///   cannot. Reported per record and peer, naming the peer.
  ///
  /// "Since" is judged by the order this device *saw* things, never by
  /// comparing its clock with the peer's: a `writtenAt` counts only when it
  /// was first seen on a later pass than the one that published the record.
  /// Comparing timestamps would go blind in exactly the case §6.9 introduced
  /// this signal for — a device whose own clock runs fast, whose records its
  /// peers refuse as future-dated, and whose publication time is therefore
  /// later than any `writtenAt` a peer will write. The cost of ordering alone
  /// is one narrow false positive: a peer that completes two whole passes
  /// while this device is between its manifest reads and its `PUT`. That
  /// reads as refusing until this device's next pass, which clears it.
  ///
  /// A peer that holds a version of the record **no older** than this
  /// device's — content at least as new, or a strictly newer existence
  /// transition — is never judged refusing, whatever its hash: that is a
  /// disagreement, not a refusal. Either this device is about to adopt the
  /// peer's version, or the two are tied or one side's copy was skipped, and
  /// each of those has a notice of its own with the right remedy — "it may
  /// need an app update" would be the wrong one. Nor is one whose copy this
  /// pass could not read: what is wrong there is already reported as skipped.
  ///
  /// Zero observed peers is not evidence (§6.9): with none, nothing is judged
  /// and no peer can be refusing.
  List<SyncPeerSummary> _recordUnreflectedPublications(
    Map<SyncRecordAddress, String> publishableHashes, {
    required Map<String, SyncMergeCandidate> ownCandidates,
    required List<({String peerId, SyncManifest manifest})> peerManifests,
    required List<Map<SyncRecordAddress, String>> peerManifestHashes,
    required List<Map<SyncRecordAddress, SyncMergeCandidate?>> peerCandidates,
    required Iterable<String> storeDevices,
    required SyncReportSink reports,
  }) {
    final cache = _peerManifestCache;
    final pass = ++cache.passSequence;
    final listed = storeDevices.toSet();
    cache.peerPublications.removeWhere((peerId, _) => !listed.contains(peerId));
    cache.publications.removeWhere(
      (address, _) => !publishableHashes.containsKey(address),
    );

    final summaries = <SyncPeerSummary>[];
    for (final (index, peer) in peerManifests.indexed) {
      final writtenAt = peer.manifest.writtenAt;
      final seen = cache.peerPublications.putIfAbsent(peer.peerId, () => []);
      if (seen.isEmpty || seen.last.writtenAt != writtenAt) {
        seen.add((writtenAt: writtenAt, pass: pass));
        if (seen.length > SyncPeerManifestCache.peerPublicationsKept) {
          seen.removeAt(0);
        }
      }
      final hashes = peerManifestHashes[index];
      var waiting = 0;
      for (final entry in publishableHashes.entries) {
        if (hashes[entry.key] == entry.value) continue;
        waiting++;
        final published = cache.publications[entry.key];
        if (published == null || published.hash != entry.value) continue;
        if (hashes.containsKey(entry.key)) {
          final theirs = peerCandidates[index][entry.key];
          final ours = ownCandidates[entry.value];
          if (theirs == null || ours == null) continue;
          // Newer content, or a strictly newer existence transition. Not an
          // equal `existenceAt`: an ordinary edit leaves it where it was, so
          // a peer still holding the previous content shares it.
          if (!theirs.updatedAt.isBefore(ours.updatedAt) ||
              theirs.existenceAt.isAfter(ours.existenceAt)) {
            continue;
          }
        }
        final since = seen.where(
          (publication) => publication.pass > published.pass,
        );
        if (since.length < 2) continue;
        reports.add(
          SyncReport(
            code: SyncReportCode.unreflectedPublication,
            kind: entry.key.kind,
            recordId: entry.key.recordId,
            peerId: peer.peerId,
            message:
                'A peer that published twice since this record was published ' // i18n-ignore: internal status
                'does not carry its hash.', // i18n-ignore: internal status
          ),
        );
      }
      summaries.add(
        SyncPeerSummary(
          peerId: peer.peerId,
          writtenAt: writtenAt,
          waitingCount: waiting,
        ),
      );
    }

    // Recorded after judging, so a hash first published on this pass cannot
    // count this pass's peer manifests — all fetched before the `PUT` — as
    // evidence about itself.
    for (final entry in publishableHashes.entries) {
      final existing = cache.publications[entry.key];
      if (existing != null && existing.hash == entry.value) continue;
      cache.publications[entry.key] = (hash: entry.value, pass: pass);
    }
    return List.unmodifiable(summaries);
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
      // A `409` is not a failure here: per §5.2 it means only that a store
      // already exists for this `id_key`, and the sole way that can be true is
      // that another holder of *this device's own phrase* recreated it first —
      // or that this device's own `201` was lost to a timeout. Either way the
      // store the user asked for is there, so adopt it and continue into the
      // ordinary fresh attach with no second `POST` and no re-prompt; the
      // stale-epoch path already joins such a store without asking. Treating
      // it as a failure left the decision pending and re-POSTed into the same
      // conflict on every confirm, forever. Any other non-2xx still fails.
      if (!created.isSuccess && created.kind != SyncResponseKind.conflict) {
        return SyncPassResult(
          SyncPassStatus.failed,
          message:
              'store creation returned ${created.statusCode}', // i18n-ignore: internal status
          failure: SyncFailure.fromResponse(
            created,
            SyncFailureStep.createStore,
          ),
        );
      }
      _replacementCreated = true;
      attached = await transport.getStore(previouslyUsed: false);
      if (attached.missingKind != null || !attached.response.isSuccess) {
        return SyncPassResult(
          SyncPassStatus.failed,
          message:
              'fresh attach did not produce a store', // i18n-ignore: internal status
          failure: attached.response.isSuccess
              ? const SyncFailure(
                  SyncFailureCause.unexpectedResponse,
                  step: SyncFailureStep.createStore,
                )
              : SyncFailure.fromResponse(
                  attached.response,
                  SyncFailureStep.createStore,
                ),
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

  /// Downloads [manifest]'s records of [kind] into [into].
  ///
  /// Once [progress] has stopped — a request answered `429` or `5xx`, or
  /// failed on the network (spec §6.3 step 5) — no further request is made in
  /// the pass: each record still to fetch joins [unresolved] *without* a
  /// report, so the merge skips it and the baseline does not advance for it,
  /// exactly as for a blob that could not be resolved, but nothing tells the
  /// user it was skipped, because it was not. A record whose hash this pass or
  /// session already holds needs no request and is still taken.
  Future<void> _downloadPeerRecords(
    SyncManifest manifest, {
    required SyncRecordKind kind,
    required Map<SyncRecordAddress, SyncMergeCandidate?> into,
    required String peerId,
    required SyncReportSink reports,
    required Set<SyncRecordAddress> unresolved,
    required Map<String, SyncMergeCandidate> candidateByHash,
    required Set<SyncRecordAddress> rejectedAddresses,
    required _PeerDownloadProgress progress,
  }) async {
    final records = manifest.records[kind];
    if (records == null) return;
    for (final recordEntry in records.entries) {
      final address = (kind: kind, recordId: recordEntry.key);
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
        if (admitted != null) into[address] = admitted;
        continue;
      }
      final List<int> body;
      switch (await _fetchPeerBlob(recordEntry.value, progress)) {
        case _BlobNotFetched():
          unresolved.add(address);
          progress.notFetched.add(address);
          continue;
        case _BlobRefused(:final statusCode):
          unresolved.add(address);
          reports.add(
            SyncReport(
              code: SyncReportCode.unresolvedBlob,
              kind: address.kind,
              recordId: address.recordId,
              peerId: peerId,
              httpStatus: statusCode,
              message:
                  'Blob returned $statusCode.', // i18n-ignore: internal report
            ),
          );
          continue;
        case _BlobBody(body: final fetched, downloaded: false):
          body = fetched;
        case _BlobBody(body: final fetched, downloaded: true):
          if (sha256Hex(fetched) != recordEntry.value) {
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
          _peerManifestCache.rememberFetchedBlob(recordEntry.value, fetched);
          progress.fetched++;
          body = fetched;
      }
      final (:blob, :failure) = _decodeBlob(body);
      if (blob == null) {
        unresolved.add(address);
        reports.add(
          SyncReport(
            // Never null without a blob: [_decodeBlob] pairs them.
            code: failure!,
            kind: address.kind,
            recordId: address.recordId,
            peerId: peerId,
            message: switch (failure) {
              SyncReportCode.newerWireVersion =>
                'Blob uses a newer wire version.', // i18n-ignore: internal report
              SyncReportCode.newerRecordFields =>
                'Blob carries a field this build cannot keep.', // i18n-ignore: internal report
              SyncReportCode.newerFigures =>
                'Blob carries figures from a newer version.', // i18n-ignore: internal report
              _ =>
                'Blob did not decode as a record.', // i18n-ignore: internal report
            },
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
      into[address] = admitted;
    }
  }

  /// Holds back every fetched record that cites, directly or through other
  /// fetched records, one in [notFetched], so it waits with them instead of
  /// being applied without them (spec §6.3 step 5).
  ///
  /// Kind order puts every *other* kind a record cites ahead of it, but a
  /// dance can link to another dance, and those links can form cycles, so no
  /// order fetches every citation first. Applied alone, a dance whose linked
  /// dance was not fetched yet is refused as citing unavailable data and
  /// reported as skipped, which is the notice the stop exists to avoid. Held
  /// back, it joins [unresolved] without a report; its blob is already in the
  /// session cache, so the next pass takes it with no request.
  ///
  /// Conservative: a citation the device can already satisfy locally holds
  /// the record back all the same. That costs one pass's delay, never a
  /// request, and needs no read of local state here.
  static void _deferCitersOfUnfetched(
    List<Map<SyncRecordAddress, SyncMergeCandidate?>> downloadedByPeer, {
    required Set<SyncRecordAddress> notFetched,
    required Set<SyncRecordAddress> unresolved,
  }) {
    if (notFetched.isEmpty) return;
    final waiting = {...notFetched};
    for (var changed = true; changed;) {
      changed = false;
      for (final downloaded in downloadedByPeer) {
        for (final entry in downloaded.entries) {
          final candidate = entry.value;
          if (candidate == null || waiting.contains(entry.key)) continue;
          if (syncRecordReferences(candidate).any(waiting.contains)) {
            waiting.add(entry.key);
            changed = true;
          }
        }
      }
    }
    for (final downloaded in downloadedByPeer) {
      downloaded.removeWhere((address, _) => waiting.contains(address));
    }
    unresolved.addAll(waiting);
  }

  /// The blob for [hash]: from the session cache, from a batch already
  /// fetched, or from the network (spec §6.3 step 5).
  ///
  /// A network fetch asks for a batch starting at [hash] and running on
  /// through the hashes the records after it will need, so a large download
  /// takes one request per [syncBlobBatchMaxHashes] records rather than one
  /// per record. Against a server without the batch route it fetches [hash]
  /// alone, and so does every later fetch this session.
  Future<_BlobOutcome> _fetchPeerBlob(
    String hash,
    _PeerDownloadProgress progress,
  ) async {
    final cached = _peerManifestCache.fetchedBlob(hash);
    if (cached != null) return _BlobBody(cached, downloaded: false);
    final batched = _takeBatched(hash, progress);
    if (batched != null) return batched;
    if (progress.stop != null) return const _BlobNotFetched();
    if (!_peerManifestCache.blobBatchUnsupported) {
      await _fetchBatch(hash, progress);
      final answered = _takeBatched(hash, progress);
      if (answered != null) return answered;
      if (progress.stop != null) return const _BlobNotFetched();
      // Otherwise the batch fell back (`_fetchBatch`), or — against a
      // non-conforming server — did not answer the hash it was asked for
      // first. Either way the single request below still can.
    }
    return _getBlob(hash, progress);
  }

  /// Takes [hash]'s answer from a batch already fetched, if it has one.
  _BlobOutcome? _takeBatched(String hash, _PeerDownloadProgress progress) {
    final outcome = progress.batched[hash];
    if (outcome is _BlobBody) progress.batched.remove(hash);
    return outcome;
  }

  /// One `POST /v1/blobs/batch` for [hash] and the hashes after it, its answers
  /// left in [_PeerDownloadProgress.batched].
  ///
  /// Every blob a response delivers is kept, even when the response is then
  /// cut off: it arrived whole, and it is verified like any other when its
  /// record is reached. A `429`, a `5xx` other than `507` or a network failure
  /// stops downloads exactly as on a single request. Any other refusal, a
  /// `200` that is not a batch, or a batch that is malformed or over its caps,
  /// is a server — or a proxy in front of it — that does not serve the route:
  /// the session falls back to single requests and nothing is reported, so
  /// each record gets whatever answer its own request gets. Copying a
  /// refusal of the whole batch onto each of its records instead would report
  /// up to 200 records skipped for a proxy's `413` that a single request
  /// never meets.
  Future<void> _fetchBatch(String hash, _PeerDownloadProgress progress) async {
    final hashes = progress.batchFrom(
      hash,
      limit: syncBlobBatchMaxHashes,
      answered: (candidate) =>
          progress.batched.containsKey(candidate) ||
          _peerManifestCache.hasFetchedBlob(candidate),
    );
    final SyncHttpResponse response;
    try {
      response = await transport.postBlobBatch(
        hashes,
        onFrame: (frame) {
          switch (frame.status) {
            case SyncBlobBatchFrameStatus.blob:
              progress.batched[frame.hash] = _BlobBody(
                frame.body!,
                downloaded: true,
              );
            case SyncBlobBatchFrameStatus.missing:
              progress.batched[frame.hash] = const _BlobRefused(404);
            case SyncBlobBatchFrameStatus.notSent:
              // Asked for again by the batch its record starts.
              break;
          }
        },
      );
    } on SyncEndpointException catch (error, stack) {
      // A malformed or oversized batch. Thrown, as on a single request, it
      // would fail every pass the same way; the frames before it are kept.
      logCaughtErrorTypeOnly(
        error,
        stack,
        source: 'sync_coordinator._fetchBatch',
      );
      _peerManifestCache.blobBatchUnsupported = true;
      return;
    } on Object catch (error, stack) {
      final cause = syncFailureCauseForError(error);
      if (!cause.isTransient) rethrow;
      logCaughtErrorTypeOnly(
        error,
        stack,
        source: 'sync_coordinator._fetchBatch',
      );
      progress.stop = SyncFailure(cause, step: SyncFailureStep.download);
      return;
    }
    if (response.isSuccess) return;
    // `501 Not Implemented` is a server saying it has no such route, not one
    // in trouble.
    if (_stopsDownloads(response.kind) && response.statusCode != 501) {
      progress.stop = SyncFailure.fromResponse(
        response,
        SyncFailureStep.download,
      );
      return;
    }
    _peerManifestCache.blobBatchUnsupported = true;
  }

  /// One `GET /v1/blobs/{hash}`.
  Future<_BlobOutcome> _getBlob(
    String hash,
    _PeerDownloadProgress progress,
  ) async {
    final SyncHttpResponse response;
    try {
      response = await transport.getBlob(hash);
    } on Object catch (error, stack) {
      // A dropped connection or a timed-out request says nothing about the
      // record, so it is not fetched yet rather than skipped. Only what
      // `SyncController` would retry by itself is caught: anything else
      // still fails the pass as it did.
      final cause = syncFailureCauseForError(error);
      if (!cause.isTransient) rethrow;
      // Logged as the throw it replaces was (`_watch`), type only: the text
      // of a transport error can carry the request URI.
      logCaughtErrorTypeOnly(error, stack, source: 'sync_coordinator._getBlob');
      progress.stop = SyncFailure(cause, step: SyncFailureStep.download);
      return const _BlobNotFetched();
    }
    if (response.isSuccess) return _BlobBody(response.body, downloaded: true);
    if (_stopsDownloads(response.kind)) {
      progress.stop = SyncFailure.fromResponse(
        response,
        SyncFailureStep.download,
      );
      return const _BlobNotFetched();
    }
    return _BlobRefused(response.statusCode);
  }

  /// Whether a record download answered [kind] stops the pass's downloads
  /// rather than skipping that one record (spec §6.3 step 5).
  ///
  /// `429` and `5xx` other than `507` are about the server, not the record:
  /// every request after a `429` fails the same way until the limit refills,
  /// and a server in trouble is not helped by hundreds more. A `507` is read as
  /// [SyncResponseKind.quotaExhausted], not a server error, and is left as the
  /// per-record report it was: a blob read cannot exhaust a quota. A `404` is about the record — its
  /// blob is gone (§7.3) — and stays a skip and a report, as does a body whose
  /// hash does not match.
  static bool _stopsDownloads(SyncResponseKind kind) =>
      kind == SyncResponseKind.rateLimited ||
      kind == SyncResponseKind.serverError;

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

  /// Uploads whichever of [localByHash] the store is missing (spec §6.3 step
  /// 7), and learns which of [fallbackHashes] it has lost.
  ///
  /// Hashes in [knownPresent] are not asked about: the store holds every blob
  /// this device's published manifest names, for as long as it names them
  /// (§7.3).
  Future<_MissingBlobUploadResult> _uploadMissingLocalBlobs(
    Map<String, SyncMergeCandidate> localByHash, {
    Set<String> fallbackHashes = const {},
    Set<String> knownPresent = const {},
    required SyncReportSink reports,
  }) async {
    final requestedHashes = {
      ...localByHash.keys,
      ...fallbackHashes,
    }.where((hash) => !knownPresent.contains(hash)).toList(growable: false);
    final unavailableFallbackHashes = <String>{};
    // Every blob the store accepted stays accepted, so the next pass's
    // `missing` list no longer names it: an upload that stops part-way has
    // still moved on, and says so (`SyncFailure.progressed`, spec §6.12).
    var uploadedCount = 0;
    // A dropped connection or a timed-out request fails the pass as the
    // transient failure it already was, but as a result rather than a throw,
    // so it can say which step stopped and how far the uploads got — as for a
    // record download (`_downloadPeerRecords`). Anything else still throws.
    _MissingBlobUploadResult transientFailure(Object error, StackTrace stack) {
      final cause = syncFailureCauseForError(error);
      if (!cause.isTransient) Error.throwWithStackTrace(error, stack);
      return _MissingBlobUploadResult.failed(
        SyncFailure(
          cause,
          step: SyncFailureStep.upload,
          progressed: uploadedCount > 0,
        ),
      );
    }

    for (
      var offset = 0;
      offset < requestedHashes.length;
      offset += _maxMissingHashesPerRequest
    ) {
      final end = (offset + _maxMissingHashesPerRequest).clamp(
        0,
        requestedHashes.length,
      );
      final SyncHttpResponse response;
      try {
        response = await transport.postMissing(
          requestedHashes.sublist(offset, end),
        );
      } on Object catch (error, stack) {
        final failed = transientFailure(error, stack);
        logCaughtErrorTypeOnly(
          error,
          stack,
          source: 'sync_coordinator._uploadMissingLocalBlobs',
        );
        return failed;
      }
      if (!response.isSuccess) {
        return _MissingBlobUploadResult.failed(
          SyncFailure.fromResponse(
            response,
            SyncFailureStep.upload,
          ).withProgress(uploadedCount > 0),
        );
      }
      final missing = _decodeMissing(response.body);
      if (missing == null) {
        return const _MissingBlobUploadResult.failed(
          SyncFailure(
            SyncFailureCause.unexpectedResponse,
            step: SyncFailureStep.upload,
          ),
        );
      }
      // Encoded only when its request is built, so a chunk of thousands of
      // records is never held in memory a second time as bytes.
      final uploads = <({String hash, SyncMergeCandidate candidate})>[];
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
          return const _MissingBlobUploadResult.failed(
            SyncFailure(
              SyncFailureCause.unexpectedResponse,
              step: SyncFailureStep.upload,
            ),
          );
        }
        uploads.add((hash: hash, candidate: candidate));
      }
      List<int> bodyAt(int index) =>
          encodeSyncRecordBlobUtf8(uploads[index].candidate.blob);
      final singles = <({String hash, SyncMergeCandidate candidate})>[];
      var index = 0;
      while (index < uploads.length) {
        if (_peerManifestCache.blobUploadBatchUnsupported) {
          singles.addAll(uploads.sublist(index));
          break;
        }
        // A blob over the size cap goes alone, so its `413` is the one a
        // single upload gets rather than a refusal of the whole batch.
        final first = bodyAt(index);
        if (first.length > syncMaxBlobResponseBytes) {
          singles.add(uploads[index++]);
          continue;
        }
        final batch = [(hash: uploads[index++].hash, body: first)];
        var bytes = first.length;
        while (index < uploads.length &&
            batch.length < syncBlobBatchMaxUploadBlobs) {
          // A blob that does not fit is encoded again for the next batch:
          // cheaper than holding it.
          final body = bodyAt(index);
          if (body.length > syncMaxBlobResponseBytes ||
              bytes + body.length > syncBlobBatchMaxBlobBytes) {
            break;
          }
          bytes += body.length;
          batch.add((hash: uploads[index++].hash, body: body));
        }
        final SyncHttpResponse response;
        try {
          response = await transport.putBlobBatch(batch);
        } on Object catch (error, stack) {
          final failed = transientFailure(error, stack);
          logCaughtErrorTypeOnly(
            error,
            stack,
            source: 'sync_coordinator._uploadMissingLocalBlobs',
          );
          return failed;
        }
        final statuses = response.isSuccess
            ? _decodeUploadStatuses(response.body, batch)
            : null;
        if (statuses == null) {
          // A `429`, or a `5xx` other than `507` and `501`, means what it
          // means on a single upload. Anything else — a refusal, or a `200`
          // that is not this route's answer — is a server or proxy that does
          // not serve the route: the rest of the session uploads singly.
          if (!response.isSuccess &&
              (response.kind == SyncResponseKind.rateLimited ||
                  (response.kind == SyncResponseKind.serverError &&
                      response.statusCode != 501))) {
            return _MissingBlobUploadResult.failed(
              SyncFailure.fromResponse(
                response,
                SyncFailureStep.upload,
              ).withProgress(uploadedCount > 0),
            );
          }
          _peerManifestCache.blobUploadBatchUnsupported = true;
          index -= batch.length;
          continue;
        }
        // Every blob the store accepted counts, even past one it refused: the
        // store keeps each on its own.
        SyncHttpResponse? refused;
        for (final status in statuses) {
          if (status == 200 || status == 201) {
            uploadedCount++;
          } else {
            refused ??= SyncHttpResponse(
              statusCode: status,
              kind: syncResponseKindForStatus(status),
              headers: const {},
              body: const [],
            );
          }
        }
        if (refused != null) {
          return _MissingBlobUploadResult.failed(
            SyncFailure.fromResponse(
              refused,
              SyncFailureStep.upload,
            ).withProgress(uploadedCount > 0),
          );
        }
      }
      for (final (:hash, :candidate) in singles) {
        final SyncHttpResponse uploaded;
        try {
          uploaded = await transport.putBlob(
            hash,
            encodeSyncRecordBlobUtf8(candidate.blob),
          );
        } on Object catch (error, stack) {
          final failed = transientFailure(error, stack);
          logCaughtErrorTypeOnly(
            error,
            stack,
            source: 'sync_coordinator._uploadMissingLocalBlobs',
          );
          return failed;
        }
        if (!uploaded.isSuccess) {
          return _MissingBlobUploadResult.failed(
            SyncFailure.fromResponse(
              uploaded,
              SyncFailureStep.upload,
            ).withProgress(uploadedCount > 0),
          );
        }
        uploadedCount++;
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

  /// The peer manifest in [body], or null with [newer] saying whether it
  /// failed only because a newer build wrote it.
  static ({SyncManifest? manifest, bool newer}) _decodeManifest(
    List<int> body,
  ) {
    try {
      return (
        manifest: decodeSyncManifest(utf8.decode(body, allowMalformed: false)),
        newer: false,
      );
    } on SyncNewerWireVersionException {
      // diagnostics: silent — reported by the caller as newerWireVersion.
      return (manifest: null, newer: true);
    } on FormatException {
      // diagnostics: silent — malformed peer manifests are reported by the
      // caller as per-record failures.
      return (manifest: null, newer: false);
    }
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
    }
    return null;
  }

  /// The peer blob in [body] with a null [failure], or a null blob with
  /// [failure] the code the caller reports: whether it failed only because a
  /// newer build wrote it — in a newer envelope, or with a part this build
  /// cannot keep — or is malformed.
  static ({SyncRecordBlob? blob, SyncReportCode? failure}) _decodeBlob(
    List<int> body,
  ) {
    try {
      return (
        blob: decodeSyncRecordBlob(utf8.decode(body, allowMalformed: false)),
        failure: null,
      );
    } on SyncNewerWireVersionException {
      // diagnostics: silent — reported by the caller as newerWireVersion.
      return (blob: null, failure: SyncReportCode.newerWireVersion);
    } on SyncNewerFieldException catch (error) {
      // diagnostics: silent — reported by the caller as newerFigures when a
      // newer build added something inside a dance's figures, which the
      // notice names; otherwise as newerRecordFields.
      return (
        blob: null,
        failure: error.path.startsWith('figures')
            ? SyncReportCode.newerFigures
            : SyncReportCode.newerRecordFields,
      );
    } on FormatException {
      // diagnostics: silent — malformed peer blobs are reported by the caller
      // and do not advance the baseline.
      return (blob: null, failure: SyncReportCode.malformedRecord);
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
        quota: SyncStoreQuota.tryParse(decoded['quota']),
      );
    } on FormatException {
      // diagnostics: silent — malformed store metadata is surfaced as a
      // failed pass.
      return null;
    }
  }

  /// The per-blob statuses of a `PUT /v1/blobs/batch` answer (spec §5.2), in
  /// the order of [batch], or null when [body] is not that answer: not JSON,
  /// not one result per blob, or not in order.
  static List<int>? _decodeUploadStatuses(
    List<int> body,
    List<({String hash, List<int> body})> batch,
  ) {
    try {
      final decoded = jsonDecode(utf8.decode(body, allowMalformed: false));
      if (decoded is! Map || decoded['results'] is! List) return null;
      final results = decoded['results'] as List;
      if (results.length != batch.length) return null;
      final statuses = <int>[];
      for (final (index, result) in results.indexed) {
        if (result is! Map ||
            result['hash'] != batch[index].hash ||
            result['status'] is! int) {
          return null;
        }
        statuses.add(result['status'] as int);
      }
      return statuses;
    } on FormatException {
      // diagnostics: silent — an answer that is not the route's falls back to
      // single uploads.
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
  const _StoreMetadata({
    required this.epoch,
    required this.devices,
    required this.quota,
  });

  final String epoch;
  final List<String> devices;
  final SyncStoreQuota? quota;
}
