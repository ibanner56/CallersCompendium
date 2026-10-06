import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

final _baseTime = DateTime.utc(2026, 7, 15, 12);

extension on SyncRecordBlob {
  SyncRecordAddress get address => (kind: kind, recordId: id);
}

void main() {
  const engine = SyncMergeEngine();

  test('covers the total baseline table, including both-side absence', () {
    final baselineBlob = _setting('theme_mode', 'baseline');
    final changedLocal = _setting('theme_mode', 'local', seconds: 1);
    final remote = _setting('theme_mode', 'remote', seconds: 2);
    final absentAddress = _dance('absent', 'absent').address;

    final plan = engine.plan(
      local: {
        baselineBlob.address: SyncMergeCandidate.fromBlob(changedLocal),
        absentAddress: null,
        _dance(
          'baseline-absent-local',
          'local',
        ).address: SyncMergeCandidate.fromBlob(
          _dance('baseline-absent-local', 'local'),
        ),
      },
      baseline: {
        baselineBlob.address: SyncBaselineEntry(
          kind: baselineBlob.kind,
          recordId: baselineBlob.id,
          wireHash: SyncMergeCandidate.fromBlob(baselineBlob).wireHash,
        ),
        absentAddress: const SyncBaselineEntry(
          kind: SyncRecordKind.dance,
          recordId: 'absent',
          wireHash: 'baseline-hash',
        ),
        _dance('local-absent', 'baseline').address: const SyncBaselineEntry(
          kind: SyncRecordKind.dance,
          recordId: 'local-absent',
          wireHash: 'baseline-hash',
        ),
      },
      peers: [
        {
          baselineBlob.address: SyncMergeCandidate.fromBlob(remote),
          _dance('local-absent', 'peer').address: SyncMergeCandidate.fromBlob(
            _dance('local-absent', 'peer'),
          ),
        },
        {
          _dance(
            'baseline-absent-remote',
            'peer',
          ).address: SyncMergeCandidate.fromBlob(
            _dance('baseline-absent-remote', 'peer'),
          ),
        },
      ],
    );

    expect(
      plan.decisions.firstWhere((d) => d.address == absentAddress).action,
      SyncMergeAction.dropBaseline,
    );
    expect(
      plan.decisions
          .firstWhere(
            (d) => d.address == _dance('local-absent', 'baseline').address,
          )
          .action,
      SyncMergeAction.download,
    );
    expect(
      plan.decisions
          .firstWhere((d) => d.address == baselineBlob.address)
          .action,
      SyncMergeAction.download,
    );
    expect(
      plan.decisions
          .firstWhere(
            (d) =>
                d.address == _dance('baseline-absent-local', 'local').address,
          )
          .action,
      SyncMergeAction.upload,
    );
    expect(
      plan.decisions
          .firstWhere(
            (d) =>
                d.address == _dance('baseline-absent-remote', 'peer').address,
          )
          .action,
      SyncMergeAction.download,
    );
  });

  test('keeps same UUIDs in different kinds independent', () {
    final setting = _setting('theme_mode', 'setting');
    final dance = _dance('theme_mode', 'dance');
    final plan = engine.plan(
      local: {
        setting.address: SyncMergeCandidate.fromBlob(setting),
        dance.address: SyncMergeCandidate.fromBlob(dance),
      },
      baseline: const {},
      peers: const [{}],
    );

    expect(plan.decisions, hasLength(2));
    expect(plan.decisions.map((decision) => decision.address.kind).toSet(), {
      SyncRecordKind.setting,
      SyncRecordKind.dance,
    });
  });

  group('equal updatedAt with differing bodies (§6.3)', () {
    SyncBaselineEntry agreedOn(SyncRecordBlob blob) => SyncBaselineEntry(
      kind: blob.kind,
      recordId: blob.id,
      wireHash: SyncMergeCandidate.fromBlob(blob).wireHash,
    );

    test('hands the choice to the user and applies neither body', () {
      final local = _setting('theme_mode', 'local');
      final remote = _setting('theme_mode', 'remote');
      final plan = engine.plan(
        local: {local.address: SyncMergeCandidate.fromBlob(local)},
        baseline: {local.address: agreedOn(local)},
        peers: [
          {remote.address: SyncMergeCandidate.fromBlob(remote, peerId: 'p')},
        ],
      );

      final decision = plan.decisions.single;
      expect(decision.action, SyncMergeAction.review);
      expect(decision.winner, isNull);
      expect(plan.downloads, isEmpty);
      expect(plan.uploads, isEmpty);
      expect(
        plan.reports,
        isEmpty,
        reason: 'a queued choice replaces the per-pass report',
      );
      expect(decision.conflict!.local!.blob.body['value'], 'local');
      expect(decision.conflict!.candidates.map((c) => c.blob.body['value']), [
        'remote',
      ]);
    });

    test('is a review from both sides, so the choice is offered on either '
        'device', () {
      final left = _setting('theme_mode', 'left');
      final right = _setting('theme_mode', 'right');
      SyncMergeDecision decide(SyncRecordBlob mine, SyncRecordBlob theirs) =>
          engine
              .plan(
                local: {mine.address: SyncMergeCandidate.fromBlob(mine)},
                baseline: const {},
                peers: [
                  {theirs.address: SyncMergeCandidate.fromBlob(theirs)},
                ],
              )
              .decisions
              .single;

      expect(decide(left, right).action, SyncMergeAction.review);
      expect(decide(right, left).action, SyncMergeAction.review);
    });

    test('offers each distinct body once, however many peers hold it', () {
      final local = _setting('theme_mode', 'local');
      final remote = _setting('theme_mode', 'remote');
      final plan = engine.plan(
        local: {local.address: SyncMergeCandidate.fromBlob(local)},
        baseline: const {},
        peers: [
          {remote.address: SyncMergeCandidate.fromBlob(remote, peerId: 'a')},
          {remote.address: SyncMergeCandidate.fromBlob(remote, peerId: 'b')},
        ],
      );

      expect(plan.decisions.single.conflict!.candidates, hasLength(1));
    });

    test('a tie between two peers offers both even when this device holds '
        'nothing', () {
      final left = _setting('theme_mode', 'left');
      final right = _setting('theme_mode', 'right');
      final plan = engine.plan(
        local: const {},
        baseline: const {},
        peers: [
          {left.address: SyncMergeCandidate.fromBlob(left)},
          {right.address: SyncMergeCandidate.fromBlob(right)},
        ],
      );

      final decision = plan.decisions.single;
      expect(decision.action, SyncMergeAction.review);
      expect(decision.conflict!.local, isNull);
      expect(
        decision.conflict!.candidates.map((c) => c.blob.body['value']).toSet(),
        {'left', 'right'},
      );
    });

    test('a tie between tombstones stays a report: there is nothing to '
        'choose between', () {
      final local = _setting('theme_mode', 'local', deleted: true);
      final remote = _setting('theme_mode', 'remote', deleted: true);
      final plan = engine.plan(
        local: {local.address: SyncMergeCandidate.fromBlob(local)},
        baseline: const {},
        peers: [
          {remote.address: SyncMergeCandidate.fromBlob(remote)},
        ],
      );

      expect(plan.decisions.single.action, SyncMergeAction.report);
      expect(plan.reports.single.code, SyncReportCode.equalUpdatedAt);
    });

    test('converges once either device decides, with the decision stamped '
        'past the tie', () {
      final address = _setting('theme_mode', 'x').address;
      final left = _SimulatedDevice(
        'left',
        SyncMergeCandidate.fromBlob(_setting('theme_mode', 'left')),
      );
      final right = _SimulatedDevice(
        'right',
        SyncMergeCandidate.fromBlob(_setting('theme_mode', 'right')),
      );
      final devices = [left, right];
      _runSimulatedPass(left, devices);
      _runSimulatedPass(right, devices);
      expect(left.local[address]!.blob.body['value'], 'left');
      expect(right.local[address]!.blob.body['value'], 'right');

      // The user keeps the right-hand version on the left device: storage
      // writes it one tick past the tied stamp.
      final decided = SyncMergeCandidate.fromBlob(
        _setting('theme_mode', 'right', seconds: 1),
      );
      left.local[address] = decided;
      left.manifest[address] = decided;

      for (var round = 0; round < 2; round++) {
        for (final device in devices) {
          _runSimulatedPass(device, devices);
        }
      }
      _expectConverged(devices, address, 'right');
    });
  });

  group('whole-collection settings (ADR-004, Consequences)', () {
    SyncBaselineEntry agreedOn(SyncRecordBlob blob) => SyncBaselineEntry(
      kind: blob.kind,
      recordId: blob.id,
      wireHash: SyncMergeCandidate.fromBlob(blob).wireHash,
    );

    for (final key in syncWholeCollectionSettingKeys) {
      test('$key: changed on both devices goes to review even when one '
          'edit is newer', () {
        final agreed = _setting(key, 'agreed');
        final local = _setting(key, 'local set', seconds: 1);
        final remote = _setting(key, 'remote set', seconds: 2);
        final plan = engine.plan(
          local: {local.address: SyncMergeCandidate.fromBlob(local)},
          baseline: {agreed.address: agreedOn(agreed)},
          peers: [
            {remote.address: SyncMergeCandidate.fromBlob(remote)},
          ],
        );

        expect(plan.decisions.single.action, SyncMergeAction.review);
        expect(plan.downloads, isEmpty);
      });
    }

    test('a version chosen against on this device is not counted as a '
        'change, so the choice ends the conflict', () {
      final agreed = _setting('custom_dialects', 'agreed');
      final decided = _setting('custom_dialects', 'chosen set', seconds: 3);
      final against = _setting('custom_dialects', 'other set', seconds: 2);
      final againstHash = SyncMergeCandidate.fromBlob(against).wireHash;
      for (final baseline in [
        {agreed.address: agreedOn(agreed)},
        const <SyncRecordAddress, SyncBaselineEntry>{},
      ]) {
        final plan = engine.plan(
          local: {decided.address: SyncMergeCandidate.fromBlob(decided)},
          baseline: baseline,
          peers: [
            {against.address: SyncMergeCandidate.fromBlob(against)},
          ],
          decidedAgainst: {
            decided.address: {againstHash},
          },
        );

        expect(plan.decisions.single.action, SyncMergeAction.upload);
      }
    });

    test('names every copy on offer that the choice does not show', () {
      final agreed = _setting('custom_dialects', 'agreed');
      final local = _setting('custom_dialects', 'local set', seconds: 1);
      final ownCopy = _setting('custom_dialects', 'local set', seconds: 2);
      final older = _setting('custom_dialects', 'remote set', seconds: 2);
      final newer = _setting('custom_dialects', 'remote set', seconds: 3);
      SyncMergeCandidate c(SyncRecordBlob blob) =>
          SyncMergeCandidate.fromBlob(blob);
      final plan = engine.plan(
        local: {local.address: c(local)},
        baseline: {agreed.address: agreedOn(agreed)},
        peers: [
          {older.address: c(older)},
          {newer.address: c(newer)},
          {ownCopy.address: c(ownCopy)},
        ],
      );

      final conflict = plan.decisions.single.conflict!;
      expect(conflict.candidates.map((x) => x.wireHash), [c(newer).wireHash]);
      expect(conflict.copies, {c(older).wireHash, c(ownCopy).wireHash});
    });

    test('a decided-against hash never drops this device\'s own copy, nor '
        'a version it was not chosen against', () {
      final agreed = _setting('custom_dialects', 'agreed');
      final local = _setting('custom_dialects', 'local set', seconds: 1);
      final remote = _setting('custom_dialects', 'remote set', seconds: 2);
      final plan = engine.plan(
        local: {local.address: SyncMergeCandidate.fromBlob(local)},
        baseline: {agreed.address: agreedOn(agreed)},
        peers: [
          {remote.address: SyncMergeCandidate.fromBlob(remote)},
        ],
        decidedAgainst: {
          local.address: {
            SyncMergeCandidate.fromBlob(local).wireHash,
            SyncMergeCandidate.fromBlob(agreed).wireHash,
          },
        },
      );

      expect(plan.decisions.single.action, SyncMergeAction.review);
    });

    test('two other devices that each changed the set go to review while '
        'this device still holds the agreed one', () {
      final agreed = _setting('custom_dialects', 'agreed');
      final left = _setting('custom_dialects', 'left set', seconds: 1);
      final right = _setting('custom_dialects', 'right set', seconds: 2);
      final plan = engine.plan(
        local: {agreed.address: SyncMergeCandidate.fromBlob(agreed)},
        baseline: {agreed.address: agreedOn(agreed)},
        peers: [
          {left.address: SyncMergeCandidate.fromBlob(left)},
          {right.address: SyncMergeCandidate.fromBlob(right)},
        ],
      );

      final decision = plan.decisions.single;
      expect(decision.action, SyncMergeAction.review);
      expect(
        decision.conflict!.candidates.map((c) => c.blob.body['value']).toSet(),
        {'left set', 'right set'},
      );
    });

    test('two other devices that each hold a set go to review when this '
        'device holds none', () {
      final left = _setting('custom_dialects', 'left set', seconds: 1);
      final right = _setting('custom_dialects', 'right set', seconds: 2);
      final plan = engine.plan(
        local: const {},
        baseline: const {},
        peers: [
          {left.address: SyncMergeCandidate.fromBlob(left)},
          {right.address: SyncMergeCandidate.fromBlob(right)},
        ],
      );

      expect(plan.decisions.single.action, SyncMergeAction.review);
      expect(plan.decisions.single.conflict!.local, isNull);
    });

    test('first pairing of two devices that each hold a set goes to '
        'review', () {
      final local = _setting('custom_dialects', 'local set', seconds: 5);
      final remote = _setting('custom_dialects', 'remote set', seconds: 9);
      final plan = engine.plan(
        local: {local.address: SyncMergeCandidate.fromBlob(local)},
        baseline: const {},
        peers: [
          {remote.address: SyncMergeCandidate.fromBlob(remote)},
        ],
        freshAttach: true,
      );

      expect(plan.decisions.single.action, SyncMergeAction.review);
    });

    test('an edit made on one device only still syncs without asking', () {
      final agreed = _setting('custom_dialects', 'agreed');
      final remote = _setting('custom_dialects', 'remote set', seconds: 2);
      final downloaded = engine.plan(
        local: {agreed.address: SyncMergeCandidate.fromBlob(agreed)},
        baseline: {agreed.address: agreedOn(agreed)},
        peers: [
          {remote.address: SyncMergeCandidate.fromBlob(remote)},
        ],
      );
      expect(downloaded.decisions.single.action, SyncMergeAction.download);

      final local = _setting('custom_dialects', 'local set', seconds: 2);
      final uploaded = engine.plan(
        local: {local.address: SyncMergeCandidate.fromBlob(local)},
        baseline: {agreed.address: agreedOn(agreed)},
        peers: [
          {agreed.address: SyncMergeCandidate.fromBlob(agreed)},
        ],
      );
      expect(uploaded.decisions.single.action, SyncMergeAction.upload);
    });

    test('an ordinary preference changed on both devices is still '
        'last-writer-wins', () {
      final agreed = _setting('theme_mode', 'agreed');
      final local = _setting('theme_mode', 'dark', seconds: 1);
      final remote = _setting('theme_mode', 'light', seconds: 2);
      final plan = engine.plan(
        local: {local.address: SyncMergeCandidate.fromBlob(local)},
        baseline: {agreed.address: agreedOn(agreed)},
        peers: [
          {remote.address: SyncMergeCandidate.fromBlob(remote)},
        ],
      );

      expect(plan.decisions.single.action, SyncMergeAction.download);
      expect(plan.decisions.single.winner!.blob.body['value'], 'light');
    });
  });

  test('preserves the peer identity on a remote download winner', () {
    final remote = SyncMergeCandidate.fromBlob(
      _setting('theme_mode', 'remote'),
      peerId: 'peer-a',
    );
    final plan = engine.plan(
      local: const {},
      baseline: const {},
      peers: [
        {remote.address: remote},
      ],
    );

    final decision = plan.decisions.single;
    expect(decision.action, SyncMergeAction.download);
    expect(decision.winner?.peerId, 'peer-a');
  });

  test('guards an unequal tombstone over a baseline-absent setting', () {
    final local = _setting('theme_mode', 'local');
    final tombstone = _setting(
      'theme_mode',
      'remote',
      seconds: 1,
      deleted: true,
    );
    final plan = engine.plan(
      local: {local.address: SyncMergeCandidate.fromBlob(local)},
      baseline: const {},
      peers: [
        {tombstone.address: SyncMergeCandidate.fromBlob(tombstone)},
      ],
    );

    expect(plan.decisions.single.action, SyncMergeAction.report);
    expect(plan.reports.single.code, SyncReportCode.unseenLocalCreation);
  });

  test(
    'equal existenceAt silently chooses the tombstone and fresh attach bypasses guard',
    () {
      final local = _setting('theme_mode', 'local');
      final tombstone = _setting('theme_mode', 'local', deleted: true);
      final steadyState = engine.plan(
        local: {local.address: SyncMergeCandidate.fromBlob(local)},
        baseline: const {},
        peers: [
          {tombstone.address: SyncMergeCandidate.fromBlob(tombstone)},
        ],
      );
      final freshAttach = engine.plan(
        local: {local.address: SyncMergeCandidate.fromBlob(local)},
        baseline: const {},
        peers: [
          {tombstone.address: SyncMergeCandidate.fromBlob(tombstone)},
        ],
        freshAttach: true,
      );

      expect(steadyState.decisions.single.action, SyncMergeAction.download);
      expect(freshAttach.decisions.single.action, SyncMergeAction.download);
      expect(steadyState.reports, isEmpty);
      expect(freshAttach.reports, isEmpty);
    },
  );

  test('fresh attach reuses shipped title normalization across clients', () {
    final pairs = [
      (
        _danceCandidate('z-nfc', 'The Résumé'),
        _danceCandidate('a-nfd', 're\u0301sume\u0301'),
      ),
      (
        _danceCandidate('z-case', 'NICE COMBINATION'),
        _danceCandidate('a-case', 'nice combination'),
      ),
      (
        _danceCandidate('z-space', 'Nice   Combination'),
        _danceCandidate('a-space', 'nice combination'),
      ),
      (
        _danceCandidate('z-punctuation', 'Nice-Combination'),
        _danceCandidate('a-punctuation', 'nice combination'),
      ),
    ];

    for (final pair in pairs) {
      final plan = planFreshAttachDedupe([pair.$1, pair.$2]);

      expect(plan.merges, hasLength(1));
      expect(plan.merges.single.winner.blob.id, startsWith('a-'));
      expect(plan.merges.single.losingIds, contains(startsWith('z-')));
      expect(plan.ambiguities, isEmpty);
    }
  });

  test(
    'fresh attach excludes tombstones and preserves deterministic merge rules',
    () {
      final older = _danceCandidate(
        'z-older',
        'The Shared Dance',
        walkthrough: 'older',
        rating: 2,
        authors: ['author-a'],
        tags: ['tag-a'],
        updatedSeconds: 1,
      );
      final survivor = _danceCandidate(
        'a-survivor',
        'shared dance',
        walkthrough: 'survivor',
        rating: 1,
        authors: ['author-b'],
        tags: ['tag-b'],
        updatedSeconds: 1,
      );
      final newest = _danceCandidate(
        'm-newest',
        'SHARED DANCE',
        walkthrough: 'newest',
        rating: 5,
        authors: ['author-c'],
        tags: ['tag-c'],
        updatedSeconds: 2,
      );
      final tombstone = _danceCandidate(
        'b-tombstone',
        'shared dance',
        deleted: true,
        updatedSeconds: 3,
      );

      final plan = planFreshAttachDedupe([older, survivor, newest, tombstone]);

      expect(plan.ambiguities, isEmpty);
      expect(plan.merges, hasLength(1));
      final merge = plan.merges.single;
      expect(merge.winner.blob.id, 'a-survivor');
      expect(merge.losingIds, ['m-newest', 'z-older']);
      expect(merge.winner.blob.body['walkthrough'], 'newest');
      expect(merge.winner.blob.body['rating'], 5);
      expect(merge.winner.blob.body['authorIds'], [
        'author-b',
        'author-c',
        'author-a',
      ]);
      expect(merge.winner.blob.body['tagIds'], ['tag-b', 'tag-c', 'tag-a']);
      expect(plan.aliases, {'m-newest': 'a-survivor', 'z-older': 'a-survivor'});
    },
  );

  test(
    'fresh attach collection unions outrank an equal-time survivor peer',
    () {
      final survivor = _danceCandidate(
        'a-survivor',
        'Shared dance',
        tags: ['tag-a'],
      );
      final duplicate = _danceCandidate(
        'z-duplicate',
        'The shared dance',
        tags: ['tag-z'],
      );

      final merged = mergeDanceCandidates([survivor, duplicate]).winner;

      expect(merged.blob.body['tagIds'], ['tag-a', 'tag-z']);
      expect(merged.updatedAt, _baseTime.add(storedTimestampTick));

      final peerPlan = engine.plan(
        local: {survivor.address: survivor},
        baseline: const {},
        peers: [
          {merged.address: merged},
        ],
      );

      expect(peerPlan.decisions.single.action, SyncMergeAction.download);
      expect(peerPlan.decisions.single.winner!.wireHash, merged.wireHash);

      final mergedPeerPlan = engine.plan(
        local: {merged.address: merged},
        baseline: const {},
        peers: [
          {survivor.address: survivor},
        ],
      );
      expect(mergedPeerPlan.decisions.single.action, SyncMergeAction.upload);
      expect(mergedPeerPlan.decisions.single.winner!.wireHash, merged.wireHash);
    },
  );

  test(
    'fresh attach queues ambiguity instead of merging different choreography',
    () {
      final left = _danceCandidate(
        'a-left',
        'Shared dance',
        figures: const [
          {
            'move': 'balance',
            'params': {'side': 'left'},
          },
        ],
      );
      final right = _danceCandidate(
        'b-right',
        'The SHARED DANCE',
        figures: const [
          {
            'move': 'balance',
            'params': {'side': 'right'},
          },
        ],
      );

      final plan = planFreshAttachDedupe([left, right]);

      expect(plan.merges, isEmpty);
      expect(plan.aliases, isEmpty);
      expect(plan.ambiguities, hasLength(1));
      expect(plan.ambiguities.single.firstId, 'a-left');
      expect(plan.ambiguities.single.secondId, 'b-right');
      expect(plan.ambiguities.single.candidate.blob.id, 'b-right');
    },
  );

  test(
    'fresh attach queues ambiguity only between surviving choreography groups',
    () {
      final survivor = _danceCandidate(
        'a-survivor',
        'Shared dance',
        figures: const [
          {
            'move': 'balance',
            'params': {'hand': 'left'},
          },
        ],
      );
      final equalChoreography = _danceCandidate(
        'c-duplicate',
        'The SHARED DANCE',
        figures: const [
          {
            'move': 'balance',
            'params': {'hand': 'left'},
          },
        ],
      );
      final differentChoreography = _danceCandidate(
        'b-different',
        'shared dance',
        figures: const [
          {
            'move': 'balance',
            'params': {'hand': 'right'},
          },
        ],
      );

      final plan = planFreshAttachDedupe([
        survivor,
        equalChoreography,
        differentChoreography,
      ]);

      expect(plan.merges.single.losingIds, ['c-duplicate']);
      expect(
        plan.ambiguities.map(
          (ambiguity) => (ambiguity.firstId, ambiguity.secondId),
        ),
        [('a-survivor', 'b-different')],
      );
    },
  );

  test('fresh attach deduplicates citations by published source', () {
    final older = _danceCandidate(
      'a-older',
      'Shared dance',
      sourceCitations: const [
        {'sourceId': 'source-1', 'page': '1'},
      ],
    );
    final newer = _danceCandidate(
      'z-newer',
      'The shared dance',
      sourceCitations: const [
        {'sourceId': 'source-1', 'page': '2'},
      ],
      updatedSeconds: 1,
    );

    final plan = planFreshAttachDedupe([older, newer]);

    expect(plan.merges.single.winner.blob.body['sourceCitations'], [
      {'sourceId': 'source-1', 'page': '2'},
    ]);
  });

  test(
    'fresh attach keeps survivor provenance when the duplicate is newer',
    () {
      final older = _danceCandidate(
        'a-older',
        'Shared dance',
        provenance: const {'source': 'older'},
      );
      final newer = _danceCandidate(
        'z-newer',
        'The shared dance',
        updatedSeconds: 1,
        provenance: const {'source': 'newer'},
      );

      final plan = planFreshAttachDedupe([older, newer]);

      expect(plan.merges.single.winner.blob.body['provenance'], {
        'source': 'older',
      });
    },
  );

  test('keeps an unresolved baseline entry retryable', () {
    final address = _setting('theme_mode', 'local').address;
    final plan = engine.plan(
      local: {address: null},
      baseline: {
        address: const SyncBaselineEntry(
          kind: SyncRecordKind.setting,
          recordId: 'theme_mode',
          wireHash: 'baseline-hash',
        ),
      },
      peers: const [{}],
      unresolved: {address},
    );

    expect(plan.decisions, isEmpty);
  });

  test(
    'skips an unresolved address even when another peer has an older blob',
    () {
      final local = _setting('theme_mode', 'local', seconds: 2);
      final older = _setting('theme_mode', 'older');
      final address = local.address;
      final plan = engine.plan(
        local: {address: SyncMergeCandidate.fromBlob(local)},
        baseline: {
          address: SyncBaselineEntry(
            kind: address.kind,
            recordId: address.recordId,
            wireHash: SyncMergeCandidate.fromBlob(local).wireHash,
          ),
        },
        peers: [
          {address: SyncMergeCandidate.fromBlob(older)},
        ],
        unresolved: {address},
      );

      expect(plan.decisions, isEmpty);
      expect(plan.reports, isEmpty);
    },
  );

  test('takes the newest content across three peers', () {
    final local = _setting('theme_mode', 'local', seconds: 1);
    final older = _setting('theme_mode', 'older');
    final newest = _setting('theme_mode', 'newest', seconds: 3);
    final plan = engine.plan(
      local: {local.address: SyncMergeCandidate.fromBlob(local)},
      baseline: const {},
      peers: [
        {older.address: SyncMergeCandidate.fromBlob(older)},
        {newest.address: SyncMergeCandidate.fromBlob(newest)},
        {local.address: SyncMergeCandidate.fromBlob(local)},
      ],
    );

    expect(plan.decisions.single.action, SyncMergeAction.download);
    expect(plan.decisions.single.winner!.blob.body['value'], 'newest');
  });

  test('distinguishes all four both-present baseline rows', () {
    final baseline = _settingAt(
      'theme_mode',
      'baseline',
      updatedSeconds: 5,
      existenceSeconds: 0,
    );
    final baselineCandidate = SyncMergeCandidate.fromBlob(baseline);
    final baselineEntry = SyncBaselineEntry(
      kind: baseline.kind,
      recordId: baseline.id,
      wireHash: baselineCandidate.wireHash,
    );

    SyncMergePlan planFor(SyncRecordBlob local, SyncRecordBlob remote) =>
        engine.plan(
          local: {local.address: SyncMergeCandidate.fromBlob(local)},
          baseline: {local.address: baselineEntry},
          peers: [
            {remote.address: SyncMergeCandidate.fromBlob(remote)},
          ],
        );

    final sameSame = planFor(baseline, baseline);
    expect(sameSame.decisions.single.action, SyncMergeAction.none);

    final changedSame = planFor(
      _settingAt(
        'theme_mode',
        'local change',
        updatedSeconds: 1,
        existenceSeconds: 0,
      ),
      baseline,
    );
    expect(changedSame.decisions.single.action, SyncMergeAction.upload);
    expect(
      changedSame.decisions.single.winner!.blob.body['value'],
      'local change',
    );

    final sameChanged = planFor(
      baseline,
      _settingAt(
        'theme_mode',
        'remote change',
        updatedSeconds: 6,
        existenceSeconds: 0,
      ),
    );
    expect(sameChanged.decisions.single.action, SyncMergeAction.download);
    expect(
      sameChanged.decisions.single.winner!.blob.body['value'],
      'remote change',
    );

    final changedChanged = planFor(
      _settingAt(
        'theme_mode',
        'local conflict',
        updatedSeconds: 7,
        existenceSeconds: 0,
      ),
      _settingAt(
        'theme_mode',
        'remote conflict',
        updatedSeconds: 8,
        existenceSeconds: 0,
      ),
    );
    expect(changedChanged.decisions.single.action, SyncMergeAction.download);
    expect(
      changedChanged.decisions.single.winner!.blob.body['value'],
      'remote conflict',
    );
  });

  test(
    'converges three device manifests and baselines across interleaved passes',
    () {
      final address = (kind: SyncRecordKind.setting, recordId: 'theme_mode');
      final devices = [
        _SimulatedDevice(
          'device-a',
          SyncMergeCandidate.fromBlob(
            _settingAt(
              'theme_mode',
              'a-initial',
              updatedSeconds: 0,
              existenceSeconds: 0,
            ),
          ),
        ),
        _SimulatedDevice(
          'device-b',
          SyncMergeCandidate.fromBlob(
            _settingAt(
              'theme_mode',
              'b-initial',
              updatedSeconds: 1,
              existenceSeconds: 0,
            ),
          ),
        ),
        _SimulatedDevice(
          'device-c',
          SyncMergeCandidate.fromBlob(
            _settingAt(
              'theme_mode',
              'c-initial',
              updatedSeconds: 2,
              existenceSeconds: 0,
            ),
          ),
        ),
      ];

      for (final device in devices) {
        _runSimulatedPass(device, devices);
      }
      _expectConverged(devices, address, 'c-initial');

      devices[0].local[address] = SyncMergeCandidate.fromBlob(
        _settingAt(
          'theme_mode',
          'a-interleaved',
          updatedSeconds: 3,
          existenceSeconds: 0,
        ),
      );
      _runSimulatedPass(devices[0], devices);
      _runSimulatedPass(devices[1], devices);
      _runSimulatedPass(devices[2], devices);
      _runSimulatedPass(devices[0], devices);
      _expectConverged(devices, address, 'a-interleaved');

      devices[2].local[address] = SyncMergeCandidate.fromBlob(
        _settingAt(
          'theme_mode',
          'c-interleaved',
          updatedSeconds: 4,
          existenceSeconds: 0,
        ),
      );
      _runSimulatedPass(devices[2], devices);
      _runSimulatedPass(devices[0], devices);
      _runSimulatedPass(devices[1], devices);
      _runSimulatedPass(devices[2], devices);
      _expectConverged(devices, address, 'c-interleaved');
    },
  );

  test('resolves body content among candidates in the winning state', () {
    final local = _settingAt(
      'theme_mode',
      'local',
      updatedSeconds: 0,
      existenceSeconds: 0,
    );
    final newestBody = _settingAt(
      'theme_mode',
      'newest body',
      updatedSeconds: 3,
      existenceSeconds: 4,
      deleted: true,
    );
    final newestExistence = _settingAt(
      'theme_mode',
      'stale body',
      updatedSeconds: 2,
      existenceSeconds: 5,
      deleted: true,
    );
    final middle = _settingAt(
      'theme_mode',
      'middle body',
      updatedSeconds: 1,
      existenceSeconds: 2,
    );

    final plan = engine.plan(
      local: {local.address: SyncMergeCandidate.fromBlob(local)},
      baseline: {
        local.address: SyncBaselineEntry(
          kind: local.address.kind,
          recordId: local.address.recordId,
          wireHash: SyncMergeCandidate.fromBlob(local).wireHash,
        ),
      },
      peers: [
        {newestBody.address: SyncMergeCandidate.fromBlob(newestBody)},
        {newestExistence.address: SyncMergeCandidate.fromBlob(newestExistence)},
        {middle.address: SyncMergeCandidate.fromBlob(middle)},
      ],
    );

    final winner = plan.decisions.single.winner!;
    expect(plan.decisions.single.action, SyncMergeAction.download);
    expect(winner.blob.body['value'], 'newest body');
    expect(winner.updatedAt, newestBody.updatedAt);
    expect(winner.existenceAt, newestExistence.existenceAt);
    expect(winner.isDeleted, isTrue);
  });
}

