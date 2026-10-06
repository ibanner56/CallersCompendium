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
///
/// [review] leaves both sides untouched and hands the user the choice
/// (sync-spec §6.3): differing bodies at an equal `updatedAt`, which no
/// convergent rule may decide on the user's behalf, and a changed/changed
/// conflict on a whole-collection setting, where last-writer-wins would discard
/// one device's entire set.
enum SyncMergeAction { none, upload, download, report, review, dropBaseline }

/// The settings keys whose single value is a whole user-built collection.
///
/// A changed/changed conflict on one of these is routed to review instead of
/// resolved by last-writer-wins, because the losing side is not one edit but
/// every dialect, theme, shorthand or snippet that device holds (ADR-004,
/// *Consequences*). The app declares the same keys beside the controllers that
/// own them; `app/test/sync/sync_whole_collection_keys_test.dart` holds the
/// two together.
const Set<String> syncWholeCollectionSettingKeys = {
  'custom_dialects',
  'custom_themes',
  'shorthand_mappings',
  'walkthrough_snippets',
};

/// A conflict the user must decide: the versions on offer for one record.
///
/// [local] is this device's live copy, when it holds one. [candidates] are the
/// other versions, one per distinct body, each the newest copy of that body.
/// Neither is applied; storage queues them for review (sync-spec §6.6).
class SyncMergeConflict {
  const SyncMergeConflict({
    required this.local,
    required this.candidates,
    this.copies = const {},
  });

  final SyncMergeCandidate? local;
  final List<SyncMergeCandidate> candidates;

  /// The wire hashes of every other copy on offer that is not shown: an older
  /// copy of a body in [candidates], or another device's copy of [local]'s
  /// body. Never [local]'s own hash or a shown candidate's. A choice goes
  /// against these too, so they are recorded with it; recording only the
  /// shown copies would let a hidden one raise the choice again.
  final Set<String> copies;
}

/// One result of the total baseline merge table.
class SyncMergeDecision {
  const SyncMergeDecision({
    required this.address,
    required this.action,
    this.winner,
    this.report,
    this.conflict,
  });

  final SyncRecordAddress address;
  final SyncMergeAction action;
  final SyncMergeCandidate? winner;
  final SyncReport? report;

  /// Set exactly when [action] is [SyncMergeAction.review].
  final SyncMergeConflict? conflict;

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

