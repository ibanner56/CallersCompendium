import 'dart:convert';

import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';
import 'package:compendium_core/compendium_core.dart';

/// One sync store held in memory, shared by every device a test attaches.
///
/// It answers the routes a pass uses the way the server does, and nothing
/// more: a manifest per device, content-addressed blobs, and the one epoch. The
/// batch routes answer `404`, as a server without them does, so a pass uses
/// the single-blob routes it falls back to.
///
/// Use [transportFor] to give each device its own [SyncCoordinatorTransport];
/// a manifest PUT through it is what lists that device in the store.
final class InMemorySyncServer {
  InMemorySyncServer({this.epoch = 'epoch-1'});

  final String epoch;
  final _manifests = <String, List<int>>{};
  final _blobs = <String, List<int>>{};
  final _devices = <String>[];

  /// The manifest [deviceId] last wrote, decoded; null before its first.
  SyncManifest? manifestOf(String deviceId) {
    final body = _manifests[deviceId];
    return body == null ? null : decodeSyncManifest(utf8.decode(body));
  }

  SyncCoordinatorTransport transportFor(String deviceId) =>
      _InMemoryTransport(this, deviceId);
}

final class _InMemoryTransport implements SyncCoordinatorTransport {
  _InMemoryTransport(this._server, this._deviceId);

  final InMemorySyncServer _server;
  final String _deviceId;

  @override
  Future<SyncStoreResult> getStore({required bool previouslyUsed}) async =>
      SyncStoreResult(
        response: _response(
          200,
          body: jsonEncode({
            'epoch': _server.epoch,
            'devices': [..._server._devices],
          }),
        ),
      );

  @override
  Future<SyncHttpResponse> createStore() async => _response(201);

  @override
  Future<SyncHttpResponse> getManifest(String deviceId, {String? etag}) async {
    final body = _server._manifests[deviceId];
    if (body == null) return _response(404);
    return SyncHttpResponse(
      statusCode: 200,
      kind: SyncResponseKind.success,
      headers: const {},
      body: body,
    );
  }

  @override
  Future<SyncHttpResponse> putManifest(String deviceId, List<int> body) async {
    assert(deviceId == _deviceId, 'a device writes only its own manifest');
    _server._manifests[deviceId] = [...body];
    if (!_server._devices.contains(deviceId)) _server._devices.add(deviceId);
    return _response(200);
  }

  @override
  Future<SyncHttpResponse> postMissing(Iterable<String> hashes) async =>
      _response(
        200,
        body: jsonEncode({
          'missing': [
            for (final hash in hashes)
              if (!_server._blobs.containsKey(hash)) hash,
          ],
        }),
      );

  @override
  Future<SyncHttpResponse> getBlob(String hash) async {
    final body = _server._blobs[hash];
    if (body == null) return _response(404);
    return SyncHttpResponse(
      statusCode: 200,
      kind: SyncResponseKind.success,
      headers: const {},
      body: body,
    );
  }

  @override
  Future<SyncHttpResponse> postBlobBatch(
    List<String> hashes, {
    required void Function(SyncBlobBatchFrame frame) onFrame,
  }) async => _response(404);

  @override
  Future<SyncHttpResponse> putBlob(String hash, List<int> body) async {
    _server._blobs[hash] = [...body];
    return _response(201);
  }

  @override
  Future<SyncHttpResponse> putBlobBatch(
    List<({String hash, List<int> body})> blobs,
  ) async => _response(404);

  static SyncHttpResponse _response(int status, {String? body}) =>
      SyncHttpResponse(
        statusCode: status,
        kind: switch (status) {
          200 => SyncResponseKind.success,
          201 => SyncResponseKind.created,
          404 => SyncResponseKind.notFound,
          _ => SyncResponseKind.unexpectedStatus,
        },
        headers: const {},
        body: body == null ? const [] : utf8.encode(body),
      );
}

/// One device attached to an [InMemorySyncServer]: its own database and a
/// real [SyncCoordinator] over a real [CompendiumSyncCoordinatorStore].
final class InMemorySyncDevice {
  InMemorySyncDevice(
    InMemorySyncServer server, {
    required this.deviceId,
    required this.repositories,
  }) : coordinator = SyncCoordinator(
         syncId: 'in-memory',
         deviceId: deviceId,
         store: CompendiumSyncCoordinatorStore(
           repositories,
           syncId: 'in-memory',
         ),
         transport: server.transportFor(deviceId),
       );

  final String deviceId;
  final CompendiumRepositories repositories;
  final SyncCoordinator coordinator;

  /// Runs one pass and returns it, failing loudly if it did not complete.
  Future<SyncPassResult> sync() async {
    var result = await coordinator.syncNow();
    // A first pass may stop to finish attaching; the next completes it.
    for (var i = 0; i < 3 && result.status != SyncPassStatus.completed; i++) {
      result = await coordinator.syncNow();
    }
    if (result.status != SyncPassStatus.completed) {
      throw StateError(
        'pass on $deviceId ended ${result.status}: ${result.message}',
      );
    }
    return result;
  }

  void dispose() => coordinator.dispose();
}
