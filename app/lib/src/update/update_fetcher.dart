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
  final uri = Uri.parse(manifestUrlForChannel(channel));
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
    // Any transport failure (offline, DNS, TLS, malformed URL) is a silent
    // no-op per the privacy contract — never surfaced as an error.
    return null;
  } finally {
    if (ownClient) effectiveClient.close();
  }
}
