import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

extension on SyncRecordBlob {
  SyncRecordAddress get address => (kind: kind, recordId: id);
}

void main() {
  test(
    'applies a shareable overlay without replacing local-only fields',
    () async {
      final storage = _MemoryApplyStorage({
        (kind: SyncRecordKind.setting, recordId: 'custom_dialects'): {
          'value': 'local',
          'deviceOnly': 'preserve',
        },
      });
      final blob = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        updatedAt: DateTime.utc(2026, 7, 15, 12),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 7, 15, 12),
        body: {'value': 'remote'},
      );

      final result = await const SyncApplyEngine().apply(
        candidates: [SyncMergeCandidate.fromBlob(blob)],
        storage: storage,
      );

      expect(result.applied, [blob.address]);
      expect(storage.records[blob.address], {
        'value': 'remote',
        'deviceOnly': 'preserve',
      });
      expect(storage.rebuilds, 1);
    },
  );

  test('does not rebuild derived indexes for a no-op apply', () async {
    final storage = _MemoryApplyStorage({});

    final result = await const SyncApplyEngine().apply(
      candidates: const [],
      storage: storage,
    );

    expect(result.applied, isEmpty);
    expect(storage.rebuilds, 0);
  });

  test('coalesces noncanonical reports separately for each peer', () {
    final sink = SyncReportSink();
    SyncReport report(String peerId, String message) => SyncReport(
      code: SyncReportCode.nonCanonicalWireBody,
      kind: SyncRecordKind.setting,
      recordId: 'custom_dialects',
      peerId: peerId,
      message: message,
    );

    sink
      ..add(report('peer-a', 'first'))
      ..add(report('peer-a', 'duplicate'))
      ..add(report('peer-b', 'second'));

    expect(sink.reports, hasLength(2));
    expect(sink.reports.map((value) => value.peerId), ['peer-a', 'peer-b']);
  });

  test(
    'malformed records do not abort valid records in the same batch',
    () async {
      final storage = _MemoryApplyStorage({});
      final valid = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        updatedAt: DateTime.utc(2026, 7, 15, 12),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 7, 15, 12),
        body: {'value': 'remote'},
      );

      final result = await const SyncApplyEngine().applyJson(
        blobs: [
          '{"v":1,"kind":"setting","id":"bad","updatedAt":"not-a-date",'
              '"deletedAt":null,"existenceAt":"2026-07-15T12:00:00.000Z",'
              '"body":{"value":"bad"}}',
          encodeSyncRecordBlob(valid),
        ],
        storage: storage,
      );

      expect(result.applied, [valid.address]);
      expect(
        result.reports.map((report) => report.code),
        contains(SyncReportCode.malformedRecord),
      );
    },
  );

  test(
    'refuses inbound records whose timestamps are more than a day ahead',
    () async {
      final storage = _MemoryApplyStorage({});
      final localNow = DateTime.utc(2026, 7, 15, 12);
      final future = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        updatedAt: localNow.add(const Duration(hours: 25)),
        deletedAt: null,
        existenceAt: localNow.add(const Duration(hours: 25)),
        body: {'value': 'future'},
      );
      final valid = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'default_program_band',
        updatedAt: localNow.add(const Duration(hours: 24)),
        deletedAt: null,
        existenceAt: localNow.add(const Duration(hours: 24)),
        body: {'value': 'valid'},
      );

      final result = await SyncApplyEngine(now: () => localNow).apply(
        candidates: [
          SyncMergeCandidate.fromBlob(future, peerId: 'peer-a'),
          SyncMergeCandidate.fromBlob(valid),
        ],
        storage: storage,
      );

      expect(result.applied, [valid.address]);
      expect(storage.records, {
        valid.address: {'value': 'valid'},
      });
      expect(result.reports, hasLength(1));
      expect(result.reports.single.code, SyncReportCode.malformedRecord);
      expect(result.reports.single.kind, future.kind);
      expect(result.reports.single.recordId, future.id);
      expect(result.reports.single.peerId, 'peer-a');
    },
  );

  test('does not adopt receive-only sync credentials', () async {
    final storage = _MemoryApplyStorage({
      (kind: SyncRecordKind.setting, recordId: 'sync_id'): {
        'value': 'local-credential',
      },
      (kind: SyncRecordKind.setting, recordId: 'sync_device_id'): {
        'value': 'local-device',
      },
    });

    final result = await const SyncApplyEngine().applyJson(
      blobs: [
        '{"v":1,"kind":"setting","id":"sync_id",'
            '"updatedAt":"2026-07-15T12:00:00.000Z","deletedAt":null,'
            '"existenceAt":"2026-07-15T12:00:00.000Z",'
            '"body":{"value":"peer-credential"}}',
        '{"v":1,"kind":"setting","id":"sync_device_id",'
            '"updatedAt":"2026-07-15T12:00:00.000Z","deletedAt":null,'
            '"existenceAt":"2026-07-15T12:00:00.000Z",'
            '"body":{"value":"peer-device"}}',
      ],
      storage: storage,
    );

    expect(result.applied, isEmpty);
    expect(
      storage.records[(
        kind: SyncRecordKind.setting,
        recordId: 'sync_id',
      )]?['value'],
      'local-credential',
    );
    expect(
      storage.records[(
        kind: SyncRecordKind.setting,
        recordId: 'sync_device_id',
      )]?['value'],
      'local-device',
    );
    expect(result.reports, hasLength(2));
    expect(
      result.reports.map((report) => report.code),
      everyElement(
        anyOf(
          SyncReportCode.invalidClassification,
          SyncReportCode.malformedRecord,
        ),
      ),
    );
  });

  test(
    'rejects noncanonical bodies without mutating the record or its peers',
    () async {
      final bad = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        updatedAt: DateTime.utc(2026, 7, 15, 12),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 7, 15, 12),
        body: {'value': 'e\u0301'},
      );
      final valid = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'default_program_band',
        updatedAt: DateTime.utc(2026, 7, 15, 12, 1),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 7, 15, 12, 1),
        body: {'value': 'remote'},
      );
      final storage = _MemoryApplyStorage({
        bad.address: {'value': 'local'},
      });

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate.fromBlob(bad, peerId: 'peer-a'),
          SyncMergeCandidate.fromBlob(valid, peerId: 'peer-a'),
        ],
        storage: storage,
      );

      expect(result.applied, [valid.address]);
      expect(storage.records[bad.address], {'value': 'local'});
      expect(result.reports, hasLength(1));
      expect(result.reports.single.code, SyncReportCode.nonCanonicalWireBody);
      expect(result.reports.single.peerId, 'peer-a');
      expect(
        result.reports.single.message,
        contains('Update the sending device'),
      );
    },
  );

  test(
    'admits timestamp projections and preserves their source blob',
    () async {
      final envelopeUpdatedAt = DateTime.utc(2026, 7, 15, 12);
      final envelopeDeletedAt = DateTime.utc(2026, 7, 15, 12, 1);
      final candidate = SyncRecordBlob(
        kind: SyncRecordKind.dance,
        id: 'projection-dance',
        updatedAt: envelopeUpdatedAt,
        deletedAt: envelopeDeletedAt,
        existenceAt: envelopeDeletedAt,
        body: {
          'id': 'projection-dance',
          'title': 'Projection dance',
          'updatedAt': DateTime.utc(2099, 1, 1).toIso8601String(),
          'deletedAt': DateTime.utc(2099, 1, 1, 1).toIso8601String(),
        },
      );
      final storage = _MemoryApplyStorage({});

      final result = await const SyncApplyEngine().apply(
        candidates: [SyncMergeCandidate.fromBlob(candidate)],
        storage: storage,
      );

      expect(result.reports, isEmpty);
      expect(result.applied, [candidate.address]);
      final source = storage.sourceBlobs[candidate.address];
      expect(source, isNotNull);
      expect(source!.body['updatedAt'], envelopeUpdatedAt.toIso8601String());
      expect(source.body['deletedAt'], envelopeDeletedAt.toIso8601String());
    },
  );

  test('rejects noncanonical candidates before batch reconciliation', () async {
    final bad = SyncRecordBlob(
      kind: SyncRecordKind.tag,
      id: 'noncanonical-tag',
      updatedAt: DateTime.utc(2026, 7, 15, 12),
      deletedAt: null,
      existenceAt: DateTime.utc(2026, 7, 15, 12),
      body: {'id': 'noncanonical-tag', 'name': 'Caf\u0065\u0301'},
    );
    final valid = SyncRecordBlob(
      kind: SyncRecordKind.setting,
      id: 'default_program_band',
      updatedAt: DateTime.utc(2026, 7, 15, 12, 1),
      deletedAt: null,
      existenceAt: DateTime.utc(2026, 7, 15, 12, 1),
      body: {'value': 'remote'},
    );
    final storage = _BatchProbeStorage();

    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate.fromBlob(bad),
        SyncMergeCandidate.fromBlob(valid),
      ],
      storage: storage,
    );

    expect(result.applied, [valid.address]);
    expect(storage.reconciledAddresses, [valid.address]);
    expect(storage.records.containsKey(bad.address), isFalse);
    expect(result.reports.single.code, SyncReportCode.nonCanonicalWireBody);
  });

  test('an interrupted apply rolls back every earlier record', () async {
    final firstAddress = (
      kind: SyncRecordKind.setting,
      recordId: 'custom_dialects',
    );
    final secondAddress = (
      kind: SyncRecordKind.setting,
      recordId: 'default_program_band',
    );
    final storage = _RollbackApplyStorage({
      firstAddress: {'value': 'before-first'},
      secondAddress: {'value': 'before-second'},
    }, failOnWrite: 2);
    final first = SyncRecordBlob(
      kind: SyncRecordKind.setting,
      id: firstAddress.recordId,
      updatedAt: DateTime.utc(2026, 7, 15, 12),
      deletedAt: null,
      existenceAt: DateTime.utc(2026, 7, 15, 12),
      body: {'value': 'after-first'},
    );
    final second = SyncRecordBlob(
      kind: SyncRecordKind.setting,
      id: secondAddress.recordId,
      updatedAt: DateTime.utc(2026, 7, 15, 12, 1),
      deletedAt: null,
      existenceAt: DateTime.utc(2026, 7, 15, 12, 1),
      body: {'value': 'after-second'},
    );

    await expectLater(
      const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate.fromBlob(first),
          SyncMergeCandidate.fromBlob(second),
        ],
        storage: storage,
      ),
      throwsA(isA<InterruptedApply>()),
    );

    expect(storage.records, {
      firstAddress: {'value': 'before-first'},
      secondAddress: {'value': 'before-second'},
    });
    expect(storage.rebuilds, 0);
  });

  test(
    'isolates an unavailable reference from valid records in the same batch',
    () async {
      final bad = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'custom_dialects',
        updatedAt: DateTime.utc(2026, 7, 15, 12),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 7, 15, 12),
        body: {'value': 'bad'},
      );
      final valid = SyncRecordBlob(
        kind: SyncRecordKind.setting,
        id: 'default_program_band',
        updatedAt: DateTime.utc(2026, 7, 15, 12, 1),
        deletedAt: null,
        existenceAt: DateTime.utc(2026, 7, 15, 12, 1),
        body: {'value': 'valid'},
      );
      final storage = _ReferenceFailureStorage(bad.address);

      final result = await const SyncApplyEngine().apply(
        candidates: [
          SyncMergeCandidate.fromBlob(bad),
          SyncMergeCandidate.fromBlob(valid),
        ],
        storage: storage,
      );

      expect(result.applied, [valid.address]);
      expect(result.reports.single.code, SyncReportCode.unresolvedReference);
      expect(storage.records[valid.address], {'value': 'valid'});
    },
  );

  test('isolates normalized text collisions to one record', () async {
    final storage = _MemoryApplyStorage({});
    final collision = SyncRecordBlob(
      kind: SyncRecordKind.dance,
      id: 'collision',
      updatedAt: DateTime.utc(2026, 7, 15, 12),
      deletedAt: null,
      existenceAt: DateTime.utc(2026, 7, 15, 12),
      body: {
        'id': 'collision',
        'title': 'Collision',
        'figures': [
          {'e\u0301': 'first', '\u00e9': 'second'},
        ],
      },
    );
    final valid = SyncRecordBlob(
      kind: SyncRecordKind.setting,
      id: 'custom_dialects',
      updatedAt: DateTime.utc(2026, 7, 15, 12),
      deletedAt: null,
      existenceAt: DateTime.utc(2026, 7, 15, 12),
      body: {'value': 'remote'},
    );

    final result = await const SyncApplyEngine().apply(
      candidates: [
        SyncMergeCandidate.fromBlob(collision),
        SyncMergeCandidate.fromBlob(valid),
      ],
      storage: storage,
    );

    expect(result.applied, [valid.address]);
    expect(result.reports.single.code, SyncReportCode.malformedRecord);
  });
}