final class _SimulatedDevice {
  _SimulatedDevice(this.id, SyncMergeCandidate initial)
    : local = {initial.address: initial},
      manifest = {initial.address: initial};

  final String id;
  final Map<SyncRecordAddress, SyncMergeCandidate?> local;
  final Map<SyncRecordAddress, SyncMergeCandidate?> manifest;
  final Map<SyncRecordAddress, SyncBaselineEntry> baseline = {};
}

void _runSimulatedPass(
  _SimulatedDevice device,
  List<_SimulatedDevice> devices,
) {
  final peers = [
    for (final peer in devices)
      if (peer.id != device.id) peer.manifest,
  ];
  final plan = const SyncMergeEngine().plan(
    local: device.local,
    baseline: device.baseline,
    peers: peers,
  );
  for (final decision in plan.decisions) {
    switch (decision.action) {
      case SyncMergeAction.download:
        if (decision.winner != null) {
          device.local[decision.address] = decision.winner;
        }
      case SyncMergeAction.dropBaseline:
        device.local.remove(decision.address);
      case SyncMergeAction.none:
      case SyncMergeAction.upload:
      case SyncMergeAction.report:
      case SyncMergeAction.review:
        break;
    }
  }

  device.manifest
    ..clear()
    ..addAll(device.local);
  for (final decision in plan.decisions) {
    if (decision.action == SyncMergeAction.dropBaseline) {
      device.baseline.remove(decision.address);
    }
  }
  for (final entry in device.local.entries) {
    final candidate = entry.value;
    if (candidate == null) continue;
    if (!peers.any((peer) => peer[entry.key]?.wireHash == candidate.wireHash)) {
      continue;
    }
    device.baseline[entry.key] = SyncBaselineEntry(
      kind: candidate.blob.kind,
      recordId: candidate.blob.id,
      wireHash: candidate.wireHash,
      bodyHash: candidate.bodyHash,
    );
  }
}

