import '../storage/repositories/sync_local_repository.dart';
import 'canonical_json.dart';
import 'sync_codec.dart';
import 'sync_report.dart';

/// A record candidate carrying the hashes needed by the baseline diff.
class SyncMergeCandidate {
  SyncMergeCandidate({required this.blob, String? wireHash})
    : wireHash = wireHash ?? sha256Hex(encodeSyncRecordBlobUtf8(blob));

  factory SyncMergeCandidate.fromBlob(SyncRecordBlob blob) =>
      SyncMergeCandidate(blob: blob);

  final SyncRecordBlob blob;
  final String wireHash;

  SyncRecordAddress get address => (kind: blob.kind, recordId: blob.id);

  String get bodyHash => contentHash(blob.body);

  bool get isDeleted => blob.deletedAt != null;

  DateTime get updatedAt => blob.updatedAt;

  DateTime get existenceAt => blob.existenceAt;
}

/// The action required for one address after comparing all available copies.
enum SyncMergeAction { none, upload, download, report, dropBaseline }

/// One result of the total baseline merge table.
class SyncMergeDecision {
  const SyncMergeDecision({
    required this.address,
    required this.action,
    this.winner,
    this.report,
  });

  final SyncRecordAddress address;
  final SyncMergeAction action;
  final SyncMergeCandidate? winner;
  final SyncReport? report;

  bool get changesLocalState =>
      action == SyncMergeAction.download ||
      action == SyncMergeAction.dropBaseline;
}

/// The complete result of one pure merge calculation.
class SyncMergePlan {
  const SyncMergePlan({required this.decisions, required this.reports});

  final List<SyncMergeDecision> decisions;
  final List<SyncReport> reports;

  Iterable<SyncMergeDecision> get uploads =>
      decisions.where((decision) => decision.action == SyncMergeAction.upload);

  Iterable<SyncMergeDecision> get downloads => decisions.where(
    (decision) => decision.action == SyncMergeAction.download,
  );
}

/// Pure implementation of the steady-state baseline table.
class SyncMergeEngine {
  const SyncMergeEngine();

  /// Calculates actions for every address named by local state, the baseline,
  /// or any peer. A missing peer entry is absence from that manifest, not a
  /// deletion.
  SyncMergePlan plan({
    required Map<SyncRecordAddress, SyncMergeCandidate?> local,
    required Map<SyncRecordAddress, SyncBaselineEntry> baseline,
    required Iterable<Map<SyncRecordAddress, SyncMergeCandidate?>> peers,
    bool freshAttach = false,
    Set<SyncRecordAddress> unresolved = const {},
  }) {
    final peerMaps = peers.toList(growable: false);
    final addresses = <SyncRecordAddress>{
      ...local.keys,
      ...baseline.keys.map(
        (entry) => (kind: entry.kind, recordId: entry.recordId),
      ),
      for (final peer in peerMaps) ...peer.keys,
    }.toList()..sort(_compareAddress);

    final decisions = <SyncMergeDecision>[];
    final reports = <SyncReport>[];
    for (final address in addresses) {
      final baselineEntry = baseline[address];
      final localCandidate = local[address];
      final remoteCandidates = [for (final peer in peerMaps) ?peer[address]];

      if (baselineEntry != null &&
          localCandidate == null &&
          remoteCandidates.isEmpty) {
        if (unresolved.contains(address)) continue;
        decisions.add(
          SyncMergeDecision(
            address: address,
            action: SyncMergeAction.dropBaseline,
          ),
        );
        continue;
      }

      if (localCandidate == null && remoteCandidates.isEmpty) continue;

      if (localCandidate != null && remoteCandidates.isEmpty) {
        final changed =
            baselineEntry == null ||
            localCandidate.wireHash != baselineEntry.wireHash;
        if (changed) {
          decisions.add(
            SyncMergeDecision(
              address: address,
              action: SyncMergeAction.upload,
              winner: localCandidate,
            ),
          );
        }
        continue;
      }

      if (localCandidate == null) {
        final resolution = _resolve(
          local: null,
          remotes: remoteCandidates,
          baselinePresent: baselineEntry != null,
          freshAttach: freshAttach,
        );
        if (resolution.report != null) {
          reports.add(resolution.report!);
          decisions.add(
            SyncMergeDecision(
              address: address,
              action: SyncMergeAction.report,
              report: resolution.report,
            ),
          );
        } else {
          decisions.add(
            SyncMergeDecision(
              address: address,
              action: SyncMergeAction.download,
              winner: resolution.winner,
            ),
          );
        }
        continue;
      }

      final resolution = _resolve(
        local: localCandidate,
        remotes: remoteCandidates,
        baselinePresent: baselineEntry != null,
        freshAttach: freshAttach,
      );
      if (resolution.report != null) {
        reports.add(resolution.report!);
        decisions.add(
          SyncMergeDecision(
            address: address,
            action: SyncMergeAction.report,
            report: resolution.report,
          ),
        );
        continue;
      }

      final winner = resolution.winner!;
      if (winner.wireHash == localCandidate.wireHash) {
        final hasDifferentRemote = remoteCandidates.any(
          (candidate) => candidate.wireHash != localCandidate.wireHash,
        );
        decisions.add(
          SyncMergeDecision(
            address: address,
            action: hasDifferentRemote
                ? SyncMergeAction.upload
                : SyncMergeAction.none,
            winner: winner,
          ),
        );
      } else {
        decisions.add(
          SyncMergeDecision(
            address: address,
            action: SyncMergeAction.download,
            winner: winner,
          ),
        );
      }
    }

    return SyncMergePlan(
      decisions: List.unmodifiable(decisions),
      reports: List.unmodifiable(reports),
    );
  }

