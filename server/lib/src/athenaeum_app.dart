import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:shelf/shelf.dart';

import 'athenaeum_config.dart';
import 'athenaeum_store.dart';

typedef ClientAddressResolver = String Function(Request request);
typedef AthenaeumDiagnosticLogger =
    void Function(AthenaeumDiagnosticEvent event);
typedef AthenaeumPeriodicTimer =
    Timer Function(Duration interval, void Function(Timer timer) callback);
typedef AthenaeumSweep = void Function();

class AthenaeumDiagnosticEvent {
  const AthenaeumDiagnosticEvent({
    required this.status,
    required this.idKey,
    required this.hash,
  });

  final int status;
  final String? idKey;
  final String? hash;
  final Duration retention = const Duration(days: 30);

  Map<String, Object?> toJson() => {
    'status': status,
    'idKey': idKey,
    'hash': hash,
    'retentionDays': retention.inDays,
  };
}

class AthenaeumSweepController {
  AthenaeumSweepController(
    this.store, {
    AthenaeumPeriodicTimer? schedule,
    this.interval = const Duration(hours: 1),
    AthenaeumSweep? sweep,
  }) : _schedule = schedule ?? Timer.periodic,
       _sweep = sweep ?? store.sweep;

  final AthenaeumStore store;
  final AthenaeumPeriodicTimer _schedule;
  final AthenaeumSweep _sweep;
  final Duration interval;
  Timer? _timer;

