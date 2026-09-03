import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:shelf/shelf.dart';

import 'athenaeum_config.dart';
import 'athenaeum_store.dart';

typedef ClientAddressResolver = String Function(Request request);

class AthenaeumApp {
  AthenaeumApp({
    required AthenaeumConfig config,
    AthenaeumStore? store,
    ClientAddressResolver? clientAddressResolver,
  }) : config = config,
       store = store ?? AthenaeumStore(config: config),
       _clientAddressResolver = clientAddressResolver ?? _defaultClientAddress;

  final AthenaeumConfig config;
  final AthenaeumStore store;
  final ClientAddressResolver _clientAddressResolver;
  final _FailureBudget _failureBudget = _FailureBudget();
  final _CreationBudget _creationBudget = _CreationBudget();

  Handler get handler => call;

  Future<Response> call(Request request) async {
    final segments = request.url.pathSegments;
    if (segments.length < 2 || segments.first != 'v1') {
      return _jsonResponse(404, {'error': 'not found'});
    }
    try {
      return switch (segments[1]) {
        'store' => await _storeRoute(request, segments),
        'manifests' => await _manifestRoute(request, segments),
        'blobs' => await _blobRoute(request, segments),
        _ => _jsonResponse(404, {'error': 'not found'}),
      };
    } on _RequestFailure catch (error) {
      return _jsonResponse(error.status, {'error': error.message});
    }
  }

  Future<Response> _storeRoute(Request request, List<String> segments) async {
    if (segments.length != 2) return _jsonResponse(404, {'error': 'not found'});
    final auth = await _authenticate(request);
    if (auth.response != null) return auth.response!;
    final identity = auth.identity!;
    if (request.method == 'GET') {
      final storeRow = store.lookup(identity.idKey);
      if (storeRow == null) {
        return _failedResolution(request, 404, 'store not found');
      }
      store.touch(identity.idKey);
      return _jsonResponse(200, store.metadata(storeRow).toJson());
    }
    if (request.method == 'POST') {
      final body = await _readBody(request, 1);
      if (body.isNotEmpty) {
        throw const _RequestFailure(400, 'store creation has no body');
      }
      if (!_creationBudget.allow()) {
        return _rateLimitedResponse();
      }
      try {
        final created = store.create(identity.idKey);
        return _jsonResponse(201, store.metadata(created).toJson());
      } on StoreAlreadyExists {
        return _failedResolution(request, 409, 'store already exists');
      }
    }
    if (request.method == 'DELETE') {
      final storeRow = store.lookup(identity.idKey);
      if (storeRow == null) {
        return _failedResolution(request, 404, 'store not found');
      }
      store.deleteStore(identity.idKey);
      return Response(204);
    }
    return _methodNotAllowed();
  }

  Future<Response> _manifestRoute(
    Request request,
    List<String> segments,
  ) async {
    if (segments.length != 3) return _jsonResponse(404, {'error': 'not found'});
    final deviceId = segments[2];
    try {
      AthenaeumStore.validateDeviceId(deviceId);
    } on FormatException {
      throw const _RequestFailure(400, 'invalid device id');
    }
    final auth = await _authenticate(request);
    if (auth.response != null) return auth.response!;
    final identity = auth.identity!;
    final current = store.lookup(identity.idKey);
    if (current == null) {
      return _failedResolution(request, 404, 'store not found');
    }
    if (request.method == 'GET') {
      final manifest = store.manifest(identity.idKey, current.epoch, deviceId);
      if (manifest == null) {
        return _failedResolution(request, 404, 'manifest not found');
      }
      if (request.headers['if-none-match'] == '"${manifest.etag}"') {
        return Response(304, headers: {'etag': '"${manifest.etag}"'});
      }
      return Response(
        200,
        body: manifest.body,
        headers: {
          'content-type': 'application/json',
          'etag': '"${manifest.etag}"',
        },
      );
    }
    if (request.method == 'PUT') {
      _requireContentType(request, 'application/json');
      final body = await _readBody(request, maxManifestBytes);
      final manifest = _decodeManifest(body);
      if (manifest.deviceId != deviceId) {
        throw const _RequestFailure(
          400,
          'manifest device id does not match path',
        );
      }
      if (manifest.epoch != current.epoch) {
        throw const _RequestFailure(409, 'stale manifest epoch');
      }
      store.putManifest(
        idKey: identity.idKey,
        epoch: current.epoch,
        deviceId: deviceId,
        etag: rawBodyHash(body),
        writtenAt: manifest.writtenAt.millisecondsSinceEpoch ~/ 1000,
        body: body,
      );
      return Response(
        201,
        headers: {
          'content-type': 'application/json',
          'etag': '"${rawBodyHash(body)}"',
        },
      );
    }
    if (request.method == 'DELETE') {
      store.deleteManifest(identity.idKey, current.epoch, deviceId);
      return Response(204);
    }
    return _methodNotAllowed();
  }

