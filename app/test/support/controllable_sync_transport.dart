import 'dart:io';

import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_http_client.dart';

/// A [SyncCoordinatorTransport] whose `getStore`/`createStore` results are set
/// by the test and whose call counts are inspectable, for guarding the §6.14
/// item 6 replacement invariants (confirm creates once; cancel issues no
/// `POST`). Every other member throws — a test that reaches one has drifted
/// outside the replacement flow it meant to exercise.
final class ControllableSyncTransport implements SyncCoordinatorTransport {
  SyncStoreResult getStoreResult = SyncStoreResult(
    response: const SyncHttpResponse(
      statusCode: HttpStatus.ok,
      kind: SyncResponseKind.success,
      headers: {},
      body: [],
    ),
  );
  SyncHttpResponse createStoreResponse = const SyncHttpResponse(
    statusCode: HttpStatus.created,
    kind: SyncResponseKind.created,
    headers: {},
    body: [],
  );

  int getStoreCalls = 0;
  int createStoreCalls = 0;

  @override
  Future<SyncStoreResult> getStore({required bool previouslyUsed}) async {
    getStoreCalls++;
    return getStoreResult;
  }

  @override
  Future<SyncHttpResponse> createStore() async {
    createStoreCalls++;
    return createStoreResponse;
  }

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
