import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:test/test.dart';

/// The running pending-deletion total (SRV-1) and the sliced hourly sweep
/// (SRV-5).
void main() {
  late Directory dataDirectory;
  late DateTime now;
  late Duration elapsed;
  late Duration elapsedPerRead;
  var failFileDeletes = false;
  var failTemporaryDeletes = false;
  var failDirectoryDeletes = false;

  AthenaeumStore open({
    // Small enough that the byte limit a PUT is offered moves with usage.
    AthenaeumQuotaLimits quotaLimits = const AthenaeumQuotaLimits(
      maxBytes: 64 * 1024,
    ),
  }) => AthenaeumStore(
    config: AthenaeumConfig(
      dataDirectory: dataDirectory.path,
      pepper: List<int>.filled(32, 0x42),
    ),
    quotaLimits: quotaLimits,
    clock: () => now,
    elapsed: () => elapsed += elapsedPerRead,
    deleteFile: (file) {
      if (failFileDeletes ||
          (failTemporaryDeletes && file.path.endsWith('.tmp'))) {
        throw const FileSystemException('injected');
      }
      file.deleteSync();
    },
    deleteDirectory: (directory) {
      if (failDirectoryDeletes) throw const FileSystemException('injected');
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    },
  );

  setUp(() {
    dataDirectory = Directory.systemTemp.createTempSync(
      'athenaeum-pending-usage-',
    );
    now = DateTime.utc(2026, 9, 3, 12);
    elapsed = Duration.zero;
    elapsedPerRead = Duration.zero;
    failFileDeletes = false;
    failTemporaryDeletes = false;
    failDirectoryDeletes = false;
  });
  tearDown(() => dataDirectory.deleteSync(recursive: true));

  String hashOf(int index) => index.toRadixString(16).padLeft(64, '0');

  Uint8List bodyOf(int index) =>
      Uint8List.fromList(List<int>.filled(1 + index % 7, index % 256));

  /// Uploads [count] blobs, then 25 h later publishes a manifest naming none
  /// of them and collects garbage without draining: every blob is pending.
  ({String idKey, String epoch}) queueDeletions(
    AthenaeumStore store,
    int count,
  ) {
    final idKey = 'a' * 64;
    final epoch = store.create(idKey).epoch;
    final statuses = store.putBlobs(
      idKey: idKey,
      epoch: epoch,
      blobs: [
        for (var index = 0; index < count; index++)
          (hash: hashOf(index), body: bodyOf(index)),
      ],
    );
    expect(statuses, everyElement(201));
    now = now.add(const Duration(hours: 25));
    store.putManifest(
      idKey: idKey,
      epoch: epoch,
      deviceId: 'device',
      etag: 'etag',
      writtenAt: 0,
      body: Uint8List.fromList('{}'.codeUnits),
      referencedHashes: const [],
    );
    store.collectGarbageForStore(idKey, retryMaxJobs: null);
    return (idKey: idKey, epoch: epoch);
  }

  test('quota checks read pending deletions once, not per request or per '
      'blob', () {
    final store = open();
    addTearDown(store.close);
    final (:idKey, :epoch) = queueDeletions(store, 200);
    final scansBefore = store.pendingDeletionScans;

    final row = store.lookup(idKey)!;
    expect(store.metadata(row).blobs, 200);
    store.blobUploadLimit(idKey, epoch, hashOf(1000));
    store.manifestUploadPreflight(
      idKey: idKey,
      epoch: epoch,
      deviceId: 'device',
    );
    store.putBlob(
      idKey: idKey,
      epoch: epoch,
      hash: hashOf(1000),
      body: bodyOf(1000),
    );
    final statuses = store.putBlobs(
      idKey: idKey,
      epoch: epoch,
      blobs: [
        for (var index = 2000; index < 2050; index++)
          (hash: hashOf(index), body: bodyOf(index)),
      ],
    );
    expect(statuses, everyElement(201));
    store.retryPendingDeletions(maxJobs: 20);
    expect(store.metadata(store.lookup(idKey)!).blobs, 51 + 180);

    expect(store.pendingDeletionScans - scansBefore, lessThanOrEqualTo(1));
  });

  test('the running total matches a fresh scan through every change', () {
    final store = open();
    addTearDown(store.close);
    final (:idKey, :epoch) = queueDeletions(store, 12);

    void expectMatchesScan(String step) {
      final row = store.lookup(idKey);
      if (row == null) return;
      ({int blobs, int bytes, int limit}) read() {
        final metadata = store.metadata(row);
        int limit;
        try {
          // The PUT of a pending hash leaves its own file out.
          limit = store.blobUploadLimit(idKey, row.epoch, hashOf(3));
        } on StoreQuotaExceeded {
          limit = -1;
        }
        return (blobs: metadata.blobs, bytes: metadata.bytes, limit: limit);
      }

      final running = read();
      store.forgetPendingDeletionUsage();
      expect(running, read(), reason: step);
    }

    expectMatchesScan('queued');
    // A pending hash re-uploaded singly and in a batch, beside a new one.
    store.putBlob(idKey: idKey, epoch: epoch, hash: hashOf(0), body: bodyOf(0));
    expectMatchesScan('single re-upload');
    store.putBlobs(
      idKey: idKey,
      epoch: epoch,
      blobs: [
        (hash: hashOf(1), body: bodyOf(1)),
        (hash: hashOf(2), body: bodyOf(2)),
        (hash: hashOf(500), body: bodyOf(500)),
      ],
    );
    expectMatchesScan('batch re-upload');
    // A temporary file a crashed upload left beside a queued blob, as the
    // store finds it on its next start.
    for (final index in [1, 11]) {
      final leftover = store.blobFile(idKey, epoch, hashOf(index));
      File('${leftover.path}.1.2.ab.tmp').writeAsBytesSync([1, 2, 3]);
    }
    store.forgetPendingDeletionUsage();
    expectMatchesScan('temporary file');
    // Collected again while their old jobs are still queued.
    now = now.add(const Duration(hours: 25));
    store.collectGarbageForStore(idKey, retryMaxJobs: null);
    expectMatchesScan('requeued');
    store.retryPendingDeletions(maxJobs: 3);
    expectMatchesScan('drained in part');
    failFileDeletes = true;
    store.retryPendingDeletions(maxJobs: 2);
    expectMatchesScan('failed deletion');
    failFileDeletes = false;
    // A job whose blob file is deleted and whose temporary file is not.
    failTemporaryDeletes = true;
    store.retryPendingDeletions(maxJobs: 100);
    expectMatchesScan('half-failed deletion');
    failTemporaryDeletes = false;

    // A deleted store whose directory survives, recreated under the same
    // key: its old epoch's files are pending through a directory job.
    store.putBlob(
      idKey: idKey,
      epoch: epoch,
      hash: hashOf(600),
      body: bodyOf(600),
    );
    failDirectoryDeletes = true;
    store.deleteStore(idKey);
    final recreated = store.create(idKey);
    expectMatchesScan('directory job');
    expect(store.metadata(store.lookup(idKey)!).blobs, greaterThan(0));
    store.putBlob(
      idKey: idKey,
      epoch: recreated.epoch,
      hash: hashOf(3),
      body: bodyOf(3),
    );
    expectMatchesScan('upload beside a directory job');
    store.retryPendingDeletions(maxJobs: 1);
    expectMatchesScan('directory job failed');
    failDirectoryDeletes = false;
    store.retryPendingDeletions(maxJobs: 100);
    expectMatchesScan('drained');
    expect(store.metadata(store.lookup(idKey)!).blobs, 1);
  });

  test('a batch is charged for pending files as a run of single PUTs is', () {
    final store = open(quotaLimits: const AthenaeumQuotaLimits(maxBlobs: 3));
    addTearDown(store.close);
    final (:idKey, :epoch) = queueDeletions(store, 3);
    // Three pending files fill the blob quota. Re-uploading two of them
    // replaces their files rather than adding to them; a new blob after
    // them does not fit, since the third is still pending.
    expect(
      store.putBlobs(
        idKey: idKey,
        epoch: epoch,
        blobs: [
          (hash: hashOf(0), body: bodyOf(0)),
          (hash: hashOf(1), body: bodyOf(1)),
          (hash: hashOf(700), body: bodyOf(700)),
        ],
      ),
      [201, 201, 507],
    );
  });

  test('a sweep in slices yields to the event loop between them', () async {
    final store = open();
    addTearDown(store.close);
    final idKeys = [for (var index = 0; index < 3; index++) hashOf(index)];
    final epochs = <String>[];
    for (final idKey in idKeys) {
      final epoch = store.create(idKey).epoch;
      epochs.add(epoch);
      store.putBlob(
        idKey: idKey,
        epoch: epoch,
        hash: 'b' * 64,
        body: bodyOf(1),
      );
    }
    now = now.add(const Duration(hours: 25));
    int collected() => [
      for (var index = 0; index < 3; index++)
        if (store.blobRef(idKeys[index], epochs[index], 'b' * 64) == null)
          index,
    ].length;

    // Every unit of work spends the whole slice.
    elapsedPerRead = const Duration(seconds: 1);
    final sweeping = store.sweepInSlices(
      sliceBudget: const Duration(milliseconds: 1),
    );
    expect(collected(), 1, reason: 'one unit of work, then a yield');
    await sweeping;
    expect(collected(), 3);
  });

  test('a sweep in slices does not reap a store used since it began', () async {
    final store = open();
    addTearDown(store.close);
    final idKeys = ['c' * 64, 'd' * 64];
    for (final idKey in idKeys) {
      store.create(idKey);
    }
    now = now.add(const Duration(days: 31));

    final sweeping = store.sweepInSlices(sliceBudget: Duration.zero);
    // One store is reaped before the first yield. Before the slice that
    // would reap the other, a request authenticates to it.
    final survivor = idKeys.singleWhere((idKey) => store.lookup(idKey) != null);
    store.touch(survivor);
    await sweeping;

    expect(store.lookup(survivor), isNotNull);
    expect(idKeys.where((idKey) => store.lookup(idKey) == null), hasLength(1));
  });

  test('a sweep in slices stops between slices when asked', () async {
    final store = open();
    addTearDown(store.close);
    for (var index = 0; index < 3; index++) {
      store.create(hashOf(index));
    }
    now = now.add(const Duration(days: 31));
    var stop = false;
    final sweeping = store.sweepInSlices(
      sliceBudget: Duration.zero,
      shouldStop: () => stop,
    );
    stop = true;
    await sweeping;
    final remaining = [
      for (var index = 0; index < 3; index++) store.lookup(hashOf(index)),
    ].nonNulls;
    expect(remaining, hasLength(2));
  });
}
