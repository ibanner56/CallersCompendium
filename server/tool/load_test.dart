// Load test for the Athenaeum: measures how many requests a single server
// process can serve, so the request-rate limits in spec §5.4 can be chosen
// from a measurement rather than a guess.
//
// The real [AthenaeumApp] runs in its own isolate with every budget lifted, so
// the client's load generation does not share a thread with the server and no
// `429` caps the result. Run it on the hardware you intend to deploy to, with
// `--data-dir` on the disk the server will use: every authenticated request
// commits a SQLite write and a blob upload also flushes a file, so the disk's
// sync latency dominates and a tmpfs directory reports a fantasy.
//
//   dart run tool/load_test.dart
//   dart run tool/load_test.dart --scenario blob-put --concurrency 1,16,64
//   dart run tool/load_test.dart --data-dir /var/lib/athenaeum-loadtest --json
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:callers_compendium_server/callers_compendium_server.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

const _scenarios = ['store-get', 'blob-get', 'blob-put', 'first-sync'];
const _unlimited = 1 << 30;
const _unlimitedRate = 1073741824.0;
const _clientAddressHeader = 'x-load-test-client';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption(
      'scenario',
      allowed: [..._scenarios, 'all'],
      defaultsTo: ['all'],
      help:
          'store-get: GET /v1/store. blob-get: GET one record blob. '
          'blob-put: PUT a fresh record blob. first-sync: one device '
          'uploading a whole library into a new store.',
    )
    ..addOption(
      'concurrency',
      defaultsTo: '1,4,16,64',
      help: 'Comma-separated in-flight request counts to step through.',
    )
    ..addOption(
      'duration',
      defaultsTo: '10',
      help:
          'Seconds per step. Workers start no new work after it, so a '
          'first-sync step also waits for its in-flight devices to finish.',
    )
    ..addOption(
      'stores',
      defaultsTo: '64',
      help: 'Stores the read and blob-put scenarios spread requests across.',
    )
    ..addOption(
      'records',
      defaultsTo: '500',
      help: 'Records per device in the first-sync scenario.',
    )
    ..addOption(
      'blob-bytes',
      defaultsTo: '1500',
      help: 'Approximate encoded size of each record blob.',
    )
    ..addOption(
      'data-dir',
      help:
          'Directory for the SQLite databases and blobs. Defaults to a '
          'temporary directory, which is deleted afterwards.',
    )
    ..addFlag(
      'shipped-request-limits',
      negatable: false,
      help:
          'Run with the shipped request-rate budgets instead of lifting '
          'them, each worker of each step as its own client address, to see '
          'where they refuse. The server-wide bucket carries over between '
          'steps, and workers retry a 429 at once rather than after a minute '
          'as the app does. The failure and creation budgets stay lifted.',
    )
    ..addFlag('json', negatable: false, help: 'Print results as JSON lines.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(arguments);
  if (options['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }
  final selected = (options['scenario'] as List<String>).contains('all')
      ? _scenarios
      : options['scenario'] as List<String>;
  final concurrencies = (options['concurrency'] as String)
      .split(',')
      .map((value) => int.parse(value.trim()))
      .toList();
  final duration = Duration(seconds: int.parse(options['duration'] as String));
  final storeCount = int.parse(options['stores'] as String);
  final recordCount = int.parse(options['records'] as String);
  final blobBytes = int.parse(options['blob-bytes'] as String);
  final json = options['json'] as bool;

  final suppliedDirectory = options['data-dir'] as String?;
  final dataDirectory = suppliedDirectory == null
      ? await Directory.systemTemp.createTemp('athenaeum-load-')
      : await Directory(suppliedDirectory).create(recursive: true);
  final server = await _ServerHandle.start(
    dataDirectory.path,
    shippedRequestLimits: options['shipped-request-limits'] as bool,
  );
  final client = HttpClient()
    ..maxConnectionsPerHost = concurrencies.reduce(max);
  final target = _Target(client, server.port);
  try {
    if (!json) {
      stdout.writeln(
        'Athenaeum load test — data dir ${dataDirectory.path}, '
        '${duration.inSeconds}s per step, blobs ~$blobBytes bytes',
      );
    }
    final fixture = await _Fixture.create(target, storeCount, blobBytes);
    for (final scenario in selected) {
      if (!json) stdout.writeln('\n$scenario');
      if (!json) stdout.writeln(_Result.header);
      for (final concurrency in concurrencies) {
        final result = await _run(
          scenario,
          shared: target,
          fixture: fixture,
          concurrency: concurrency,
          duration: duration,
          recordCount: recordCount,
          blobBytes: blobBytes,
        );
        stdout.writeln(json ? jsonEncode(result.toJson()) : result.row());
      }
    }
  } finally {
    client.close(force: true);
    await server.stop();
    if (suppliedDirectory == null) {
      await dataDirectory.delete(recursive: true);
    }
  }
}

Future<_Result> _run(
  String scenario, {
  required _Target shared,
  required _Fixture fixture,
  required int concurrency,
  required Duration duration,
  required int recordCount,
  required int blobBytes,
}) async {
  final recorder = _Recorder(scenario, concurrency);
  final deadline = DateTime.now().add(duration);
  var sequence = 0;
  final random = Random(concurrency);

  Future<void> worker(int index) async {
    final target = shared.as('$scenario-$concurrency-worker-$index');
    while (DateTime.now().isBefore(deadline)) {
      final n = sequence++;
      switch (scenario) {
        case 'store-get':
          final store = fixture.stores[random.nextInt(fixture.stores.length)];
          await recorder.time(() => target.request('GET', '/v1/store', store));
        case 'blob-get':
          final store = fixture.stores[random.nextInt(fixture.stores.length)];
          await recorder.time(
            () => target.request(
              'GET',
              '/v1/blobs/${fixture.hashes[store]}',
              store,
            ),
          );
        case 'blob-put':
          final store = fixture.stores[random.nextInt(fixture.stores.length)];
          final blob = _recordBlob('put-$concurrency-$n', blobBytes);
          await recorder.time(
            () => target.request(
              'PUT',
              '/v1/blobs/${sha256.convert(blob)}',
              store,
              body: blob,
              contentType: 'application/octet-stream',
            ),
            expected: 201,
          );
        case 'first-sync':
          await _firstSync(
            target,
            recorder,
            syncId: _syncId('sync$concurrency', n),
            recordCount: recordCount,
            blobBytes: blobBytes,
          );
      }
    }
  }

  final clock = Stopwatch()..start();
  await Future.wait([for (var i = 0; i < concurrency; i++) worker(i)]);
  clock.stop();
  return recorder.finish(clock.elapsed);
}

/// One device's first pass into an empty store, in the order the app's sync
/// coordinator sends it for a fresh attach: create, read the store, probe for
/// missing blobs and upload them, then the continuation pass reads the store
/// again, probes again before publishing, and publishes the manifest. The time
/// per device is the figure a rate limit stretches, so it is recorded alongside
/// the request latencies, and only when every request in the pass succeeded.
Future<void> _firstSync(
  _Target target,
  _Recorder recorder, {
  required String syncId,
  required int recordCount,
  required int blobBytes,
}) async {
  final started = Stopwatch()..start();
  Future<String?> step(
    String method,
    String path, {
    List<int>? body,
    String? contentType,
    int? expected,
  }) => recorder.time(
    () => target.request(
      method,
      path,
      syncId,
      body: body,
      contentType: contentType,
    ),
    expected: expected,
  );

  if (await step('POST', '/v1/store', expected: 201) == null) return;
  final store = await step('GET', '/v1/store', expected: 200);
  if (store == null) return;
  final epoch = (jsonDecode(store) as Map<String, Object?>)['epoch']! as String;
  final records = <String, ({String id, Uint8List blob})>{};
  for (var i = 0; i < recordCount; i++) {
    final id = 'c$i';
    final blob = _recordBlob(id, blobBytes);
    records[sha256.convert(blob).toString()] = (id: id, blob: blob);
  }
  final probe = utf8.encode(jsonEncode({'hashes': records.keys.toList()}));
  Future<String?> probeMissing() => step(
    'POST',
    '/v1/blobs/missing',
    body: probe,
    contentType: 'application/json; charset=utf-8',
    expected: 200,
  );

  if (await probeMissing() == null) return;
  for (final MapEntry(key: hash, value: record) in records.entries) {
    final uploaded = await step(
      'PUT',
      '/v1/blobs/$hash',
      body: record.blob,
      contentType: 'application/octet-stream',
      expected: 201,
    );
    if (uploaded == null) return;
  }
  if (await step('GET', '/v1/store', expected: 200) == null) return;
  if (await probeMissing() == null) return;
  final manifest = SyncManifest(
    deviceId: 'device-one',
    epoch: epoch,
    writtenAt: DateTime.now().toUtc(),
    records: {
      SyncRecordKind.choreographer: {
        for (final MapEntry(key: hash, value: record) in records.entries)
          record.id: hash,
      },
    },
  );
  final published = await step(
    'PUT',
    '/v1/manifests/device-one',
    body: encodeSyncManifestUtf8(manifest),
    contentType: 'application/json; charset=utf-8',
    expected: 201,
  );
  if (published == null) return;
  recorder.devices.add(started.elapsed);
}

/// A choreographer record padded to roughly [size] bytes. A choreographer is
/// used because its shareable body is small enough to construct here; the
/// server runs the same envelope and allow-list checks for every kind.
Uint8List _recordBlob(String id, int size) {
  Uint8List encode(String name) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'kind': 'choreographer',
        'id': id,
        'updatedAt': '2026-09-03T00:00:00.000Z',
        'deletedAt': null,
        'existenceAt': '2026-09-03T00:00:00.000Z',
        'body': {'id': id, 'name': name},
      }),
    ),
  );
  final bare = encode('');
  return encode('x' * max(0, size - bare.length));
}

