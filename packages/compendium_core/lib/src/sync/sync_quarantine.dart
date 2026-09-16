import '../model/stored_timestamp.dart';
import '../storage/repositories/sync_local_repository.dart';
import 'sync_codec.dart';
import 'sync_merge.dart';
import 'sync_record_kind.dart';

const Duration syncQuarantineWindow = Duration(hours: 24);

DateTime syncQuarantineWindowEnd(DateTime localNow) =>
    localNow.toUtc().add(syncQuarantineWindow);

enum SyncQuarantineField { updatedAt, existenceAt }

class SyncQuarantineAssessment {
  const SyncQuarantineAssessment({
    required this.updatedAtOutOfWindow,
    required this.existenceAtOutOfWindow,
  });

  final bool updatedAtOutOfWindow;
  final bool existenceAtOutOfWindow;

  bool get isQuarantined => updatedAtOutOfWindow || existenceAtOutOfWindow;

  Set<SyncQuarantineField> get fields => {
    if (updatedAtOutOfWindow) SyncQuarantineField.updatedAt,
    if (existenceAtOutOfWindow) SyncQuarantineField.existenceAt,
  };
}

class SyncQuarantineClassifier {
  const SyncQuarantineClassifier();

  SyncQuarantineAssessment assess(
    SyncMergeCandidate candidate, {
    required DateTime windowEnd,
  }) {
    final limit = windowEnd.toUtc();
    return SyncQuarantineAssessment(
      updatedAtOutOfWindow: candidate.updatedAt.isAfter(limit),
      existenceAtOutOfWindow: candidate.existenceAt.isAfter(limit),
    );
  }
}

class SyncRepairResult {
  const SyncRepairResult({
    required this.original,
    required this.repaired,
    required this.before,
    required this.after,
  });

  final SyncMergeCandidate original;
  final SyncMergeCandidate? repaired;
  final SyncQuarantineAssessment before;
  final SyncQuarantineAssessment after;

  bool get completed => repaired != null && !after.isQuarantined;
}

SyncRepairResult repairSyncCandidate({
  required SyncMergeCandidate local,
  required SyncBaselineEntry? baseline,
  required Iterable<SyncMergeCandidate> peers,
  required DateTime windowEnd,
}) {
  const classifier = SyncQuarantineClassifier();
  final before = classifier.assess(local, windowEnd: windowEnd);
  if (!before.isQuarantined) {
    return SyncRepairResult(
      original: local,
      repaired: local,
      before: before,
      after: before,
    );
  }

  final peerList = peers.toList(growable: false);
  var updatedAt = local.updatedAt;
  var existenceAt = local.existenceAt;

  if (before.existenceAtOutOfWindow) {
    final inWindow = peerList
        .where((peer) => !peer.existenceAt.isAfter(windowEnd))
        .toList(growable: false);
    if (inWindow.isNotEmpty) {
      final matchingState = inWindow
          .where((peer) => peer.isDeleted == local.isDeleted)
          .toList(growable: false);
      final source = _greatestByExistence(
        matchingState.isNotEmpty ? matchingState : inWindow,
      );
      existenceAt = matchingState.isNotEmpty
          ? source.existenceAt
          : source.existenceAt.add(storedTimestampTick);
    }
  }

  if (before.updatedAtOutOfWindow) {
    final inWindow = peerList
        .where((peer) => !peer.updatedAt.isAfter(windowEnd))
        .toList(growable: false);
    if (inWindow.isNotEmpty) {
      final matchingBody = inWindow
          .where((peer) => _bodyAgreesWithLocal(local, baseline, peer))
          .toList(growable: false);
      if (matchingBody.isNotEmpty) {
        updatedAt = _greatestByUpdatedAt(matchingBody).updatedAt;
      } else if (baseline != null) {
        // A pre-body-hash baseline proves agreement only when a peer still
        // carries the same body. Do not stamp a different body over it.
      } else {
        updatedAt = _greatestByUpdatedAt(
          inWindow,
        ).updatedAt.add(storedTimestampTick);
      }
    }
  }

  final candidate = SyncMergeCandidate.fromBlob(
    SyncRecordBlob(
      v: local.blob.v,
      kind: local.blob.kind,
      id: local.blob.id,
      updatedAt: updatedAt,
      deletedAt: local.blob.deletedAt,
      existenceAt: existenceAt,
      body: local.blob.body,
    ),
  );
  final after = classifier.assess(candidate, windowEnd: windowEnd);
  return SyncRepairResult(
    original: local,
    repaired: candidate,
    before: before,
    after: after,
  );
}