class _MemoryApplyStorage implements SyncApplyStorage {
  _MemoryApplyStorage(Map<SyncRecordAddress, Map<String, Object?>> records)
    : records = {
        for (final entry in records.entries)
          entry.key: Map<String, Object?>.from(entry.value),
      };

  final Map<SyncRecordAddress, Map<String, Object?>> records;
  final sourceBlobs = <SyncRecordAddress, SyncRecordBlob?>{};
  int rebuilds = 0;

  @override
  Future<T> transaction<T>(Future<T> Function() action) => action();

  @override
  Future<Map<String, Object?>?> read(SyncRecordAddress address) async =>
      records[address] == null ? null : Map.of(records[address]!);

  @override
  Future<void> write(SyncApplyRecord record) async {
    records[record.address] = Map.of(record.body);
    sourceBlobs[record.address] = record.sourceBlob;
  }

  @override
  Future<void> rebuildDerivedIndexes() async {
    rebuilds++;
  }
}

final class InterruptedApply implements Exception {
  const InterruptedApply();
}

final class _RollbackApplyStorage extends _MemoryApplyStorage {
  _RollbackApplyStorage(super.records, {required this.failOnWrite});

  final int failOnWrite;
  var writes = 0;

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    final snapshot = {
      for (final entry in records.entries) entry.key: Map.of(entry.value),
    };
    try {
      return await action();
    } catch (_) {
      records
        ..clear()
        ..addAll({
          for (final entry in snapshot.entries) entry.key: Map.of(entry.value),
        });
      rethrow;
    }
  }

  @override
  Future<void> write(SyncApplyRecord record) async {
    writes++;
    if (writes == failOnWrite) throw const InterruptedApply();
    await super.write(record);
  }
}