  void start() {
    _timer ??= _schedule(interval, (_) {
      try {
        _sweep();
      } catch (error) {
        stderr.writeln('Athenaeum sweep failed (${error.runtimeType})');
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

const _blobEnvelopeKeys = <String>{
  'v',
  'kind',
  'id',
  'updatedAt',
  'deletedAt',
  'existenceAt',
  'body',
};

class AthenaeumBudgetLimits {
  const AthenaeumBudgetLimits({
    this.perIpFailuresPerMinute = maxFailedResolutionsPerIp,
    this.perIpFailureBurst = maxFailedResolutionsPerIpBurst,
    this.serverWideFailuresPerMinute = maxFailedResolutionsServerWide,
    this.creationsPerMinute = maxStoreCreationsPerMinute,
  });

  final int perIpFailuresPerMinute;
  final int perIpFailureBurst;
  final int serverWideFailuresPerMinute;
  final int creationsPerMinute;
}

class AthenaeumApp {
  AthenaeumApp({
    required AthenaeumConfig config,
    AthenaeumStore? store,
    ClientAddressResolver? clientAddressResolver,
    AthenaeumBudgetLimits budgetLimits = const AthenaeumBudgetLimits(),
    AthenaeumDiagnosticLogger? diagnosticLogger,
  }) : config = config,
       store = store ?? AthenaeumStore(config: config),
       _clientAddressResolver = clientAddressResolver ?? _defaultClientAddress,
       _failureBudget = _FailureBudget(budgetLimits),
       _creationBudget = _CreationBudget(budgetLimits) {
    _diagnosticLogger =
        diagnosticLogger ??
        (event) => this.store.recordDiagnostic(
          status: event.status,
          idKey: event.idKey,
          hash: event.hash,
        );
  }

  final AthenaeumConfig config;
  final AthenaeumStore store;
  final ClientAddressResolver _clientAddressResolver;
  final _FailureBudget _failureBudget;
  final _CreationBudget _creationBudget;
  late final AthenaeumDiagnosticLogger _diagnosticLogger;

  Handler get handler => call;

  Future<Response> call(Request request) async {
    store.retryPendingDeletions();
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
      _logFailure(request, error);
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
      final existing = store.lookup(identity.idKey);
      if (existing != null) {
        return _failedResolution(request, 409, 'store already exists');
      }
      if (!_creationBudget.allow()) return _rateLimitedResponse();
      var created = false;
      try {
        final storeRow = store.create(identity.idKey);
        created = true;
        return _jsonResponse(201, store.metadata(storeRow).toJson());
      } on StoreAlreadyExists {
        return _failedResolution(request, 409, 'store already exists');
      } finally {
        if (!created) _creationBudget.refund();
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
    return _methodNotAllowed(const ['GET', 'POST', 'DELETE']);
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
        return _jsonResponse(404, {'error': 'manifest not found'});
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
      if (_declaredLengthExceeds(request, maxManifestBytes)) {
        throw const _RequestFailure(413, 'request body exceeds limit');
      }
      try {
        store.manifestUploadPreflight(
          idKey: identity.idKey,
          epoch: current.epoch,
          deviceId: deviceId,
        );
      } on StoreEpochMismatch {
        throw const _RequestFailure(409, 'stale manifest epoch');
      } on StoreQuotaExceeded catch (error) {
        throw _RequestFailure(507, error.message);
      }
      final depthScanner = _MissingHashScanner();
      final body = await _readBody(
        request,
        maxManifestBytes,
        onChunk: depthScanner.add,
      );
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
      late final bool created;
      try {
        created = store.putManifest(
          idKey: identity.idKey,
          epoch: current.epoch,
          deviceId: deviceId,
          etag: rawBodyHash(body),
          writtenAt: manifest.writtenAt.millisecondsSinceEpoch ~/ 1000,
          body: body,
        );
      } on StoreEpochMismatch {
        throw const _RequestFailure(409, 'stale manifest epoch');
      } on StoreQuotaExceeded catch (error) {
        throw _RequestFailure(507, error.message);
      }
      try {
        store.collectGarbage(identity.idKey, current.epoch);
      } on Object catch (error) {
        stderr.writeln(
          'Athenaeum post-manifest garbage collection failed '
          '(${error.runtimeType})',
        );
      }
      return Response(
        created ? 201 : 200,
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
    return _methodNotAllowed(const ['GET', 'PUT', 'DELETE']);
  }

  Future<Response> _blobRoute(Request request, List<String> segments) async {
    if (segments.length == 3 && segments[2] == 'missing') {
      if (request.method != 'POST') return _methodNotAllowed(const ['POST']);
      _requireContentType(request, 'application/json');
      final auth = await _authenticate(request);
      if (auth.response != null) return auth.response!;
      final identity = auth.identity!;
      final current = store.lookup(identity.idKey);
      if (current == null) {
        return _failedResolution(request, 404, 'store not found');
      }
      if (_declaredLengthExceeds(request, maxManifestBytes)) {
        throw const _RequestFailure(413, 'request body exceeds limit');
      }
      final hashScanner = _MissingHashScanner();
      final body = await _readBody(
        request,
        maxManifestBytes,
        onChunk: hashScanner.add,
      );
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
        return _jsonResponse(404, {'error': 'blob not found'});
      }
      final file = store.blobFile(identity.idKey, current.epoch, hash);
      if (!file.existsSync()) {
        return _jsonResponse(404, {'error': 'blob not found'});
      }
      return Response(
        200,
        body: file.readAsBytesSync(),
        headers: {
          'content-type': 'application/octet-stream',
          'cache-control': 'private, max-age=31536000, immutable',
        },
      );
    }
    if (request.method == 'PUT') {
      _requireContentType(request, 'application/octet-stream');
      if (request.headers['content-encoding']?.toLowerCase() != 'gzip' &&
          _declaredLengthExceeds(request, maxBlobBytes)) {
        throw const _RequestFailure(413, 'request body exceeds limit');
      }
      late final int quotaLimit;
      try {
        quotaLimit = store.blobUploadLimit(identity.idKey, current.epoch, hash);
      } on StoreQuotaExceeded catch (error) {
        throw _RequestFailure(507, error.message);
      } on StoreEpochMismatch {
        throw const _RequestFailure(409, 'stale blob epoch');
      }
      if (request.headers['content-encoding']?.toLowerCase() != 'gzip' &&
          _declaredLengthExceeds(request, quotaLimit)) {
        throw const _RequestFailure(507, 'byte quota exhausted');
      }
      final body = await _readBody(
        request,
        maxBlobBytes,
        quotaBytes: quotaLimit,
      );
      if (rawBodyHash(body) != hash) {
        throw const _RequestFailure(400, 'blob body hash does not match path');
      }

      _validateBlobAllowList(body);

      late final bool created;
      try {
        created = store.putBlob(
          idKey: identity.idKey,
          epoch: current.epoch,
          hash: hash,
          body: body,
        );
      } on StoreQuotaExceeded catch (error) {
        throw _RequestFailure(507, error.message);
      } on StoreEpochMismatch {
        throw const _RequestFailure(409, 'stale blob epoch');
      }
      return Response(created ? 201 : 200);
    }
    return _methodNotAllowed(const ['GET', 'PUT']);
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

  void _logFailure(Request request, _RequestFailure error) {
    String? idKey;
    final authorization = request.headers['authorization'];
    if (authorization != null && authorization.startsWith('Bearer ')) {
      try {
        final syncId = decodeSyncCredential(authorization.substring(7));
        validateSyncId(syncId);
        idKey = deriveIncomingSyncIdKey(syncId, config.pepper);
      } on FormatException {
        idKey = null;
      }
    }
    String? hash;
    final segments = request.url.pathSegments;
    if (segments.length == 3 &&
        segments[1] == 'blobs' &&
        _validHash(segments[2])) {
      hash = segments[2];
    }
    if (idKey == null) return;
    try {
      _diagnosticLogger(
        AthenaeumDiagnosticEvent(
          status: error.status,
          idKey: idKey,
          hash: hash,
        ),
      );
    } on Object catch (loggerError) {
      stderr.writeln(
        'Athenaeum diagnostic logging failed (${loggerError.runtimeType})',
      );
    }
  }

  static void _requireContentType(Request request, String expected) {
    final value = request.headers['content-type'];
    if (value == null) return;
    final mediaType = value.split(';').first.trim().toLowerCase();
    if (mediaType != expected) {
      throw const _RequestFailure(415, 'unsupported content type');
    }
  }

  static Future<Uint8List> _readBody(
    Request request,
    int maxBytes, {
    void Function(List<int> chunk)? onChunk,
    int? quotaBytes,
  }) async {
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
    final iterator = StreamIterator(input);
    try {
      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        size += chunk.length;
        final expansionExceeded =
            encoding == 'gzip' &&
            compressed.value > 0 &&
            size > compressed.value * 10;
        if (size > maxBytes || size > maxGzipBytes || expansionExceeded) {
          await iterator.cancel();
          tooLarge = true;
          break;
        }
        if (quotaBytes != null && size > quotaBytes) {
          await iterator.cancel();
          throw const _RequestFailure(507, 'byte quota exhausted');
        } else if (!tooLarge) {
          onChunk?.call(chunk);
          output.add(chunk);
        }
      }
    } catch (error, stackTrace) {
      if (error is FormatException) {
        await iterator.cancel();
        throw const _RequestFailure(400, 'malformed compressed body');
      }
      await iterator.cancel();
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (tooLarge) {
      throw const _RequestFailure(413, 'request body exceeds limit');
    }
    return output.takeBytes();
  }

  static bool _declaredLengthExceeds(Request request, int maxBytes) {
    final length = int.tryParse(request.headers['content-length'] ?? '');
    return length != null &&
        request.headers['content-encoding']?.toLowerCase() != 'gzip' &&
        length > maxBytes;
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

  static void _validateBlobAllowList(Uint8List body) {
    final envelope = _inspectBlobEnvelope(body);
    if (!envelope.recognizable) return;
    _validateJsonDepthBytes(body);
    if (_hasDuplicateJsonKeys(body)) {
      throw const _RequestFailure(
        422,
        'blob contains an invalid record envelope',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(body, allowMalformed: false));
    } on FormatException {
      throw const _RequestFailure(
        422,
        'blob contains an invalid record envelope',
      );
    }
    if (decoded is! Map ||
        envelope.hasDuplicateKey ||
        envelope.hasUnknownKey ||
        envelope.keys.length != _blobEnvelopeKeys.length) {
      throw const _RequestFailure(
        422,
        'blob contains an invalid record envelope',
      );
    }

    final kindValue = decoded['kind'];
    final idValue = decoded['id'];
    final rawBody = decoded['body'];
    if (kindValue is! String || rawBody is! Map) {
      throw const _RequestFailure(
        422,
        'blob contains an invalid record envelope',
      );
    }
    final recordBody = <String, Object?>{};
    for (final entry in rawBody.entries) {
      if (entry.key is! String) return;
      recordBody[entry.key as String] = entry.value;
    }

    final kind = _recordKind(kindValue);
    if (kind == null) {
      throw const _RequestFailure(422, 'blob contains an unknown record kind');
    }
    final String? settingsKey = idValue is String ? idValue : null;
    if (kind == SyncRecordKind.setting && settingsKey == null) {
      throw const _RequestFailure(422, 'blob contains an invalid settings key');
    }
    final validation = validateShareableRecordBody(
      kind,
      recordBody,
      settingsKey: kind == SyncRecordKind.setting ? settingsKey : null,
    );
    if (!validation.isValid) {
      throw const _RequestFailure(422, 'blob contains a non-shareable field');
    }
  }

  static _BlobEnvelopeShape _inspectBlobEnvelope(Uint8List body) {
    String source;
    try {
      source = utf8.decode(body, allowMalformed: false);
    } on FormatException {
      return const _BlobEnvelopeShape();
    }
    var first = 0;
    while (first < source.length &&
        _isJsonWhitespace(source.codeUnitAt(first))) {
      first++;
    }
    if (first >= source.length || source.codeUnitAt(first) != 0x7b) {
      return const _BlobEnvelopeShape();
    }

    final keys = <String>{};
    var hasDuplicateKey = false;
    var hasUnknownKey = false;
    var depth = 0;
    var inString = false;
    var escaped = false;
    var stringStart = -1;
    for (var index = first; index < source.length; index++) {
      final code = source.codeUnitAt(index);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == 0x22) {
          inString = false;
          if (depth == 1) {
            var next = index + 1;
            while (next < source.length &&
                _isJsonWhitespace(source.codeUnitAt(next))) {
              next++;
            }
            if (next < source.length && source.codeUnitAt(next) == 0x3a) {
              try {
                final key = jsonDecode(
                  source.substring(stringStart, index + 1),
                );
                if (key is String) {
                  if (!_blobEnvelopeKeys.contains(key)) {
                    hasUnknownKey = true;
                  } else if (!keys.add(key)) {
                    hasDuplicateKey = true;
                  }
                }
              } on FormatException {
                // The complete JSON decode below handles malformed blobs.
              }
            }
          }
        }
        continue;
      }
      if (code == 0x22) {
        inString = true;
        stringStart = index;
      } else if (code == 0x7b || code == 0x5b) {
        depth++;
      } else if (code == 0x7d || code == 0x5d) {
        depth--;
      }
    }
    return _BlobEnvelopeShape(
      keys: keys,
      hasDuplicateKey: hasDuplicateKey,
      hasUnknownKey: hasUnknownKey,
    );
  }

  static bool _hasDuplicateJsonKeys(Uint8List body) {
    final source = utf8.decode(body, allowMalformed: false);
    final contexts = <Set<String>?>[];
    var inString = false;
    var escaped = false;
    var stringStart = -1;
    for (var index = 0; index < source.length; index++) {
      final code = source.codeUnitAt(index);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == 0x22) {
          inString = false;
          final context = contexts.isNotEmpty ? contexts.last : null;
          if (context != null) {
            var next = index + 1;
            while (next < source.length &&
                _isJsonWhitespace(source.codeUnitAt(next))) {
              next++;
            }
            if (next < source.length && source.codeUnitAt(next) == 0x3a) {
              try {
                final key = jsonDecode(
                  source.substring(stringStart, index + 1),
                );
                if (key is String && !context.add(key)) return true;
              } on FormatException {
                // The complete JSON decode below handles malformed blobs.
              }
            }
          }
        }
        continue;
      }
      if (code == 0x22) {
        inString = true;
        stringStart = index;
      } else if (code == 0x7b) {
        contexts.add(<String>{});
      } else if (code == 0x5b) {
        contexts.add(null);
      } else if (code == 0x7d || code == 0x5d) {
        if (contexts.isNotEmpty) contexts.removeLast();
      }
    }
    return false;
  }

  static bool _isJsonWhitespace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;

  static SyncRecordKind? _recordKind(String value) {
    for (final kind in SyncRecordKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }

  static Object? _decodeJson(Uint8List body) {
    try {
      _validateJsonDepthBytes(body);
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

  static void _validateJsonDepthBytes(Uint8List body) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (final byte in body) {
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (byte == 0x5c) {
          escaped = true;
        } else if (byte == 0x22) {
          inString = false;
        }
        continue;
      }
      if (byte == 0x22) {
        inString = true;
      } else if (byte == 0x5b || byte == 0x7b) {
        depth++;
        if (depth > maxJsonDepth) {
          throw const _RequestFailure(413, 'JSON nesting depth exceeds limit');
        }
      } else if (byte == 0x5d || byte == 0x7d) {
        depth--;
      }
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

  static Response _methodNotAllowed(Iterable<String> methods) =>
      Response(405, headers: {'allow': methods.join(', ')});

  static String _defaultClientAddress(Request request) => 'unknown';
}

class _BlobEnvelopeShape {
  const _BlobEnvelopeShape({
    this.keys = const <String>{},
    this.hasDuplicateKey = false,
    this.hasUnknownKey = false,
  });

  final Set<String> keys;
  final bool hasDuplicateKey;
  final bool hasUnknownKey;

  bool get recognizable =>
      keys.contains('v') &&
      keys.contains('kind') &&
      keys.contains('id') &&
      keys.contains('body');
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

class _MissingHashScanner {
  final List<_JsonContext> _contexts = [];
  var _inString = false;
  var _escaped = false;
  var _stringIsKey = false;
  var _keyAscii = true;
  var _key = StringBuffer();
  var _keyUnicodeDigits = 0;
  var _keyUnicodeValue = 0;
  var _pendingHashesKey = false;
  var _seenHashesKey = false;
  var _expectingHashValue = false;
  var _hashArrayDepth = 0;
  var _hashArrayExpectingValue = false;
  var _inPrimitive = false;
  var _count = 0;

  void add(List<int> bytes) {
    for (final byte in bytes) {
      if (_inString) {
        _consumeStringByte(byte);
        continue;
      }
      if (_inPrimitive) {
        if (_isDelimiter(byte)) {
          _inPrimitive = false;
        } else {
          continue;
        }
      }
      if (byte <= 0x20) continue;
      if (byte == 0x22) {
        _startString();
      } else if (byte == 0x7b) {
        _startContainer(object: true);
      } else if (byte == 0x5b) {
        _startContainer(object: false);
      } else if (byte == 0x7d || byte == 0x5d) {
        _endContainer();
      } else if (byte == 0x3a) {
        _consumeColon();
      } else if (byte == 0x2c) {
        _consumeComma();
      } else {
        _startPrimitive();
      }
    }
  }

  void _consumeStringByte(int byte) {
    if (_keyUnicodeDigits > 0) {
      final digit = _hexDigit(byte);
      if (digit < 0) {
        _keyAscii = false;
        _keyUnicodeDigits = 0;
        return;
      }
      _keyUnicodeValue = (_keyUnicodeValue << 4) | digit;
      _keyUnicodeDigits--;
      if (_keyUnicodeDigits == 0) {
        _appendDecodedKeyChar(_keyUnicodeValue);
      }
      return;
    }
    if (_escaped) {
      _escaped = false;
      if (_stringIsKey) {
        if (byte == 0x75) {
          _keyUnicodeDigits = 4;
          _keyUnicodeValue = 0;
        } else {
          switch (byte) {
            case 0x22:
            case 0x2f:
            case 0x5c:
              _key.writeCharCode(byte);
              break;
            default:
              _keyAscii = false;
          }
        }
      }
      return;
    }
    if (byte == 0x5c) {
      _escaped = true;
    } else if (byte == 0x22) {
      _inString = false;
      if (_stringIsKey) {
        final key = _keyAscii ? _key.toString() : null;
        _pendingHashesKey = _contexts.length == 1 && key == 'hashes';
        if (_pendingHashesKey) {
          if (_seenHashesKey) {
            throw const _RequestFailure(400, 'duplicate hashes key');
          }
          _seenHashesKey = true;
        }
      }
    } else if (_stringIsKey) {
      if (byte > 0x7f || byte < 0x20) {
        _keyAscii = false;
      } else {
        _key.writeCharCode(byte);
      }
    }
  }

  void _appendDecodedKeyChar(int charCode) {
    if (charCode > 0x7f || charCode < 0x20) {
      _keyAscii = false;
    } else {
      _key.writeCharCode(charCode);
    }
  }

  static int _hexDigit(int byte) {
    if (byte >= 0x30 && byte <= 0x39) return byte - 0x30;
    if (byte >= 0x41 && byte <= 0x46) return byte - 0x41 + 10;
    if (byte >= 0x61 && byte <= 0x66) return byte - 0x61 + 10;
    return -1;
  }

  void _startString() {
    _inString = true;
    _escaped = false;
    _stringIsKey =
        _contexts.isNotEmpty &&
        _contexts.last.object &&
        _contexts.last.expectingKey;
    _keyAscii = true;
    _key = StringBuffer();
    _keyUnicodeDigits = 0;
    _keyUnicodeValue = 0;
    _startHashValue();
  }

  void _startContainer({required bool object}) {
    if (_contexts.length >= maxJsonDepth) {
      throw const _RequestFailure(413, 'JSON nesting depth exceeds limit');
    }
    final isHashesValue = _expectingHashValue;
    _startHashValue();
    if (isHashesValue && !object) {
      _expectingHashValue = false;
      _hashArrayDepth = 1;
      _hashArrayExpectingValue = true;
    } else if (_hashArrayDepth > 0) {
      if (_hashArrayDepth == 1 && _hashArrayExpectingValue) {
        _countHashElement();
        _hashArrayExpectingValue = false;
      }
      _hashArrayDepth++;
    }
    _contexts.add(_JsonContext(object));
  }

  void _endContainer() {
    if (_hashArrayDepth > 0) {
      _hashArrayDepth--;
      if (_hashArrayDepth == 0) _hashArrayExpectingValue = false;
    }
    if (_contexts.isNotEmpty) _contexts.removeLast();
  }

  void _consumeColon() {
    if (_contexts.isEmpty || !_contexts.last.object) return;
    _contexts.last.expectingKey = false;
    if (_pendingHashesKey) {
      _expectingHashValue = true;
      _pendingHashesKey = false;
    }
  }

  void _consumeComma() {
    if (_hashArrayDepth == 1) _hashArrayExpectingValue = true;
    if (_contexts.isNotEmpty && _contexts.last.object) {
      _contexts.last.expectingKey = true;
    }
  }

  void _startPrimitive() {
    _startHashValue();
    _inPrimitive = true;
  }

  void _startHashValue() {
    if (_expectingHashValue) _expectingHashValue = false;
    if (_hashArrayDepth == 1 && _hashArrayExpectingValue) {
      _countHashElement();
      _hashArrayExpectingValue = false;
    }
  }

  void _countHashElement() {
    _count++;
    if (_count > maxMissingHashes) {
      throw const _RequestFailure(413, 'too many hashes');
    }
  }

  static bool _isDelimiter(int byte) =>
      byte <= 0x20 ||
      byte == 0x2c ||
      byte == 0x3a ||
      byte == 0x5d ||
      byte == 0x7d;
}

class _JsonContext {
  _JsonContext(this.object) : expectingKey = object;

  final bool object;
  bool expectingKey;
}

class _RequestFailure implements Exception {
  const _RequestFailure(this.status, this.message);

  final int status;
  final String message;
}

class _FailureBudget {
  _FailureBudget(AthenaeumBudgetLimits limits) : _limits = limits;

  final AthenaeumBudgetLimits _limits;
  final Map<String, _TokenBucket> _perIp = <String, _TokenBucket>{};
  final List<DateTime> _global = [];

  bool allow(String address) {
    final now = DateTime.now();
    _prune(_global, now);
    _perIp.removeWhere((_, bucket) => bucket.isInactive(now));
    if (_global.length >= _limits.serverWideFailuresPerMinute) return false;
    var bucket = _perIp[address];
    if (bucket == null) {
      if (_perIp.length >= maxFailedResolutionsServerWide) {
        return false;
      }
      bucket = _TokenBucket(
        capacity: _limits.perIpFailureBurst,
        refillPerMinute: _limits.perIpFailuresPerMinute,
      );
      _perIp[address] = bucket;
    }
    if (!bucket.tryTake(now)) {
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

  bool isInactive(DateTime now) =>
      now.difference(_updatedAt).inSeconds >=
      ((capacity * 60) / refillPerMinute).ceil();
}

class _CreationBudget {
  _CreationBudget(AthenaeumBudgetLimits limits)
    : _limit = limits.creationsPerMinute;

  final int _limit;
  final List<DateTime> _timestamps = [];

  bool allow() {
    final now = DateTime.now();
    _timestamps.removeWhere((value) => now.difference(value).inSeconds >= 60);
    if (_timestamps.length >= _limit) return false;
    _timestamps.add(now);
    return true;
  }

  void refund() {
    if (_timestamps.isNotEmpty) _timestamps.removeLast();
  }
}
