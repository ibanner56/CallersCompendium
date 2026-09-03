import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:compendium_core/compendium_core.dart'
    show SyncId, encodeSyncCredential, normalizeSyncId;

/// Maximum number of redirect hops followed by the sync client.
const int syncMaxRedirects = 5;

/// Maximum uncompressed response body accepted by the client.
const int syncMaxResponseBytes = 32 * 1024 * 1024;

/// The result category for one sync HTTP response.
enum SyncResponseKind {
  success,
  created,
  notModified,
  malformedRequest,
  unauthorized,
  invalidSyncId,
  notFound,
  conflict,
  payloadTooLarge,
  unsupportedMediaType,
  rejected,
  rateLimited,
  quotaExhausted,
  redirectRefused,
  serverError,
  unexpectedStatus,
}

/// A bounded response with a typed status category.
class SyncHttpResponse {
  const SyncHttpResponse({
    required this.statusCode,
    required this.kind,
    required this.headers,
    required this.body,
    this.retryAfter,
  });

  final int statusCode;
  final SyncResponseKind kind;
  final Map<String, String> headers;
  final List<int> body;
  final Duration? retryAfter;

  bool get isSuccess =>
      kind == SyncResponseKind.success ||
      kind == SyncResponseKind.created ||
      kind == SyncResponseKind.notModified;
}

/// The two distinct missing-store states required by the pairing protocol.
enum SyncStoreMissingKind { firstTime, replacementRequired }

/// A store lookup result that preserves missing-store provenance.
class SyncStoreResult {
  const SyncStoreResult({required this.response, this.missingKind});

  final SyncHttpResponse response;
  final SyncStoreMissingKind? missingKind;

  bool get isMissing => missingKind != null;
}

/// Raised when an endpoint or redirect violates the sync transport policy.
class SyncEndpointException implements Exception {
  const SyncEndpointException(this.message);

  final String message;

  @override
  String toString() => 'SyncEndpointException: $message';
}

