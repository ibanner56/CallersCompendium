// Measures what one `/v1` request costs the Athenaeum, to compare costing
// rules for `POST /v1/blobs/batch` against the request-rate limits (spec
// §5.4). Run from `server/`:
//
//     dart run tool/blob_batch_cost_bench.dart corpus.json [--batch]
//
// It drives the real handler in-process with the rate limits lifted, against a
// real store on disk, populated with the canonical blobs
// `packages/compendium_core/tool/sync_bench_corpus.dart` writes, passed as the
// first argument. Numbers are medians over many requests on a warm
// process: they compare designs on one machine and are not capacity figures.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:shelf/shelf.dart';

const _syncId = 'alpha-beta-gamma-delta';
const _iterations = 3000;

Future<void> main(List<String> arguments) async {
  final library = _readCorpus(arguments.first);
  _reportSizes(library);

  final directory = await Directory.systemTemp.createTemp('blob-batch-bench-');
  final config = AthenaeumConfig(
    dataDirectory: directory.path,
    pepper: List<int>.filled(32, 0x42),
  );
  final app = AthenaeumApp(
    config: config,
    clientAddressResolver: (_) => 'bench',
    budgetLimits: const AthenaeumBudgetLimits(
      perIpRequestsPerMinute: 1 << 30,
      perIpRequestBurst: 1 << 30,
      perStoreRequestsPerMinute: 1 << 30,
      perStoreRequestBurst: 1 << 30,
    ),
  );
  try {
    final idKey = deriveIncomingSyncIdKey(_syncId, config.pepper);
    final store = app.store.create(idKey);
    for (final blob in library) {
      app.store.putBlob(
        idKey: idKey,
        epoch: store.epoch,
        hash: blob.hash,
        body: blob.bytes,
      );
    }
    final authorization = 'Bearer ${encodeSyncCredential(_syncId)}';
    Future<int> send(
      String method,
      String path, {
      List<int>? body,
      bool gzip = false,
    }) async {
      final response = await app.handler(
        Request(
          method,
          Uri.parse('http://bench$path'),
          headers: {
            'authorization': authorization,
            if (body != null) 'content-type': 'application/json',
            if (gzip) 'accept-encoding': 'gzip',
          },
          body: body,
        ),
      );
      var bytes = 0;
      await for (final chunk in response.read()) {
        bytes += chunk.length;
      }
      return bytes;
    }

    final absent = sha256Hex(utf8.encode('not stored'));
    final hashes = [for (final blob in library) blob.hash];

    stdout.writeln('\n## Per-request handler time (in-process, µs, median)');
    final store_ = await _time(() => send('GET', '/v1/store'));
    stdout.writeln('GET /v1/store                         ${_fmt(store_)}');
    final miss = await _time(() => send('GET', '/v1/blobs/$absent'));
    stdout.writeln('GET /v1/blobs/{unreferenced} (404)    ${_fmt(miss)}');
    var next = 0;
    final hit = await _time(
      () => send('GET', '/v1/blobs/${hashes[next++ % hashes.length]}'),
    );
    stdout.writeln('GET /v1/blobs/{hash} (200)            ${_fmt(hit)}');

    stdout.writeln('\n## Components (µs, median)');
    final hmac = await _time(
      () async => deriveIncomingSyncIdKey(_syncId, config.pepper),
    );
    stdout.writeln('HMAC store key                        ${_fmt(hmac)}');
    final lookup = await _time(() async => app.store.lookup(idKey));
    stdout.writeln('store.lookup                          ${_fmt(lookup)}');
    final touch = await _time(() async => app.store.touch(idKey));
    stdout.writeln('store.touch                           ${_fmt(touch)}');
    final retry = await _time(
      () async => app.store.retryPendingDeletions(
        maxDuration: requestPendingDeletionBudget,
      ),
    );
    stdout.writeln(
      'retryPendingDeletions (queue empty)   ${_fmt(retry)}'
      '   (bounded at ${requestPendingDeletionBudget.inMilliseconds} ms '
      'when jobs are queued)',
    );
    next = 0;
    final ref = await _time(
      () async =>
          app.store.blobRef(idKey, store.epoch, hashes[next++ % hashes.length]),
    );
    stdout.writeln('store.blobRef                         ${_fmt(ref)}');
    next = 0;
    final read = await _time(
      () async => app.store
          .blobFile(idKey, store.epoch, hashes[next++ % hashes.length])
          .readAsBytesSync(),
    );
    stdout.writeln('blob file readAsBytesSync             ${_fmt(read)}');

    if (arguments.contains('--batch')) {
      stdout.writeln('\n## POST /v1/blobs/batch (in-process, µs, median)');
      for (final (size, compressed) in [
        (1, false),
        (50, false),
        (200, false),
        (1, true),
        (200, true),
      ]) {
        var offset = 0;
        var wireBytes = 0;
        final batch = await _time(() {
          final slice = [
            for (var i = 0; i < size; i++) hashes[(offset + i) % hashes.length],
          ];
          offset += size;
          return send(
            'POST',
            '/v1/blobs/batch',
            body: utf8.encode(jsonEncode({'hashes': slice})),
            gzip: compressed,
          ).then((bytes) => wireBytes = bytes);
        }, iterations: size == 200 ? 300 : 1000);
        final label = '$size hashes${compressed ? ', gzip' : ''}'.padRight(38);
        stdout.writeln(
          '$label${_fmt(batch)}   per blob '
          '${(batch / size).toStringAsFixed(1)}   last response '
          '$wireBytes bytes',
        );
      }
    }
  } finally {
    app.store.close();
    await directory.delete(recursive: true);
  }
  stdout.writeln(
    '\nMachine: ${Platform.numberOfProcessors} logical CPUs, '
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}, '
    'Dart ${Platform.version.split(' ').first}',
  );
}

