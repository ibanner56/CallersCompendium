import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

final _localNow = DateTime.utc(2026, 7, 15, 12);
final _windowEnd = syncQuarantineWindowEnd(_localNow);

void main() {
  test('quarantine assesses updatedAt and existenceAt independently', () {
    final candidate = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      updatedAt: _windowEnd,
      existenceAt: _windowEnd.add(const Duration(seconds: 1)),
    );

    final assessment = const SyncQuarantineClassifier().assess(
      candidate,
      windowEnd: _windowEnd,
    );

    expect(assessment.updatedAtOutOfWindow, isFalse);
    expect(assessment.existenceAtOutOfWindow, isTrue);
    expect(assessment.isQuarantined, isTrue);
  });

  test('repair selects the greatest matching peer for each field', () {
    final local = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'local',
      updatedAt: _windowEnd.add(const Duration(hours: 1)),
      existenceAt: _localNow,
    );
    final matchingEarlier = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'local',
      updatedAt: _localNow.add(const Duration(hours: 1)),
      existenceAt: _localNow,
    );
    final matchingLater = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'local',
      updatedAt: _localNow.add(const Duration(hours: 2)),
      existenceAt: _localNow,
    );
    final differentBody = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'different',
      updatedAt: _localNow.add(const Duration(hours: 3)),
      existenceAt: _localNow,
    );
    final futureMatching = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'local',
      updatedAt: _windowEnd.add(const Duration(minutes: 1)),
      existenceAt: _localNow,
    );

    final result = repairSyncCandidate(
      local: local,
      baseline: SyncBaselineEntry(
        kind: local.address.kind,
        recordId: local.address.recordId,
        wireHash: local.wireHash,
        bodyHash: local.bodyHash,
      ),
      peers: [matchingEarlier, matchingLater, differentBody, futureMatching],
      windowEnd: _windowEnd,
    );

    expect(result.completed, isTrue);
    expect(result.repaired!.updatedAt, matchingLater.updatedAt);
    expect(result.repaired!.existenceAt, local.existenceAt);
    expect(result.repaired!.bodyHash, local.bodyHash);
  });

  test('repair protects a local edit from a stale baseline peer', () {
    final baselineBody = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'baseline',
      updatedAt: _localNow,
      existenceAt: _localNow,
    );
    final local = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'local edit',
      updatedAt: _windowEnd.add(const Duration(hours: 1)),
      existenceAt: _localNow,
    );
    final peer = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'baseline',
      updatedAt: _localNow.add(const Duration(hours: 1)),
      existenceAt: _localNow,
    );

    final result = repairSyncCandidate(
      local: local,
      baseline: SyncBaselineEntry(
        kind: local.address.kind,
        recordId: local.address.recordId,
        wireHash: baselineBody.wireHash,
        bodyHash: baselineBody.bodyHash,
      ),
      peers: [peer],
      windowEnd: _windowEnd,
    );

    expect(result.completed, isFalse);
    expect(result.after.isQuarantined, isTrue);
    expect(result.repaired!.updatedAt, local.updatedAt);
  });

  test('wire-only baselines repair only when a peer carries the same body', () {
    final local = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'local',
      updatedAt: _windowEnd.add(const Duration(hours: 1)),
      existenceAt: _localNow,
    );
    final matchingPeer = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'local',
      updatedAt: _localNow.add(const Duration(hours: 1)),
      existenceAt: _localNow,
    );
    final differingPeer = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'peer',
      updatedAt: _localNow.add(const Duration(hours: 2)),
      existenceAt: _localNow,
    );

    final repaired = repairSyncCandidate(
      local: local,
      baseline: SyncBaselineEntry(
        kind: local.address.kind,
        recordId: local.address.recordId,
        wireHash: local.wireHash,
      ),
      peers: [differingPeer, matchingPeer],
      windowEnd: _windowEnd,
    );
    final quarantined = repairSyncCandidate(
      local: local,
      baseline: SyncBaselineEntry(
        kind: local.address.kind,
        recordId: local.address.recordId,
        wireHash: local.wireHash,
      ),
      peers: [differingPeer],
      windowEnd: _windowEnd,
    );

    expect(repaired.completed, isTrue);
    expect(repaired.repaired!.updatedAt, matchingPeer.updatedAt);
    expect(quarantined.completed, isFalse);
    expect(quarantined.after.isQuarantined, isTrue);
  });

  test('legacy full-body baselines never authorize timestamp repair', () {
    final local = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'local',
      updatedAt: _windowEnd.add(const Duration(hours: 1)),
      existenceAt: _localNow,
    );
    final peer = _candidate(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      value: 'local',
      updatedAt: _localNow.add(const Duration(hours: 1)),
      existenceAt: _localNow,
    );

    final result = repairSyncCandidate(
      local: local,
      baseline: SyncBaselineEntry(
        kind: local.address.kind,
        recordId: local.address.recordId,
        wireHash: local.wireHash,
        bodyHash: local.comparisonBodyHash,
        bodyHashVersion: SyncBaselineBodyHashVersion.legacyFullBody,
      ),
      peers: [peer],
      windowEnd: _windowEnd,
    );

    expect(result.completed, isFalse);
    expect(result.repaired!.updatedAt, local.updatedAt);
    expect(result.after.isQuarantined, isTrue);
  });

  for (final kind in [SyncRecordKind.dance, SyncRecordKind.program]) {
    for (final deleted in [false, true]) {
      for (final hasBaseline in [false, true]) {
        test('repair ignores timestamp projections for ${kind.name} '
            '${deleted ? 'pending tombstone' : 'live'} '
            '${hasBaseline ? 'with' : 'without'} baseline', () {
          final localDeletedAt = deleted
              ? _windowEnd.add(const Duration(hours: 1))
              : null;
          final peerDeletedAt = deleted
              ? _localNow.add(const Duration(hours: 2))
              : null;
          final local = _timestampedEntityCandidate(
            kind: kind,
            id: '${kind.name}-${deleted ? 'deleted' : 'live'}',
            updatedAt: _windowEnd.add(const Duration(hours: 1)),
            deletedAt: localDeletedAt,
          );
          final peer = _timestampedEntityCandidate(
            kind: kind,
            id: local.blob.id,
            updatedAt: _localNow.add(const Duration(hours: 2)),
            deletedAt: peerDeletedAt,
          );
          final baselineCandidate = _timestampedEntityCandidate(
            kind: kind,
            id: local.blob.id,
            updatedAt: _localNow,
            deletedAt: deleted ? _localNow : null,
          );

          final result = repairSyncCandidate(
            local: local,
            baseline: hasBaseline
                ? SyncBaselineEntry(
                    kind: local.address.kind,
                    recordId: local.address.recordId,
                    wireHash: baselineCandidate.wireHash,
                    bodyHash: baselineCandidate.comparisonBodyHash,
                  )
                : null,
            peers: [peer],
            windowEnd: _windowEnd,
          );

          expect(result.completed, isTrue);
          expect(result.repaired!.updatedAt, peer.updatedAt);
          expect(result.repaired!.existenceAt, local.existenceAt);
          expect(result.repaired!.blob.deletedAt, local.blob.deletedAt);
          expect(result.repaired!.blob.body, local.blob.body);
          expect(result.repaired!.blob.id, local.blob.id);
          expect(result.repaired!.blob.kind, local.blob.kind);
          expect(
            result.repaired!.wireHash,
            sha256Hex(encodeSyncRecordBlobUtf8(result.repaired!.blob)),
          );
        });
      }
    }
  }

  test(
    'post-repair recheck keeps a boundary peer plus one tick quarantined',
    () {
      final local = _candidate(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        value: 'local',
        updatedAt: _windowEnd.add(const Duration(hours: 1)),
        existenceAt: _localNow,
      );
      final differentPeer = _candidate(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        value: 'peer',
        updatedAt: _windowEnd,
        existenceAt: _localNow,
      );

      final result = repairSyncCandidate(
        local: local,
        baseline: null,
        peers: [differentPeer],
        windowEnd: _windowEnd,
      );

      expect(result.completed, isFalse);
      expect(result.repaired!.updatedAt, _windowEnd.add(storedTimestampTick));
      expect(result.after.isQuarantined, isTrue);
    },
  );

  test(
    'quarantine closure reaches database-enforced dependents but skips venueId',
    () {
      final quarantinedAuthor = _candidate(
        kind: SyncRecordKind.choreographer,
        id: 'author-1',
        updatedAt: _windowEnd.add(const Duration(minutes: 1)),
        existenceAt: _localNow,
      );
      final dance = _candidate(
        kind: SyncRecordKind.dance,
        id: 'dance-1',
        body: const {
          'id': 'dance-1',
          'title': 'Dance',
          'authorIds': ['author-1'],
        },
        updatedAt: _localNow,
        existenceAt: _localNow,
      );
      final program = _candidate(
        kind: SyncRecordKind.program,
        id: 'program-1',
        body: const {
          'id': 'program-1',
          'slots': [
            {'danceId': 'dance-1'},
          ],
        },
        updatedAt: _localNow,
        existenceAt: _localNow,
      );
      final venue = _candidate(
        kind: SyncRecordKind.venue,
        id: 'venue-1',
        updatedAt: _windowEnd.add(const Duration(minutes: 1)),
        existenceAt: _localNow,
      );
      final venueOnlyProgram = _candidate(
        kind: SyncRecordKind.program,
        id: 'program-2',
        body: const {'id': 'program-2', 'venueId': 'venue-1', 'slots': []},
        updatedAt: _localNow,
        existenceAt: _localNow,
      );
      final candidates = {
        quarantinedAuthor.address: quarantinedAuthor,
        dance.address: dance,
        program.address: program,
        venue.address: venue,
        venueOnlyProgram.address: venueOnlyProgram,
      };

      final blocked = syncQuarantineClosure(
        candidates: candidates,
        quarantined: syncQuarantinedAddresses(
          candidates,
          windowEnd: _windowEnd,
        ),
      );

      expect(blocked, containsAll([quarantinedAuthor.address, dance.address]));
      expect(blocked, contains(program.address));
      expect(blocked, contains(venue.address));
      expect(blocked, isNot(contains(venueOnlyProgram.address)));
    },
  );

  test(
    'publication falls back to an agreed wire hash and publishes dependents',
    () {
      final root = _candidate(
        kind: SyncRecordKind.choreographer,
        id: 'author-1',
        updatedAt: _windowEnd.add(const Duration(minutes: 1)),
        existenceAt: _localNow,
      );
      final dependent = _candidate(
        kind: SyncRecordKind.dance,
        id: 'dance-1',
        body: const {
          'id': 'dance-1',
          'title': 'Dance',
          'authorIds': ['author-1'],
        },
        updatedAt: _localNow,
        existenceAt: _localNow,
      );
      final safe = _candidate(
        kind: SyncRecordKind.setting,
        id: 'default_program_band',
        value: 'safe',
        updatedAt: _localNow,
        existenceAt: _localNow,
      );

      final plan = planSyncPublication(
        publication: {
          root.address: root,
          dependent.address: dependent,
          safe.address: safe,
        },
        baseline: {
          root.address: SyncBaselineEntry(
            kind: root.address.kind,
            recordId: root.address.recordId,
            wireHash: 'a' * 64,
          ),
        },
        windowEnd: _windowEnd,
      );

      expect(plan.manifestHashes[root.address], 'a' * 64);
      expect(plan.manifestHashes[dependent.address], dependent.wireHash);
      expect(plan.manifestHashes[safe.address], safe.wireHash);
      expect(plan.uploadCandidates.keys, contains(dependent.wireHash));
      expect(plan.uploadCandidates.keys, contains(safe.wireHash));
      expect(plan.uploadCandidates.keys, isNot(contains(root.wireHash)));
      expect(plan.withheld, contains(root.address));
      expect(plan.withheld, isNot(contains(dependent.address)));
    },
  );

  test(
    'publication omits a dependent fallback when its quarantined root has no baseline',
    () {
      final root = _candidate(
        kind: SyncRecordKind.choreographer,
        id: 'author-without-baseline',
        updatedAt: _windowEnd.add(const Duration(minutes: 1)),
        existenceAt: _localNow,
      );
      final dependent = _candidate(
        kind: SyncRecordKind.dance,
        id: 'dance-with-baseline',
        body: const {
          'id': 'dance-with-baseline',
          'title': 'Dance',
          'authorIds': ['author-without-baseline'],
        },
        updatedAt: _localNow,
        existenceAt: _localNow,
      );

      final plan = planSyncPublication(
        publication: {root.address: root, dependent.address: dependent},
        baseline: {
          dependent.address: SyncBaselineEntry(
            kind: dependent.address.kind,
            recordId: dependent.address.recordId,
            wireHash: 'b' * 64,
          ),
        },
        windowEnd: _windowEnd,
      );

      expect(plan.manifestHashes, isNot(contains(root.address)));
      expect(plan.manifestHashes, isNot(contains(dependent.address)));
      expect(plan.withheld, containsAll([root.address, dependent.address]));
    },
  );

  test('publication does not withhold a program that only cites venueId', () {
    final venue = _candidate(
      kind: SyncRecordKind.venue,
      id: 'venue-1',
      updatedAt: _windowEnd.add(const Duration(minutes: 1)),
      existenceAt: _localNow,
    );
    final program = _candidate(
      kind: SyncRecordKind.program,
      id: 'program-1',
      body: const {'id': 'program-1', 'venueId': 'venue-1', 'slots': []},
      updatedAt: _localNow,
      existenceAt: _localNow,
    );

    final plan = planSyncPublication(
      publication: {venue.address: venue, program.address: program},
      baseline: const {},
      windowEnd: _windowEnd,
    );

    expect(plan.withheld, contains(venue.address));
    expect(plan.withheld, isNot(contains(program.address)));
    expect(plan.manifestHashes[program.address], program.wireHash);
  });
}

SyncMergeCandidate _timestampedEntityCandidate({
  required SyncRecordKind kind,
  required String id,
  required DateTime updatedAt,
  required DateTime? deletedAt,
}) {
  final body = <String, Object?>{
    'id': id,
    'title': kind == SyncRecordKind.dance ? 'Dance' : 'Program',
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };
  return SyncMergeCandidate.fromBlob(
    SyncRecordBlob(
      kind: kind,
      id: id,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      existenceAt: _localNow,
      body: body,
    ),
  );
}

SyncMergeCandidate _candidate({
  required SyncRecordKind kind,
  required String id,
  String value = 'value',
  DateTime? updatedAt,
  DateTime? existenceAt,
  Map<String, Object?>? body,
}) {
  return SyncMergeCandidate.fromBlob(
    SyncRecordBlob(
      kind: kind,
      id: id,
      updatedAt: updatedAt ?? _localNow,
      deletedAt: null,
      existenceAt: existenceAt ?? _localNow,
      body:
          body ??
          (kind == SyncRecordKind.setting
              ? {'value': value}
              : {'id': id, 'name': value}),
    ),
  );
}
