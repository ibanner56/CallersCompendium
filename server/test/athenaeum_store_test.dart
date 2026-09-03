import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('cleanup retry queues have ordered selection indexes', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-queue-index-test-',
    );
    final database = sqlite3.openInMemory();
    final breakGlassDatabase = sqlite3.openInMemory();
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: breakGlassDatabase,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final indexes = database
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name IN ('deletion_jobs_queued_at_idx', "
          "'blob_deletion_jobs_queued_at_idx', 'stores_last_seen_idx')",
        )
        .map((row) => row['name'] as String)
        .toSet();
    expect(
      indexes,
      equals({
        'deletion_jobs_queued_at_idx',
        'blob_deletion_jobs_queued_at_idx',
        'stores_last_seen_idx',
      }),
    );
    final breakGlassIndexes = breakGlassDatabase
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'break_glass_access_linkable_idx'",
        )
        .map((row) => row['name'] as String)
        .toSet();
    expect(breakGlassIndexes, {'break_glass_access_linkable_idx'});
  });

  test('ref-protected directory jobs rotate behind eligible jobs', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-directory-queue-rotation-',
    );
    final database = sqlite3.openInMemory();
    var attempts = 0;
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      deleteDirectory: (_) {
        attempts++;
        throw const FileSystemException('injected directory failure');
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    for (var index = 0; index < maxPendingDeletionRetriesPerRequest; index++) {
      final idKey = index.toRadixString(16).padLeft(64, '0');
      final epoch = 'protected-$index';
      database.execute(
        'INSERT INTO blob_refs (id_key, epoch, hash, size, uploaded_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [idKey, epoch, 'a' * 64, 1, 0],
      );
      database.execute(
        'INSERT INTO deletion_jobs (id_key, epoch, queued_at) VALUES (?, ?, ?)',
        [idKey, epoch, 0],
      );
    }
    database.execute(
      'INSERT INTO deletion_jobs (id_key, epoch, queued_at) VALUES (?, ?, ?)',
      ['f' * 64, 'eligible', 0],
    );

    store.retryPendingDeletions(maxJobs: maxPendingDeletionRetriesPerRequest);
    expect(attempts, 0);
    store.retryPendingDeletions(maxJobs: maxPendingDeletionRetriesPerRequest);
    expect(attempts, 1);
  });

  test('duplicate blob uploads preserve the original uploaded timestamp', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = '0' * 64;
    final created = store.create(idKey);
    final hash = '1' * 64;
    final body = Uint8List.fromList([2]);
    expect(
      store.putBlob(idKey: idKey, epoch: created.epoch, hash: hash, body: body),
      isTrue,
    );
    final first = store.blobRef(idKey, created.epoch, hash)!;
    expect(
      store.putBlob(idKey: idKey, epoch: created.epoch, hash: hash, body: body),
      isFalse,
    );
    final second = store.blobRef(idKey, created.epoch, hash)!;
    expect(second.uploadedAt, first.uploadedAt);
    database.execute(
      'UPDATE blob_refs SET uploaded_at = ? WHERE id_key = ? AND epoch = ?',
      [123, idKey, created.epoch],
    );
    expect(
      store.putBlob(idKey: idKey, epoch: created.epoch, hash: hash, body: body),
      isFalse,
    );
    expect(store.blobRef(idKey, created.epoch, hash)!.uploadedAt, 123);
  });

  test('garbage collection preserves reachable and recent blobs', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final breakGlassDatabase = sqlite3.openInMemory();
    var now = DateTime.utc(2026, 9, 3, 12);
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: breakGlassDatabase,
      clock: () => now,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = '0' * 64;
    final created = store.create(idKey);
    final reachableHash = '1' * 64;
    final staleHash = '2' * 64;
    final recentHash = '3' * 64;
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: reachableHash,
      body: Uint8List.fromList([1]),
    );
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: staleHash,
      body: Uint8List.fromList([2]),
    );
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: recentHash,
      body: Uint8List.fromList([3]),
    );
    final manifestBody = utf8.encode(
      '{"records":{"dance":{"one":"$reachableHash"}}}',
    );
    store.putManifest(
      idKey: idKey,
      epoch: created.epoch,
      deviceId: 'device-one',
      etag: '4' * 64,
      writtenAt: now.millisecondsSinceEpoch ~/ 1000,
      body: Uint8List.fromList(manifestBody),
    );
    database.execute(
      'UPDATE blob_refs SET uploaded_at = ? '
      'WHERE id_key = ? AND epoch = ? AND hash = ?',
      [
        (now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000),
        idKey,
        created.epoch,
        staleHash,
      ],
    );

    store.collectGarbage(idKey, created.epoch, now: now);
    expect(
      store.blobFile(idKey, created.epoch, reachableHash).existsSync(),
      isTrue,
    );
    expect(
      store.blobFile(idKey, created.epoch, staleHash).existsSync(),
      isFalse,
    );
    expect(
      store.blobFile(idKey, created.epoch, recentHash).existsSync(),
      isTrue,
    );

    now = now.add(const Duration(hours: 25));
    expect(
      store.putBlob(
        idKey: idKey,
        epoch: created.epoch,
        hash: recentHash,
        body: Uint8List.fromList([3]),
      ),
      isFalse,
    );
    store.collectGarbage(idKey, created.epoch, now: now);
    expect(
      store.blobFile(idKey, created.epoch, reachableHash).existsSync(),
      isTrue,
    );
    expect(
      store.blobFile(idKey, created.epoch, recentHash).existsSync(),
      isFalse,
    );
  });

  test(
    'garbage collection skips manifest parsing without stale candidates',
    () {
      final dataDirectory = Directory.systemTemp.createTempSync(
        'athenaeum-gc-empty-candidates-',
      );
      final database = sqlite3.openInMemory();
      final store = AthenaeumStore(
        config: AthenaeumConfig(
          dataDirectory: dataDirectory.path,
          pepper: List<int>.filled(32, 0x42),
        ),
        database: database,
      );
      addTearDown(() {
        store.close();
        dataDirectory.deleteSync(recursive: true);
      });

      final idKey = '0' * 64;
      final epoch = 'epoch-without-stale-blobs';
      database.execute(
        'INSERT INTO manifests '
        '(id_key, epoch, device_id, etag, written_at, body) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          idKey,
          epoch,
          'device-one',
          '1' * 64,
          0,
          Uint8List.fromList([0xff]),
        ],
      );

      expect(() => store.collectGarbage(idKey, epoch), returnsNormally);
    },
  );

  test('garbage collection rolls back metadata without losing files', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final breakGlassDatabase = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: breakGlassDatabase,
      clock: () => now,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });
    final idKey = '4' * 64;
    final created = store.create(idKey);
    for (final hash in ['5' * 64, '6' * 64]) {
      store.putBlob(
        idKey: idKey,
        epoch: created.epoch,
        hash: hash,
        body: Uint8List.fromList([1]),
      );
    }
    database.execute('UPDATE blob_refs SET uploaded_at = ? WHERE id_key = ?', [
      now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
      idKey,
    ]);
    database.execute(
      'CREATE TRIGGER fail_blob_job BEFORE INSERT ON blob_deletion_jobs '
      "WHEN NEW.hash = '6${'6' * 63}' "
      "BEGIN SELECT RAISE(ABORT, 'injected job failure'); END",
    );

    expect(
      () => store.collectGarbage(idKey, created.epoch, now: now),
      throwsA(isA<SqliteException>()),
    );
    for (final hash in ['5' * 64, '6' * 64]) {
      expect(store.blobRef(idKey, created.epoch, hash), isNotNull);
      expect(store.blobFile(idKey, created.epoch, hash).existsSync(), isTrue);
    }
  });

  test('stale blob deletion jobs cannot remove a re-uploaded blob', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final breakGlassDatabase = sqlite3.openInMemory();
    var failDelete = true;
    final now = DateTime.utc(2026, 9, 3, 12);
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: breakGlassDatabase,
      clock: () => now,
      deleteFile: (file) {
        if (failDelete) {
          throw const FileSystemException('injected file failure');
        }
        file.deleteSync();
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });
    final idKey = '7' * 64;
    final created = store.create(idKey);
    final hash = '8' * 64;
    final body = Uint8List.fromList([1]);
    store.putBlob(idKey: idKey, epoch: created.epoch, hash: hash, body: body);
    database.execute('UPDATE blob_refs SET uploaded_at = ? WHERE id_key = ?', [
      now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
      idKey,
    ]);
    store.collectGarbage(idKey, created.epoch, now: now);
    expect(database.select('SELECT * FROM blob_deletion_jobs'), hasLength(1));

    failDelete = false;
    expect(
      store.putBlob(idKey: idKey, epoch: created.epoch, hash: hash, body: body),
      isTrue,
    );
    store.retryPendingBlobDeletions();
    expect(store.blobRef(idKey, created.epoch, hash), isNotNull);
    expect(store.blobFile(idKey, created.epoch, hash).existsSync(), isTrue);
    expect(database.select('SELECT * FROM blob_deletion_jobs'), isEmpty);
  });

  test('diagnostic storage is indexed and bounded', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final breakGlassDatabase = sqlite3.openInMemory();
    final diagnosticDatabase = sqlite3.openInMemory();
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: breakGlassDatabase,
      diagnosticDatabase: diagnosticDatabase,
      diagnosticRowLimit: 1,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    store.recordDiagnostic(status: 400, idKey: '1' * 64, hash: '2' * 64);
    store.recordDiagnostic(status: 413, idKey: '3' * 64, hash: '4' * 64);

    expect(
      diagnosticDatabase
          .select('SELECT COUNT(*) AS count FROM diagnostic_events')
          .single['count'],
      1,
    );
    expect(
      diagnosticDatabase.select(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'diagnostic_events_recorded_at_idx'",
      ),
      hasLength(1),
    );
  });

  test('stale-epoch uploads still consume store quota', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final breakGlassDatabase = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: breakGlassDatabase,
      clock: () => now,
      quotaLimits: const AthenaeumQuotaLimits(maxBytes: 1),
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });
    final idKey = 'a' * 64;
    final first = store.create(idKey);
    store.deleteStore(idKey);
    final recreated = store.create(idKey);

    expect(
      store.putBlob(
        idKey: idKey,
        epoch: first.epoch,
        hash: 'b' * 64,
        body: Uint8List.fromList([1]),
      ),
      isTrue,
    );
    expect(
      () => store.putBlob(
        idKey: idKey,
        epoch: recreated.epoch,
        hash: 'c' * 64,
        body: Uint8List.fromList([2]),
      ),
      throwsA(isA<StoreQuotaExceeded>()),
    );
    final staleFile = store.blobFile(idKey, first.epoch, 'b' * 64);
    expect(staleFile.existsSync(), isTrue);
    store.sweep(now: now.add(const Duration(hours: 25)));
    expect(staleFile.existsSync(), isFalse);
  });

  test('sweep removes stores past the rolling disuse TTL', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final breakGlassDatabase = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: breakGlassDatabase,
      clock: () => now,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });
    final idKey = 'a' * 64;
    final created = store.create(idKey);
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: 'b' * 64,
      body: Uint8List.fromList([1]),
    );
    database.execute('UPDATE stores SET last_seen = ? WHERE id_key = ?', [
      now.subtract(const Duration(days: 31)).millisecondsSinceEpoch ~/ 1000,
      idKey,
    ]);

    store.sweep(now: now);

    expect(store.lookup(idKey), isNull);
    expect(
      store.blobFile(idKey, created.epoch, 'b' * 64).existsSync(),
      isFalse,
    );
  });

  test('break-glass access uses a separate expiring HMAC-keyed database', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final breakGlassDatabase = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    final pepper = List<int>.filled(32, 0x42);
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: pepper,
      ),
      database: database,
      breakGlassDatabase: breakGlassDatabase,
      clock: () => now,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    const syncId = 'café-horse-battery-staple';
    store.recordBreakGlassAccess(syncId);
    final rows = breakGlassDatabase.select(
      'SELECT id_key, accessed_at FROM break_glass_access',
    );
    expect(rows, hasLength(1));
    expect(rows.single['id_key'], deriveIncomingSyncIdKey(syncId, pepper));
    expect(rows.single['id_key'], isNot(syncId));
    expect(rows.single['accessed_at'], now.millisecondsSinceEpoch ~/ 1000);

    breakGlassDatabase.execute(
      'UPDATE break_glass_access SET accessed_at = ?',
      [now.subtract(const Duration(days: 31)).millisecondsSinceEpoch ~/ 1000],
    );
    store.purgeExpiredBreakGlassAccess(now: now);
    expect(
      breakGlassDatabase
          .select('SELECT id_key FROM break_glass_access')
          .single['id_key'],
      isNull,
    );

    store.recordDiagnostic(
      status: 400,
      idKey: '1' * 64,
      hash: '2' * 64,
      recordedAt: now,
    );
    store.sweep(now: now.add(const Duration(days: 31)));
    expect(
      store.diagnosticDatabase.select('SELECT * FROM diagnostic_events'),
      isEmpty,
    );
  });

  test('aggregate device and byte quotas reject before allocation', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final breakGlassDatabase = sqlite3.openInMemory();
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: breakGlassDatabase,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });
    final idKey = 'c' * 64;
    final created = store.create(idKey);
    for (var index = 0; index < maxStoreDevices; index++) {
      store.putManifest(
        idKey: idKey,
        epoch: created.epoch,
        deviceId: 'device-$index',
        etag: 'd' * 64,
        writtenAt: 0,
        body: Uint8List.fromList([1]),
      );
    }
    expect(
      () => store.putManifest(
        idKey: idKey,
        epoch: created.epoch,
        deviceId: 'device-over-cap',
        etag: 'e' * 64,
        writtenAt: 0,
        body: Uint8List.fromList([1]),
      ),
      throwsA(isA<StoreQuotaExceeded>()),
    );

    database.execute('UPDATE stores SET bytes_used = ? WHERE id_key = ?', [
      maxStoreBytes,
      idKey,
    ]);
    final hash = 'f' * 64;
    expect(
      () => store.putBlob(
        idKey: idKey,
        epoch: created.epoch,
        hash: hash,
        body: Uint8List.fromList([1]),
      ),
      throwsA(isA<StoreQuotaExceeded>()),
    );
    expect(store.blobFile(idKey, created.epoch, hash).existsSync(), isFalse);
  });

  test('store deletion rolls back all metadata when a delete fails', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = 'a' * 64;
    final created = store.create(idKey);
    store.putManifest(
      idKey: idKey,
      epoch: created.epoch,
      deviceId: 'device-one',
      etag: 'b' * 64,
      writtenAt: 0,
      body: Uint8List.fromList([1]),
    );
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: 'c' * 64,
      body: Uint8List.fromList([2]),
    );
    database.execute(
      'CREATE TRIGGER fail_blob_delete BEFORE DELETE ON blob_refs '
      "BEGIN SELECT RAISE(ABORT, 'injected delete failure'); END",
    );
    expect(() => store.deleteStore(idKey), throwsA(isA<SqliteException>()));
    expect(store.lookup(idKey), isNotNull);
    expect(store.manifest(idKey, created.epoch, 'device-one'), isNotNull);
  });

  test('store deletion remains successful when post-commit cleanup fails', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-delete-cleanup-',
    );
    final database = sqlite3.openInMemory();
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      deleteDirectory: (directory) => directory.deleteSync(recursive: true),
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = 'b' * 64;
    final created = store.create(idKey);
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: 'c' * 64,
      body: Uint8List.fromList([1]),
    );
    database.execute(
      'CREATE TRIGGER fail_cleanup_job_delete '
      'BEFORE DELETE ON deletion_jobs '
      "BEGIN SELECT RAISE(ABORT, 'injected cleanup failure'); END",
    );

    expect(() => store.deleteStore(idKey), returnsNormally);
    expect(store.lookup(idKey), isNull);
    expect(database.select('SELECT * FROM deletion_jobs'), hasLength(1));
  });

  test('filesystem deletion failures remain queued for retry', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    var failDelete = true;
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      deleteDirectory: (directory) {
        if (failDelete) {
          throw const FileSystemException('injected filesystem failure');
        }
        directory.deleteSync(recursive: true);
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = 'd' * 64;
    final created = store.create(idKey);
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: 'e' * 64,
      body: Uint8List.fromList([2]),
    );
    final blobFile = store.blobFile(idKey, created.epoch, 'e' * 64);

    store.deleteStore(idKey);
    expect(blobFile.existsSync(), isTrue);
    expect(database.select('SELECT * FROM deletion_jobs'), hasLength(1));
    expect(store.lookup(idKey), isNull);

    final recreated = store.create(idKey);
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: 'e' * 64,
      body: Uint8List.fromList([3]),
    );
    store.putBlob(
      idKey: idKey,
      epoch: recreated.epoch,
      hash: 'f' * 64,
      body: Uint8List.fromList([4]),
    );
    store.deleteStore(idKey);
    expect(database.select('SELECT * FROM deletion_jobs'), hasLength(2));

    failDelete = false;
    store.retryPendingDeletions();
    expect(blobFile.existsSync(), isFalse);
    expect(database.select('SELECT * FROM deletion_jobs'), isEmpty);
  });

  test('failed blob deletion remains charged against the byte quota', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-pending-quota-',
    );
    final database = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      clock: () => now,
      quotaLimits: const AthenaeumQuotaLimits(maxBytes: 3),
      deleteFile: (_) {
        throw const FileSystemException('injected file failure');
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });
    final idKey = '1' * 64;
    final created = store.create(idKey);
    final hash = '2' * 64;
    final body = Uint8List.fromList([1, 2, 3]);
    store.putBlob(idKey: idKey, epoch: created.epoch, hash: hash, body: body);
    database.execute('UPDATE blob_refs SET uploaded_at = ? WHERE id_key = ?', [
      now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
      idKey,
    ]);
    store.collectGarbage(idKey, created.epoch, now: now);
    expect(store.blobFile(idKey, created.epoch, hash).existsSync(), isTrue);
    final metadata = store.metadata(store.lookup(idKey)!);
    expect(metadata.blobs, 1);
    expect(metadata.bytes, 3);
    expect(
      store.putBlob(idKey: idKey, epoch: created.epoch, hash: hash, body: body),
      isTrue,
    );
    expect(
      () => store.putBlob(
        idKey: idKey,
        epoch: created.epoch,
        hash: '3' * 64,
        body: Uint8List.fromList([4]),
      ),
      throwsA(isA<StoreQuotaExceeded>()),
    );
  });

  test('failed store deletion remains charged across recreation', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-pending-store-quota-',
    );
    final database = sqlite3.openInMemory();
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      quotaLimits: const AthenaeumQuotaLimits(maxBlobs: 1, maxBytes: 100),
      deleteDirectory: (_) {
        throw const FileSystemException('injected directory failure');
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = '6' * 64;
    final first = store.create(idKey);
    final hash = '7' * 64;
    store.putBlob(
      idKey: idKey,
      epoch: first.epoch,
      hash: hash,
      body: Uint8List.fromList([1, 2, 3]),
    );
    store.deleteStore(idKey);
    final recreated = store.create(idKey);

    final metadata = store.metadata(recreated);
    expect(metadata.blobs, 1);
    expect(metadata.bytes, 3);
    expect(
      () => store.putBlob(
        idKey: idKey,
        epoch: recreated.epoch,
        hash: '8' * 64,
        body: Uint8List.fromList([4]),
      ),
      throwsA(isA<StoreQuotaExceeded>()),
    );
  });

  test('same-epoch replacement excludes a pending directory file', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-pending-replacement-quota-',
    );
    final database = sqlite3.openInMemory();
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      quotaLimits: const AthenaeumQuotaLimits(maxBlobs: 1, maxBytes: 3),
      deleteDirectory: (_) {
        throw const FileSystemException('injected directory failure');
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = '8' * 64;
    final created = store.create(idKey);
    final hash = '9' * 64;
    final body = Uint8List.fromList([1, 2, 3]);
    store.putBlob(idKey: idKey, epoch: created.epoch, hash: hash, body: body);
    store.deleteStore(idKey);
    store.create(idKey);

    expect(
      store.putBlob(idKey: idKey, epoch: created.epoch, hash: hash, body: body),
      isTrue,
    );
  });

  test('overlapping blob and store deletion jobs charge a file once', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-overlapping-deletion-quota-',
    );
    final database = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      clock: () => now,
      quotaLimits: const AthenaeumQuotaLimits(maxBlobs: 2, maxBytes: 4),
      deleteDirectory: (_) {
        throw const FileSystemException('injected directory failure');
      },
      deleteFile: (_) {
        throw const FileSystemException('injected file failure');
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = 'b' * 64;
    final created = store.create(idKey);
    final hash = 'c' * 64;
    store.putBlob(
      idKey: idKey,
      epoch: created.epoch,
      hash: hash,
      body: Uint8List.fromList([1, 2, 3]),
    );
    database.execute('UPDATE blob_refs SET uploaded_at = ? WHERE id_key = ?', [
      now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
      idKey,
    ]);
    store.collectGarbage(idKey, created.epoch, now: now);
    store.deleteStore(idKey);
    final recreated = store.create(idKey);

    final metadata = store.metadata(recreated);
    expect(metadata.blobs, 1);
    expect(metadata.bytes, 3);
    expect(
      store.putBlob(
        idKey: idKey,
        epoch: recreated.epoch,
        hash: 'd' * 64,
        body: Uint8List.fromList([4]),
      ),
      isTrue,
    );
  });

  test('request-path deletion retries are bounded', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-retry-bound-',
    );
    final database = sqlite3.openInMemory();
    var attempts = 0;
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      deleteFile: (_) {
        attempts++;
        throw const FileSystemException('injected file failure');
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = '9' * 64;
    final created = store.create(idKey);
    final uploadedAt =
        DateTime.now()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch ~/
        1000;
    for (
      var index = 0;
      index < maxPendingDeletionRetriesPerRequest + 1;
      index++
    ) {
      final hash = index.toRadixString(16).padLeft(64, '0');
      store.putBlob(
        idKey: idKey,
        epoch: created.epoch,
        hash: hash,
        body: Uint8List.fromList([index]),
      );
    }
    database.execute('UPDATE blob_refs SET uploaded_at = ? WHERE id_key = ?', [
      uploadedAt,
      idKey,
    ]);
    store.collectGarbage(idKey, created.epoch);
    expect(attempts, maxPendingDeletionRetriesPerRequest);
    attempts = 0;

    store.retryPendingDeletions();

    expect(attempts, maxPendingDeletionRetriesPerRequest);
    expect(database.select('SELECT * FROM blob_deletion_jobs'), hasLength(17));
  });

  test('sweep drains the blob retry backlog once after epoch collection', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-sweep-retry-bound-',
    );
    final database = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    var attempts = 0;
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      clock: () => now,
      deleteFile: (_) {
        attempts++;
        throw const FileSystemException('injected file failure');
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    for (var storeIndex = 0; storeIndex < 2; storeIndex++) {
      final idKey = (storeIndex == 0 ? '2' : '3') * 64;
      final created = store.create(idKey);
      for (
        var index = 0;
        index < maxPendingDeletionRetriesPerRequest + 1;
        index++
      ) {
        final hash = (storeIndex * 32 + index)
            .toRadixString(16)
            .padLeft(64, '0');
        store.putBlob(
          idKey: idKey,
          epoch: created.epoch,
          hash: hash,
          body: Uint8List.fromList([index]),
        );
      }
      database.execute(
        'UPDATE blob_refs SET uploaded_at = ? WHERE id_key = ?',
        [
          now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
          idKey,
        ],
      );
    }

    store.sweep(now: now);

    expect(attempts, 2 * (maxPendingDeletionRetriesPerRequest + 1));
  });

  test('sweep drains the global retry queue once after expired stores', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-sweep-store-retry-bound-',
    );
    final database = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    var attempts = 0;
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      clock: () => now,
      deleteDirectory: (_) {
        attempts++;
        throw const FileSystemException('injected directory failure');
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    for (var storeIndex = 0; storeIndex < 2; storeIndex++) {
      final idKey = (storeIndex == 0 ? '6' : '7') * 64;
      final created = store.create(idKey);
      store.putBlob(
        idKey: idKey,
        epoch: created.epoch,
        hash: '8' * 64,
        body: Uint8List.fromList([storeIndex]),
      );
      database.execute('UPDATE stores SET last_seen = ? WHERE id_key = ?', [
        0,
        idKey,
      ]);
    }

    store.sweep(now: now);

    expect(attempts, 4);
  });

  test('directory retries preserve epochs that gain stale refs', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-stale-directory-job-',
    );
    final database = sqlite3.openInMemory();
    var directoryAttempts = 0;
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      deleteDirectory: (_) {
        directoryAttempts++;
        throw const FileSystemException('injected directory failure');
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = 'e' * 64;
    final oldStore = store.create(idKey);
    store.deleteStore(idKey);
    final recreated = store.create(idKey);
    directoryAttempts = 0;
    store.putBlob(
      idKey: idKey,
      epoch: oldStore.epoch,
      hash: 'f' * 64,
      body: Uint8List.fromList([1]),
    );

    store.retryPendingDeletions();

    expect(directoryAttempts, 0);
    expect(database.select('SELECT * FROM deletion_jobs'), hasLength(1));
    final metadata = store.metadata(recreated);
    expect(metadata.blobs, 1);
    expect(metadata.bytes, 1);
    expect(
      store.blobFile(idKey, oldStore.epoch, 'f' * 64).existsSync(),
      isTrue,
    );
    expect(recreated.epoch, isNot(oldStore.epoch));
  });

  test('store deletion discovers stale blob-only epochs', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-stale-blob-job-',
    );
    final database = sqlite3.openInMemory();
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      deleteFile: (_) {
        throw const FileSystemException('injected file failure');
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = '1' * 64;
    final oldStore = store.create(idKey);
    store.deleteStore(idKey);
    final recreated = store.create(idKey);
    final hash = '2' * 64;
    store.putBlob(
      idKey: idKey,
      epoch: oldStore.epoch,
      hash: hash,
      body: Uint8List.fromList([1]),
    );
    database.execute(
      'UPDATE blob_refs SET uploaded_at = ? WHERE id_key = ? AND epoch = ?',
      [
        DateTime.now()
                .subtract(const Duration(days: 2))
                .millisecondsSinceEpoch ~/
            1000,
        idKey,
        oldStore.epoch,
      ],
    );
    store.collectGarbage(idKey, oldStore.epoch);
    expect(database.select('SELECT * FROM deletion_jobs'), isEmpty);
    expect(database.select('SELECT * FROM blob_deletion_jobs'), hasLength(1));

    store.deleteStore(idKey);

    expect(store.blobFile(idKey, oldStore.epoch, hash).existsSync(), isFalse);
    expect(database.select('SELECT * FROM blob_deletion_jobs'), isEmpty);
    expect(recreated.epoch, isNot(oldStore.epoch));
  });

  test('successful directory deletion clears redundant blob jobs', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-directory-job-cleanup-',
    );
    final database = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      clock: () => now,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = '3' * 64;
    final created = store.create(idKey);
    for (
      var index = 0;
      index < maxPendingDeletionRetriesPerRequest + 1;
      index++
    ) {
      store.putBlob(
        idKey: idKey,
        epoch: created.epoch,
        hash: index.toRadixString(16).padLeft(64, '0'),
        body: Uint8List.fromList([1]),
      );
    }
    database.execute(
      'UPDATE blob_refs SET uploaded_at = ? WHERE id_key = ? AND epoch = ?',
      [0, idKey, created.epoch],
    );
    store.collectGarbage(idKey, created.epoch, now: now, retryMaxJobs: null);
    expect(
      database.select('SELECT * FROM blob_deletion_jobs'),
      hasLength(maxPendingDeletionRetriesPerRequest + 1),
    );

    store.deleteStore(idKey);

    expect(database.select('SELECT * FROM deletion_jobs'), isEmpty);
    expect(database.select('SELECT * FROM blob_deletion_jobs'), isEmpty);
    expect(
      store.blobFile(idKey, created.epoch, '0'.padLeft(64, '0')).existsSync(),
      isFalse,
    );
  });

  test('startup queues crash-orphaned blob files for cleanup', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-orphan-recovery-',
    );
    final config = AthenaeumConfig(
      dataDirectory: dataDirectory.path,
      pepper: List<int>.filled(32, 0x42),
    );
    AthenaeumStore? recovered;
    addTearDown(() {
      recovered?.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final initial = AthenaeumStore(config: config);
    final idKey = '5' * 64;
    final created = initial.create(idKey);
    final hash = '6' * 64;
    final orphan = initial.blobFile(idKey, created.epoch, hash);
    orphan.parent.createSync(recursive: true);
    orphan.writeAsBytesSync([1], flush: true);
    final temporaryHash = '7' * 64;
    final temporary = File(
      '${initial.blobFile(idKey, created.epoch, temporaryHash).path}'
      '.123.456.abc.tmp',
    );
    temporary.parent.createSync(recursive: true);
    temporary.writeAsBytesSync([2], flush: true);
    initial.close();

    var failDelete = true;
    recovered = AthenaeumStore(
      config: config,
      deleteFile: (file) {
        if (failDelete) {
          throw const FileSystemException('injected recovery failure');
        }
        file.deleteSync();
      },
    );
    expect(
      recovered.database.select('SELECT * FROM blob_deletion_jobs'),
      hasLength(2),
    );
    expect(orphan.existsSync(), isTrue);
    expect(temporary.existsSync(), isTrue);

    failDelete = false;
    recovered.retryPendingBlobDeletions();
    expect(orphan.existsSync(), isFalse);
    expect(temporary.existsSync(), isFalse);
    expect(
      recovered.database.select('SELECT * FROM blob_deletion_jobs'),
      isEmpty,
    );
  });

  test('store deletion prioritizes all of its directories', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-priority-delete-',
    );
    final database = sqlite3.openInMemory();
    var failDelete = true;
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      deleteDirectory: (directory) {
        if (failDelete) {
          throw const FileSystemException('injected directory failure');
        }
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    for (
      var index = 0;
      index < maxPendingDeletionRetriesPerRequest + 1;
      index++
    ) {
      final idKey = (index.toRadixString(16)) * 64;
      store.create(idKey);
      store.deleteStore(idKey);
    }
    final targetId = 'a' * 64;
    final target = store.create(targetId);
    final targetFile = store.blobFile(targetId, target.epoch, 'b' * 64);
    targetFile.parent.createSync(recursive: true);
    targetFile.writeAsBytesSync([1]);

    failDelete = false;
    store.deleteStore(targetId);

    expect(targetFile.existsSync(), isFalse);
  });

  test('directory retry batches rotate failed jobs', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-directory-retry-rotation-',
    );
    final database = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    var failDelete = true;
    final failedIds = <String>{};
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      clock: () => now,
      deleteDirectory: (directory) {
        final shouldFail = failedIds.any(directory.path.contains);
        if (failDelete || shouldFail) {
          throw const FileSystemException('injected directory failure');
        }
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    for (var index = 0; index < maxPendingDeletionRetriesPerRequest; index++) {
      final idKey = (index.toRadixString(16)) * 64;
      failedIds.add(idKey);
      store.create(idKey);
      store.deleteStore(idKey);
    }
    final targetId = '${'a' * 63}b';
    final target = store.create(targetId);
    final targetFile = store.blobFile(targetId, target.epoch, 'b' * 64);
    targetFile.parent.createSync(recursive: true);
    targetFile.writeAsBytesSync([1]);
    store.deleteStore(targetId);
    database.execute('UPDATE deletion_jobs SET queued_at = ?', [
      now.millisecondsSinceEpoch ~/ 1000,
    ]);

    failDelete = false;
    store.retryPendingDeletions(maxJobs: maxPendingDeletionRetriesPerRequest);
    store.retryPendingDeletions(maxJobs: maxPendingDeletionRetriesPerRequest);

    expect(targetFile.existsSync(), isFalse);
  });

  test('blob retry batches rotate failed jobs', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-blob-retry-rotation-',
    );
    final database = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    var failDelete = true;
    final failedHashes = <String>{};
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      clock: () => now,
      deleteFile: (file) {
        final shouldFail = failedHashes.any(file.path.endsWith);
        if (failDelete || shouldFail) {
          throw const FileSystemException('injected blob failure');
        }
        file.deleteSync();
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = 'b' * 64;
    final epoch = store.create(idKey).epoch;
    final queuedAt = now.millisecondsSinceEpoch ~/ 1000;
    for (
      var index = 0;
      index < maxPendingDeletionRetriesPerRequest + 1;
      index++
    ) {
      final hash = index.toRadixString(16).padLeft(64, '0');
      if (index < maxPendingDeletionRetriesPerRequest) {
        failedHashes.add(hash);
      }
      final file = store.blobFile(idKey, epoch, hash);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync([1]);
      database.execute(
        'INSERT INTO blob_deletion_jobs (id_key, epoch, hash, queued_at) '
        'VALUES (?, ?, ?, ?)',
        [idKey, epoch, hash, queuedAt],
      );
    }

    failDelete = false;
    store.retryPendingBlobDeletions(
      maxJobs: maxPendingDeletionRetriesPerRequest,
    );
    store.retryPendingBlobDeletions(
      maxJobs: maxPendingDeletionRetriesPerRequest,
    );

    final targetHash = maxPendingDeletionRetriesPerRequest
        .toRadixString(16)
        .padLeft(64, '0');
    expect(store.blobFile(idKey, epoch, targetHash).existsSync(), isFalse);
  });

  test('retention purges continue after an epoch cleanup failure', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-retention-isolation-',
    );
    final database = sqlite3.openInMemory();
    final breakGlassDatabase = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: breakGlassDatabase,
      clock: () => now,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = 'a' * 64;
    final created = store.create(idKey);
    database.execute(
      'INSERT INTO blob_refs (id_key, epoch, hash, size, uploaded_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [idKey, created.epoch, 'c' * 64, 1, 0],
    );
    database.execute(
      'INSERT INTO manifests '
      '(id_key, epoch, device_id, etag, written_at, body) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        idKey,
        created.epoch,
        'poisoned',
        'b' * 64,
        0,
        Uint8List.fromList([0]),
      ],
    );
    store.recordBreakGlassAccess(
      'café-horse-battery-staple',
      accessedAt: now.subtract(const Duration(days: 31)),
    );
    store.recordDiagnostic(
      status: 400,
      idKey: idKey,
      hash: null,
      recordedAt: now.subtract(const Duration(days: 31)),
    );
    breakGlassDatabase.execute(
      'CREATE TRIGGER fail_break_glass BEFORE UPDATE ON break_glass_access '
      "BEGIN SELECT RAISE(ABORT, 'injected retention failure'); END",
    );

    store.sweep(now: now);

    final accessRows = breakGlassDatabase.select(
      'SELECT id_key, accessed_at FROM break_glass_access',
    );
    expect(accessRows, hasLength(1));
    expect(accessRows.single['id_key'], isNotNull);
    expect(
      store.diagnosticDatabase.select('SELECT * FROM diagnostic_events'),
      isEmpty,
    );
  });

  test('pending deletion bytes remain charged across epochs', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-cross-epoch-quota-',
    );
    final database = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 3, 12);
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
      breakGlassDatabase: sqlite3.openInMemory(),
      clock: () => now,
      quotaLimits: const AthenaeumQuotaLimits(maxBytes: 3),
      deleteDirectory: (_) {},
      deleteFile: (_) {
        throw const FileSystemException('injected file failure');
      },
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });
    final idKey = '4' * 64;
    final oldStore = store.create(idKey);
    final hash = '5' * 64;
    final body = Uint8List.fromList([1, 2, 3]);
    store.putBlob(idKey: idKey, epoch: oldStore.epoch, hash: hash, body: body);
    store.deleteStore(idKey);
    final currentStore = store.create(idKey);
    store.putBlob(idKey: idKey, epoch: oldStore.epoch, hash: hash, body: body);
    database.execute(
      'UPDATE blob_refs SET uploaded_at = ? WHERE id_key = ? AND epoch = ?',
      [
        now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
        idKey,
        oldStore.epoch,
      ],
    );
    store.collectGarbage(idKey, oldStore.epoch, now: now);
    expect(database.select('SELECT * FROM blob_deletion_jobs'), hasLength(1));
    expect(
      () => store.putBlob(
        idKey: idKey,
        epoch: currentStore.epoch,
        hash: hash,
        body: Uint8List.fromList([4]),
      ),
      throwsA(isA<StoreQuotaExceeded>()),
    );
  });

  test('deleting a recreated store cleans stale epoch directories', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final idKey = 'f' * 64;
    final first = store.create(idKey);
    store.deleteStore(idKey);
    final recreated = store.create(idKey);
    store.putBlob(
      idKey: idKey,
      epoch: first.epoch,
      hash: '1' * 64,
      body: Uint8List.fromList([3]),
    );
    final staleFile = store.blobFile(idKey, first.epoch, '1' * 64);
    final currentFile = store.blobFile(idKey, recreated.epoch, '2' * 64);
    currentFile.parent.createSync(recursive: true);
    currentFile.writeAsBytesSync([4]);

    store.deleteStore(idKey);
    store.retryPendingDeletions();

    expect(staleFile.existsSync(), isFalse);
    expect(currentFile.existsSync(), isFalse);
  });

  test('store blob directories remain isolated during deletion', () {
    final dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-store-test-',
    );
    final database = sqlite3.openInMemory();
    final store = AthenaeumStore(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory.path,
        pepper: List<int>.filled(32, 0x42),
      ),
      database: database,
    );
    addTearDown(() {
      store.close();
      dataDirectory.deleteSync(recursive: true);
    });

    final firstId = 'a' * 64;
    final secondId = 'b' * 64;
    final hash = 'c' * 64;
    final first = store.create(firstId);
    final second = store.create(secondId);
    store.putBlob(
      idKey: firstId,
      epoch: first.epoch,
      hash: hash,
      body: Uint8List.fromList([1]),
    );
    store.putBlob(
      idKey: secondId,
      epoch: second.epoch,
      hash: hash,
      body: Uint8List.fromList([2]),
    );

    store.deleteStore(firstId);

    expect(store.blobFile(secondId, second.epoch, hash).existsSync(), isTrue);
  });
}
