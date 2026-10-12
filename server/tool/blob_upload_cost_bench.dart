// Measures what one blob upload costs the Athenaeum, to design and cost a
// batched upload. Run from `server/`:
//
//     dart run tool/blob_upload_cost_bench.dart corpus.json
//
// The corpus is the library `packages/compendium_core/tool/sync_bench_corpus.dart`
// writes. Every blob is uploaded once, in order, through the real handler with
// the rate limits lifted, into a store on disk; the handler time of each
// `PUT /v1/blobs/{hash}` is reported by how full the store already was, since
// the quota check scans the store's blob rows. The store-level steps are then
// timed on their own at the final size.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:shelf/shelf.dart';

const _syncId = 'alpha-beta-gamma-delta';

Future<void> main(List<String> arguments) async {
  final library = _readCorpus(arguments.first);
  final directory = await Directory.systemTemp.createTemp('blob-upload-bench-');
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
    final epoch = app.store.create(idKey).epoch;
    final authorization = 'Bearer ${encodeSyncCredential(_syncId)}';
    final samples = <int>[];
    final watch = Stopwatch();
    for (final blob in library) {
      watch
        ..reset()
        ..start();
      final response = await app.handler(
        Request(
          'PUT',
          Uri.parse('http://bench/v1/blobs/${blob.hash}'),
          headers: {
            'authorization': authorization,
            'content-type': 'application/octet-stream',
          },
          body: blob.bytes,
        ),
      );
      await response.read().drain<void>();
      samples.add(watch.elapsedMicroseconds);
      if (response.statusCode != 201) {
        throw StateError('PUT answered ${response.statusCode}');
      }
    }
    stdout.writeln('## PUT /v1/blobs/{hash}, in-process (µs, median)');
    for (var start = 0; start < samples.length; start += 1000) {
      final window = samples.sublist(
        start,
        (start + 1000).clamp(0, samples.length),
      )..sort();
      stdout.writeln(
        'blobs ${start.toString().padLeft(5)}–'
        '${(start + window.length).toString().padRight(5)} already stored: '
        '${window[window.length ~/ 2]}',
      );
    }

    stdout.writeln('\n## PUT /v1/blobs/batch, in-process (µs, median of 20)');
    for (final size in [1, 10, 50]) {
      final batchSamples = <int>[];
      for (var round = 0; round < 20; round++) {
        final body = BytesBuilder(copy: false);
        for (var i = 0; i < size; i++) {
          final blob = utf8.encode('{"round":$round,"size":$size,"i":$i}');
          body
            ..add(
              encodeSyncBlobBatchFrameHead(
                SyncBlobBatchFrameStatus.blob,
                sha256Hex(blob),
                length: blob.length,
              ),
            )
            ..add(blob);
        }
        watch
          ..reset()
          ..start();
        final response = await app.handler(
          Request(
            'PUT',
            Uri.parse('http://bench/v1/blobs/batch'),
            headers: {
              'authorization': authorization,
              'content-type': syncBlobBatchMediaType,
            },
            body: body.takeBytes(),
          ),
        );
        await response.read().drain<void>();
        batchSamples.add(watch.elapsedMicroseconds);
      }
      batchSamples.sort();
      final median = batchSamples[batchSamples.length ~/ 2];
      stdout.writeln(
        '${size.toString().padLeft(3)} blobs into ${library.length}: '
        '$median   per blob ${(median / size).toStringAsFixed(0)}',
      );
    }

    stdout.writeln('\n## Store steps at ${library.length} blobs (µs, median)');
    final absent = sha256Hex(utf8.encode('never stored'));
    stdout.writeln(
      'blobUploadLimit (quota preflight)   '
      '${_time(() => app.store.blobUploadLimit(idKey, epoch, absent))}',
    );
    final extra = [for (var i = 0; i < 300; i++) utf8.encode('{"bench":$i}')];
    var next = 0;
    stdout.writeln(
      'putBlob (quota, file write+flush, commit) '
      '${_time(() {
        final body = Uint8List.fromList(extra[next++ % extra.length] + [next]);
        app.store.putBlob(idKey: idKey, epoch: epoch, hash: sha256Hex(body), body: body);
      }, iterations: 200)}',
    );
    final file = File('${directory.path}/flush-probe');
    final bytes = library.first.bytes;
    stdout.writeln(
      'file write with flush (1.7 KB)      '
      '${_time(() => file.writeAsBytesSync(bytes, flush: true))}',
    );
    stdout.writeln(
      'file write without flush (1.7 KB)   '
      '${_time(() => file.writeAsBytesSync(bytes))}',
    );
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

int _time(void Function() action, {int iterations = 1000}) {
  for (var i = 0; i < 20; i++) {
    action();
  }
  final samples = <int>[];
  final watch = Stopwatch();
  for (var i = 0; i < iterations; i++) {
    watch
      ..reset()
      ..start();
    action();
    samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

/// One record of a library `packages/compendium_core/tool/sync_bench_corpus.dart`
/// wrote.
final class BenchBlob {
  BenchBlob(this.bytes) : hash = sha256Hex(bytes);

  final Uint8List bytes;
  final String hash;
}

List<BenchBlob> _readCorpus(String path) => [
  for (final record
      in (jsonDecode(File(path).readAsStringSync()) as Map)['records'] as List)
    BenchBlob(base64.decode((record as Map)['blob'] as String)),
];