Future<double> _time(
  Future<Object?> Function() action, {
  int iterations = _iterations,
}) async {
  for (var i = 0; i < 200; i++) {
    await action();
  }
  final samples = <int>[];
  final watch = Stopwatch();
  for (var i = 0; i < iterations; i++) {
    watch
      ..reset()
      ..start();
    await action();
    samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2].toDouble();
}

String _fmt(double micros) => micros.toStringAsFixed(0).padLeft(6);

void _reportSizes(List<BenchBlob> library) {
  stdout.writeln('## Blob sizes (bytes)');
  stdout.writeln(
    'kind              n   median raw  median gz-alone  total raw  '
    'total gz-alone  gz-batched(200)  ratio',
  );
  final kinds = <SyncRecordKind, List<BenchBlob>>{};
  for (final blob in library) {
    (kinds[blob.kind] ??= []).add(blob);
  }
  for (final entry in [
    ...kinds.entries,
    MapEntry<SyncRecordKind?, List<BenchBlob>>(null, library),
  ]) {
    final blobs = entry.value;
    final raw = [for (final b in blobs) b.bytes.length]..sort();
    final alone = [for (final b in blobs) gzip.encode(b.bytes).length]..sort();
    final rawTotal = raw.fold(0, (a, b) => a + b);
    final aloneTotal = alone.fold(0, (a, b) => a + b);
    // What a batch response would compress to: the blobs streamed back to
    // back, 200 at a time, each with its 37-byte frame header.
    var batched = 0;
    for (var i = 0; i < blobs.length; i += 200) {
      final builder = BytesBuilder(copy: false);
      for (final b in blobs.skip(i).take(200)) {
        builder
          ..addByte(0)
          ..add(_hexToBytes(b.hash))
          ..add(_u32(b.bytes.length))
          ..add(b.bytes);
      }
      batched += gzip.encode(builder.takeBytes()).length;
    }
    stdout.writeln(
      '${(entry.key?.name ?? 'ALL').padRight(15)}'
      '${blobs.length.toString().padLeft(5)}'
      '${raw[raw.length ~/ 2].toString().padLeft(13)}'
      '${alone[alone.length ~/ 2].toString().padLeft(17)}'
      '${rawTotal.toString().padLeft(11)}'
      '${aloneTotal.toString().padLeft(16)}'
      '${batched.toString().padLeft(17)}'
      '${(rawTotal / batched).toStringAsFixed(2).padLeft(7)}',
    );
  }
}

Uint8List _hexToBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

Uint8List _u32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value);

/// One record of a library `packages/compendium_core/tool/sync_bench_corpus.dart`
/// wrote.
final class BenchBlob {
  BenchBlob(this.kind, this.id, this.bytes) : hash = sha256Hex(bytes);

  final SyncRecordKind kind;
  final String id;
  final Uint8List bytes;
  final String hash;
}

List<BenchBlob> _readCorpus(String path) => [
  for (final record
      in (jsonDecode(File(path).readAsStringSync()) as Map)['records'] as List)
    BenchBlob(
      SyncRecordKind.values.byName((record as Map)['kind'] as String),
      record['id'] as String,
      base64.decode(record['blob'] as String),
    ),
];
