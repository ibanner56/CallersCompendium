import '../storage/repositories/sync_local_repository.dart';
import '../imports/dedupe.dart';
import '../model/stored_timestamp.dart';
import 'canonical_json.dart';
import 'sync_codec.dart';
import 'sync_record_kind.dart';
import 'sync_report.dart';

/// A record candidate carrying the hashes needed by the baseline diff.
class SyncMergeCandidate {
  SyncMergeCandidate({required this.blob, String? wireHash, this.peerId})
    : wireHash = wireHash ?? sha256Hex(encodeSyncRecordBlobUtf8(blob));

  factory SyncMergeCandidate.fromBlob(SyncRecordBlob blob, {String? peerId}) =>
      SyncMergeCandidate(blob: blob, peerId: peerId);

  final SyncRecordBlob blob;
  final String wireHash;
  final String? peerId;

  SyncRecordAddress get address => (kind: blob.kind, recordId: blob.id);

  String get bodyHash => contentHash(blob.body);

  /// Hashes user content for quarantine repair agreement.
  ///
  /// Archive-shaped dance and program bodies repeat the envelope's timestamp
  /// fields. Those projections are ignored only for this comparison; the
  /// full body hash and wire hash retain their existing meanings.
  String get comparisonBodyHash {
    switch (blob.kind) {
      case SyncRecordKind.dance:
      case SyncRecordKind.program:
        final body = Map<String, Object?>.from(blob.body)
          ..remove('updatedAt')
          ..remove('deletedAt');
        return contentHash(body);
      case SyncRecordKind.choreographer:
      case SyncRecordKind.tag:
      case SyncRecordKind.publishedSource:
      case SyncRecordKind.customFieldDef:
      case SyncRecordKind.difficultyLevel:
      case SyncRecordKind.venue:
      case SyncRecordKind.setting:
        return bodyHash;
    }
  }

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

/// One deterministic live-dance merge discovered during a fresh attach.
///
/// The [winner] already contains the merged body under the lexicographically
/// smallest dance ID. [losingIds] are the identities that must be aliased,
/// rewired, and removed by the storage transaction.
class SyncDanceDedupeMerge {
  const SyncDanceDedupeMerge({required this.winner, required this.losingIds});

  final SyncMergeCandidate winner;
  final List<String> losingIds;
}

/// A title match whose choreography is not equal and therefore needs the
/// durable review surface rather than a silent merge.
class SyncDanceDedupeAmbiguity {
  const SyncDanceDedupeAmbiguity({required this.left, required this.right});

  final SyncMergeCandidate left;
  final SyncMergeCandidate right;

  String get firstId =>
      left.blob.id.compareTo(right.blob.id) <= 0 ? left.blob.id : right.blob.id;

  String get secondId =>
      left.blob.id.compareTo(right.blob.id) <= 0 ? right.blob.id : left.blob.id;

  /// The candidate stored in the canonical `(firstId, secondId)` queue row.
  SyncMergeCandidate get candidate => left.blob.id == secondId ? left : right;
}

/// The pure result of comparing all live dance candidates in a fresh union.
class SyncFreshAttachDedupePlan {
  const SyncFreshAttachDedupePlan({
    required this.merges,
    required this.ambiguities,
    required this.aliases,
  });