void _expectConverged(
  List<_SimulatedDevice> devices,
  SyncRecordAddress address,
  String value,
) {
  expect(
    devices.map((device) => device.local[address]!.blob.body['value']),
    everyElement(value),
  );
  expect(
    devices.map((device) => device.manifest[address]!.wireHash).toSet(),
    hasLength(1),
  );
  expect(
    devices.map((device) => device.baseline[address]!.wireHash).toSet(),
    hasLength(1),
  );
}

SyncRecordBlob _setting(
  String id,
  String value, {
  int seconds = 0,
  bool deleted = false,
}) {
  final stamp = _baseTime.add(Duration(seconds: seconds));
  return SyncRecordBlob(
    kind: SyncRecordKind.setting,
    id: id,
    updatedAt: stamp,
    deletedAt: deleted ? stamp : null,
    existenceAt: stamp,
    body: {'value': value},
  );
}

SyncRecordBlob _settingAt(
  String id,
  String value, {
  required int updatedSeconds,
  required int existenceSeconds,
  bool deleted = false,
}) {
  final updatedAt = _baseTime.add(Duration(seconds: updatedSeconds));
  final existenceAt = _baseTime.add(Duration(seconds: existenceSeconds));
  return SyncRecordBlob(
    kind: SyncRecordKind.setting,
    id: id,
    updatedAt: updatedAt,
    deletedAt: deleted ? existenceAt : null,
    existenceAt: existenceAt,
    body: {'value': value},
  );
}

