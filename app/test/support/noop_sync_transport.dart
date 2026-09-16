import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';

/// A transport for coordinator lifecycle tests whose pass operation never
/// reaches the network-backed runner.
final class NoopSyncCoordinatorTransport implements SyncCoordinatorTransport {
  @override
  Future<SyncStoreResult> getStore({required bool previouslyUsed}) async =>
      throw StateError('unexpected sync transport call');

  @override
  Future<SyncHttpResponse> createStore() async =>
      throw StateError('unexpected sync transport call');

  @override
  Future<SyncHttpResponse> getManifest(String deviceId, {String? etag}) async =>
      throw StateError('unexpected sync transport call');

  @override
  Future<SyncHttpResponse> putManifest(String deviceId, List<int> body) async =>
      throw StateError('unexpected sync transport call');

  @override
  Future<SyncHttpResponse> postMissing(Iterable<String> hashes) async =>
      throw StateError('unexpected sync transport call');

  @override
  Future<SyncHttpResponse> getBlob(String hash) async =>
      throw StateError('unexpected sync transport call');

  @override
  Future<SyncHttpResponse> putBlob(String hash, List<int> body) async =>
      throw StateError('unexpected sync transport call');
}