  Iterable<SyncMergeDecision> get reviews =>
      decisions.where((decision) => decision.action == SyncMergeAction.review);
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
  ///
  /// [decidedAgainst] holds, per whole-collection setting, the wire hashes of
  /// the versions the user chose against on this device (sync-spec §6.6); see
  /// [_wholeCollectionConflict].
  SyncMergePlan plan({
    required Map<SyncRecordAddress, SyncMergeCandidate?> local,
    required Map<SyncRecordAddress, SyncBaselineEntry> baseline,
    required Iterable<Map<SyncRecordAddress, SyncMergeCandidate?>> peers,
    bool freshAttach = false,
    Set<SyncRecordAddress> unresolved = const {},
    Map<SyncRecordAddress, Set<String>> decidedAgainst = const {},
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
          decidedAgainst: decidedAgainst[address] ?? const {},
        );
        if (resolution.conflict != null) {
          decisions.add(
            SyncMergeDecision(
              address: address,
              action: SyncMergeAction.review,
              conflict: resolution.conflict,
            ),
          );
        } else if (resolution.report != null) {
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
        decidedAgainst: decidedAgainst[address] ?? const {},
      );
      if (resolution.conflict != null) {
        decisions.add(
          SyncMergeDecision(
            address: address,
            action: SyncMergeAction.review,
            conflict: resolution.conflict,
          ),
        );
        continue;
      }
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
    required Set<String> decidedAgainst,
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
    final wholeCollection = _wholeCollectionConflict(
      local: local,
      contentCandidates: contentCandidates,
      baselineEntry: baselineEntry,
      deletedWins: deletedWins,
      decidedAgainst: decidedAgainst,
    );
    if (wholeCollection != null) return _Resolution.review(wholeCollection);
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
      // A live tie goes to the user (§6.3): there is no newer edit to prefer,
      // and any rule that picked one would discard the other without asking.
      // A tie between tombstones offers nothing a user could meaningfully
      // choose between, so it stays a report.
      if (!deletedWins) {
        return _Resolution.review(
          _conflict(
            local: local != null && !local.isDeleted ? local : null,
            offered: updatedWinners,
          ),
        );
      }
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

  /// A changed/changed conflict on a whole-collection setting, or null.
  ///
  /// The conflict is between every version that changed since the baseline
  /// — this device's and any peer's alike; with no baseline (a fresh attach,
  /// or a key the devices never agreed on) every version counts as changed.
  /// Two or more distinct changed bodies go to review, whichever devices hold
  /// them: two peers that each changed the set while this device held the
  /// agreed one, or held none, would otherwise have the newer set silently
  /// discard the other. A single changed version is an ordinary one-sided
  /// edit and syncs normally.
  ///
  /// A version whose wire hash is in [decidedAgainst] is not counted: the user
  /// already chose against it on this device, and the choice — stamped past
  /// every version on offer — wins last-writer-wins against it. Without this
  /// the choice could not end the conflict, because the baseline advances only
  /// once a peer carries the chosen version, and a peer that has not synced
  /// since, or a leftover manifest that never will, still publishes the old
  /// one. This device's own copy is never dropped.
  SyncMergeConflict? _wholeCollectionConflict({
    required SyncMergeCandidate? local,
    required List<SyncMergeCandidate> contentCandidates,
    required SyncBaselineEntry? baselineEntry,
    required bool deletedWins,
    required Set<String> decidedAgainst,
  }) {
    if (deletedWins || contentCandidates.isEmpty) return null;
    final key = contentCandidates.first.blob;
    if (key.kind != SyncRecordKind.setting ||
        !syncWholeCollectionSettingKeys.contains(key.id)) {
      return null;
    }
    final changed = [
      for (final candidate in contentCandidates)
        if (!candidate.isDeleted &&
            (baselineEntry == null ||
                candidate.wireHash != baselineEntry.wireHash) &&
            (identical(candidate, local) ||
                !decidedAgainst.contains(candidate.wireHash)))
          candidate,
    ];
    if (changed.map((candidate) => candidate.bodyHash).toSet().length < 2) {
      return null;
    }
    return _conflict(
      local: local != null && !local.isDeleted ? local : null,
      offered: changed,
    );
  }

  /// Builds the user's choice: this device's live copy, plus one candidate
  /// per distinct non-local body. Each is the newest copy of its body, ties
  /// broken by wire hash, so every pass queues the same rows. The copies not
  /// shown are named in [SyncMergeConflict.copies].
  SyncMergeConflict _conflict({
    required SyncMergeCandidate? local,
    required List<SyncMergeCandidate> offered,
  }) {
    final byBody = <String, SyncMergeCandidate>{};
    for (final candidate in offered) {
      if (identical(candidate, local)) continue;
      if (local != null && candidate.bodyHash == local.bodyHash) continue;
      final current = byBody[candidate.bodyHash];
      if (current == null ||
          candidate.updatedAt.isAfter(current.updatedAt) ||
          (candidate.updatedAt == current.updatedAt &&
              candidate.wireHash.compareTo(current.wireHash) < 0)) {
        byBody[candidate.bodyHash] = candidate;
      }
    }
    final candidates = byBody.values.toList()
      ..sort((left, right) => left.wireHash.compareTo(right.wireHash));
    final shown = {?local?.wireHash, for (final c in candidates) c.wireHash};
    return SyncMergeConflict(
      local: local,
      candidates: List.unmodifiable(candidates),
      copies: Set.unmodifiable({
        for (final candidate in offered)
          if (!shown.contains(candidate.wireHash)) candidate.wireHash,
      }),
    );
  }

  static int _compareAddress(SyncRecordAddress left, SyncRecordAddress right) {
    final kind = left.kind.index.compareTo(right.kind.index);
    return kind == 0 ? left.recordId.compareTo(right.recordId) : kind;
  }
}

class _Resolution {
  const _Resolution._({this.winner, this.report, this.conflict});

  const _Resolution.winner(SyncMergeCandidate candidate)
    : this._(winner: candidate);

  const _Resolution.report(SyncReport report) : this._(report: report);

  const _Resolution.review(SyncMergeConflict conflict)
    : this._(conflict: conflict);

  final SyncMergeCandidate? winner;
  final SyncReport? report;
  final SyncMergeConflict? conflict;
}