/// An authenticated, endpoint-isolated HTTP client for Device Sync.
class SyncHttpClient {
  SyncHttpClient({
    required Uri endpoint,
    required String syncId,
    this.maxRedirects = syncMaxRedirects,
    this.maxResponseBytes = syncMaxResponseBytes,
  }) : endpoint = validateSyncEndpoint(endpoint),
       _syncId = SyncId.parse(normalizeSyncId(syncId)),
       _client = _defaultClient() {
    if (maxRedirects < 0) {
      throw ArgumentError.value(maxRedirects, 'maxRedirects');
    }
    if (maxRedirects > syncMaxRedirects) {
      throw ArgumentError.value(maxRedirects, 'maxRedirects');
    }
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
    }
    if (maxResponseBytes > syncMaxResponseBytes) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
    }
  }

  final Uri endpoint;
  final int maxRedirects;
  final int maxResponseBytes;
  final SyncId _syncId;
  final http.Client _client;

  /// Sends a store lookup. This method never issues a creation request.
  Future<SyncStoreResult> getStore({required bool previouslyUsed}) async {
    final response = await request('GET', 'store');
    if (response.statusCode != HttpStatus.notFound) {
      return SyncStoreResult(response: response);
    }
    return SyncStoreResult(
      response: response,
      missingKind: previouslyUsed
          ? SyncStoreMissingKind.replacementRequired
          : SyncStoreMissingKind.firstTime,
    );
  }

  /// Explicitly creates a store after the caller has made that decision.
  Future<SyncHttpResponse> createStore() => request('POST', 'store');

  /// Fetches a manifest and optionally supplies its strong ETag.
  Future<SyncHttpResponse> getManifest(String deviceId, {String? etag}) =>
      request(
        'GET',
        'manifests/${Uri.encodeComponent(deviceId)}',
        ifNoneMatch: etag,
      );

  /// Publishes a manifest body with the JSON media type.
  Future<SyncHttpResponse> putManifest(
    String deviceId,
    List<int> body, {
    required String epoch,
  }) => request(
    'PUT',
    'manifests/${Uri.encodeComponent(deviceId)}',
    body: body,
    contentType: 'application/json',
    extraHeaders: {'X-Sync-Epoch': epoch},
  );

  /// Fetches one content-addressed blob.
  Future<SyncHttpResponse> getBlob(String hash) =>
      request('GET', 'blobs/${Uri.encodeComponent(hash)}');

  /// Uploads one content-addressed blob without JSON encoding.
  Future<SyncHttpResponse> putBlob(String hash, List<int> body) => request(
    'PUT',
    'blobs/${Uri.encodeComponent(hash)}',
    body: body,
    contentType: 'application/octet-stream',
  );

  /// Sends one authenticated request under `/v1`.
  ///
  /// Redirects are followed manually so authorization is never sent to a
  /// foreign origin. The default [IOClient] uses the platform certificate and
  /// hostname verifier and does not install an override.
  Future<SyncHttpResponse> request(
    String method,
    String relativePath, {
    List<int>? body,
    String? contentType,
    String? ifNoneMatch,
    Map<String, String> extraHeaders = const {},
  }) async {
    final initial = _uri(relativePath);
    var current = initial;
    for (var redirects = 0; ; redirects++) {
      final request = http.Request(method, current)
        ..followRedirects = false
        ..headers.addAll(extraHeaders);
      request.headers['Authorization'] =
          'Bearer ${encodeSyncCredential(_syncId.value)}';
      if (contentType != null) request.headers['Content-Type'] = contentType;
      if (ifNoneMatch != null) request.headers['If-None-Match'] = ifNoneMatch;
      if (body != null) request.bodyBytes = body;

      final response = await _client.send(request);
      if (!_isRedirect(response.statusCode)) {
        return _readResponse(response);
      }

      try {
        await _discardBoundedBody(response);
      } on SyncEndpointException {
        // diagnostics: silent — redirect response is discarded and surfaced as
        // a typed redirectRefused result.
        return SyncHttpResponse(
          statusCode: response.statusCode,
          kind: SyncResponseKind.redirectRefused,
          headers: Map.unmodifiable(response.headers),
          body: const [],
        );
      }
      if (redirects >= maxRedirects) {
        return SyncHttpResponse(
          statusCode: response.statusCode,
          kind: SyncResponseKind.redirectRefused,
          headers: Map.unmodifiable(response.headers),
          body: const [],
        );
      }
      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        return SyncHttpResponse(
          statusCode: response.statusCode,
          kind: SyncResponseKind.redirectRefused,
          headers: Map.unmodifiable(response.headers),
          body: const [],
        );
      }
      final parsed = Uri.tryParse(location);
      if (parsed == null) {
        return SyncHttpResponse(
          statusCode: response.statusCode,
          kind: SyncResponseKind.redirectRefused,
          headers: Map.unmodifiable(response.headers),
          body: const [],
        );
      }
      final next = current.resolveUri(parsed);
      if (!_isAllowedRedirect(next)) {
        return SyncHttpResponse(
          statusCode: response.statusCode,
          kind: SyncResponseKind.redirectRefused,
          headers: Map.unmodifiable(response.headers),
          body: const [],
        );
      }
      current = next;
    }
  }

  void close() {
    _client.close();
  }

  Uri _uri(String relativePath) {
    if (relativePath.startsWith('/') || relativePath.contains('..')) {
      throw ArgumentError.value(relativePath, 'relativePath');
    }
    final base = endpoint.path.endsWith('/')
        ? endpoint
        : endpoint.replace(path: '${endpoint.path}/');
    return base.resolve('v1/$relativePath');
  }

  bool _isAllowedRedirect(Uri uri) =>
      _sameOrigin(endpoint, uri) &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      !uri.hasQuery;

  bool _sameOrigin(Uri a, Uri b) =>
      a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
      a.host.toLowerCase() == b.host.toLowerCase() &&
      _effectivePort(a) == _effectivePort(b);

  int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  Future<SyncHttpResponse> _readResponse(http.StreamedResponse response) async {
    final headers = Map<String, String>.unmodifiable(response.headers);
    final body = await _readBoundedBody(response);
    return SyncHttpResponse(
      statusCode: response.statusCode,
      kind: _kindForStatus(response.statusCode),
      headers: headers,
      body: body,
      retryAfter: _retryAfter(headers['retry-after']),
    );
  }

  Future<List<int>> _readBoundedBody(http.StreamedResponse response) async {
    final bytes = <int>[];
    await _consumeBoundedBody(response, bytes.addAll);
    return bytes;
  }

  Future<void> _discardBoundedBody(http.StreamedResponse response) =>
      _consumeBoundedBody(response, (_) {});

  Future<void> _consumeBoundedBody(
    http.StreamedResponse response,
    void Function(List<int>) onChunk,
  ) async {
    final encoding = response.headers['content-encoding']?.toLowerCase();
    var compressedBytes = 0;
    var decodedBytes = 0;
    Stream<List<int>> decoded = response.stream;
    if (encoding == 'gzip') {
      final source = response.stream.map((chunk) {
        compressedBytes += chunk.length;
        return chunk;
      });
      decoded = gzip.decoder.bind(source);
    }
    await for (final chunk in decoded) {
      decodedBytes += chunk.length;
      if (decodedBytes > maxResponseBytes ||
          (encoding == 'gzip' &&
              decodedBytes >
                  min(maxResponseBytes, max(1, compressedBytes * 10)))) {
        throw const SyncEndpointException('sync response exceeds size limit');
      }
      onChunk(chunk);
    }
  }

  SyncResponseKind _kindForStatus(int status) => switch (status) {
    200 => SyncResponseKind.success,
    201 => SyncResponseKind.created,
    204 => SyncResponseKind.success,
    304 => SyncResponseKind.notModified,
    400 => SyncResponseKind.malformedRequest,
    401 => SyncResponseKind.unauthorized,
    403 => SyncResponseKind.invalidSyncId,
    404 => SyncResponseKind.notFound,
    409 => SyncResponseKind.conflict,
    413 => SyncResponseKind.payloadTooLarge,
    415 => SyncResponseKind.unsupportedMediaType,
    422 => SyncResponseKind.rejected,
    429 => SyncResponseKind.rateLimited,
    507 => SyncResponseKind.quotaExhausted,
    >= 500 && <= 599 => SyncResponseKind.serverError,
    _ => SyncResponseKind.unexpectedStatus,
  };

  Duration? _retryAfter(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    final seconds = int.tryParse(trimmed);
    if (seconds != null) {
      return seconds < 0 ? null : Duration(seconds: seconds);
    }
    try {
      final delay = HttpDate.parse(trimmed).difference(DateTime.now().toUtc());
      return delay.isNegative ? Duration.zero : delay;
    } on FormatException {
      // diagnostics: silent — malformed Retry-After is treated as absent.
      return null;
    }
  }
}

Uri validateSyncEndpoint(Uri uri) {
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw const SyncEndpointException(
      'sync endpoint must not contain userinfo, query, or fragment',
    );
  }
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final localHttp =
      scheme == 'http' && (host == 'localhost' || host == '127.0.0.1');
  if (scheme != 'https' && !localHttp) {
    throw const SyncEndpointException(
      'sync endpoint must use HTTPS except exact localhost or 127.0.0.1',
    );
  }
  if (host.isEmpty) {
    throw const SyncEndpointException('sync endpoint must have a host');
  }
  return uri;
}

http.Client _defaultClient() => IOClient(HttpClient()..autoUncompress = false);

bool _isRedirect(int statusCode) =>
    statusCode == 301 ||
    statusCode == 302 ||
    statusCode == 303 ||
    statusCode == 307 ||
    statusCode == 308;
