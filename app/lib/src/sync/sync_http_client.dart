import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:compendium_core/compendium_core.dart'
    show
        SyncBlobBatchFormatException,
        SyncBlobBatchFrame,
        SyncBlobBatchFrameReader,
        SyncBlobBatchFrameStatus,
        encodeSyncBlobBatchFrameHead,
        SyncId,
        encodeSyncCredential,
        normalizeSyncId,
        syncBlobBatchMaxResponseBytes,
        syncBlobBatchMediaType;

/// The project-operated Athenaeum, pre-filled in the pairing form. A user may
/// replace it with a self-hosted server; see `isDefaultSyncEndpoint`.
const String kDefaultSyncEndpoint = 'https://athenaeum.callerscompendium.com/';

/// Whether [endpoint] is the project-operated server. Compared by origin: a
/// differing path on the same origin is not a different trust decision.
bool isDefaultSyncEndpoint(Uri endpoint) =>
    endpoint.origin == Uri.parse(kDefaultSyncEndpoint).origin;

/// Parses and validates a user-entered endpoint (spec §8: https or an exact
/// `localhost`/`127.0.0.1`, no userinfo, query or fragment), or returns null.
Uri? tryParseSyncEndpoint(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null) return null;
  try {
    return validateSyncEndpoint(uri);
  } on SyncEndpointException {
    // diagnostics: silent — surfaced to the user as a typed field error.
    return null;
  }
}

/// Maximum number of redirect hops followed by the sync client.
const int syncMaxRedirects = 5;

/// Maximum uncompressed response body accepted by the client.
const int syncMaxResponseBytes = 32 * 1024 * 1024;

/// Maximum decoded manifest response body accepted by the client.
const int syncMaxManifestResponseBytes = 16 * 1024 * 1024;

/// Maximum decoded blob response body accepted by the client.
const int syncMaxBlobResponseBytes = 1 * 1024 * 1024;

/// Maximum decoded `POST /v1/blobs/batch` response body accepted by the
/// client: every blob byte the server may send in one response, plus a frame
/// for each hash it may name (spec §5.4).
const int syncMaxBlobBatchResponseBytes = syncBlobBatchMaxResponseBytes;

/// Maximum time allowed for one sync request, including its response body.
const Duration syncRequestTimeout = Duration(seconds: 30);

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

/// Raised when a request cannot complete before its transport deadline.
class SyncTransportException implements Exception {
  const SyncTransportException(this.message);

  final String message;

  @override
  String toString() => 'SyncTransportException: $message';
}

/// An authenticated, endpoint-isolated HTTP client for Device Sync.
class SyncHttpClient {
  SyncHttpClient({
    required Uri endpoint,
    required String syncId,
    this.maxRedirects = syncMaxRedirects,
    this.maxResponseBytes = syncMaxResponseBytes,
    this.requestTimeout = syncRequestTimeout,
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
    if (requestTimeout <= Duration.zero ||
        requestTimeout > syncRequestTimeout) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout');
    }
  }

  final Uri endpoint;
  final int maxRedirects;
  final int maxResponseBytes;
  final Duration requestTimeout;
  final SyncId _syncId;
  late http.Client _client;
  var _isClosed = false;

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
      _request(
        'GET',
        'manifests/${Uri.encodeComponent(deviceId)}',
        ifNoneMatch: etag,
        maxDecodedBytes: min(maxResponseBytes, syncMaxManifestResponseBytes),
        allowNotModified: etag != null,
      );

  /// Publishes a manifest body with the JSON media type.
  Future<SyncHttpResponse> putManifest(String deviceId, List<int> body) =>
      request(
        'PUT',
        'manifests/${Uri.encodeComponent(deviceId)}',
        body: body,
        contentType: 'application/json',
      );

  /// Fetches one content-addressed blob.
  Future<SyncHttpResponse> getBlob(String hash) => request(
    'GET',
    'blobs/${Uri.encodeComponent(hash)}',
    maxDecodedBytes: min(maxResponseBytes, syncMaxBlobResponseBytes),
  );