/// Four hyphen-separated words satisfy the structural sync-ID rule.
String _syncId(String prefix, int n) => 'load-$prefix-store-$n';

class _Fixture {
  _Fixture(this.stores, this.hashes);

  final List<String> stores;
  final Map<String, String> hashes;

  static Future<_Fixture> create(
    _Target target,
    int storeCount,
    int blobBytes,
  ) async {
    final stores = <String>[];
    final hashes = <String, String>{};
    for (var i = 0; i < storeCount; i++) {
      final syncId = _syncId('fixture', i);
      final created = await target.request('POST', '/v1/store', syncId);
      _expectStatus(created, 201, 'create fixture store');
      final blob = _recordBlob('fixture-$i', blobBytes);
      final hash = sha256.convert(blob).toString();
      final put = await target.request(
        'PUT',
        '/v1/blobs/$hash',
        syncId,
        body: blob,
        contentType: 'application/octet-stream',
      );
      _expectStatus(put, 201, 'upload fixture blob');
      stores.add(syncId);
      hashes[syncId] = hash;
    }
    return _Fixture(stores, hashes);
  }

  static void _expectStatus(_Response response, int status, String step) {
    if (response.status != status) {
      throw StateError('could not $step: ${response.status} ${response.body}');
    }
  }
}

class _Response {
  const _Response(this.status, this.body);