SyncRecordBlob _dance(String id, String title) => SyncRecordBlob(
  kind: SyncRecordKind.dance,
  id: id,
  updatedAt: _baseTime,
  deletedAt: null,
  existenceAt: _baseTime,
  body: {'id': id, 'title': title},
);

SyncMergeCandidate _danceCandidate(
  String id,
  String title, {
  List<Object?> figures = const [],
  String walkthrough = '',
  int? rating,
  List<String> authors = const [],
  List<String> tags = const [],
  List<Object?> sourceCitations = const [],
  Object? provenance,
  int updatedSeconds = 0,
  bool deleted = false,
}) {
  final updatedAt = _baseTime.add(Duration(seconds: updatedSeconds));
  return SyncMergeCandidate(
    blob: SyncRecordBlob(
      kind: SyncRecordKind.dance,
      id: id,
      updatedAt: updatedAt,
      deletedAt: deleted ? updatedAt : null,
      existenceAt: updatedAt,
      body: {
        'id': id,
        'title': title,
        'form': 'contra',
        'formation': {'shape': 'duple_improper'},
        'progression': 'single',
        'phraseStructure': '',
        'figures': figures,
        'hook': '',
        'callingNotes': '',
        'walkthrough': walkthrough,
        'status': 'active',
        'difficultyLevelId': null,
        'mixedLevel': false,
        'mixer': false,
        'rating': rating,
        'tunes': const [],
        'authorIds': authors,
        'customFields': const [],
        'tagIds': tags,
        'links': const [],
        'sourceCitations': sourceCitations,
        'provenance': provenance,
        'composedOn': null,
        'revisedOn': null,
        'createdAt': _baseTime.toIso8601String(),
      },
    ),
  );
}