bool _bodyAgreesWithLocal(
  SyncMergeCandidate local,
  SyncBaselineEntry? baseline,
  SyncMergeCandidate peer,
) {
  final expected = baseline?.bodyHash;
  if (expected != null) {
    return local.comparisonBodyHash == expected &&
        peer.comparisonBodyHash == expected;
  }
  return peer.comparisonBodyHash == local.comparisonBodyHash;
}

SyncMergeCandidate _greatestByExistence(List<SyncMergeCandidate> candidates) {
  var greatest = candidates.first;
  for (final candidate in candidates.skip(1)) {
    final comparison = candidate.existenceAt.compareTo(greatest.existenceAt);
    if (comparison > 0 ||
        (comparison == 0 &&
            candidate.wireHash.compareTo(greatest.wireHash) < 0)) {
      greatest = candidate;
    }
  }
  return greatest;
}

SyncMergeCandidate _greatestByUpdatedAt(List<SyncMergeCandidate> candidates) {
  var greatest = candidates.first;
  for (final candidate in candidates.skip(1)) {
    final comparison = candidate.updatedAt.compareTo(greatest.updatedAt);
    if (comparison > 0 ||
        (comparison == 0 &&
            candidate.wireHash.compareTo(greatest.wireHash) < 0)) {
      greatest = candidate;
    }
  }
  return greatest;
}

Set<SyncRecordAddress> syncQuarantineClosure({
  required Map<SyncRecordAddress, SyncMergeCandidate?> candidates,
  required Set<SyncRecordAddress> quarantined,
}) {
  final blocked = {...quarantined};
  var changed = true;
  while (changed) {
    changed = false;
    for (final entry in candidates.entries) {
      final candidate = entry.value;
      if (candidate == null || blocked.contains(entry.key)) continue;
      if (syncRecordReferences(candidate).any(blocked.contains)) {
        changed = blocked.add(entry.key) || changed;
      }
    }
  }
  return blocked;
}

Set<SyncRecordAddress> syncQuarantinedAddresses(
  Map<SyncRecordAddress, SyncMergeCandidate?> candidates, {
  required DateTime windowEnd,
}) {
  const classifier = SyncQuarantineClassifier();
  return {
    for (final entry in candidates.entries)
      if (entry.value != null &&
          classifier.assess(entry.value!, windowEnd: windowEnd).isQuarantined)
        entry.key,
  };
}

Map<SyncRecordAddress, SyncMergeCandidate?> filterSyncQuarantinedCandidates(
  Map<SyncRecordAddress, SyncMergeCandidate?> candidates, {
  required DateTime windowEnd,
}) {
  final blocked = syncQuarantineClosure(
    candidates: candidates,
    quarantined: syncQuarantinedAddresses(candidates, windowEnd: windowEnd),
  );
  return {
    for (final entry in candidates.entries)
      if (!blocked.contains(entry.key)) entry.key: entry.value,
  };
}

class SyncPublicationPlan {
  const SyncPublicationPlan({
    required this.manifestHashes,
    required this.uploadCandidates,
    required this.withheld,
  });

  final Map<SyncRecordAddress, String> manifestHashes;
  final Map<String, SyncMergeCandidate> uploadCandidates;
  final Set<SyncRecordAddress> withheld;
}