  /// Fetches the blobs for [hashes] in one request (spec §5.2,
  /// `POST /v1/blobs/batch`).
  ///
  /// When the server answers with a batch, each frame goes to [onFrame] as soon
  /// as it is complete, before the next is read, and the returned response has
  /// an empty body. So a response cut off part-way has already delivered every
  /// blob that arrived before the cut, and the throw that reports the cut
  /// loses none of them. A frame's blob is *not* verified here: the caller
  /// checks its hash, as for [getBlob].
  ///
  /// Any other answer is returned as [request] would return it. A `200` that is
  /// not a batch — a server or proxy that does not know the route — comes back
  /// as [SyncResponseKind.unexpectedStatus].
  Future<SyncHttpResponse> postBlobBatch(
    List<String> hashes, {
    required void Function(SyncBlobBatchFrame frame) onFrame,
  }) => _request(
    'POST',
    'blobs/batch',
    body: utf8.encode(jsonEncode({'hashes': hashes})),
    contentType: 'application/json',
    extraHeaders: const {'Accept-Encoding': 'gzip'},
    readSuccess: (response) => _readBlobBatch(response, hashes, onFrame),
  );

  /// Uploads [blobs] in one request (spec §5.2, `PUT /v1/blobs/batch`), as
  /// gzip-compressed blob frames.
  ///
  /// The response is returned as [request] would return it; for a batch the
  /// server stored, its body is the per-blob results, read by the caller.
  Future<SyncHttpResponse> putBlobBatch(
    List<({String hash, List<int> body})> blobs,
  ) {
    final frames = BytesBuilder(copy: false);
    for (final (:hash, :body) in blobs) {
      frames
        ..add(
          encodeSyncBlobBatchFrameHead(
            SyncBlobBatchFrameStatus.blob,
            hash,
            length: body.length,
          ),
        )
        ..add(body);
    }
    return request(
      'PUT',
      'blobs/batch',
      body: gzip.encode(frames.takeBytes()),
      contentType: syncBlobBatchMediaType,
      extraHeaders: const {'Content-Encoding': 'gzip'},
    );
  }

  /// Returns the content-addressed blobs the store does not yet have.
  Future<SyncHttpResponse> postMissing(Iterable<String> hashes) => request(
    'POST',
    'blobs/missing',
    body: utf8.encode(jsonEncode({'hashes': hashes.toList(growable: false)})),
    contentType: 'application/json',
  );

  /// Uploads one content-addressed blob without JSON encoding.
  Future<SyncHttpResponse> putBlob(String hash, List<int> body) => request(
    'PUT',
    'blobs/${Uri.encodeComponent(hash)}',
    body: body,
    contentType: 'application/octet-stream',
  );

  /// Removes one device's manifest from the store (spec §3.3): the remedy for
  /// a device that is genuinely gone, so its identifier stops holding one of
  /// the store's device slots and the aliases only it still lists can retire.
  ///
  /// Idempotent server-side — a manifest that is already absent still answers
  /// `204` — so a repeated call is not an error. A `404` here means the
  /// *store* is gone, not the manifest.
  Future<SyncHttpResponse> deleteManifest(String deviceId) =>
      request('DELETE', 'manifests/${Uri.encodeComponent(deviceId)}');

