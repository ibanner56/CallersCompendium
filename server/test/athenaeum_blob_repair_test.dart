import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

AthenaeumConfig _config(Directory directory) => AthenaeumConfig(
  dataDirectory: directory.path,
  pepper: List<int>.filled(32, 0x42),
);

Directory _tempDirectory(String prefix) {
  final directory = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // A store that failed to construct may still hold its database open.
    }
  });
  return directory;
}

void main() {
  group('blob file repair', () {
    late Directory dataDirectory;
    late Database database;
    late AthenaeumStore store;
    late String idKey;
    late String epoch;
    final body = Uint8List.fromList([1, 2, 3, 4]);
    final hash = rawBodyHash(body);

    setUp(() {
      dataDirectory = _tempDirectory('athenaeum-blob-repair-');
      database = sqlite3.openInMemory();
      store = AthenaeumStore(
        config: _config(dataDirectory),
        database: database,
        quotaLimits: const AthenaeumQuotaLimits(maxBlobs: 1, maxBytes: 4),
      );
      addTearDown(store.close);
      idKey = '0' * 64;
      epoch = store.create(idKey).epoch;
      expect(
        store.putBlob(idKey: idKey, epoch: epoch, hash: hash, body: body),
        isTrue,
      );
    });

    test('missing reports a referenced blob whose file is gone', () {
      expect(store.missingBlobs(idKey, epoch, [hash]), isEmpty);
      store.blobFile(idKey, epoch, hash).deleteSync();
      expect(store.missingBlobs(idKey, epoch, [hash]), [hash]);
    });

    test(
      'put rewrites the file without charging quota or touching the ref',
      () {
        final before = store.blobRef(idKey, epoch, hash)!;
        final usedBefore = store.lookup(idKey)!.bytesUsed;
        database.execute('UPDATE blob_refs SET uploaded_at = 7');
        final file = store.blobFile(idKey, epoch, hash)..deleteSync();

        // The store is at both its blob and byte limit, so any re-charge fails.
        expect(
          store.putBlob(idKey: idKey, epoch: epoch, hash: hash, body: body),
          isFalse,
        );

        expect(file.readAsBytesSync(), body);
        expect(store.missingBlobs(idKey, epoch, [hash]), isEmpty);
        final after = store.blobRef(idKey, epoch, hash)!;
        expect(after.size, before.size);
        expect(after.uploadedAt, 7);
        expect(store.lookup(idKey)!.bytesUsed, usedBefore);
        expect(database.select('SELECT * FROM blob_refs'), hasLength(1));
        expect(file.parent.listSync().map((entity) => entity.path), [
          file.path,
        ], reason: 'no temporary file is left behind');
      },
    );

    test('put rejects a body whose size or hash differs from the ref', () {
      final file = store.blobFile(idKey, epoch, hash)..deleteSync();
      for (final wrong in [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([9, 9, 9, 9]),
      ]) {
        expect(
          () => store.putBlob(
            idKey: idKey,
            epoch: epoch,
            hash: hash,
            body: wrong,
          ),
          throwsA(isA<StoreBlobMismatch>()),
        );
        expect(file.existsSync(), isFalse);
        expect(file.parent.listSync(), isEmpty);
      }
      expect(store.missingBlobs(idKey, epoch, [hash]), [hash]);
    });

    test('put never overwrites a file that is still present', () {
      final file = store.blobFile(idKey, epoch, hash);
      file.writeAsBytesSync([0xAA]);
      expect(
        store.putBlob(idKey: idKey, epoch: epoch, hash: hash, body: body),
        isFalse,
      );
      expect(file.readAsBytesSync(), [0xAA]);
    });

    test('a pending deletion job does not remove a repaired blob', () {
      final file = store.blobFile(idKey, epoch, hash)..deleteSync();
      database.execute(
        'INSERT INTO blob_deletion_jobs (id_key, epoch, hash, queued_at) '
        'VALUES (?, ?, ?, 0)',
        [idKey, epoch, hash],
      );
      store.putBlob(idKey: idKey, epoch: epoch, hash: hash, body: body);
      store.retryPendingBlobDeletions();
      expect(file.readAsBytesSync(), body);
      expect(database.select('SELECT * FROM blob_deletion_jobs'), isEmpty);
    });
  });

  test(
    'HTTP: a repaired blob is reported missing, then served again',
    () async {
      final dataDirectory = _tempDirectory('athenaeum-blob-repair-http-');
      final app = AthenaeumApp(
        config: _config(dataDirectory),
        clientAddressResolver: (_) => 'test',
      );
      addTearDown(app.store.close);
      const syncId = 'café-horse-battery-staple';
      final headers = {
        'authorization': 'Bearer ${encodeSyncCredential(syncId)}',
      };
      Future<Response> send(
        String method,
        String path, {
        Object? body,
        String contentType = 'application/json',
      }) => app.call(
        Request(
          method,
          Uri.parse('http://127.0.0.1$path'),
          headers: {...headers, 'content-type': contentType},
          body: body,
        ),
      );
      expect((await send('POST', '/v1/store')).statusCode, 201);
      final bytes = Uint8List.fromList([5, 6, 7]);
      final hash = rawBodyHash(bytes);
      Future<Response> put() => send(
        'PUT',
        '/v1/blobs/$hash',
        body: bytes,
        contentType: 'application/octet-stream',
      );
      expect((await put()).statusCode, 201);

      final idKey = deriveIncomingSyncIdKey(syncId, app.config.pepper);
      final epoch = app.store.lookup(idKey)!.epoch;
      app.store.blobFile(idKey, epoch, hash).deleteSync();

      final missing = await send(
        'POST',
        '/v1/blobs/missing',
        body: '{"hashes":["$hash"]}',
      );
      expect(await missing.readAsString(), '{"missing":["$hash"]}');
      expect((await send('GET', '/v1/blobs/$hash')).statusCode, 404);
      expect((await put()).statusCode, 200);
      final served = await send('GET', '/v1/blobs/$hash');
      expect(served.statusCode, 200);
      expect(await served.read().expand((chunk) => chunk).toList(), bytes);
      final again = await send(
        'POST',
        '/v1/blobs/missing',
        body: '{"hashes":["$hash"]}',
      );
      expect(await again.readAsString(), '{"missing":[]}');
    },
  );

  group('time-budgeted cleanup retry', () {
    test('stops between directory jobs once the budget is spent', () {
      final dataDirectory = _tempDirectory('athenaeum-retry-budget-');
      var now = DateTime.utc(2026, 1, 1);
      final deleted = <String>[];
      final database = sqlite3.openInMemory();
      final store = AthenaeumStore(
        config: _config(dataDirectory),
        database: database,
        clock: () => now,
        deleteDirectory: (directory) {
          deleted.add(directory.path);
          now = now.add(const Duration(milliseconds: 400));
        },
      );
      addTearDown(store.close);
      for (var index = 0; index < 8; index++) {
        database.execute(
          'INSERT INTO deletion_jobs (id_key, epoch, queued_at) '
          'VALUES (?, ?, ?)',
          ['a' * 64, 'epoch$index', index],
        );
      }

      // 400 ms per job against a 1 s budget: three jobs fit, well below the
      // 16-job count cap that would otherwise admit all eight.
      store.retryPendingDeletions(maxDuration: const Duration(seconds: 1));
      expect(deleted, hasLength(3));
      expect(database.select('SELECT * FROM deletion_jobs'), hasLength(5));

      // A spent budget still makes progress: one job per call.
      store.retryPendingDeletions(maxDuration: Duration.zero);
      expect(deleted, hasLength(4));

      // Without a budget (sweep, startup, deleteStore) behaviour is unchanged.
      store.retryPendingDeletions();
      expect(deleted, hasLength(8));
      expect(database.select('SELECT * FROM deletion_jobs'), isEmpty);
    });

    test('shares one budget across directory and blob jobs', () {
      final dataDirectory = _tempDirectory('athenaeum-retry-budget-blob-');
      var now = DateTime.utc(2026, 1, 1);
      var blobDeletes = 0;
      final database = sqlite3.openInMemory();
      final store = AthenaeumStore(
        config: _config(dataDirectory),
        database: database,
        clock: () => now,
        deleteDirectory: (_) {
          now = now.add(const Duration(seconds: 2));
        },
        deleteFile: (file) {
          blobDeletes++;
          now = now.add(const Duration(milliseconds: 400));
          file.deleteSync();
        },
      );
      addTearDown(store.close);
      database.execute(
        'INSERT INTO deletion_jobs (id_key, epoch, queued_at) VALUES (?, ?, 0)',
        ['a' * 64, 'epoch'],
      );
      void queueBlob(int index) {
        final hash = index.toRadixString(16).padLeft(64, '0');
        final file = store.blobFile('b' * 64, 'c' * 32, hash)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync([index]);
        expect(file.existsSync(), isTrue);
        database.execute(
          'INSERT INTO blob_deletion_jobs (id_key, epoch, hash, queued_at) '
          'VALUES (?, ?, ?, ?)',
          ['b' * 64, 'c' * 32, hash, index],
        );
      }

      for (var index = 0; index < 4; index++) {
        queueBlob(index);
      }

      // The directory job alone spends the 1 s budget, so no blob job runs.
      store.retryPendingDeletions(maxDuration: const Duration(seconds: 1));
      expect(blobDeletes, 0);

      // With no directory job queued, blob jobs are budgeted on their own:
      // the first always runs, then 400 ms each against 1 s admits three.
      store.retryPendingDeletions(maxDuration: const Duration(seconds: 1));
      expect(blobDeletes, 3);
    });
  });

  group('startup orphan reconciliation', () {
    test('queues exactly the orphaned files across many stores and epochs', () {
      final dataDirectory = _tempDirectory('athenaeum-orphan-scan-');
      final config = _config(dataDirectory);
      final initial = AthenaeumStore(config: config);
      final expected = <String>{};
      var counter = 0;
      String nextHash() => (counter++).toRadixString(16).padLeft(64, '0');
      for (final storeDigit in ['1', '2', '3']) {
        final idKey = storeDigit * 64;
        final epoch = initial.create(idKey).epoch;
        final otherEpoch = 'e' * 32;
        for (var index = 0; index < 40; index++) {
          final hash = nextHash();
          if (index.isEven) {
            initial.putBlob(
              idKey: idKey,
              epoch: epoch,
              hash: hash,
              body: Uint8List.fromList([index]),
            );
            continue;
          }
          final targetEpoch = index % 3 == 0 ? otherEpoch : epoch;
          final file = initial.blobFile(idKey, targetEpoch, hash)
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync([index]);
          expected.add('$idKey/$targetEpoch/$hash');
          if (index % 5 == 0) {
            File('${file.path}.1.2.ab.tmp').writeAsBytesSync([index]);
          }
        }
        // Files the scanner must ignore: wrong shard, wrong depth, wrong name.
        final stray = nextHash();
        final wrongShard = File(
          '${initial.blobDirectory.path}/$idKey/$epoch/zz/zz/$stray',
        )..parent.createSync(recursive: true);
        wrongShard.writeAsBytesSync([0]);
        File(
          '${initial.blobDirectory.path}/$idKey/$epoch/not-a-hash',
        ).writeAsBytesSync([0]);
      }
      initial.close();

      // Startup also drains up to 16 jobs, so make deletion fail to keep the
      // queued set observable.
      final recovered = AthenaeumStore(
        config: config,
        deleteFile: (_) => throw const FileSystemException('injected'),
      );
      addTearDown(recovered.close);
      final queued = {
        for (final row in recovered.database.select(
          'SELECT id_key, epoch, hash FROM blob_deletion_jobs',
        ))
          '${row['id_key']}/${row['epoch']}/${row['hash']}',
      };
      expect(queued, expected);
    });

    test('an epoch is queued atomically', () {
      final dataDirectory = _tempDirectory('athenaeum-orphan-atomic-');
      final config = _config(dataDirectory);
      final initial = AthenaeumStore(config: config);
      final idKey = '4' * 64;
      final epoch = initial.create(idKey).epoch;
      for (final digit in ['1', '2', 'f']) {
        final file = initial.blobFile(idKey, epoch, digit * 64)
          ..parent.createSync(recursive: true);
        file.writeAsBytesSync([1]);
      }
      initial.database.execute(
        'CREATE TRIGGER poison BEFORE INSERT ON blob_deletion_jobs '
        "WHEN NEW.hash = '${'f' * 64}' "
        "BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      initial.close();

      expect(() => AthenaeumStore(config: config), throwsA(isA<Object>()));

      final inspect = sqlite3.open('${dataDirectory.path}/athenaeum.sqlite');
      addTearDown(inspect.close);
      expect(inspect.select('SELECT * FROM blob_deletion_jobs'), isEmpty);
    });
  });
}