  final int status;
  final String body;
}

class _Target {
  _Target(this.client, this.port, {this.clientAddress = 'fixture'});

  final HttpClient client;
  final int port;

  /// The address the server's rate limiter sees, sent as a header that only
  /// this tool's server reads.
  final String clientAddress;

  _Target as(String clientAddress) =>
      _Target(client, port, clientAddress: clientAddress);

  Future<_Response> request(
    String method,
    String path,
    String syncId, {
    List<int>? body,
    String? contentType,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.http('127.0.0.1:$port', path),
    );
    request.headers.set(
      'authorization',
      'Bearer ${encodeSyncCredential(syncId)}',
    );
    request.headers.set(_clientAddressHeader, clientAddress);
    if (contentType != null) request.headers.set('content-type', contentType);
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close();
    return _Response(
      response.statusCode,
      await response.transform(utf8.decoder).join(),
    );
  }
}

class _Recorder {
  _Recorder(this.scenario, this.concurrency);

  final String scenario;
  final int concurrency;
  final List<int> _latenciesMicros = [];
  final Map<int, int> _statuses = {};
  final List<Duration> devices = [];
  var _unexpected = 0;

  /// Times one request. Returns the body when the status is [expected] (any
  /// 2xx when null), otherwise counts it as unexpected and returns null.
  Future<String?> time(
    Future<_Response> Function() send, {
    int? expected,
  }) async {
    final watch = Stopwatch()..start();
    final response = await send();
    _latenciesMicros.add(watch.elapsedMicroseconds);
    _statuses.update(response.status, (n) => n + 1, ifAbsent: () => 1);
    final ok = expected == null
        ? response.status >= 200 && response.status < 300
        : response.status == expected;
    if (!ok) {
      _unexpected++;
      return null;
    }
    return response.body;
  }

  _Result finish(Duration elapsed) {
    _latenciesMicros.sort();
    double percentile(double p) => _latenciesMicros.isEmpty
        ? 0
        : _latenciesMicros[min(
                _latenciesMicros.length - 1,
                (p * _latenciesMicros.length).floor(),
              )] /
              1000;
    devices.sort();
    return _Result(
      scenario: scenario,
      concurrency: concurrency,
      requests: _latenciesMicros.length,
      elapsed: elapsed,
      p50Ms: percentile(0.50),
      p95Ms: percentile(0.95),
      p99Ms: percentile(0.99),
      statuses: Map.of(_statuses),
      unexpected: _unexpected,
      devices: devices.length,
      deviceMedian: devices.isEmpty ? null : devices[devices.length ~/ 2],
    );
  }
}

class _Result {
  _Result({
    required this.scenario,
    required this.concurrency,
    required this.requests,
    required this.elapsed,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.statuses,
    required this.unexpected,
    required this.devices,
    required this.deviceMedian,
  });