  /// Destroys the whole store and everything under the sync ID (spec glossary
  /// *wipe*, §5.3). Not reversible, and it affects every device at once.
  ///
  /// Answers `404` when no store exists for this sync ID, which is the end
  /// state the caller asked for rather than a failure.
  Future<SyncHttpResponse> deleteStore() => request('DELETE', 'store');

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
    int? maxDecodedBytes,
  }) => _request(
    method,
    relativePath,
    body: body,
    contentType: contentType,
    ifNoneMatch: ifNoneMatch,
    extraHeaders: extraHeaders,
    maxDecodedBytes: maxDecodedBytes,
  );

  Future<SyncHttpResponse> _request(
    String method,
    String relativePath, {
    List<int>? body,
    String? contentType,
    String? ifNoneMatch,
    Map<String, String> extraHeaders = const {},
    int? maxDecodedBytes,
    bool allowNotModified = false,
    Future<SyncHttpResponse> Function(http.StreamedResponse response)?
    readSuccess,
  }) async {
    final decodedLimit = maxDecodedBytes ?? maxResponseBytes;
    if (decodedLimit <= 0 || decodedLimit > maxResponseBytes) {
      throw ArgumentError.value(decodedLimit, 'maxDecodedBytes');
    }
    final initial = _uri(relativePath);
    var current = initial;
    var redirectMethod = method;
    var redirectBody = body;
    var redirectContentType = contentType;
    var redirectHeaders = extraHeaders;
    final elapsed = Stopwatch()..start();
    for (var redirects = 0; ; redirects++) {
      final request = http.Request(redirectMethod, current)
        ..followRedirects = false
        ..headers.addAll(redirectHeaders);
      request.headers['Authorization'] =
          'Bearer ${encodeSyncCredential(_syncId.value)}';
      if (redirectContentType != null) {
        request.headers['Content-Type'] = redirectContentType;
      }
      if (ifNoneMatch != null) request.headers['If-None-Match'] = ifNoneMatch;
      if (redirectBody != null) request.bodyBytes = redirectBody;

      final response = await _beforeDeadline(_client.send(request), elapsed);
      if (!_isRedirect(response.statusCode)) {
        return _beforeDeadline(
          readSuccess != null && response.statusCode == HttpStatus.ok
              ? readSuccess(response)
              : _readResponse(response, decodedLimit, allowNotModified),
          elapsed,
        );
      }

      try {
        await _beforeDeadline(
          _discardBoundedBody(response, decodedLimit),
          elapsed,
        );
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
      if (_redirectChangesToGet(response.statusCode, redirectMethod)) {
        redirectMethod = 'GET';
        redirectBody = null;
        redirectContentType = null;
        redirectHeaders = const {};
      }
      current = next;
    }
  }

  void close() {
    _isClosed = true;
    _client.close();
  }

  Future<T> _beforeDeadline<T>(Future<T> operation, Stopwatch elapsed) {
    final remaining = requestTimeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      _cancelTimedOutRequest();
      return Future<T>.error(
        const SyncTransportException('sync request timed out'),
      );
    }
    return operation.timeout(
      remaining,
      onTimeout: () {
        _cancelTimedOutRequest();
        throw const SyncTransportException('sync request timed out');
      },
    );
  }

  void _cancelTimedOutRequest() {
    _client.close();
    if (!_isClosed) _client = _defaultClient();
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
      _isDefaultPort(uri) &&
      _sameOrigin(endpoint, uri) &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      !uri.hasQuery;

  bool _isDefaultPort(Uri uri) =>
      _effectivePort(uri) == (uri.scheme.toLowerCase() == 'https' ? 443 : 80);

  bool _sameOrigin(Uri a, Uri b) =>
      a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
      a.host.toLowerCase() == b.host.toLowerCase() &&
      _effectivePort(a) == _effectivePort(b);

  int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  bool _redirectChangesToGet(int statusCode, String method) {
    if (method == 'HEAD') return false;
    if (statusCode == HttpStatus.seeOther) return true;
    return method == 'POST' &&
        (statusCode == HttpStatus.movedPermanently ||
            statusCode == HttpStatus.found);
  }

  Future<SyncHttpResponse> _readResponse(
    http.StreamedResponse response,
    int maxDecodedBytes,
    bool allowNotModified,
  ) async {
    final headers = Map<String, String>.unmodifiable(response.headers);
    final body = await _readBoundedBody(response, maxDecodedBytes);
    return SyncHttpResponse(
      statusCode: response.statusCode,
      kind: _kindForStatus(response.statusCode, allowNotModified),
      headers: headers,
      body: body,
      retryAfter: _retryAfter(headers['retry-after']),
    );
  }

  /// Buffers the body as bytes: a growable `List<int>` costs a machine word
  /// per byte, which a manifest-sized body would pay in the worker isolate.
  Future<Uint8List> _readBoundedBody(
    http.StreamedResponse response,
    int maxDecodedBytes,
  ) async {
    final bytes = BytesBuilder(copy: false);
    await _consumeBoundedBody(response, bytes.add, maxDecodedBytes);
    return bytes.takeBytes();
  }

  /// Reads a batch response frame by frame (spec §5.2), handing each to
  /// [onFrame] as it completes.
  ///
  /// Bounded by [syncMaxBlobBatchResponseBytes] decoded and slightly more
  /// encoded, and each blob by [syncMaxBlobResponseBytes]. Not by the 10×
  /// expansion guard [_consumeBoundedBody] applies elsewhere: real batches
  /// compress past it — a batch of programs, whose slots repeat the same
  /// keys, measured above 20× — and the guard exists to bound what a small
  /// response can make the client allocate, which the absolute cap already
  /// does here.
  Future<SyncHttpResponse> _readBlobBatch(
    http.StreamedResponse response,
    List<String> hashes,
    void Function(SyncBlobBatchFrame frame) onFrame,
  ) async {
    final headers = Map<String, String>.unmodifiable(response.headers);
    final maxDecoded = min(maxResponseBytes, syncMaxBlobBatchResponseBytes);
    final mediaType = headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (mediaType != syncBlobBatchMediaType) {
      await _discardBoundedBody(response, maxDecoded);
      return SyncHttpResponse(
        statusCode: response.statusCode,
        kind: SyncResponseKind.unexpectedStatus,
        headers: headers,
        body: const [],
      );
    }
    final encoding = headers['content-encoding']?.toLowerCase();
    // A stream of empty gzip members decodes to nothing, so the decoded cap
    // alone would never stop it.
    final maxEncoded = maxDecoded + (maxDecoded >> 8) + 1024;
    var encodedBytes = 0;
    Stream<List<int>> decoded = response.stream.map((chunk) {
      encodedBytes += chunk.length;
      if (encodedBytes > maxEncoded) {
        throw const SyncEndpointException('sync response exceeds size limit');
      }
      return chunk;
    });
    if (encoding == 'gzip') decoded = gzip.decoder.bind(decoded);
    final reader = SyncBlobBatchFrameReader(
      hashes,
      maxBlobBytes: syncMaxBlobResponseBytes,
    );
    var decodedBytes = 0;
    try {
      await for (final chunk in decoded) {
        decodedBytes += chunk.length;
        if (decodedBytes > maxDecoded) {
          throw const SyncEndpointException('sync response exceeds size limit');
        }
        reader.add(chunk, onFrame);
      }
      reader.close();
    } on SyncBlobBatchFormatException {
      // diagnostics: silent — rethrown as the transport's own malformed-reply
      // exception, which the caller logs before falling back to single
      // requests.
      throw const SyncEndpointException('malformed blob batch response');
    } on FormatException {
      // diagnostics: silent — the gzip decoder's answer to a corrupt body,
      // rethrown as above. Left as it is, it reads as an internal fault and
      // fails every pass, where a malformed batch should fall back.
      throw const SyncEndpointException('malformed blob batch response');
    }
    if (!reader.isComplete) {
      // The server ended the response cleanly without answering every hash:
      // what arrived has been handed on, and the rest is not fetched yet.
      throw const HttpException('blob batch response ended early');
    }
    return SyncHttpResponse(
      statusCode: response.statusCode,
      kind: SyncResponseKind.success,
      headers: headers,
      body: const [],
    );
  }

  Future<void> _discardBoundedBody(
    http.StreamedResponse response,
    int maxDecodedBytes,
  ) => _consumeBoundedBody(response, (_) {}, maxDecodedBytes);

  Future<void> _consumeBoundedBody(
    http.StreamedResponse response,
    void Function(List<int>) onChunk,
    int maxDecodedBytes,
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
      if (decodedBytes > maxDecodedBytes ||
          (encoding == 'gzip' &&
              decodedBytes >
                  min(maxDecodedBytes, max(1, compressedBytes * 10)))) {
        throw const SyncEndpointException('sync response exceeds size limit');
      }
      onChunk(chunk);
    }
  }

  SyncResponseKind _kindForStatus(int status, bool allowNotModified) =>
      syncResponseKindForStatus(status, allowNotModified: allowNotModified);

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
    } on HttpException {
      // diagnostics: silent — malformed Retry-After is treated as absent.
      return null;
    }
  }
}

/// The category a response with [status] falls in. Exposed so a status that
/// arrives inside a batch's results reads exactly as the same status on its
/// own request would (`PUT /v1/blobs/batch`, spec §5.2).
SyncResponseKind syncResponseKindForStatus(
  int status, {
  bool allowNotModified = false,
}) => switch (status) {
  200 => SyncResponseKind.success,
  201 => SyncResponseKind.created,
  204 => SyncResponseKind.success,
  304 when allowNotModified => SyncResponseKind.notModified,
  304 => SyncResponseKind.unexpectedStatus,
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
