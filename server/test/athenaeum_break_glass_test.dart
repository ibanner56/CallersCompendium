import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Guards for the audited `--break-glass` read (SRV-7): what is read is
/// recorded before any byte is, an audit failure reads nothing, the audit
/// never holds content, and its linkable columns expire with the access row's.
///
/// Real files throughout, as `--break-glass` runs: a second connection to the
/// server's volume, with `athenaeum.sqlite` read-only.
void main() {
  late Directory dataDirectory;
  late AthenaeumConfig config;
  late AthenaeumStore server;
  late String epoch;
  const syncId = 'audited-breakglass-horse-staple';
  final manifestBody = Uint8List.fromList('manifest-bytes'.codeUnits);
  final blobBody = Uint8List.fromList('blob-content-bytes'.codeUnits);
  final blobHash = '3' * 64;

  String idKey() => deriveIncomingSyncIdKey(syncId, config.pepper);
  String logPath() => '${dataDirectory.path}/athenaeum-break-glass.sqlite';

  setUp(() {
    dataDirectory = Directory.systemTemp.createTempSync('athenaeum-bg-read-');
    config = AthenaeumConfig(
      dataDirectory: dataDirectory.path,
      pepper: List<int>.filled(32, 0x42),
    );
    server = AthenaeumStore(config: config);
    epoch = server.create(idKey()).epoch;
    server.putManifest(
      idKey: idKey(),
      epoch: epoch,
      deviceId: 'device-one',
      etag: 'etag-one',
      writtenAt: 1,
      body: manifestBody,
      referencedHashes: const [],
    );
    server.putBlob(
      idKey: idKey(),
      epoch: epoch,
      hash: blobHash,
      body: blobBody,
    );
  });

  tearDown(() {
    server.close();
    dataDirectory.deleteSync(recursive: true);
  });

  Future<({int code, List<int> output, String errors})> run(
    BreakGlassRead read, {
    String? input = syncId,
  }) async {
    final outFile = File('${dataDirectory.path}/out.bin');
    final errFile = File('${dataDirectory.path}/err.txt');
    final out = outFile.openWrite();
    final err = errFile.openWrite();
    final code = runBreakGlass(
      config,
      read: read,
      syncIdLine: input,
      output: out,
      errors: err,
    );
    await out.close();
    await err.close();
    final errors = errFile.readAsStringSync();
    // The terminal never sees the sync ID or the store key.
    expect(errors, isNot(contains(syncId)));
    expect(errors, isNot(contains(idKey())));
    return (code: code, output: outFile.readAsBytesSync(), errors: errors);
  }

  List<Map<String, Object?>> reads(Database log) => [
    for (final row in log.select(
      'SELECT kind, id_key, epoch, device_id, hash, accessed_at '
      'FROM break_glass_reads',
    ))
      {for (final column in row.keys) column: row[column]},
  ];

  int accessCount(Database log) =>
      log.select('SELECT COUNT(*) AS n FROM break_glass_access').single['n']
          as int;

  test('a manifest read records the store, device and resolved epoch, and '
      'writes only the manifest', () async {
    final result = await run(BreakGlassRead.manifest(deviceId: 'device-one'));
    expect(result.code, 0);
    expect(result.output, manifestBody);

    final log = sqlite3.open(logPath());
    addTearDown(log.close);
    expect(accessCount(log), 1);
    final row = reads(log).single;
    expect(row['kind'], 'manifest');
    expect(row['id_key'], idKey());
    expect(row['epoch'], epoch, reason: 'the current epoch is recorded');
    expect(row['device_id'], 'device-one');
    expect(row['hash'], isNull);
  });

  test('a blob read records the hash it read, never the content', () async {
    final result = await run(BreakGlassRead.blob(hash: blobHash, epoch: epoch));
    expect(result.code, 0);
    expect(result.output, blobBody);

    final log = sqlite3.open(logPath());
    addTearDown(log.close);
    final row = reads(log).single;
    expect(row['kind'], 'blob');
    expect(row['hash'], blobHash);
    expect(row['epoch'], epoch);
    expect(row['device_id'], isNull);
    // No column of either audit table holds the bytes read.
    for (final table in ['break_glass_access', 'break_glass_reads']) {
      for (final values in log.select('SELECT * FROM $table')) {
        for (final value in values.values) {
          expect(value, isNot(isA<List<int>>()), reason: table);
          if (value is String) {
            expect(value, isNot(contains('blob-content')), reason: table);
          }
        }
      }
    }
  });

  test('a failed audit write reads and writes nothing', () async {
    final log = sqlite3.open(logPath());
    addTearDown(log.close);
    for (final table in breakGlassTableSchemas) {
      log.execute(table.createSql());
    }
    log.execute(
      'CREATE TRIGGER fail_read BEFORE INSERT ON break_glass_reads '
      "BEGIN SELECT RAISE(ABORT, 'audit unavailable'); END",
    );

    for (final read in [
      BreakGlassRead.manifest(deviceId: 'device-one'),
      BreakGlassRead.blob(hash: blobHash),
    ]) {
      final result = await run(read);
      expect(result.code, 1);
      expect(result.output, isEmpty);
      expect(result.errors, 'break-glass read failed (SqliteException)\n');
      // The access row is in the same transaction, so it is not left behind
      // claiming a read that never happened.
      expect(accessCount(log), 0);
    }
  });

  test('a failure recording the resolved epoch reads nothing', () async {
    final log = sqlite3.open(logPath());
    addTearDown(log.close);
    for (final table in breakGlassTableSchemas) {
      log.execute(table.createSql());
    }
    log.execute(
      'CREATE TRIGGER fail_epoch BEFORE UPDATE ON break_glass_reads '
      "BEGIN SELECT RAISE(ABORT, 'audit unavailable'); END",
    );

    final result = await run(BreakGlassRead.blob(hash: blobHash));
    expect(result.code, 1);
    expect(result.output, isEmpty);
  });

  test(
    'an unknown store or item is still audited, and outputs nothing',
    () async {
      for (final (read, input) in [
        (BreakGlassRead.manifest(deviceId: 'device-one'), 'no-such-store-here'),
        (BreakGlassRead.manifest(deviceId: 'device-two'), syncId),
        (BreakGlassRead.blob(hash: '4' * 64), syncId),
      ]) {
        final result = await run(read, input: input);
        expect(result.code, 1);
        expect(result.output, isEmpty);
      }
      final log = sqlite3.open(logPath());
      addTearDown(log.close);
      expect(accessCount(log), 3);
      expect(reads(log), hasLength(3));
    },
  );

  test('empty input records nothing', () async {
    final result = await run(
      BreakGlassRead.manifest(deviceId: 'device-one'),
      input: '  ',
    );
    expect(result.code, 2);
    expect(result.output, isEmpty);
    final log = sqlite3.open(logPath());
    addTearDown(log.close);
    expect(accessCount(log), 0);
  });

  test('the read leaves athenaeum.sqlite untouched', () async {
    final before = server.database
        .select('SELECT last_seen FROM stores')
        .single['last_seen'];
    final result = await run(BreakGlassRead.blob(hash: blobHash));
    expect(result.code, 0);
    expect(
      server.database
          .select('SELECT last_seen FROM stores')
          .single['last_seen'],
      before,
    );
  });

  test('the retention sweep nulls what was read with the store key, keeping '
      'kind and time', () {
    final now = DateTime.utc(2026, 11, 11, 12);
    final store = AthenaeumStore.breakGlass(config: config);
    addTearDown(store.close);
    store.recordBreakGlassRead(
      syncId,
      BreakGlassRead.blob(hash: blobHash, epoch: epoch),
      accessedAt: now.subtract(const Duration(days: 31)),
    );
    store.recordBreakGlassRead(
      syncId,
      BreakGlassRead.manifest(deviceId: 'device-one', epoch: epoch),
      accessedAt: now.subtract(const Duration(days: 29)),
    );
    store.purgeExpiredBreakGlassAccess(now: now);

    final rows = [
      for (final row in store.breakGlassDatabase.select(
        'SELECT kind, id_key, epoch, device_id, hash FROM break_glass_reads '
        'ORDER BY accessed_at',
      ))
        {for (final column in row.keys) column: row[column]},
    ];
    expect(rows.first, {
      'kind': 'blob',
      'id_key': null,
      'epoch': null,
      'device_id': null,
      'hash': null,
    });
    expect(rows.last, {
      'kind': 'manifest',
      'id_key': idKey(),
      'epoch': epoch,
      'device_id': 'device-one',
      'hash': null,
    });
  });

  test('a read names exactly one valid item', () {
    expect(
      () => BreakGlassRead.blob(hash: 'not-a-hash'),
      throwsFormatException,
    );
    expect(
      () => BreakGlassRead.blob(hash: blobHash, epoch: 'bad'),
      throwsFormatException,
    );
    expect(
      () => BreakGlassRead.manifest(deviceId: 'has spaces'),
      throwsFormatException,
    );
  });
}