  final List<SyncDanceDedupeMerge> merges;
  final List<SyncDanceDedupeAmbiguity> ambiguities;
  final Map<String, String> aliases;
}

/// Merges live dance candidates after an explicit dedupe decision.
///
/// The caller may use this for a choreography ambiguity only after the user
/// chose Merge. Automatic fresh-attach planning calls the same helper only
/// for candidates whose choreography already matches.
SyncDanceDedupeMerge mergeDanceCandidates(
  Iterable<SyncMergeCandidate> candidates,
) {
  final group = candidates.toList(growable: false)
    ..sort((left, right) => left.blob.id.compareTo(right.blob.id));
  if (group.length < 2 ||
      group.any(
        (candidate) =>
            candidate.blob.kind != SyncRecordKind.dance || candidate.isDeleted,
      )) {
    throw ArgumentError(
      'dance merge requires at least two live dance candidates',
    );
  }
  final survivor = group.first;
  final latestUpdatedAt = group
      .map((candidate) => candidate.blob.updatedAt)
      .reduce((left, right) => left.isAfter(right) ? left : right);
  final merged = SyncMergeCandidate(
    blob: SyncRecordBlob(
      v: survivor.blob.v,
      kind: SyncRecordKind.dance,
      id: survivor.blob.id,
      updatedAt: latestUpdatedAt.add(storedTimestampTick),
      deletedAt: null,
      existenceAt: group
          .map((candidate) => candidate.blob.existenceAt)
          .reduce((left, right) => left.isAfter(right) ? left : right),
      body: _mergeDanceBodies(group, survivor.blob.id),
    ),
  );
  return SyncDanceDedupeMerge(
    winner: merged,
    losingIds: List.unmodifiable([
      for (final candidate in group.skip(1)) candidate.blob.id,
    ]),
  );
}

/// Finds live dance duplicates without touching storage.
///
/// Matching intentionally delegates title normalization to the shipped import
/// normalizer. Choreography comparison includes figure parameters and all
/// intrinsic fields, while collections and non-choreography scalars are
/// resolved only after a match is established.
SyncFreshAttachDedupePlan planFreshAttachDedupe(
  Iterable<SyncMergeCandidate> candidates,
) {
  final liveDances = [
    for (final candidate in candidates)
      if (candidate.blob.kind == SyncRecordKind.dance &&
          !candidate.isDeleted &&
          candidate.blob.body['title'] is String)
        candidate,
  ]..sort((left, right) => left.blob.id.compareTo(right.blob.id));

  final byTitle = <String, List<SyncMergeCandidate>>{};
  for (final candidate in liveDances) {
    final title = normalizeTitle(candidate.blob.body['title']! as String);
    if (title.isEmpty) continue;
    byTitle.putIfAbsent(title, () => []).add(candidate);
  }

  final choreographyGroups = <List<SyncMergeCandidate>>[];
  final ambiguities = <SyncDanceDedupeAmbiguity>[];
  for (final titleCandidates in byTitle.values) {
    final byChoreography = <String, List<SyncMergeCandidate>>{};
    for (final candidate in titleCandidates) {
      byChoreography
          .putIfAbsent(_syncChoreographyKey(candidate.blob.body), () => [])
          .add(candidate);
    }
    final groups = byChoreography.values.toList()
      ..forEach(
        (group) =>
            group.sort((left, right) => left.blob.id.compareTo(right.blob.id)),
      )
      ..sort(
        (left, right) => left.first.blob.id.compareTo(right.first.blob.id),
      );
    choreographyGroups.addAll(groups);
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        ambiguities.add(
          SyncDanceDedupeAmbiguity(
            left: groups[i].first,
            right: groups[j].first,
          ),
        );
      }
    }
  }

  final merges = <SyncDanceDedupeMerge>[];
  final aliases = <String, String>{};
  for (final group in choreographyGroups) {
    if (group.length < 2) continue;
    final merge = mergeDanceCandidates(group);
    for (final losingId in merge.losingIds) {
      aliases[losingId] = merge.winner.blob.id;
    }
    merges.add(merge);
  }

  ambiguities.sort((left, right) {
    final first = left.firstId.compareTo(right.firstId);
    return first == 0 ? left.secondId.compareTo(right.secondId) : first;
  });
  merges.sort((left, right) {
    final first = left.winner.blob.id.compareTo(right.winner.blob.id);
    return first == 0
        ? left.losingIds.first.compareTo(right.losingIds.first)
        : first;
  });
  return SyncFreshAttachDedupePlan(
    merges: List.unmodifiable(merges),
    ambiguities: List.unmodifiable(ambiguities),
    aliases: Map.unmodifiable(aliases),
  );
}

