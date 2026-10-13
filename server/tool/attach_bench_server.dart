// Serves a real Athenaeum on loopback, pre-loaded with a peer's library, for
// `app/test/sync/attach_bench_test.dart` to fresh-attach against. Not shipped.
// Run from `server/`:
//
//     dart run tool/attach_bench_server.dart --corpus corpus.json
//     dart run tool/attach_bench_server.dart --corpus corpus.json --no-batch
//     dart run tool/attach_bench_server.dart --corpus corpus.json --no-gzip
//
// The corpus is the library `packages/compendium_core/tool/sync_bench_corpus.dart`
// writes.
//
// It also serves an empty store under [benchPublishSyncId], for the client to
// publish the attached library into.
//
// `--no-batch` answers `POST` and `PUT /v1/blobs/batch` as an Athenaeum from
// before the routes does (`400`), so the client falls back to one `GET` or
// `PUT` per record: the "before" measurement. `--no-gzip` strips `Accept-Encoding`, so the same
// batches go uncompressed. The rate limits are the shipped defaults and the
// clock is real.
//
// `GET /__bench/stats` returns the requests and response-body bytes counted so
// far, by route, and resets them. It is answered before the Athenaeum sees the
// request, so it costs no rate-limit token.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// The sync ID the harness and the client share.
const benchSyncId = 'alpha-beta-gamma-delta';

/// The sync ID of the empty store the client publishes into.
const benchPublishSyncId = 'epsilon-zeta-eta-theta';

Future<void> main(List<String> arguments) async {
  final options =
      (ArgParser()
            ..addOption('corpus', mandatory: true)
            ..addOption('port', defaultsTo: '33390')
            ..addFlag('batch', defaultsTo: true)
            ..addFlag('gzip', defaultsTo: true))
          .parse(arguments);
  final batch = options['batch'] as bool;
  final compress = options['gzip'] as bool;
  final library = _readCorpus(options['corpus'] as String);

  final directory = await Directory.systemTemp.createTemp('attach-bench-');
  final config = AthenaeumConfig(
    dataDirectory: directory.path,
    pepper: List<int>.filled(32, 0x42),
  );
  final app = AthenaeumApp(config: config);
  final idKey = deriveIncomingSyncIdKey(benchSyncId, config.pepper);
  final epoch = app.store.create(idKey).epoch;
  app.store.create(deriveIncomingSyncIdKey(benchPublishSyncId, config.pepper));
  for (final blob in library) {
    app.store.putBlob(
      idKey: idKey,
      epoch: epoch,
      hash: blob.hash,
      body: blob.bytes,
    );
  }
  final manifest = encodeSyncManifestUtf8(
    SyncManifest(
      deviceId: 'peer',
      epoch: epoch,
      writtenAt: DateTime.utc(2026, 9, 1, 12),
      records: {
        for (final kind in {for (final blob in library) blob.kind})
          kind: {
            for (final blob in library)
              if (blob.kind == kind) blob.id: blob.hash,
          },
      },
    ),
  );
  app.store.putManifest(
    idKey: idKey,
    epoch: epoch,
    deviceId: 'peer',
    etag: sha256Hex(manifest),
    writtenAt: DateTime.utc(2026, 9, 1, 12).millisecondsSinceEpoch ~/ 1000,
    body: manifest,
  );

  final requests = <String, int>{};
  final bytes = <String, int>{};
  Future<Response> handler(Request request) async {
    final path = request.url.path;
    if (path == '__bench/stats') {
      final body = jsonEncode({'requests': requests, 'bytes': bytes});
      requests.clear();
      bytes.clear();
      return Response.ok(body, headers: {'content-type': 'application/json'});
    }
    if (!batch && path == 'v1/blobs/batch') {
      // What an Athenaeum from before the route answers, at the same cost:
      // `400`, reading the last segment as a malformed hash.
      request = Request(
        request.method,
        request.requestedUri.replace(path: '/v1/blobs/not-a-hash'),
        headers: request.headers,
        body: request.read(),
        context: request.context,
      );
    }
    final forwarded = compress
        ? request
        : request.change(headers: {'accept-encoding': 'identity'});
    final response = await app.call(forwarded);
    final route = _route(request.method, path);
    final key = '$route ${response.statusCode}';
    requests[key] = (requests[key] ?? 0) + 1;
    return response.change(
      body: response.read().map((chunk) {
        bytes[key] = (bytes[key] ?? 0) + chunk.length;
        return chunk;
      }),
    );
  }

  final server = await shelf_io.serve(
    handler,
    InternetAddress.loopbackIPv4,
    int.parse(options['port'] as String),
  );
  final total = library.fold<int>(0, (sum, blob) => sum + blob.bytes.length);
  stdout.writeln(
    'attach bench: ${library.length} records, $total blob bytes, '
    'batch=${batch ? 'on' : 'off'}, gzip=${compress ? 'on' : 'off'}, '
    'listening on 127.0.0.1:${server.port}',
  );
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close(force: true);
    app.store.close();
    await directory.delete(recursive: true);
    exit(0);
  });
}

String _route(String method, String path) {
  if (path.startsWith('v1/manifests/')) return '$method /v1/manifests/*';
  if (path == 'v1/blobs/batch' || path == 'v1/blobs/missing') {
    return '$method /$path';
  }
  if (path.startsWith('v1/blobs/')) return '$method /v1/blobs/{hash}';
  return '$method /$path';
}

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
