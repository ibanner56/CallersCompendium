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

/// Fetches the raw manifest text for [channel], or `null` on any failure.
/// Test seam: widget/unit tests pass a fake/`MockClient` to return canned text
/// (or fail) without a real network call.
typedef UpdateManifestFetcher =
    Future<String?> Function(UpdateChannel channel, {http.Client? client});

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
/// Returns the response body on a 2xx with a non-empty body, or `null` for a
/// timeout, an unreachable host (offline), a non-2xx status (e.g. 404 before
/// A11c publishes the page), or an empty body. Never throws.
Future<String?> fetchUpdateManifest(
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
    final body = response.body;
    if (body.trim().isEmpty) return null;
    return body;
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
