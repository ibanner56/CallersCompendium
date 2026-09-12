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
      baseline: {
        local.address: SyncBaselineEntry(
          kind: local.address.kind,
          recordId: local.address.recordId,
          wireHash: SyncMergeCandidate.fromBlob(local).wireHash,
        ),
      },
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
      final tombstone = _setting('custom_dialects', 'local', deleted: true);
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

  test(
    'skips an unresolved address even when another peer has an older blob',
    () {
      final local = _setting('custom_dialects', 'local', seconds: 2);
      final older = _setting('custom_dialects', 'older');
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

  test('distinguishes all four both-present baseline rows', () {
    final baseline = _settingAt(
      'custom_dialects',
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
        'custom_dialects',
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
        'custom_dialects',
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
        'custom_dialects',
        'local conflict',
        updatedSeconds: 7,
        existenceSeconds: 0,
      ),
      _settingAt(
        'custom_dialects',
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
      final address = (
        kind: SyncRecordKind.setting,
        recordId: 'custom_dialects',
      );
      final devices = [
        _SimulatedDevice(
          'device-a',
          SyncMergeCandidate.fromBlob(
            _settingAt(
              'custom_dialects',
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
              'custom_dialects',
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
              'custom_dialects',
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
          'custom_dialects',
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
          'custom_dialects',
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
      'custom_dialects',
      'local',
      updatedSeconds: 0,
      existenceSeconds: 0,
    );
    final newestBody = _settingAt(
      'custom_dialects',
      'newest body',
      updatedSeconds: 3,
      existenceSeconds: 1,
    );
    final newestExistence = _settingAt(
      'custom_dialects',
      'stale body',
      updatedSeconds: 2,
      existenceSeconds: 5,
      deleted: true,
    );
    final middle = _settingAt(
      'custom_dialects',
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
    expect(winner.blob.body['value'], 'stale body');
    expect(winner.updatedAt, newestExistence.updatedAt);
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
