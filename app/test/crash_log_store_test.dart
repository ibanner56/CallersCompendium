import 'dart:io';

import 'package:compendium_app/src/diagnostics/crash_log_store.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

CrashLogRecord _record(int i) => CrashLogRecord(
  timestampUtc: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
  appVersion: '0.1.0',
  platform: 'testos',
  source: 'unit',
  errorType: 'StateError',
  errorMessage: 'boom $i with some padding to give the line a realistic size',
  stack: '#0 main (package:compendium_app/main.dart:$i:2)',
);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('crash_log_store_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  CrashLogStore storeWith({
    int maxFileBytes = 1 << 20,
    int maxRolledFiles = 3,
  }) => CrashLogStore(
    directoryProvider: () async => dir,
    maxFileBytes: maxFileBytes,
    maxRolledFiles: maxRolledFiles,
  );

  test('append then read returns records newest-first', () async {
    final store = storeWith();
    for (var i = 0; i < 3; i++) {
      await store.append(_record(i));
    }
    final records = await store.readRecords();
    expect(records.map((r) => r.errorMessage.split(' ')[1]), ['2', '1', '0']);
  });

  test(
    'rotates at the size cap and prunes beyond the retained budget',
    () async {
      // A tiny cap forces a rotation roughly every couple of records.
      final store = storeWith(maxFileBytes: 400, maxRolledFiles: 2);
      for (var i = 0; i < 40; i++) {
        await store.append(_record(i));
      }

      // Never more than the active log + the retained rolled files.
      final logFiles = dir
          .listSync()
          .whereType<File>()
          .where(
            (f) => f.uri.pathSegments.last.startsWith(CrashLogStore.baseName),
          )
          .toList();
      expect(logFiles.length, lessThanOrEqualTo(3));

      final records = await store.readRecords();
      // Pruning dropped the oldest records...
      expect(records.length, lessThan(40));
      expect(
        records.any((r) => r.errorMessage.contains('boom 0 ')),
        isFalse,
        reason: 'oldest record should have been pruned',
      );
      // ...but the newest is retained and comes first.
      expect(records.first.errorMessage, contains('boom 39 '));
    },
  );

  test('clear deletes the active log and every rolled file', () async {
    final store = storeWith(maxFileBytes: 400, maxRolledFiles: 2);
    for (var i = 0; i < 20; i++) {
      await store.append(_record(i));
    }
    expect(await store.readRecords(), isNotEmpty);

    await store.clear();

    expect(await store.readRecords(), isEmpty);
    final remaining = dir.listSync().whereType<File>().where(
      (f) => f.uri.pathSegments.last.startsWith(CrashLogStore.baseName),
    );
    expect(remaining, isEmpty);
  });

  test('reads tolerate malformed/partial trailing lines', () async {
    final store = storeWith();
    await store.append(_record(1));
    // Simulate a torn write / foreign line appended to the active log.
    final active = File('${dir.path}/${CrashLogStore.baseName}');
    await active.writeAsString('not json\n{partial', mode: FileMode.append);
    final records = await store.readRecords();
    expect(records, hasLength(1));
    expect(records.single.errorMessage, contains('boom 1 '));
  });
}
