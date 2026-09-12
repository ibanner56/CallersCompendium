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
  int rebuilds = 0;

  @override
  Future<T> transaction<T>(Future<T> Function() action) => action();

  @override
  Future<Map<String, Object?>?> read(SyncRecordAddress address) async =>
      records[address] == null ? null : Map.of(records[address]!);

  @override
  Future<void> write(SyncApplyRecord record) async {
    records[record.address] = Map.of(record.body);
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