/// Finds the live dance pairs §6.10's fuzzy tier defers to `review_queue`.
///
/// The exact-title tier owns equal normalized titles — [planFreshAttachDedupe]
/// merges an equal-choreography group silently and queues a differing one as a
/// choreography ambiguity — so any pair whose titles are equal is skipped here
/// rather than queued twice under two reasons. Testing title equality directly,
/// instead of subtracting the ambiguity set, keeps that exclusion true even if
/// the ambiguity enumeration is ever changed.
///
/// [authorNamesByDanceId] supplies the author display **names**, which is what
/// [DedupeIndex] matches on; a sync body carries author ids only, so the caller
/// resolves them exactly as `ImportPipeline.buildDedupeIndex` does.
///
/// Every verdict is [DedupeIndex]'s own. The length banding below only decides
/// which pairs are *offered* to it, and offers a strict superset of the pairs
/// that could clear [threshold] — see [DedupeIndex.maxTitleLengthGap]. Without
/// it this is a full O(n²) Levenshtein sweep of the library, run inside the
/// fresh-attach transaction.
List<SyncDanceDedupeAmbiguity> planFreshAttachFuzzyDuplicates(
  Iterable<SyncMergeCandidate> candidates, {
  required Map<String, List<String>> authorNamesByDanceId,
  double threshold = DedupeIndex.defaultThreshold,
}) {
  final liveDances = [
    for (final candidate in candidates)
      if (candidate.blob.kind == SyncRecordKind.dance &&
          !candidate.isDeleted &&
          candidate.blob.body['title'] is String &&
          normalizeTitle(candidate.blob.body['title']! as String).isNotEmpty)
        candidate,
  ];
  if (liveDances.length < 2) return const [];

  final normalizedTitle = <String, String>{
    for (final candidate in liveDances)
      candidate.blob.id: normalizeTitle(
        candidate.blob.body['title']! as String,
      ),
  };
  // Sorted by title length so the eligible band is a contiguous window, then
  // by id so the sweep is deterministic across devices.
  liveDances.sort((left, right) {
    final byLength = normalizedTitle[left.blob.id]!.length.compareTo(
      normalizedTitle[right.blob.id]!.length,
    );
    return byLength != 0 ? byLength : left.blob.id.compareTo(right.blob.id);
  });

  final entries = [
    for (final candidate in liveDances)
      DedupeEntry(
        danceId: candidate.blob.id,
        title: candidate.blob.body['title']! as String,
        authorNames: authorNamesByDanceId[candidate.blob.id] ?? const [],
      ),
  ];
  final byId = {
    for (final candidate in liveDances) candidate.blob.id: candidate,
  };

  final pairs = <String, SyncDanceDedupeAmbiguity>{};
  for (var index = 0; index < liveDances.length - 1; index++) {
    final subject = liveDances[index];
    final subjectLength = normalizedTitle[subject.blob.id]!.length;
    // Only forward partners are offered. The band is symmetric, so every pair
    // is reached exactly once, from its shorter-titled side.
    var windowEnd = index + 1;
    while (windowEnd < liveDances.length) {
      final otherLength =
          normalizedTitle[liveDances[windowEnd].blob.id]!.length;
      // The partner is the longer side here, so the bound scales with it.
      if (otherLength - subjectLength >
          DedupeIndex.maxTitleLengthGap(otherLength, threshold: threshold)) {
        break;
      }
      windowEnd++;
    }
    if (windowEnd == index + 1) continue;
    // `entries` was built from the sorted `liveDances`, so the slices align.
    final window = DedupeIndex(entries.sublist(index + 1, windowEnd));
    for (final match in window.fuzzyMatches(
      subject.blob.body['title']! as String,
      authorNamesByDanceId[subject.blob.id] ?? const [],
      threshold: threshold,
    )) {
      final other = byId[match.danceId];
      if (other == null) continue;
      if (normalizedTitle[subject.blob.id] == normalizedTitle[other.blob.id]) {
        continue;
      }
      final ambiguity = SyncDanceDedupeAmbiguity(left: subject, right: other);
      pairs[canonicalJson([ambiguity.firstId, ambiguity.secondId])] = ambiguity;
    }
  }

  final result = pairs.values.toList()
    ..sort((left, right) {
      final first = left.firstId.compareTo(right.firstId);
      return first == 0 ? left.secondId.compareTo(right.secondId) : first;
    });
  return List.unmodifiable(result);
}

String _syncChoreographyKey(Map<String, Object?> body) =>
    contentHash(choreographyFingerprint(body));

Map<String, Object?> _mergeDanceBodies(
  List<SyncMergeCandidate> candidates,
  String survivorId,
) {
  final survivor = candidates.firstWhere(
    (candidate) => candidate.blob.id == survivorId,
  );
  final latest = _latestDanceCandidate(candidates, survivorId);
  final body = _copySyncBody(survivor.blob.body)..['id'] = survivorId;

  for (final key in const [
    'walkthrough',
    'rating',
    'status',
    'composedOn',
    'revisedOn',
  ]) {
    if (latest.blob.body.containsKey(key)) {
      body[key] = latest.blob.body[key];
    }
  }

  body['authorIds'] = _unionStrings(candidates, 'authorIds');
  body['tagIds'] = _unionStrings(candidates, 'tagIds');
  body['customFields'] = _unionObjects(
    candidates,
    'customFields',
    keyOf: (value) => value is Map && value['fieldId'] is String
        ? value['fieldId']! as String
        : canonicalJson(value),
  );
  body['links'] = _unionObjects(
    candidates,
    'links',
    keyOf: (value) => value is Map && value['id'] is String
        ? value['id']! as String
        : canonicalJson(value),
  );
  body['sourceCitations'] = _unionObjects(
    candidates,
    'sourceCitations',
    keyOf: (value) => value is Map && value['sourceId'] is String
        ? value['sourceId']! as String
        : canonicalJson(value),
  );
  return body;
}

