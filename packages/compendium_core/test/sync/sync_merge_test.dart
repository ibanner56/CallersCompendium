import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

final _baseTime = DateTime.utc(2026, 7, 15, 12);

extension on SyncRecordBlob {
  SyncRecordAddress get address => (kind: kind, recordId: id);
}

void main() {
  const engine = SyncMergeEngine();

  test('covers the total baseline table, including both-side absence', () {
    final baselineBlob = _setting('custom_dialects', 'baseline');
    final changedLocal = _setting('custom_dialects', 'local', seconds: 1);
    final remote = _setting('custom_dialects', 'remote', seconds: 2);
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
    final setting = _setting('custom_dialects', 'setting');
    final dance = _dance('custom_dialects', 'dance');
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

  test('reports equal updatedAt bodies without choosing either', () {
    final local = _setting('custom_dialects', 'local');
    final remote = _setting('custom_dialects', 'remote');
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

  test('guards an unequal tombstone over a baseline-absent setting', () {
    final local = _setting('custom_dialects', 'local');
    final tombstone = _setting(
      'custom_dialects',
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
      final local = _setting('custom_dialects', 'local');
      final tombstone = _setting('custom_dialects', 'remote', deleted: true);
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

  test('keeps an unresolved baseline entry retryable', () {
    final address = _setting('custom_dialects', 'local').address;
    final plan = engine.plan(
      local: {address: null},
      baseline: {
        address: const SyncBaselineEntry(
          kind: SyncRecordKind.setting,
          recordId: 'custom_dialects',
          wireHash: 'baseline-hash',
        ),
      },
      peers: const [{}],
      unresolved: {address},
    );

    expect(plan.decisions, isEmpty);
  });

  test('takes the newest content across three peers', () {
    final local = _setting('custom_dialects', 'local', seconds: 1);
    final older = _setting('custom_dialects', 'older');
    final newest = _setting('custom_dialects', 'newest', seconds: 3);
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

SyncRecordBlob _dance(String id, String title) => SyncRecordBlob(
  kind: SyncRecordKind.dance,
  id: id,
  updatedAt: _baseTime,
  deletedAt: null,
  existenceAt: _baseTime,
  body: {'id': id, 'title': title},
);
