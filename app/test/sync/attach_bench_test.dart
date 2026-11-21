// A measurement, not a check: fresh-attaches a new device to the library that
// `server/tool/attach_bench_server.dart` serves, through the production pass
// (`IsolatedSyncPassOperation`: worker isolate, real HTTP client, database on
// disk), and prints how many passes, requests and response bytes it took.
// Skipped unless `ATTACH_BENCH_PORT` names the bench server's port:
//
//     (cd server && dart run tool/attach_bench_server.dart --corpus c.json) &
//     ATTACH_BENCH_PORT=33390 flutter test test/sync/attach_bench_test.dart
//
// With `ATTACH_BENCH_PUBLISH=1` it then waits for the per-IP limit to refill
// and has the same device, now holding the library, publish it into the
// server's empty second store, and prints the same figures for that.
//
// Between failed passes it waits as `SyncController` would for a pass that
// stopped part-way with progress: the first backoff step (one minute), never
// sooner than `Retry-After`. The waits are real, because the server's rate
// limits run on its real clock.
import 'dart:convert';
import 'dart:io';

import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_isolate.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final port = int.tryParse(Platform.environment['ATTACH_BENCH_PORT'] ?? '');

  test(
    'fresh attach against the bench server',
    () async {
      final directory = await Directory.systemTemp.createTemp('attach-bench-');
      addTearDown(() => directory.delete(recursive: true));
      final databasePath = '${directory.path}/compendium.sqlite';
      final database = CompendiumDatabase(NativeDatabase(File(databasePath)));
      final repositories = CompendiumRepositories(database, contraTaxonomy);
      await repositories.ensureMigrated();
      await database.close();

      final endpoint = Uri.parse('http://127.0.0.1:$port');
      final client = HttpClient();
      addTearDown(client.close);
      Future<Map<String, Object?>> stats() async {
        final request = await client.getUrl(endpoint.resolve('/__bench/stats'));
        final response = await request.close();
        return jsonDecode(await utf8.decodeStream(response))
            as Map<String, Object?>;
      }

      await run(
        databasePath: databasePath,
        endpoint: endpoint,
        syncId: 'alpha-beta-gamma-delta',
        stats: stats,
      );
      if (Platform.environment['ATTACH_BENCH_PUBLISH'] != '1') return;
      // Burst 300 at 5 a second: a minute refills the per-IP bucket, and the
      // second is margin.
      await Future<void>.delayed(const Duration(minutes: 2));
      await stats();
      await run(
        databasePath: databasePath,
        endpoint: endpoint,
        syncId: 'epsilon-zeta-eta-theta',
        stats: stats,
      );
    },
    skip: port == null ? 'set ATTACH_BENCH_PORT to run' : false,
    timeout: Timeout.none,
  );
}

/// Runs passes until one does not fail, waiting between them as
/// `SyncController` would, and prints what they took.
Future<void> run({
  required String databasePath,
  required Uri endpoint,
  required String syncId,
  required Future<Map<String, Object?>> Function() stats,
}) async {
  await stats();
  final operation = IsolatedSyncPassOperation(
    databasePath: databasePath,
    endpoint: endpoint,
    syncId: syncId,
    deviceId: 'bench-device',
    peerManifestCache: SyncPeerManifestCache(),
  );
  final total = Stopwatch()..start();
  final passTimes = <int>[];
  SyncPassResult? last;
  for (var pass = 1; pass <= 200; pass++) {
    final watch = Stopwatch()..start();
    last = await operation.call();
    passTimes.add(watch.elapsedMilliseconds);
    if (last.status != SyncPassStatus.failed) break;
    expect(last.failure?.cause.isTransient, isTrue);
    final retryAfter = last.failure?.retryAfter ?? Duration.zero;
    const firstStep = Duration(minutes: 1);
    await Future<void>.delayed(retryAfter > firstStep ? retryAfter : firstStep);
  }
  total.stop();
  final counted = await stats();
  final reopened = CompendiumDatabase(NativeDatabase(File(databasePath)));
  final dances = await CompendiumRepositories(
    reopened,
    contraTaxonomy,
  ).dances.listAll();
  await reopened.close();
  final requests = counted['requests']! as Map<String, Object?>;
  final bytes = counted['bytes']! as Map<String, Object?>;
  // ignore: avoid_print
  print(
    const JsonEncoder.withIndent('  ').convert({
      'syncId': syncId,
      'status': last!.status.name,
      'reports': last.reports.length,
      'passes': passTimes.length,
      'passMilliseconds': passTimes,
      'wallSeconds': total.elapsedMilliseconds / 1000,
      'requestsTotal': requests.values.fold<int>(0, (a, b) => a + (b! as int)),
      'responseBytesTotal': bytes.values.fold<int>(
        0,
        (a, b) => a + (b! as int),
      ),
      'requests': requests,
      'responseBytes': bytes,
      'dancesApplied': dances.length,
    }),
  );
  expect(last.status, SyncPassStatus.completed);
}
