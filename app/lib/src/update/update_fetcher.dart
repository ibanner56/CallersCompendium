/// The injected fetch seam for the update check, mirroring the `UrlFetcher`
/// pattern in `app/lib/src/data/import_io.dart` (injectable `http.Client`,
/// short timeout). `package:http` is already an app dependency, so Stage 1 adds
/// none.
///
/// Unlike `UrlFetcher` — which throws a user-presentable [message] on failure —
/// the update fetcher is **message-safe and silent**: it returns `null` for any
/// failure (offline, timeout, 404, non-2xx, empty body) so the caller treats a
/// missing/unavailable manifest as a no-op, never an error dialog (ADR-002 §5).
/// This matters because the GitHub Pages manifest URL is not live until A11c.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'update_config.dart';
import 'update_manifest.dart';

/// Fetches the **raw wire bytes** of the manifest for [channel], or `null` on
/// any failure. Returning bytes (not a decoded `String`) is deliberate and
/// security-critical (issue #431): the signature must be verified over the
/// *exact* bytes the server sent. `package:http`'s `response.body` decodes
/// `bodyBytes` using the `Content-Type` charset and **defaults to latin1** when
/// the server sends no `charset`, so re-encoding that String as UTF-8 could
/// differ from the signed bytes for any non-ASCII content. The caller verifies
/// over these bytes and only then UTF-8-decodes for parsing.
///
/// Test seam: widget/unit tests pass a fake/`MockClient` to return canned bytes
/// (or fail) without a real network call.
typedef UpdateManifestFetcher =
    Future<List<int>?> Function(UpdateChannel channel, {http.Client? client});

/// Fetches the raw detached-signature text for [channel]'s manifest, or `null`
/// on any failure. Same injectable-seam pattern as [UpdateManifestFetcher] so
/// tests can return a canned signature (or `null`) without a real network call.
typedef UpdateManifestSignatureFetcher =
    Future<String?> Function(UpdateChannel channel, {http.Client? client});

/// Default [UpdateManifestFetcher]: a **plain HTTPS `GET`** of the channel's
/// static manifest with a short [kUpdateCheckTimeout]. Privacy contract
/// (ADR-002 §5): no query params, no fingerprinting/identifying headers (no
/// custom `User-Agent`, no app version, no OS/arch) — nothing beyond the bare
/// request is sent, and platform/arch selection happens client-side later.
///
/// Returns the response's **raw bytes** on a 2xx with a non-empty body, or
/// `null` for a timeout, an unreachable host (offline), a non-2xx status (e.g.
/// 404 before A11c publishes the page), or an empty body. Never throws. The
/// bytes are returned undecoded so the caller can verify the signature over the
/// exact wire bytes before trusting or decoding them.
Future<List<int>?> fetchUpdateManifest(
  UpdateChannel channel, {
  http.Client? client,
}) async {
  final uri = Uri.tryParse(manifestUrlForChannel(channel));
  if (uri == null) return null;
  final ownClient = client == null;
  final effectiveClient = client ?? http.Client();
  try {
    final response = await effectiveClient
        .get(uri)
        .timeout(kUpdateCheckTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    // Verify/parse operate on the exact wire bytes; never re-encode a decoded
    // String (which package:http may have decoded as latin1). An empty or
    // blank (ASCII-whitespace-only) body is a silent no-op like an unreachable
    // manifest. The whitespace check scans bytes directly — any non-whitespace
    // byte (including any non-ASCII byte) makes it a real body we keep verbatim.
    final bytes = response.bodyBytes;
    if (_isBlank(bytes)) return null;
    return bytes;
  } on TimeoutException {
    return null;
  } on Object {
    // Any transport failure (offline, DNS, TLS) is a silent no-op per the
    // privacy contract — never surfaced as an error. A malformed URL is caught
    // earlier by the Uri.tryParse guard above.
    return null;
  } finally {
    if (ownClient) effectiveClient.close();
  }
}

/// Whether [bytes] is empty or contains only ASCII whitespace (space, tab, CR,
/// LF, form-feed, vertical-tab). Used to treat an empty/blank manifest response
/// as a silent no-op without decoding the body (which would risk a latin1
/// misread). Any non-whitespace byte — including any non-ASCII byte — makes the
/// body "real" and it is kept verbatim for signature verification.
bool _isBlank(List<int> bytes) {
  for (final b in bytes) {
    // 0x20 space, 0x09 tab, 0x0A LF, 0x0D CR, 0x0C FF, 0x0B VT.
    if (b != 0x20 &&
        b != 0x09 &&
        b != 0x0A &&
        b != 0x0D &&
        b != 0x0C &&
        b != 0x0B) {
      return false;
    }
  }
  return true;
}

/// Default [UpdateManifestSignatureFetcher]: a **plain HTTPS `GET`** of the
/// channel manifest's `<channel>.json.sig` with the same short
/// [kUpdateCheckTimeout] and privacy contract as [fetchUpdateManifest] (no query
/// params, no identifying headers).
///
/// Returns the response body on a 2xx with a non-empty, within-bounds body, or
/// `null` for a timeout, an unreachable host, a non-2xx status (e.g. a 404
/// before the signature is published, or when signing is not yet enabled), an
/// empty body, or a body exceeding [kMaxSignatureBytes]. Never throws — a
/// missing signature is a silent no-op the caller turns into "no update"
/// (fail-closed) rather than an error dialog.
Future<String?> fetchUpdateManifestSignature(
  UpdateChannel channel, {
  http.Client? client,
}) async {
  final uri = Uri.tryParse(signatureUrlForChannel(channel));
  if (uri == null) return null;
  final ownClient = client == null;
  final effectiveClient = client ?? http.Client();
  try {
    final response = await effectiveClient
        .get(uri)
        .timeout(kUpdateCheckTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    // Bound the signature body before trusting it: a detached Ed25519 signature
    // is tiny (~88 base64 chars), so a larger body is malformed/hostile input.
    if (response.bodyBytes.length > kMaxSignatureBytes) return null;
    final body = response.body;
    if (body.trim().isEmpty) return null;
    return body;
  } on TimeoutException {
    return null;
  } on Object {
    return null;
  } finally {
    if (ownClient) effectiveClient.close();
  }
}