  Future<Response> _blobRoute(Request request, List<String> segments) async {
    if (segments.length == 3 && segments[2] == 'missing') {
      if (request.method != 'POST') return _methodNotAllowed();
      _requireContentType(request, 'application/json');
      final auth = await _authenticate(request);
      if (auth.response != null) return auth.response!;
      final identity = auth.identity!;
      final current = store.lookup(identity.idKey);
      if (current == null) {
        return _failedResolution(request, 404, 'store not found');
      }
      final body = await _readBody(request, maxManifestBytes);
      final decoded = _decodeJson(body);
      if (decoded is! Map || decoded['hashes'] is! List) {
        throw const _RequestFailure(400, 'hashes must be an array');
      }
      final rawHashes = decoded['hashes'] as List;
      if (rawHashes.length > maxMissingHashes) {
        throw const _RequestFailure(413, 'too many hashes');
      }
      final hashes = <String>[];
      for (final value in rawHashes) {
        if (value is! String || !_validHash(value)) {
          throw const _RequestFailure(400, 'invalid blob hash');
        }
        hashes.add(value);
      }
      return _jsonResponse(200, {
        'missing': store.missingBlobs(identity.idKey, current.epoch, hashes),
      });
    }
    if (segments.length != 3) return _jsonResponse(404, {'error': 'not found'});
    final hash = segments[2];
    if (!_validHash(hash)) {
      throw const _RequestFailure(400, 'invalid blob hash');
    }
    final auth = await _authenticate(request);
    if (auth.response != null) return auth.response!;
    final identity = auth.identity!;
    final current = store.lookup(identity.idKey);
    if (current == null) {
      return _failedResolution(request, 404, 'store not found');
    }
    final reference = store.blobRef(identity.idKey, current.epoch, hash);
    if (request.method == 'GET') {
      if (reference == null) {
        return _failedResolution(request, 404, 'blob not found');
      }
      final file = store.blobFile(identity.idKey, current.epoch, hash);
      if (!file.existsSync()) {
        return _failedResolution(request, 404, 'blob not found');
      }
      return Response(
        200,
        body: file.readAsBytesSync(),
        headers: {
          'content-type': 'application/octet-stream',
          'cache-control': 'public, max-age=31536000, immutable',
        },
      );
    }
    if (request.method == 'PUT') {
      _requireContentType(request, 'application/octet-stream');
      final body = await _readBody(request, maxBlobBytes);
      if (rawBodyHash(body) != hash) {
        throw const _RequestFailure(400, 'blob body hash does not match path');
      }
      store.putBlob(
        idKey: identity.idKey,
        epoch: current.epoch,
        hash: hash,
        body: body,
      );
      return Response(200);
    }
    return _methodNotAllowed();
  }

  Future<_AuthResult> _authenticate(Request request) async {
    final address = _clientAddressResolver(request);
    final authorization = request.headers['authorization'];
    if (authorization == null ||
        !authorization.startsWith('Bearer ') ||
        authorization.length <= 7) {
      return _AuthResult.response(
        _failedResolution(request, 401, 'missing or malformed authorization'),
      );
    }
    final credential = authorization.substring(7);
    late final String decoded;
    try {
      decoded = decodeSyncCredential(credential);
    } on FormatException {
      return _AuthResult.response(
        _failureResponse(address, 401, 'malformed credential'),
      );
    }
    try {
      validateSyncId(decoded);
    } on FormatException {
      return _AuthResult.response(
        _failureResponse(address, 403, 'invalid sync id structure'),
      );
    }
    final idKey = deriveIncomingSyncIdKey(decoded, config.pepper);
    final current = store.lookup(idKey);
    if (current != null) {
      store.touch(idKey);
    }
    return _AuthResult.identity(_Identity(idKey, current));
  }

  Response _failedResolution(Request request, int status, String message) =>
      _failureResponse(_clientAddressResolver(request), status, message);

  Response _failureResponse(String address, int status, String message) {
    if (!_failureBudget.allow(address)) return _rateLimitedResponse();
    return _jsonResponse(status, {'error': message});
  }

  static void _requireContentType(Request request, String expected) {
    final value = request.headers['content-type'];
    if (value == null) return;
    final mediaType = value.split(';').first.trim().toLowerCase();
    if (mediaType != expected) {
      throw const _RequestFailure(415, 'unsupported content type');
    }
  }

