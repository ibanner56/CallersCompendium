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

import 'package:flutter/foundation.dart' show visibleForTesting;
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
/// 404 before A11c publishes the page), an empty body, or a body exceeding
/// [kMaxManifestBytes]. Never throws. The body is **streamed** and the read
/// aborts as soon as the running total exceeds the cap, so an oversized
/// (misbehaving/compromised) response can never be fully buffered into memory
/// (OWASP A08). The bytes are returned undecoded so the caller can verify the
/// signature over the exact wire bytes before trusting or decoding them.
Future<List<int>?> fetchUpdateManifest(
  UpdateChannel channel, {
  http.Client? client,
}) async {
  final uri = Uri.tryParse(manifestUrlForChannel(channel));
  if (uri == null) return null;
  final ownClient = client == null;
  final effectiveClient = client ?? http.Client();
  try {
    final bytes = await _readBoundedBody(
      effectiveClient,
      uri,
      kMaxManifestBytes,
    ).timeout(kUpdateCheckTimeout);
    // Verify/parse operate on the exact wire bytes; never re-encode a decoded
    // String (which package:http may have decoded as latin1). An empty or
    // blank (ASCII-whitespace-only) body is a silent no-op like an unreachable
    // manifest. The whitespace check scans bytes directly — any non-whitespace
    // byte (including any non-ASCII byte) makes it a real body we keep verbatim.
    if (bytes == null || _isBlank(bytes)) return null;
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

/// Streams a **plain `GET`** of [uri] and accumulates the response body, but
/// **aborts as soon as the running total exceeds [maxBytes]** — returning
/// `null` without buffering the rest — so an oversized body cannot force a
/// large allocation (OWASP A08 / resource exhaustion). Returns the collected
/// bytes on a 2xx within the cap, or `null` for a non-2xx status or an
/// over-cap body. Redirects are followed **manually** (`followRedirects =
/// false`) so every hop is re-validated against [isAllowedArtifactHost] —
/// an https URL on [kAllowedArtifactHosts] with no userinfo and only the
/// default 443 port. This closes the downgrade/exfil hole that
/// `followRedirects = true` would otherwise leave open (mirrors
/// `artifact_downloader.dart:_sendFollowingHttpsRedirects`). The hop count is
/// capped at [kMaxArtifactRedirects]. Propagates transport and redirect errors
/// to the caller's `catch` (which turns them into a silent `null`).
Future<List<int>?> _readBoundedBody(
  http.Client client,
  Uri uri,
  int maxBytes,
) async {
  final response = await sendManifestFollowingHttpsRedirects(client, uri);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    // Drain (and thereby cancel) the body so the connection is freed; ignore
    // any error draining a failed response.
    unawaited(response.stream.drain<void>().catchError((Object _) {}));
    return null;
  }
  final bytes = <int>[];
  await for (final chunk in response.stream) {
    // Enforce the cap BEFORE appending: as soon as the cumulative size would
    // exceed maxBytes, abort. Returning here cancels the stream subscription,
    // so the remainder of an oversized body is never pulled or buffered.
    if (bytes.length + chunk.length > maxBytes) return null;
    bytes.addAll(chunk);
  }
  return bytes;
}

/// Sends a `GET` for [uri], following redirects **manually**
/// (`followRedirects = false`) so every request goes to an allowed host:
/// an https URL on [kAllowedArtifactHosts] with no userinfo and only the
/// default 443 port. The initial [uri] is validated before the first request
/// (mirroring `downloadArtifact`'s upfront guard) and every redirect target
/// is re-validated before the next request, so the invariant "every request
/// goes to an allowed host" holds for the whole chain, not just for hops.
/// This closes the downgrade/exfil hole that the `package:http` default
/// (`followRedirects = true`) would otherwise leave open — a manifest URL
/// that 30x-redirects to `http://…`, to an off-allowlist host, or via a
/// userinfo/port trick is refused rather than silently followed (mirrors
/// `artifact_downloader.dart:_sendFollowingHttpsRedirects`). The hop count is
/// capped at [kMaxArtifactRedirects]. Returns the final, non-redirect
/// [http.StreamedResponse] for the caller to stream.
///
/// Exposed for testing ([visibleForTesting]) so the upfront allowlist guard
/// on the initial [uri] can be verified directly, independently of the
/// hardcoded manifest URL the public API uses.
@visibleForTesting
Future<http.StreamedResponse> sendManifestFollowingHttpsRedirects(
  http.Client client,
  Uri uri,
) async {
  if (!isAllowedArtifactHost(uri)) {
    throw const _ManifestRedirectException(
      'initial URL is not an allowed host',
    );
  }
  var current = uri;
  for (var hops = 0; ; hops++) {
    final request = http.Request('GET', current)..followRedirects = false;
    final response = await client.send(request);
    if (!_isRedirectStatus(response.statusCode)) return response;

    await response.stream.drain<void>();
    if (hops >= kMaxArtifactRedirects) {
      throw const _ManifestRedirectException('too many redirects');
    }
    final location = response.headers['location'];
    if (location == null || location.isEmpty) {
      throw const _ManifestRedirectException('redirect without a location');
    }
    final next = current.resolve(location);
    if (!isAllowedArtifactHost(next)) {
      throw const _ManifestRedirectException(
        'refused redirect to a disallowed host',
      );
    }
    current = next;
  }
}

bool _isRedirectStatus(int status) =>
    status == 301 ||
    status == 302 ||
    status == 303 ||
    status == 307 ||
    status == 308;

/// Signals a redirect that [sendManifestFollowingHttpsRedirects] refused. Propagates
/// to the callers' `on Object` catch, which turns it into a silent `null`.
class _ManifestRedirectException implements Exception {
  const _ManifestRedirectException(this.message);
  final String message;

  @override
  String toString() => '_ManifestRedirectException: $message';
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
/// Returns the signature body on a 2xx with a non-empty, within-bounds body, or
/// `null` for a timeout, an unreachable host, a non-2xx status (e.g. a 404
/// before the signature is published, or when signing is not yet enabled), an
/// empty body, or a body exceeding [kMaxSignatureBytes]. The body is
/// **streamed** and the read aborts as soon as the running total exceeds the
/// cap, so an oversized body is never fully buffered (OWASP A08). Never throws —
/// a missing signature is a silent no-op the caller turns into "no update"
/// (fail-closed) rather than an error dialog. The signature is base64 (ASCII),
/// so the bounded bytes are decoded 1:1 to text.
Future<String?> fetchUpdateManifestSignature(
  UpdateChannel channel, {
  http.Client? client,
}) async {
  final uri = Uri.tryParse(signatureUrlForChannel(channel));
  if (uri == null) return null;
  final ownClient = client == null;
  final effectiveClient = client ?? http.Client();
  try {
    final bytes = await _readBoundedBody(
      effectiveClient,
      uri,
      kMaxSignatureBytes,
    ).timeout(kUpdateCheckTimeout);
    if (bytes == null || bytes.isEmpty) return null;
    // A detached Ed25519 signature is base64 (ASCII), so each byte maps 1:1 to
    // a code unit. The verifier base64-decodes + length-checks it and rejects
    // anything malformed, so we only need the text here.
    final body = String.fromCharCodes(bytes);
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