SyncPublicationPlan planSyncPublication({
  required Map<SyncRecordAddress, SyncMergeCandidate?> publication,
  required Map<SyncRecordAddress, SyncBaselineEntry> baseline,
  required DateTime windowEnd,
}) {
  final initialQuarantine = syncQuarantinedAddresses(
    publication,
    windowEnd: windowEnd,
  );
  final withheld = syncQuarantineClosure(
    candidates: publication,
    quarantined: initialQuarantine,
  );
  final manifestHashes = <SyncRecordAddress, String>{};
  for (final entry in publication.entries) {
    final candidate = entry.value;
    if (candidate == null) continue;
    if (withheld.contains(entry.key)) {
      final agreed = baseline[entry.key];
      if (agreed != null) manifestHashes[entry.key] = agreed.wireHash;
      continue;
    }
    manifestHashes[entry.key] = candidate.wireHash;
  }

  var changed = true;
  while (changed) {
    changed = false;
    for (final address in manifestHashes.keys.toList()) {
      final candidate = publication[address];
      if (candidate == null ||
          syncRecordReferences(
            candidate,
          ).any((reference) => !manifestHashes.containsKey(reference))) {
        manifestHashes.remove(address);
        changed = true;
      }
    }
  }

  final uploadCandidates = <String, SyncMergeCandidate>{};
  for (final entry in publication.entries) {
    final candidate = entry.value;
    if (candidate == null ||
        withheld.contains(entry.key) ||
        manifestHashes[entry.key] != candidate.wireHash) {
      continue;
    }
    uploadCandidates[candidate.wireHash] = candidate;
  }
  return SyncPublicationPlan(
    manifestHashes: Map.unmodifiable(manifestHashes),
    uploadCandidates: Map.unmodifiable(uploadCandidates),
    withheld: Set.unmodifiable(withheld),
  );
}

Set<SyncRecordAddress> syncRecordReferences(SyncMergeCandidate candidate) {
  final body = candidate.blob.body;
  final references = <SyncRecordAddress>{};
  void add(SyncRecordKind kind, Object? value) {
    if (value is String && value.isNotEmpty) {
      references.add((kind: kind, recordId: value));
    }
  }

  void addList(SyncRecordKind kind, Object? value) {
    if (value is! List) return;
    for (final item in value) {
      add(kind, item);
    }
  }

  switch (candidate.blob.kind) {
    case SyncRecordKind.dance:
      addList(SyncRecordKind.choreographer, body['authorIds']);
      addList(SyncRecordKind.tag, body['tagIds']);
      add(SyncRecordKind.difficultyLevel, body['difficultyLevelId']);
      final customFields = body['customFields'];
      if (customFields is List) {
        for (final item in customFields) {
          if (item is Map) {
            add(SyncRecordKind.customFieldDef, item['fieldId']);
          }
        }
      }
      final sourceCitations = body['sourceCitations'];
      if (sourceCitations is List) {
        for (final item in sourceCitations) {
          if (item is Map) {
            add(SyncRecordKind.publishedSource, item['sourceId']);
          }
        }
      }
      final links = body['links'];
      if (links is List) {
        for (final item in links) {
          if (item is Map) add(SyncRecordKind.dance, item['targetDanceId']);
        }
      }
    case SyncRecordKind.program:
      final slots = body['slots'];
      if (slots is List) {
        for (final item in slots) {
          if (item is Map) add(SyncRecordKind.dance, item['danceId']);
        }
      }
    // Programs.venueId is intentionally exempt by §6.7.
    case SyncRecordKind.choreographer:
    case SyncRecordKind.tag:
    case SyncRecordKind.publishedSource:
    case SyncRecordKind.customFieldDef:
    case SyncRecordKind.difficultyLevel:
    case SyncRecordKind.venue:
    case SyncRecordKind.setting:
      break;
  }
  return references;
}