  final String scenario;
  final int concurrency;
  final int requests;
  final Duration elapsed;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final Map<int, int> statuses;
  final int unexpected;
  final int devices;
  final Duration? deviceMedian;

  double get perSecond =>
      requests / (elapsed.inMicroseconds / Duration.microsecondsPerSecond);

  static const header =
      '  conc    req/s    p50 ms    p95 ms    p99 ms  unexpected  statuses';

  String row() {
    final statusText = (statuses.keys.toList()..sort())
        .map((status) => '$status×${statuses[status]}')
        .join(' ');
    final deviceText = deviceMedian == null
        ? ''
        : '  ($devices devices, median '
              '${(deviceMedian!.inMilliseconds / 1000).toStringAsFixed(2)}s each)';
    return '${concurrency.toString().padLeft(6)}'
        '${perSecond.toStringAsFixed(0).padLeft(9)}'
        '${p50Ms.toStringAsFixed(2).padLeft(10)}'
        '${p95Ms.toStringAsFixed(2).padLeft(10)}'
        '${p99Ms.toStringAsFixed(2).padLeft(10)}'
        '${unexpected.toString().padLeft(12)}'
        '  $statusText$deviceText';
  }

  Map<String, Object?> toJson() => {
    'scenario': scenario,
    'concurrency': concurrency,
    'requests': requests,
    'seconds': elapsed.inMicroseconds / Duration.microsecondsPerSecond,
    'perSecond': perSecond,
    'p50Ms': p50Ms,
    'p95Ms': p95Ms,
    'p99Ms': p99Ms,
    'statuses': {
      for (final entry in statuses.entries) '${entry.key}': entry.value,
    },
    'unexpected': unexpected,
    if (deviceMedian != null) 'devices': devices,
    if (deviceMedian != null)
      'deviceMedianSeconds': deviceMedian!.inMicroseconds / 1e6,
  };
}

/// The server, running in its own isolate so it has a thread to itself.
class _ServerHandle {
  _ServerHandle(this.port, this._control, this._isolate);

  final int port;
  final SendPort _control;
  final Isolate _isolate;

  static Future<_ServerHandle> start(
    String dataDirectory, {
    required bool shippedRequestLimits,
  }) async {
    // Readiness, an uncaught error and exit all arrive on one port, so a server
    // that dies before it is ready fails the run instead of hanging it.
    final events = ReceivePort();
    final isolate = await Isolate.spawn(
      _serve,
      (events.sendPort, dataDirectory, shippedRequestLimits),
      onError: events.sendPort,
      onExit: events.sendPort,
    );
    final first = await events.first;
    if (first case [final int port, final SendPort control]) {
      return _ServerHandle(port, control, isolate);
    }
    isolate.kill();
    throw StateError(switch (first) {
      [final error, final stack] => 'server failed to start: $error\n$stack',
      _ => 'server exited before it was ready',
    });
  }

  Future<void> stop() async {
    final done = ReceivePort();
    _control.send(done.sendPort);
    await done.first;
    _isolate.kill();
  }

  static Future<void> _serve((SendPort, String, bool) message) async {
    final (ready, dataDirectory, shippedRequestLimits) = message;
    const unlimitedRequests = AthenaeumBudgetLimits(
      perIpRequestsPerSecond: _unlimitedRate,
      perIpRequestBurst: _unlimited,
      perStoreRequestsPerSecond: _unlimitedRate,
      perStoreRequestBurst: _unlimited,
      perIpFailuresPerMinute: _unlimited,
      perIpFailureBurst: _unlimited,
      serverWideFailuresPerMinute: _unlimited,
      creationsPerMinute: _unlimited,
    );
    // The shipped request-rate rows; the defaults the fields fall back to.
    const shippedRequests = AthenaeumBudgetLimits(
      perIpFailuresPerMinute: _unlimited,
      perIpFailureBurst: _unlimited,
      serverWideFailuresPerMinute: _unlimited,
      creationsPerMinute: _unlimited,
    );
    final app = AthenaeumApp(
      config: AthenaeumConfig(
        dataDirectory: dataDirectory,
        pepper: List<int>.generate(32, (i) => i),
      ),
      clientAddressResolver: (request) =>
          request.headers[_clientAddressHeader] ?? 'load-test',
      budgetLimits: shippedRequestLimits ? shippedRequests : unlimitedRequests,
    );
    final server = await shelf_io.serve(
      app.handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    final control = ReceivePort();
    control.listen((reply) async {
      await server.close(force: true);
      app.store.close();
      control.close();
      (reply as SendPort).send(true);
    });
    ready.send([server.port, control.sendPort]);
  }
}