final class _ReferenceFailureStorage extends _MemoryApplyStorage {
  _ReferenceFailureStorage(this.unavailableAddress) : super({});

  final SyncRecordAddress unavailableAddress;

  @override
  Future<void> write(SyncApplyRecord record) {
    if (record.address == unavailableAddress) {
      throw StateError('unavailable reference');
    }
    return super.write(record);
  }
}

final class _BatchProbeStorage extends _MemoryApplyStorage
    implements SyncApplyReconciliationStorage {
  _BatchProbeStorage() : super({});

  final reconciledAddresses = <SyncRecordAddress>[];

  @override
  Future<SyncApplyPreparation> reconcileInbound(
    List<SyncMergeCandidate> candidates, {
    Map<SyncRecordAddress, String?>? expectedWireHashes,
  }) async {
    reconciledAddresses.addAll([
      for (final candidate in candidates) candidate.address,
    ]);
    return SyncApplyPreparation(candidates: candidates);
  }

  @override
  Future<SyncReport?> validateInboundReferences(
    SyncApplyRecord record, {
    Set<SyncRecordAddress> inboundLiveAddresses = const {},
    Set<SyncRecordAddress> inboundAddresses = const {},
    Map<SyncRecordAddress, SyncApplyRecord> inboundRecords = const {},
  }) async => null;

  @override
  Future<SyncReport?> writeWithReport(SyncApplyRecord record) async {
    await write(record);
    return null;
  }

  @override
  Future<SyncReport?> writeParentWithReport(SyncApplyRecord record) =>
      writeWithReport(record);

  @override
  Future<SyncReport?> writeJoinsWithReport(SyncApplyRecord record) async =>
      null;

  @override
  Future<void> setInboundTombstoneContext(
    Set<SyncRecordAddress> tombstonedAddresses,
  ) async {}

  @override
  Future<void> clearReconciliationContext() async {}
}