  _Resolution _resolve({
    required SyncMergeCandidate? local,
    required List<SyncMergeCandidate> remotes,
    required bool baselinePresent,
    required bool freshAttach,
  }) {
    final candidates = [?local, ...remotes];
    final maximumExistence = candidates
        .map((candidate) => candidate.existenceAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    final existenceWinners = candidates
        .where((candidate) => candidate.existenceAt == maximumExistence)
        .toList(growable: false);
    final deletedWins = existenceWinners.any(
      (candidate) => candidate.isDeleted,
    );

    if (!freshAttach &&
        !baselinePresent &&
        local != null &&
        !local.isDeleted &&
        deletedWins &&
        maximumExistence.isAfter(local.existenceAt)) {
      return _Resolution.report(
        SyncReport(
          code: SyncReportCode.unseenLocalCreation,
          kind: local.blob.kind,
          recordId: local.blob.id,
          message:
              'A locally-created record would be resolved out of existence '
              'before any peer observed it.',
        ),
      );
    }

    final maximumUpdated = candidates
        .map((candidate) => candidate.updatedAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    final updatedWinners = candidates
        .where((candidate) => candidate.updatedAt == maximumUpdated)
        .toList(growable: false);
    final hashes = updatedWinners
        .map((candidate) => candidate.bodyHash)
        .toSet();
    if (hashes.length > 1) {
      final first = updatedWinners.first;
      return _Resolution.report(
        SyncReport(
          code: SyncReportCode.equalUpdatedAt,
          kind: first.blob.kind,
          recordId: first.blob.id,
          message:
              'Different record bodies have the same updatedAt; no winner '
              'was selected.',
        ),
      );
    }

    // Prefer local only when it has the same content. This keeps the result
    // deterministic without inventing a tie-break for differing bodies.
    final contentWinner = updatedWinners.firstWhere(
      (candidate) => identical(candidate, local),
      orElse: () => updatedWinners.first,
    );
    final existenceWinner = existenceWinners.firstWhere(
      (candidate) => candidate.isDeleted,
      orElse: () => existenceWinners.first,
    );
    final winner = SyncMergeCandidate.fromBlob(
      SyncRecordBlob(
        v: contentWinner.blob.v,
        kind: contentWinner.blob.kind,
        id: contentWinner.blob.id,
        updatedAt: contentWinner.updatedAt,
        deletedAt: existenceWinner.blob.deletedAt,
        existenceAt: existenceWinner.existenceAt,
        body: contentWinner.blob.body,
      ),
    );
    return _Resolution.winner(winner);
  }

  static int _compareAddress(SyncRecordAddress left, SyncRecordAddress right) {
    final kind = left.kind.index.compareTo(right.kind.index);
    return kind == 0 ? left.recordId.compareTo(right.recordId) : kind;
  }
}

class _Resolution {
  const _Resolution._({this.winner, this.report});

  const _Resolution.winner(SyncMergeCandidate candidate)
    : this._(winner: candidate);

  const _Resolution.report(SyncReport report) : this._(report: report);

  final SyncMergeCandidate? winner;
  final SyncReport? report;
}
