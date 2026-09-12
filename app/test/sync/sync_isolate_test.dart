import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_isolate.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens the database and transport inside the pass isolate', () async {
    final directory = await Directory.systemTemp.createTemp(
      'compendium-sync-isolate-',
    );
    final database = CompendiumDatabase(
      NativeDatabase(File('${directory.path}/compendium.sqlite')),
    );
    final repositories = CompendiumRepositories(database, contraTaxonomy);
    await repositories.ensureMigrated();
    await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');

    final requests = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/v1/store') {
        request.response.write(
          jsonEncode({'epoch': 'epoch-1', 'devices': <String>[]}),
        );
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/blobs/missing') {
        request.response.write(jsonEncode({'missing': <String>[]}));
      } else if (request.method == 'PUT' &&
          request.uri.path == '/v1/manifests/device-a') {
        request.response.write('{}');
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('{}');
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await database.close();
      await directory.delete(recursive: true);
    });

    final terminalSeen = Completer<void>();
    final release = Completer<void>();
    final operation = IsolatedSyncPassOperation(
      databasePath: '${directory.path}/compendium.sqlite',
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      syncId: 'alpha-beta-gamma-delta',
      deviceId: 'device-a',
      beforeTerminalAcknowledgement: () {
        terminalSeen.complete();
        return release.future;
      },
    );
    final handle = await operation.start();
    await terminalSeen.future;
    var completed = false;
    final resultFuture = handle.result.then((result) {
      completed = true;
      return result;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    release.complete();
    final result = await resultFuture;

    expect(result.status, SyncPassStatus.completed);
    expect(requests, [
      'GET /v1/store',
      'POST /v1/blobs/missing',
      'PUT /v1/manifests/device-a',
    ]);
  });

  test('terminating during apply leaves an atomic database state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'compendium-sync-isolate-',
    );
    final databasePath = '${directory.path}/compendium.sqlite';
    final database = CompendiumDatabase(NativeDatabase(File(databasePath)));
    final repositories = CompendiumRepositories(database, contraTaxonomy);
    await repositories.ensureMigrated();
    await repositories.settings.set(
      'custom_dialects',
      'before-first',
      at: DateTime.utc(2026, 7, 15, 11),
    );
    await repositories.settings.set(
      'default_program_band',
      'before-second',
      at: DateTime.utc(2026, 7, 15, 11),
    );
    await repositories.syncLocal.replaceBaseline(epoch: 'epoch-1');
    await database.close();

    final first = _setting('custom_dialects', 'after-first', seconds: 1);
    final second = _setting('default_program_band', 'after-second', seconds: 2);
    final firstHash = sha256Hex(encodeSyncRecordBlobUtf8(first));
    final secondHash = sha256Hex(encodeSyncRecordBlobUtf8(second));
    final peerManifest = SyncManifest(
      deviceId: 'peer',
      epoch: 'epoch-1',
      writtenAt: DateTime.utc(2026, 7, 15, 12),
      records: {
        SyncRecordKind.setting: {first.id: firstHash, second.id: secondHash},
      },
    );
    final blobs = {
      firstHash: encodeSyncRecordBlobUtf8(first),
      secondHash: encodeSyncRecordBlobUtf8(second),
    };

    final requests = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/v1/store') {
        request.response.write(
          jsonEncode({
            'epoch': 'epoch-1',
            'devices': ['peer'],
          }),
        );
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/blobs/missing') {
        request.response.write(jsonEncode({'missing': <String>[]}));
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/manifests/peer') {
        request.response.write(encodeSyncManifest(peerManifest));
      } else if (request.method == 'GET' &&
          request.uri.path.startsWith('/v1/blobs/')) {
        final blob = blobs[request.uri.pathSegments.last];
        if (blob == null) {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('{}');
        } else {
          request.response.add(blob);
        }
      } else if (request.method == 'PUT' &&
          request.uri.path == '/v1/manifests/device-a') {
        request.response.write('{}');
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('{}');
      }
      await request.response.close();
    });

    final applyControl = SyncIsolateApplyControl();
    CompendiumDatabase? verificationDatabase;
    addTearDown(() async {
      await applyControl.close();
      await server.close(force: true);
      await verificationDatabase?.close();
      await directory.delete(recursive: true);
    });

    final operation = IsolatedSyncPassOperation(
      databasePath: databasePath,
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      syncId: 'alpha-beta-gamma-delta',
      deviceId: 'device-a',
    );
    final handle = await operation.start(applyControl: applyControl);
    await applyControl.applyStarted.timeout(const Duration(seconds: 10));
    handle.kill();
    await expectLater(handle.result, throwsA(isA<SyncIsolateInterrupted>()));

    verificationDatabase = CompendiumDatabase(
      NativeDatabase(File(databasePath)),
    );
    final verificationRepositories = CompendiumRepositories(
      verificationDatabase,
      contraTaxonomy,
    );
    final values = {
      'custom_dialects': await verificationRepositories.settings.get(
        'custom_dialects',
      ),
      'default_program_band': await verificationRepositories.settings.get(
        'default_program_band',
      ),
    };
    expect(values, {
      'custom_dialects': 'before-first',
      'default_program_band': 'before-second',
    });
    expect(
      await verificationRepositories.syncLocal.snapshotBaseline(),
      isEmpty,
    );
    expect(requests, contains('GET /v1/manifests/peer'));
  });
}

SyncRecordBlob _setting(String id, String value, {int seconds = 0}) {
  final stamp = DateTime.utc(2026, 7, 15, 12).add(Duration(seconds: seconds));
  return SyncRecordBlob(
    kind: SyncRecordKind.setting,
    id: id,
    updatedAt: stamp,
    deletedAt: null,
    existenceAt: stamp,
    body: {'value': value},
  );
}