SyncMergeCandidate _latestDanceCandidate(
  List<SyncMergeCandidate> candidates,
  String survivorId,
) {
  var latest = candidates.first;
  for (final candidate in candidates.skip(1)) {
    final comparison = candidate.blob.updatedAt.compareTo(
      latest.blob.updatedAt,
    );
    if (comparison > 0 ||
        (comparison == 0 &&
            candidate.blob.id == survivorId &&
            latest.blob.id != survivorId)) {
      latest = candidate;
    }
  }
  return latest;
}

List<String> _unionStrings(List<SyncMergeCandidate> candidates, String key) {
  final result = <String>[];
  final seen = <String>{};
  for (final candidate in candidates) {
    final values = candidate.blob.body[key];
    if (values is! List) continue;
    for (final value in values) {
      if (value is String && seen.add(value)) result.add(value);
    }
  }
  return result;
}

List<Object?> _unionObjects(
  List<SyncMergeCandidate> candidates,
  String field, {
  required String Function(Object?) keyOf,
}) {
  final values = <String, ({Object? value, SyncMergeCandidate source})>{};
  for (final candidate in candidates) {
    final raw = candidate.blob.body[field];
    if (raw is! List) continue;
    for (final value in raw) {
      final valueKey = keyOf(value);
      final previous = values[valueKey];
      if (previous == null ||
          _prefersDanceCandidate(
            candidate,
            previous.source,
            candidates.first,
          )) {
        values[valueKey] = (value: value, source: candidate);
      }
    }
  }
  return [for (final entry in values.entries) entry.value.value];
}

bool _prefersDanceCandidate(
  SyncMergeCandidate candidate,
  SyncMergeCandidate other,
  SyncMergeCandidate survivor,
) {
  final comparison = candidate.blob.updatedAt.compareTo(other.blob.updatedAt);
  if (comparison != 0) return comparison > 0;
  if (candidate.blob.id == survivor.blob.id) return true;
  return other.blob.id != survivor.blob.id &&
      candidate.blob.id.compareTo(other.blob.id) < 0;
}

Map<String, Object?> _copySyncBody(Map<String, Object?> body) {
  Object? copy(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: copy(entry.value),
      };
    }
    if (value is List) return [for (final item in value) copy(item)];
    return value;
  }

  return copy(body) as Map<String, Object?>;
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
      if (unresolved.contains(address)) continue;
      final baselineEntry = baseline[address];
      final localCandidate = local[address];
      final remoteCandidates = [for (final peer in peerMaps) ?peer[address]];

      if (baselineEntry != null &&
          localCandidate == null &&
          remoteCandidates.isEmpty) {
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
          baselineEntry: baselineEntry,
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
        baselineEntry: baselineEntry,
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
    required SyncBaselineEntry? baselineEntry,
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
        baselineEntry == null &&
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

    var contentCandidates = candidates
        .where((candidate) => candidate.isDeleted == deletedWins)
        .toList(growable: false);
    if (baselineEntry != null && local != null) {
      final localIsInWinningState = contentCandidates.contains(local);
      final changedRemotes = contentCandidates
          .where((candidate) => candidate.wireHash != baselineEntry.wireHash)
          .toList(growable: false);
      if (localIsInWinningState &&
          (local.wireHash != baselineEntry.wireHash ||
              changedRemotes.isNotEmpty)) {
        // Baseline classification determines which bodies enter the LWW
        // comparison: an unchanged peer must not erase a local-only edit.
        contentCandidates = [local, ...changedRemotes];
      }
    }
    final maximumUpdated = contentCandidates
        .map((candidate) => candidate.updatedAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    final updatedWinners = contentCandidates
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
      peerId: contentWinner.peerId,
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