  static Future<Uint8List> _readBody(Request request, int maxBytes) async {
    final declaredLength = int.tryParse(
      request.headers['content-length'] ?? '',
    );
    final encoding = request.headers['content-encoding']?.toLowerCase();
    if (encoding != null && encoding != 'gzip') {
      throw const _RequestFailure(415, 'unsupported content encoding');
    }
    final compressed = _ByteCounter();
    Stream<List<int>> input = _countingStream(request.read(), compressed);
    if (encoding == 'gzip') input = gzip.decoder.bind(input);
    final output = BytesBuilder(copy: false);
    var size = 0;
    var tooLarge =
        encoding != 'gzip' &&
        declaredLength != null &&
        declaredLength > maxBytes;
    try {
      await for (final chunk in input) {
        size += chunk.length;
        if (size > maxBytes || size > maxGzipBytes) {
          tooLarge = true;
        } else if (!tooLarge) {
          output.add(chunk);
        }
      }
    } on FormatException {
      throw const _RequestFailure(400, 'malformed compressed body');
    }
    if (tooLarge) {
      throw const _RequestFailure(413, 'request body exceeds limit');
    }
    if (encoding == 'gzip' &&
        compressed.value > 0 &&
        size > compressed.value * 10) {
      throw const _RequestFailure(
        413,
        'compressed request expansion exceeds limit',
      );
    }
    return output.takeBytes();
  }

  static Stream<List<int>> _countingStream(
    Stream<List<int>> source,
    _ByteCounter counter,
  ) async* {
    await for (final chunk in source) {
      counter.value += chunk.length;
      yield chunk;
    }
  }

  static SyncManifest _decodeManifest(Uint8List body) {
    try {
      final decoded = _decodeJson(body);
      validateJsonDepth(decoded);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('manifest must be an object');
      }
      return SyncManifest.fromJson(decoded);
    } on FormatException catch (error) {
      throw _RequestFailure(400, error.message);
    }
  }

  static Object? _decodeJson(Uint8List body) {
    try {
      final value = jsonDecode(utf8.decode(body, allowMalformed: false));
      try {
        validateJsonDepth(value);
      } on FormatException catch (error) {
        throw _RequestFailure(413, error.message);
      }
      return value;
    } on FormatException catch (error) {
      throw _RequestFailure(400, error.message);
    } on JsonUnsupportedObjectError {
      throw const _RequestFailure(400, 'invalid JSON');
    }
  }

  static bool _validHash(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  static Response _jsonResponse(int status, Object body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  static Response _rateLimitedResponse() => Response(
    429,
    body: jsonEncode({'error': 'rate limited'}),
    headers: {'content-type': 'application/json', 'retry-after': '60'},
  );

  static Response _methodNotAllowed() =>
      Response(405, headers: {'allow': 'GET, POST, PUT, DELETE'});

  static String _defaultClientAddress(Request request) => 'unknown';
}

class _AuthResult {
  const _AuthResult._({this.identity, this.response});

  factory _AuthResult.identity(_Identity identity) =>
      _AuthResult._(identity: identity);
  factory _AuthResult.response(Response response) =>
      _AuthResult._(response: response);

  final _Identity? identity;
  final Response? response;
}

class _Identity {
  const _Identity(this.idKey, this.store);

  final String idKey;
  final StoreRow? store;
}

class _ByteCounter {
  int value = 0;
}

class _RequestFailure implements Exception {
  const _RequestFailure(this.status, this.message);

  final int status;
  final String message;
}

class _FailureBudget {
  final Map<String, _TokenBucket> _perIp = {};
  final List<DateTime> _global = [];

  bool allow(String address) {
    final now = DateTime.now();
    _prune(_global, now);
    final bucket = _perIp.putIfAbsent(
      address,
      () => _TokenBucket(
        capacity: maxFailedResolutionsPerIpBurst,
        refillPerMinute: maxFailedResolutionsPerIp,
      ),
    );
    if (_global.length >= maxFailedResolutionsServerWide ||
        !bucket.tryTake(now)) {
      return false;
    }
    _global.add(now);
    return true;
  }

  static void _prune(List<DateTime> values, DateTime now) {
    values.removeWhere((value) => now.difference(value).inSeconds >= 60);
  }
}

class _TokenBucket {
  _TokenBucket({required this.capacity, required this.refillPerMinute})
    : _tokens = capacity.toDouble(),
      _updatedAt = DateTime.now();

  final int capacity;
  final int refillPerMinute;
  double _tokens;
  DateTime _updatedAt;

  bool tryTake(DateTime now) {
    final elapsedMinutes =
        now.difference(_updatedAt).inMicroseconds /
        Duration.microsecondsPerMinute;
    _tokens = (_tokens + elapsedMinutes * refillPerMinute)
        .clamp(0, capacity)
        .toDouble();
    _updatedAt = now;
    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }
}

class _CreationBudget {
  final List<DateTime> _timestamps = [];

  bool allow() {
    final now = DateTime.now();
    _timestamps.removeWhere((value) => now.difference(value).inSeconds >= 60);
    if (_timestamps.length >= maxStoreCreationsPerMinute) return false;
    _timestamps.add(now);
    return true;
  }
}
