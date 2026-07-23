import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../search/collection_query.dart' show ByPhraseSelections;

/// Hard cap on the size of a **local file** chosen for import, in bytes.
///
/// A picked file is **untrusted input** (OWASP A04 Insecure Design / A05
/// Security Misconfiguration — uncontrolled resource consumption): the native
/// open-file dialog hands us an arbitrary file (often originally sourced from a
/// "safer" community site, but still not to be trusted). We refuse anything
/// larger than this by reading the file as a **bounded stream** and failing
/// closed the instant more than this many bytes have been consumed (see
/// [readCappedBytes]), so a hostile or accidental multi-gigabyte file can't
/// exhaust memory. We deliberately do **not** trust a separate [XFile.length]
/// probe: a file can grow or be swapped between the probe and the read (a
/// TOCTOU window), so the cap is enforced *during* consumption, not before it.
/// 25 MiB is deliberately **aligned with the archive intake cap**
/// (`kMaxIncomingArchiveBytes`) and sits far above any real Compendium share
/// bundle or Caller's Companion `.USR` (the real ~20 MB CC sample fits with
/// margin) while bounding the blast radius. The `.USR` path adds *structural*
/// bounds on top of this (see `FmpReadLimits`) because the FileMaker reader's
/// per-table traversal makes a small-but-pathological file quadratic in work.
const int kMaxImportFileBytes = 25 * 1024 * 1024;

/// Raised when a picked import file exceeds [kMaxImportFileBytes], so the
/// oversized case is rejected *without* buffering the whole file into memory
/// (the bounded read abandons the stream as soon as the cap is crossed).
///
/// Carries only the typed [length] — no user prose. The presentation layer maps
/// this to a localized message (see `importFileTooLargeMessage` in
/// `import_error_labels.dart`); the data layer never bakes English in.
class ImportFileTooLargeException implements Exception {
  const ImportFileTooLargeException(this.length);

  /// The number of bytes consumed before the cap tripped (always greater than
  /// the cap; kept for diagnostics/tests — never shown to the user).
  final int length;

  @override
  String toString() => 'ImportFileTooLargeException(length: $length)';
}

/// Reads [stream] fully into memory, but **fails closed** the instant more than
/// [maxBytes] bytes have been consumed — throwing [ImportFileTooLargeException]
/// and abandoning the stream *without* buffering the remainder. Enforcing the
/// cap during consumption (rather than trusting a prior [XFile.length]) closes
/// the TOCTOU window: a file that grows or is swapped after it was picked still
/// can't push peak allocation past ~[maxBytes], because we stop reading the
/// moment the bound is crossed. A file of exactly [maxBytes] is accepted (the
/// boundary is inclusive), mirroring the archive intake cap.
///
/// Stream-typed (rather than [XFile]-typed) so the fail-closed behaviour is
/// unit-testable against a synthetic multi-chunk stream that keeps producing
/// data, with no real file or picker plugin.
Future<Uint8List> readCappedBytes(
  Stream<List<int>> stream, {
  int maxBytes = kMaxImportFileBytes,
}) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
    if (builder.length > maxBytes) {
      // `await for` cancels the subscription when we throw, so we never read
      // (or buffer) the rest of the file — allocation stays bounded even if the
      // underlying file keeps growing.
      throw ImportFileTooLargeException(builder.length);
    }
  }
  return builder.takeBytes();
}

/// Reads [file]'s raw bytes, failing closed via [readCappedBytes] if the file
/// exceeds [maxBytes]. Consumes [XFile.openRead] so the cap is enforced *while*
/// reading — an oversized (or mid-read growing) file is never fully buffered,
/// unlike a `length()`-then-`readAsBytes()` check, which trusts a stale length
/// and still allocates the whole file. Split out from [pickImportUsrFile] so
/// the cap is unit-testable without the native picker (tests inject an [XFile]
/// + a small [maxBytes], mirroring `ArchiveIntakeService`).
Future<Uint8List> readImportBytesCapped(
  XFile file, {
  int maxBytes = kMaxImportFileBytes,
}) => readCappedBytes(file.openRead(), maxBytes: maxBytes);

/// Reads [file]'s text, failing closed via [readImportBytesCapped] if the file
/// exceeds [maxBytes] *before* it is decoded to a string. The byte cap is
/// enforced while streaming (never trusting a prior length probe); only once
/// the whole content is confirmed within the cap is it UTF-8 decoded. The text
/// counterpart to [readImportBytesCapped] (used by the share-bundle path).
Future<String> readImportTextCapped(
  XFile file, {
  int maxBytes = kMaxImportFileBytes,
}) async {
  final bytes = await readImportBytesCapped(file, maxBytes: maxBytes);
  return utf8.decode(bytes);
}

/// Prompts the user to choose a source file for an import and returns its
/// contents, or `null` if they cancelled. See [pickImportFile] for the default
/// implementation; widget tests override this seam to return canned text so no
/// real file/picker plugin is invoked.
///
/// Mirrors [BackupPicker] in `backup_io.dart` — the import experience reuses the
/// same file-picker / paste-fallback shape as backup restore (ROADMAP 6.3).
typedef ImportPicker = Future<String?> Function();

/// Default [ImportPicker]: opens the native open-file dialog (via
/// `file_selector`), restricted to Compendium share bundles, and reads the
/// chosen file's text. Returns `null` when the user cancels.
///
/// Accepts both the app's dedicated share-bundle type — extension `.ccshare`,
/// exported UTI `org.callerscompendium.compendiumApp.share` (issue #298, PR 2) —
/// **and** plain `.json`/`public.json` for backward compatibility with bundles
/// produced before the dedicated type existed. The payload is the same
/// canonical Caller's Compendium JSON (`GenericJsonAdapter`) in either case. The
/// review flow itself is adapter-agnostic; a future source (CallersBox/ContraDB)
/// can supply its own picker/type group without changing the queue UI.
Future<String?> pickImportFile() async {
  const jsonGroup = XTypeGroup(
    label: 'Compendium share',
    extensions: ['ccshare', 'json'],
    uniformTypeIdentifiers: [
      'org.callerscompendium.compendiumApp.share',
      'public.json',
    ],
    mimeTypes: ['application/json'],
  );
  final file = await openFile(acceptedTypeGroups: const [jsonGroup]);
  if (file == null) return null;
  return readImportTextCapped(file);
}

/// Prompts the user to choose a **binary** source file for an import and returns
/// its raw bytes, or `null` if they cancelled. See [pickImportUsrFile] for the
/// default implementation; widget tests override this seam (via
/// [ImportSource.bytePicker]) to return canned bytes so no real picker plugin is
/// invoked.
///
/// Distinct from [ImportPicker] because binary sources (Caller's Companion
/// `.USR`, a FileMaker 12 database) must be read as bytes, not decoded as text.
typedef ImportBytePicker = Future<Uint8List?> Function();

/// Default [ImportBytePicker]: opens the native open-file dialog (via
/// `file_selector`), restricted to `.usr`, and reads the chosen file's bytes.
/// Returns `null` when the user cancels.
///
/// Wired for the Caller's Companion `.USR` migration (`docs/ROADMAP.md` 6.5):
/// the `.USR` is a binary FileMaker 12 container, so the review flow needs the
/// raw bytes to hand to `CallersCompanionUsrAdapter` (via `options['bytes']`),
/// not a decoded string.
Future<Uint8List?> pickImportUsrFile() async {
  const usrGroup = XTypeGroup(
    label: "Caller's Companion .USR",
    extensions: ['usr'],
    // FileMaker's `.usr` has no registered UTI/MIME; match on extension only.
    uniformTypeIdentifiers: ['public.data'],
  );
  final file = await openFile(acceptedTypeGroups: const [usrGroup]);
  if (file == null) return null;
  return readImportBytesCapped(file);
}

/// Fetches the text body of an import source over HTTP and returns it, or
/// throws a [UrlFetchException] with a user-presentable message. See
/// [fetchImportUrl] for the default implementation; tests override this seam to
/// return canned text (or throw) so no real network call is made.
///
/// Mirrors [ImportPicker] above — HTTP transport lives in the app layer only,
/// so the pure-Dart core adapters never perform I/O. The fetched body is fed to
/// the same adapter (`GenericJsonAdapter`) as the file/paste inputs; the source
/// URL is stashed on `ImportRequest.uri` for provenance. A future source
/// (CallersBox/ContraDB link) can reuse this seam without changing the queue.
typedef UrlFetcher = Future<String> Function(String url);

/// Why a [UrlFetcher] / URL builder / online-import step failed.
///
/// A discriminator carried by [UrlFetchException] so the data/service layer
/// never bakes user prose into an exception. The presentation layer maps each
/// reason to a localized message (see `importErrorMessage` in
/// `import_error_labels.dart`). Reasons whose message embeds a dynamic value
/// carry it as a typed field on the exception ([UrlFetchException.statusCode],
/// [UrlFetchException.timeoutSeconds]) — never as pre-formatted text and never
/// echoing a URL, path, or raw lower-layer/server error (OWASP; CWE-209).
enum UrlFetchFailureReason {
  // Generic URL import (fetchImportUrl / _guardFetchUri / _sendGuarded).
  emptyUrl,
  invalidUrl,
  insecureScheme,
  blockedHost,
  tooManyRedirects,
  responseTooLarge,
  timeout,
  unreachable,
  httpStatus,
  emptyResponse,
  // The Caller's Box.
  callersBoxEmptyInput,
  callersBoxInvalidUrl,
  callersBoxMissingId,
  callersBoxEmptySearch,
  callersBoxUnreachable,
  callersBoxHttpStatus,
  callersBoxEmptyPage,
  callersBoxNoImportableDance,
  callersBoxImportFailed,
  // ContraDB.
  contraDbEmptyTitle,
  contraDbEmptyDanceInput,
  contraDbInvalidDanceUrl,
  contraDbMissingDanceId,
  contraDbEmptyProgramInput,
  contraDbInvalidProgramUrl,
  contraDbMissingProgramId,
  contraDbInvalidProgramLink,
  contraDbUnreachable,
  contraDbHttpStatus,
  contraDbEmptyResponse,
  contraDbNoImportableDance,
  contraDbImportFailed,
  // Shared by the Caller's Box + ContraDB search transports (identical wording).
  searchTimeout,
}

/// Raised by a [UrlFetcher] (or a URL builder / online-import step) when a URL
/// import cannot be completed.
///
/// Carries a typed [reason] discriminator plus any dynamic values as typed
/// fields — never pre-formatted user prose, and never a URL, path, or raw
/// lower-layer/server error (OWASP; CWE-209). The presentation layer maps
/// [reason] (with [statusCode] / [timeoutSeconds]) to a localized message.
class UrlFetchException implements Exception {
  const UrlFetchException(this.reason, {this.statusCode, this.timeoutSeconds})
    : assert(
        // An HTTP-status reason must carry the status code it describes.
        !(reason == UrlFetchFailureReason.httpStatus ||
                reason == UrlFetchFailureReason.callersBoxHttpStatus ||
                reason == UrlFetchFailureReason.contraDbHttpStatus) ||
            statusCode != null,
        'statusCode is required for an HTTP-status reason',
      ),
      assert(
        // A timeout reason must carry the elapsed seconds it describes.
        !(reason == UrlFetchFailureReason.timeout ||
                reason == UrlFetchFailureReason.searchTimeout) ||
            timeoutSeconds != null,
        'timeoutSeconds is required for a timeout reason',
      );

  /// Test-only seam that skips the field invariants enforced by the default
  /// constructor's asserts. It exists solely so tests can build the
  /// otherwise-unrepresentable "missing dynamic field" state (e.g. an
  /// [UrlFetchFailureReason.httpStatus] with a null [statusCode]) and verify
  /// that the presentation mapper degrades to a generic message in release
  /// builds — where the asserts are stripped — instead of rendering "HTTP 0".
  @visibleForTesting
  const UrlFetchException.withoutInvariants(
    this.reason, {
    this.statusCode,
    this.timeoutSeconds,
  });

  /// What went wrong.
  final UrlFetchFailureReason reason;

  /// The HTTP status code, for [UrlFetchFailureReason.httpStatus] /
  /// [UrlFetchFailureReason.callersBoxHttpStatus] /
  /// [UrlFetchFailureReason.contraDbHttpStatus]; `null` otherwise.
  final int? statusCode;

  /// The elapsed timeout in whole seconds, for [UrlFetchFailureReason.timeout] /
  /// [UrlFetchFailureReason.searchTimeout]; `null` otherwise.
  final int? timeoutSeconds;

  /// Debug-only, non-prose form (safe for logs — no user prose, no URL/path).
  @override
  String toString() =>
      'UrlFetchException(${reason.name}'
      '${statusCode != null ? ', statusCode: $statusCode' : ''}'
      '${timeoutSeconds != null ? ', timeoutSeconds: $timeoutSeconds' : ''})';
}

/// How long [fetchImportUrl] waits for a response before giving up.
const Duration importFetchTimeout = Duration(seconds: 30);

/// Hard cap on the number of bytes read from an import response body.
///
/// OWASP guidance (SSRF / uncontrolled resource consumption): a fetch of a
/// user-supplied URL must not be able to exhaust memory with a hostile or
/// accidentally huge response. 8 MiB comfortably exceeds any real dance /
/// program payload while bounding the blast radius; [_sendGuarded] aborts with
/// a generic [UrlFetchException] once this many bytes have been read.
const int importMaxResponseBytes = 8 * 1024 * 1024;

/// Maximum number of HTTP redirects [_sendGuarded] will follow before giving up.
///
/// Redirects are followed manually (not by `package:http`) so the SSRF host
/// guard can be re-applied to every hop's resolved `Location`; without a cap a
/// redirect loop could otherwise run forever. Five hops is generous for the
/// canonicalizing 30x's the supported sources use in practice.
const int importMaxRedirects = 5;

/// Returns `true` if [host] must not be fetched from an online-import path,
/// because it names a loopback / private / link-local / otherwise-reserved
/// destination inside the device's trust boundary (the SSRF blast radius:
/// localhost, the LAN, and cloud metadata at 169.254.169.254).
///
/// This is the core SSRF guard for every online-import fetch. The realistic
/// threat is the shared-link angle: a malicious author shares a crafted "import
/// link"; a victim pastes it and taps Fetch, causing the victim's own device to
/// issue a GET from inside its trust boundary. Blocking reserved destinations
/// kills that blast radius while still allowing legitimate **public**
/// self-hosted instances.
///
/// Behavior:
/// - `localhost`, `*.localhost`, and `*.local` hostnames are rejected.
/// - A value that parses as an IP literal is rejected when it falls in a
///   loopback / private / link-local / CGNAT / reserved / multicast range
///   (IPv4 and IPv6, including IPv4-mapped IPv6).
/// - Any other value (a real DNS hostname) is **allowed**. Per #332,
///   DNS-resolution-time IP checking (to defeat DNS rebinding) is an explicit
///   non-goal here; a hostname is trusted to resolve to a public address.
bool isBlockedImportHost(String host) {
  var h = host.trim().toLowerCase();
  if (h.isEmpty) return true;
  // Strip the brackets Dart keeps around IPv6 literals in a URI host.
  if (h.startsWith('[') && h.endsWith(']')) {
    h = h.substring(1, h.length - 1);
  }
  // Strip any trailing dot(s): a fully-qualified form like `localhost.` or
  // `127.0.0.1.` is equivalent to the bare name/IP, but would otherwise slip
  // past the hostname checks and parse as null (an "allowed" DNS host).
  while (h.endsWith('.')) {
    h = h.substring(0, h.length - 1);
  }
  if (h.isEmpty) return true;
  // Hostname-based blocks (these never parse as IPs).
  if (h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local')) {
    return true;
  }
  final addr = InternetAddress.tryParse(h);
  // A DNS hostname (not an IP literal) — allow; see the dartdoc non-goal note.
  if (addr == null) return false;
  return _isBlockedIp(addr);
}

/// Classifies a parsed IP literal as reserved (blocked) or public (allowed).
bool _isBlockedIp(InternetAddress addr) {
  final bytes = addr.rawAddress;
  if (addr.type == InternetAddressType.IPv4) {
    return _isBlockedIpv4(bytes);
  }
  // IPv4-mapped IPv6 (::ffff:a.b.c.d): re-check the embedded IPv4 so an
  // attacker can't smuggle 127.0.0.1 past the guard as ::ffff:127.0.0.1.
  if (_isIpv4MappedIpv6(bytes)) {
    return _isBlockedIpv4(bytes.sublist(12));
  }
  // :: (unspecified).
  if (bytes.every((b) => b == 0)) return true;
  // ::1 (loopback).
  var loopback = true;
  for (var i = 0; i < 15; i++) {
    if (bytes[i] != 0) {
      loopback = false;
      break;
    }
  }
  if (loopback && bytes[15] == 1) return true;
  final first = bytes[0];
  // fc00::/7 (unique local address).
  if ((first & 0xFE) == 0xFC) return true;
  // fe80::/10 (link-local).
  if (first == 0xFE && (bytes[1] & 0xC0) == 0x80) return true;
  // ff00::/8 (multicast).
  if (first == 0xFF) return true;
  return false;
}

/// `true` when 16 raw bytes are an IPv4-mapped IPv6 address (::ffff:0:0/96).
bool _isIpv4MappedIpv6(List<int> bytes) {
  for (var i = 0; i < 10; i++) {
    if (bytes[i] != 0) return false;
  }
  return bytes[10] == 0xFF && bytes[11] == 0xFF;
}

/// Classifies 4 raw IPv4 bytes as reserved (blocked) or public (allowed).
bool _isBlockedIpv4(List<int> b) {
  final o1 = b[0], o2 = b[1], o3 = b[2];
  // 0.0.0.0/8 ("this network").
  if (o1 == 0) return true;
  // 10.0.0.0/8 (private).
  if (o1 == 10) return true;
  // 127.0.0.0/8 (loopback).
  if (o1 == 127) return true;
  // 169.254.0.0/16 (link-local, incl. 169.254.169.254 cloud metadata).
  if (o1 == 169 && o2 == 254) return true;
  // 172.16.0.0/12 (private).
  if (o1 == 172 && o2 >= 16 && o2 <= 31) return true;
  // 192.168.0.0/16 (private).
  if (o1 == 192 && o2 == 168) return true;
  // 100.64.0.0/10 (carrier-grade NAT).
  if (o1 == 100 && o2 >= 64 && o2 <= 127) return true;
  // 192.0.0.0/24 (IETF protocol assignments).
  if (o1 == 192 && o2 == 0 && o3 == 0) return true;
  // 224.0.0.0/4 (multicast).
  if (o1 >= 224 && o1 <= 239) return true;
  // 240.0.0.0/4 (reserved) incl. 255.255.255.255 (broadcast).
  if (o1 >= 240) return true;
  return false;
}

/// Validates a fetch [uri] against the SSRF guard and returns a fetch-safe copy.
///
/// Requires an `https` scheme and rejects any [isBlockedImportHost] host with a
/// generic [UrlFetchException] (the message never echoes the URL, so pasted
/// credentials or internal hostnames can't leak into the UI). On success the
/// returned URI has any embedded `userInfo` (credentials) stripped.
///
/// Requiring `https` (rather than allowing cleartext `http`) enforces encrypted
/// transport at the import trust boundary: the supported community sources are
/// all https, so this breaks nothing real while blocking a MITM on a cleartext
/// import (OWASP A02 cryptographic failures / A08 data-integrity). Because
/// [_sendGuarded] re-runs this guard on every redirect hop, it also refuses an
/// `https` → `http` downgrade in a `30x` `Location`.
Uri _guardFetchUri(Uri uri) {
  if (!uri.isScheme('https')) {
    throw const UrlFetchException(UrlFetchFailureReason.insecureScheme);
  }
  if (isBlockedImportHost(uri.host)) {
    throw const UrlFetchException(UrlFetchFailureReason.blockedHost);
  }
  return uri.userInfo.isEmpty ? uri : uri.replace(userInfo: '');
}

/// Performs a guarded HTTP GET of [url] using [client], shared by every online
/// import fetcher so they all inherit the SSRF protections.
///
/// The initial URL and every redirect hop are validated with [_guardFetchUri],
/// redirects are followed manually (`followRedirects = false`) so the host
/// guard re-runs on each resolved `Location` (an allowed host cannot 30x to an
/// internal address), the hop count is capped at [importMaxRedirects], and the
/// response body is read with a running [importMaxResponseBytes] cap. Returns a
/// buffered [http.Response] so callers decode charset/body exactly as before.
Future<http.Response> _sendGuarded(String url, http.Client client) async {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null || !parsed.hasScheme) {
    throw const UrlFetchException(UrlFetchFailureReason.invalidUrl);
  }
  var uri = _guardFetchUri(parsed);
  var redirects = 0;
  while (true) {
    final request = http.Request('GET', uri)..followRedirects = false;
    final streamed = await client.send(request);
    final status = streamed.statusCode;
    final location = streamed.headers['location'];
    if (status >= 300 && status < 400 && location != null) {
      // Drain the redirect response before issuing the next hop.
      await streamed.stream.drain<void>();
      if (redirects >= importMaxRedirects) {
        throw const UrlFetchException(UrlFetchFailureReason.tooManyRedirects);
      }
      redirects++;
      // Re-validate the resolved target so a redirect can't reach a blocked
      // host; userInfo on the hop is stripped by _guardFetchUri.
      uri = _guardFetchUri(uri.resolve(location));
      continue;
    }
    // Buffer with a running byte total checked before each add, so a single
    // oversized chunk can't push the allocation past the cap.
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      if (builder.length + chunk.length > importMaxResponseBytes) {
        throw const UrlFetchException(UrlFetchFailureReason.responseTooLarge);
      }
      builder.add(chunk);
    }
    return http.Response.bytes(
      builder.takeBytes(),
      status,
      headers: streamed.headers,
      request: streamed.request,
      reasonPhrase: streamed.reasonPhrase,
    );
  }
}

/// Default [UrlFetcher]: validates the URL, performs an HTTP GET (with a
/// [importFetchTimeout]), and returns the response body. Throws a
/// [UrlFetchException] with a clear, user-presentable message for an invalid or
/// empty URL, a network failure, a timeout, a non-2xx status, or an empty body.
///
/// [client] is an injection point for tests (e.g. `package:http`'s
/// `MockClient`); production callers omit it and a one-shot client is used.
Future<String> fetchImportUrl(String url, {http.Client? client}) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    throw const UrlFetchException(UrlFetchFailureReason.emptyUrl);
  }

  final ownClient = client == null;
  final effectiveClient = client ?? http.Client();
  final http.Response response;
  try {
    response = await _sendGuarded(
      trimmed,
      effectiveClient,
    ).timeout(importFetchTimeout);
  } on UrlFetchException {
    rethrow;
  } on TimeoutException {
    throw UrlFetchException(
      UrlFetchFailureReason.timeout,
      timeoutSeconds: importFetchTimeout.inSeconds,
    );
  } on Object {
    // Never interpolate the error/URL here: it could leak the pasted URL or
    // embedded credentials into a user-facing message.
    throw const UrlFetchException(UrlFetchFailureReason.unreachable);
  } finally {
    if (ownClient) effectiveClient.close();
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw UrlFetchException(
      UrlFetchFailureReason.httpStatus,
      statusCode: response.statusCode,
    );
  }
  final body = response.body;
  if (body.trim().isEmpty) {
    throw const UrlFetchException(UrlFetchFailureReason.emptyResponse);
  }
  return body;
}

/// Transforms the raw text a user typed in URL mode (a pasted link or a bare
/// id) into the actual URL that should be fetched. Returns the fetch URL, or
/// throws a [UrlFetchException] whose [UrlFetchException.message] is safe to
/// show directly. Returning the input unchanged (see [ImportSource.urlBuilder]
/// being `null`) means "fetch exactly what was typed".
typedef ImportUrlBuilder = String Function(String input);

/// One selectable import source in [ImportReviewScreen]: a human [label], the
/// [adapterFactory] that parses its payloads, and an optional [urlBuilder] that
/// rewrites URL-mode input before it is fetched.
///
/// Keeping the adapter choice and URL rewrite together (rather than sniffing a
/// hostname) lets the user pick the source explicitly, which is the only way to
/// route a **bare id** (e.g. `1`) — it has no host to auto-detect from.
/// Which import source a given [ImportSource] is, so the presentation layer can
/// render a localized label (see `importSourceLabel` in
/// `import_error_labels.dart`) instead of baking English on the data object.
enum ImportSourceKind {
  /// A Caller's Compendium JSON share file (the default, generic source).
  genericJson,

  /// The Caller's Box online source.
  callersBox,

  /// The ContraDB online source.
  contraDb,

  /// A Caller's Companion `.USR` binary migration file.
  callersCompanionUsr,
}

class ImportSource {
  const ImportSource({
    required this.kind,
    required this.adapterFactory,
    this.urlBuilder,
    this.matchesUrl,
    this.bytePicker,
  });

  /// Which source this is. Drives the localized label at the render site.
  final ImportSourceKind kind;

  /// Builds a fresh [SourceAdapter] for each planning run (adapters may hold
  /// per-discovery state).
  final SourceAdapter Function() adapterFactory;

  /// Rewrites URL-mode input into the URL actually fetched; `null` fetches the
  /// input verbatim (the generic-JSON case).
  final ImportUrlBuilder? urlBuilder;

  /// Returns `true` if this source recognizes [uri] as one of its own dance
  /// URLs, used by [detectSourceForUrl] to auto-select the source as the user
  /// types a URL (so they need not toggle the dropdown manually). `null` means
  /// the source is never auto-detected from a URL (the generic-JSON case —
  /// there is no host to recognize).
  ///
  /// A predicate (rather than a simple host set) is used because The Caller's
  /// Box is also mirrored on ibiblio.org under a `/thecallersbox/` path, which
  /// a host-only match cannot express.
  final bool Function(Uri uri)? matchesUrl;

  /// When non-null, this source imports from a **binary file** the user picks
  /// (its bytes are handed to [adapterFactory]'s adapter via
  /// `ImportRequest.options['bytes']`), rather than from pasted/fetched text.
  /// This governs the **input** concern only — the picker shown and how the
  /// payload is carried. It deliberately does **not** decide how commit/undo is
  /// routed (that is gated on the concrete adapter type, so a future byte source
  /// can't accidentally inherit Caller's Companion program persistence).
  ///
  /// The only byte source today is Caller's Companion `.USR` (see
  /// [defaultImportSources]).
  final ImportBytePicker? bytePicker;
}

/// The host used to build a Caller's Box JSON endpoint from a **bare id**. The
/// Caller's Box is served from ibiblio.org under [callersBoxPathPrefix].
/// Confirmed live: `.../thecallersbox/dance.php?id=1&format=JSON` returns real
/// TCB JSON. A pasted full URL keeps its own host; only bare-id input needs a
/// host supplied here.
const String callersBoxHost = 'www.ibiblio.org';

/// The path prefix under which [callersBoxHost] serves The Caller's Box: both
/// the `index.php` title search and the per-dance `dance.php` JSON endpoint live
/// beneath it (e.g. `/contradance/thecallersbox/dance.php?id=N&format=JSON`).
const String callersBoxPathPrefix = '/contradance/thecallersbox';

/// Builds the Caller's Box per-dance JSON endpoint from what the user typed.
///
/// The Caller's Box serves per-dance JSON at `dance.php?id=N&format=JSON`. This
/// accepts either:
/// - a **bare numeric id** (`"1"`) → `https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1&format=JSON`;
/// - a pasted **http(s) URL** with an `id` query param (`.../dance.php?id=N`,
///   with or without an existing `format=…`) → the same URL with `format=JSON`
///   set (any existing `format` is overwritten, so it is never doubled and an
///   already-`format=JSON` link is returned effectively unchanged). The pasted
///   host and path are preserved.
///
/// Throws a [UrlFetchException] (message safe to show) for empty input, a
/// non-http(s) URL, or a URL with no dance id.
String buildCallersBoxJsonUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const UrlFetchException(UrlFetchFailureReason.callersBoxEmptyInput);
  }

  // Bare numeric id: build the canonical endpoint from scratch.
  if (RegExp(r'^\d+$').hasMatch(trimmed)) {
    return Uri.https(callersBoxHost, '$callersBoxPathPrefix/dance.php', {
      'id': trimmed,
      'format': 'JSON',
    }).toString();
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      (!uri.isScheme('http') && !uri.isScheme('https'))) {
    throw const UrlFetchException(UrlFetchFailureReason.callersBoxInvalidUrl);
  }

  final id = uri.queryParameters['id'];
  if (id == null || id.trim().isEmpty) {
    throw const UrlFetchException(UrlFetchFailureReason.callersBoxMissingId);
  }

  // Preserve the pasted host/path/other params; force format=JSON (overwrites
  // any existing value, case-insensitively, so it is never duplicated).
  final params = <String, String>{};
  uri.queryParameters.forEach((key, value) {
    if (key.toLowerCase() != 'format') params[key] = value;
  });
  params['format'] = 'JSON';
  // Reconstruct from parts rather than `uri.replace(queryParameters: ...)`,
  // which would preserve any embedded credentials (userInfo) and fragment.
  // Dropping them matches the ContraDB builders and avoids leaking creds.
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    queryParameters: params,
  ).toString();
}

/// Fetches a **Caller's Box** search results page and returns its decoded HTML,
/// or throws a [UrlFetchException] with a user-presentable message. See
/// [fetchCallersBoxSearch] for the default implementation; tests override this
/// seam to return a canned results page (or throw) so no real network call is
/// made.
///
/// Kept separate from [UrlFetcher] because the search page is `windows-1252`
/// (not the JSON import path's UTF-8) and must be decoded from raw bytes.
typedef CallersBoxSearchFetcher = Future<String> Function(String url);

/// Builds the Caller's Box title-search URL for [title], optionally combined
/// with by-phrase figure criteria ([phrases]).
///
/// The Caller's Box search surface is an HTTP GET to `index.php` (under
/// [callersBoxPathPrefix]). It accepts a `title` query param (confirmed live;
/// the site also accepts `author`, `formation`, `progression`, but this app
/// searches by title) plus a set of figure-line fields for "search by phrase"
/// (verified live against the TCB search form, 2026):
///
/// - Global (any-phrase) figure match: `pos_lines`/`pos_mode` ("figures match")
///   and `neg_lines`/`neg_mode` ("but do not match").
/// - Per-phrase, indexed `phr1..phr4` (= the standard phrases A1, A2, B1, B2):
///   `phrN_pos_lines`/`phrN_pos_mode` and `phrN_neg_lines`/`phrN_neg_mode`.
///
/// Each `*_lines` value is a newline-separated list of figure lines. The mode
/// values are `all_any` for positives ("all of these lines, in any order" — the
/// dance must contain EVERY selected figure, order irrelevant) and `any_any`
/// for negatives ("any of these lines" — exclude if any appears). These mirror
/// the local by-phrase semantics (AND the matches, negate the excludes).
///
/// Title and phrase criteria are non-exclusive: TCB accepts both in one
/// request, so a title box and phrase figures combine.
///
/// LIMITATION (v1): [CallersBoxPhraseQuery.fromSelections] maps each selected
/// move to its taxonomy display name as the TCB figure line. TCB uses its own
/// figure vocabulary and recommends one word per figure, so a display name may
/// over- or under-match (e.g. our "star through" vs TCB "star thru"). There is
/// no curated compatibility table yet; this is accepted for v1.
///
/// Returns e.g.
/// `https://www.ibiblio.org/contradance/thecallersbox/index.php?title=<encoded>`.
///
/// Throws a [UrlFetchException] (message safe to show) when there is nothing to
/// search — an empty [title] and no effective [phrases].
String buildCallersBoxSearchUrl(
  String title, {
  CallersBoxPhraseQuery? phrases,
  String host = callersBoxHost,
}) {
  final trimmed = title.trim();
  final hasPhrases = phrases != null && !phrases.isEmpty;
  if (trimmed.isEmpty && !hasPhrases) {
    throw const UrlFetchException(UrlFetchFailureReason.callersBoxEmptySearch);
  }

  final params = <String, String>{};
  if (trimmed.isNotEmpty) params['title'] = trimmed;
  if (hasPhrases) {
    if (phrases.globalPos.isNotEmpty) {
      params['pos_lines'] = phrases.globalPos.join('\n');
      params['pos_mode'] = _tcbPosMode;
    }
    if (phrases.globalNeg.isNotEmpty) {
      params['neg_lines'] = phrases.globalNeg.join('\n');
      params['neg_mode'] = _tcbNegMode;
    }
    phrases.phrasePos.forEach((slot, lines) {
      if (lines.isEmpty) return;
      params['phr${slot}_pos_lines'] = lines.join('\n');
      params['phr${slot}_pos_mode'] = _tcbPosMode;
    });
    phrases.phraseNeg.forEach((slot, lines) {
      if (lines.isEmpty) return;
      params['phr${slot}_neg_lines'] = lines.join('\n');
      params['phr${slot}_neg_mode'] = _tcbNegMode;
    });
  }

  return Uri.https(host, '$callersBoxPathPrefix/index.php', params).toString();
}

/// TCB positive figure-match mode: "all of these lines, in any order" — the
/// dance must contain EVERY selected figure (order irrelevant). Confirmed
/// against TCB's own search help (2026): the "all of these lines, in any order"
/// option requires every listed figure to be present.
const String _tcbPosMode = 'all_any';

/// TCB negative figure mode: "any of these lines, in any order" — exclude the
/// dance if ANY of the do-not-match figures appears.
const String _tcbNegMode = 'any_any';

/// The four TCB online "search by phrase" slots (`phr1..phr4`) correspond to the
/// standard contra phrases A1, A2, B1, B2 (verified live against the TCB search
/// form, 2026). Selections on any other (non-standard) phrase label can't target
/// a slot, so [CallersBoxPhraseQuery.fromSelections] folds them into the global
/// any-phrase figure fields rather than dropping them.
const Map<String, int> _tcbPhraseSlots = {'A1': 1, 'A2': 2, 'B1': 3, 'B2': 4};

/// Resolved TCB by-phrase figure criteria, ready to serialize into the search
/// request by [buildCallersBoxSearchUrl]. Lines are already resolved to figure
/// text (not move ids). [globalPos]/[globalNeg] carry any-phrase figures;
/// [phrasePos]/[phraseNeg] map a 1-based TCB phrase slot (`phr1..phr4`) to its
/// per-phrase figure lines.
class CallersBoxPhraseQuery {
  const CallersBoxPhraseQuery({
    this.globalPos = const [],
    this.globalNeg = const [],
    this.phrasePos = const {},
    this.phraseNeg = const {},
  });

  final List<String> globalPos;
  final List<String> globalNeg;
  final Map<int, List<String>> phrasePos;
  final Map<int, List<String>> phraseNeg;

  /// True when nothing would be sent to TCB (no positive or negative lines).
  bool get isEmpty =>
      globalPos.isEmpty &&
      globalNeg.isEmpty &&
      phrasePos.values.every((l) => l.isEmpty) &&
      phraseNeg.values.every((l) => l.isEmpty);

  /// Builds a query from local by-phrase [selections], resolving each move id to
  /// its [taxonomy] display name (falling back to the raw id) as the TCB figure
  /// line. Standard phrase labels (A1/A2/B1/B2) target their `phr1..phr4` slot;
  /// any other label's figures are aggregated into the global any-phrase fields
  /// so non-standard programs degrade gracefully instead of losing selections.
  factory CallersBoxPhraseQuery.fromSelections(
    ByPhraseSelections selections,
    Taxonomy taxonomy,
  ) {
    List<String> toLines(List<String> moveIds) {
      final out = <String>[];
      for (final id in moveIds) {
        final line = (taxonomy.resolve(id)?.displayName ?? id).trim();
        if (line.isNotEmpty) out.add(line);
      }
      return out;
    }

    final phrasePos = <int, List<String>>{};
    final phraseNeg = <int, List<String>>{};
    final globalPos = <String>[];
    final globalNeg = <String>[];

    void distribute(
      Map<String, List<String>> source,
      Map<int, List<String>> perSlot,
      List<String> global,
    ) {
      source.forEach((label, moves) {
        final lines = toLines(moves);
        if (lines.isEmpty) return;
        final slot = _tcbPhraseSlots[label];
        if (slot != null) {
          (perSlot[slot] ??= <String>[]).addAll(lines);
        } else {
          global.addAll(lines);
        }
      });
    }

    distribute(selections.match, phrasePos, globalPos);
    distribute(selections.exclude, phraseNeg, globalNeg);

    return CallersBoxPhraseQuery(
      globalPos: globalPos,
      globalNeg: globalNeg,
      phrasePos: phrasePos,
      phraseNeg: phraseNeg,
    );
  }
}

/// Caller's Box HTML pages are served as `windows-1252`. The 0x80–0x9F range is
/// where windows-1252 differs from ISO-8859-1 (latin1); every other byte maps
/// to the identical code point. Undefined windows-1252 slots (0x81, 0x8D, 0x8F,
/// 0x90, 0x9D) pass through as their byte value (latin1 behavior).
const List<int> _cp1252High = <int>[
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, // 80-87
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, // 88-8F
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 90-97
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178, // 98-9F
];

/// Decodes [bytes] as `windows-1252` (CP1252) into a Dart string. Used for the
/// Caller's Box search results page; hand-rolled so no charset dependency is
/// needed (`dart:convert` ships latin1/utf8 but not windows-1252).
String decodeWindows1252(List<int> bytes) {
  final units = List<int>.generate(bytes.length, (i) {
    final b = bytes[i] & 0xFF;
    return (b >= 0x80 && b <= 0x9F) ? _cp1252High[b - 0x80] : b;
  }, growable: false);
  return String.fromCharCodes(units);
}

/// Default [CallersBoxSearchFetcher]: validates the URL, performs an HTTP GET
/// (with an [importFetchTimeout]), and returns the `windows-1252`-decoded
/// response body. Throws a [UrlFetchException] with a clear, user-presentable
/// message for an invalid URL, a network failure, a timeout, a non-2xx status,
/// or an empty body.
///
/// [client] is an injection point for tests (e.g. `package:http`'s
/// `MockClient`); production callers omit it and a one-shot client is used.
Future<String> fetchCallersBoxSearch(String url, {http.Client? client}) async {
  final ownClient = client == null;
  final effectiveClient = client ?? http.Client();
  final http.Response response;
  try {
    response = await _sendGuarded(
      url,
      effectiveClient,
    ).timeout(importFetchTimeout);
  } on UrlFetchException {
    rethrow;
  } on TimeoutException {
    throw UrlFetchException(
      UrlFetchFailureReason.searchTimeout,
      timeoutSeconds: importFetchTimeout.inSeconds,
    );
  } on Object {
    // Never interpolate the error/URL here (see fetchImportUrl).
    throw const UrlFetchException(UrlFetchFailureReason.callersBoxUnreachable);
  } finally {
    if (ownClient) effectiveClient.close();
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw UrlFetchException(
      UrlFetchFailureReason.callersBoxHttpStatus,
      statusCode: response.statusCode,
    );
  }
  final body = decodeWindows1252(response.bodyBytes);
  if (body.trim().isEmpty) {
    throw const UrlFetchException(UrlFetchFailureReason.callersBoxEmptyPage);
  }
  return body;
}

/// The host used to build a ContraDB dance URL from a **bare id**. ContraDB
/// serves the dance page as server-rendered HTML at `contradb.com/dances/N`
/// (there is no JSON endpoint — `dances/N.json` → HTTP 406). A pasted full URL
/// keeps its own host; only bare-id input needs a host supplied here.
const String contraDbHost = 'contradb.com';

/// Builds the canonical ContraDB dance-page URL from what the user typed.
///
/// ContraDB serves each dance as HTML at `contradb.com/dances/N`. This accepts
/// either:
/// - a **bare numeric id** (`"1"`) → `https://contradb.com/dances/1`;
/// - a pasted **http(s) URL** whose path contains `/dances/N` (with or without
///   a trailing slash, query string, or fragment) → the canonical
///   `https://<host>/dances/N` (the pasted host is preserved so a self-hosted
///   instance also works; the dance id is re-extracted so query/fragment cruft
///   is dropped).
///
/// Throws a [UrlFetchException] (message safe to show) for empty input, a
/// non-http(s) URL, or a URL with no dance id.
String buildContraDbUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const UrlFetchException(
      UrlFetchFailureReason.contraDbEmptyDanceInput,
    );
  }

  // Bare numeric id: build the canonical page URL from scratch.
  if (RegExp(r'^\d+$').hasMatch(trimmed)) {
    return Uri.https(contraDbHost, '/dances/$trimmed').toString();
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      (!uri.isScheme('http') && !uri.isScheme('https'))) {
    throw const UrlFetchException(
      UrlFetchFailureReason.contraDbInvalidDanceUrl,
    );
  }

  final match = RegExp(r'/dances/(\d+)').firstMatch(uri.path);
  if (match == null) {
    throw const UrlFetchException(UrlFetchFailureReason.contraDbMissingDanceId);
  }
  final id = match.group(1)!;
  // Preserve the pasted scheme/host/port; canonicalize the path and drop any
  // query/fragment. User-info (credentials) is intentionally dropped — it is
  // never needed to fetch /dances/N and could leak via logs or the UI.
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '/dances/$id',
  ).toString();
}

/// Builds the canonical ContraDB **program**-page URL from what the user typed.
///
/// ContraDB serves each program (set list) as HTML at `contradb.com/programs/N`.
/// Accepts either a bare numeric id (`"33"`) → `https://contradb.com/programs/33`,
/// or a pasted http(s) URL whose path contains `/programs/N` (query/fragment and
/// user-info are dropped; the pasted host is preserved so a self-hosted instance
/// works). Throws a [UrlFetchException] (safe message) for empty input, a
/// non-http(s) URL, or a URL with no program id.
String buildContraDbProgramUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const UrlFetchException(
      UrlFetchFailureReason.contraDbEmptyProgramInput,
    );
  }

  if (RegExp(r'^\d+$').hasMatch(trimmed)) {
    return Uri.https(contraDbHost, '/programs/$trimmed').toString();
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      (!uri.isScheme('http') && !uri.isScheme('https'))) {
    throw const UrlFetchException(
      UrlFetchFailureReason.contraDbInvalidProgramUrl,
    );
  }

  final match = RegExp(r'/programs/(\d+)').firstMatch(uri.path);
  if (match == null) {
    throw const UrlFetchException(
      UrlFetchFailureReason.contraDbMissingProgramId,
    );
  }
  final id = match.group(1)!;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '/programs/$id',
  ).toString();
}

/// Hard cap on the length of a URL string shared into the app from the OS
/// share sheet / an `ACTION_SEND` intent (issue #343).
///
/// The shared string is **untrusted OS-provided input** — a malicious app or
/// user can hand this entry point *any* string. We reject anything longer than
/// a generous real URL before parsing it, so a pathological megabyte-long
/// "URL" can't be fed into `Uri.parse` / a regex (OWASP: uncontrolled input /
/// resource consumption). A real `contradb.com/programs/N` link is well under
/// this.
const int kMaxSharedImportUrlLength = 2048;

/// OWASP-hardens a URL shared into the app from the OS **share sheet** /
/// `ACTION_SEND` intent (issue #343) and returns the canonical
/// `https://contradb.com/programs/N` URL to hand the import pipeline, or throws
/// a [UrlFetchException] whose message is safe to show and **never echoes the
/// raw shared string** (so a hostile or credential-bearing input can't leak
/// into the UI/logs).
///
/// The shared string is **untrusted input**: any app or user can share any
/// string to this boundary. This validator runs *before* the string reaches
/// [buildContraDbProgramUrl] / [fetchImportUrl], as a first, ingest-time gate
/// in **front of** — never a replacement for — the shared SSRF host guard
/// (#332, [isBlockedImportHost] / [_guardFetchUri], re-applied at fetch time
/// and on every redirect hop). Defense in depth.
///
/// Validation (in order, fail-closed):
/// 1. **Length cap** — reject empty / whitespace-only / longer than
///    [kMaxSharedImportUrlLength] input before parsing.
/// 2. **Parse + scheme allow-list** — must parse as a URI with an **`https`**
///    scheme. `http`, `file`, `javascript:`, `data:`, `content:`, a custom
///    scheme, or an unparseable/relative string are all rejected. (Stricter
///    than the manual paste flow, which tolerates `http`, because this input is
///    hostile OS text rather than something the user typed.)
/// 3. **Host allow-list** — the host must equal [contraDbHost]
///    (`contradb.com`, case-insensitively). Any other host — including a
///    self-hosted ContraDB, an SSRF probe at an internal name, or a look-alike
///    — is rejected. A shared link always carries a full host, so no bare-id
///    branch is offered here.
/// 4. **Path shape** — the path must be exactly `/programs/<digits>` (a
///    trailing slash is tolerated). `/dances/N`, arbitrary paths, path-traversal
///    attempts, and missing ids are rejected.
///
/// On success it returns the canonicalized URL built from the validated id
/// only (query, fragment, and any user-info credentials are dropped — nothing
/// from the shared string is interpolated verbatim), so there is no injection
/// surface into the URL handed onward.
String validateSharedContraDbProgramUrl(String shared) {
  const rejected = UrlFetchException(
    UrlFetchFailureReason.contraDbInvalidProgramLink,
  );

  final trimmed = shared.trim();
  if (trimmed.isEmpty || trimmed.length > kMaxSharedImportUrlLength) {
    throw rejected;
  }

  final uri = Uri.tryParse(trimmed);
  // Require an absolute https URL: reject unparseable input, relative refs,
  // and any non-https scheme (http/file/javascript/data/content/custom).
  if (uri == null || !uri.hasScheme || !uri.isScheme('https')) {
    throw rejected;
  }

  // Host allow-list: contradb.com only. `Uri.host` is already lowercased.
  if (uri.host != contraDbHost) {
    throw rejected;
  }

  // Path shape: exactly /programs/<digits> (optionally a trailing slash).
  final match = RegExp(r'^/programs/(\d+)/?$').firstMatch(uri.path);
  if (match == null) {
    throw rejected;
  }

  // Build the canonical URL from the validated id only — nothing from the
  // shared string is carried over verbatim (no query/fragment/user-info), so
  // there is no injection path into the URL handed to the pipeline.
  return Uri.https(contraDbHost, '/programs/${match.group(1)!}').toString();
}

/// Hard cap on the length of the **raw** OS share payload (issue #343) before
/// any tokenizing/scanning happens.
///
/// Unlike a bare link, this payload may legitimately be `"Title\nURL"` (see
/// [extractSharedContraDbProgramUrl]), so it can be a little longer than a lone
/// URL — but it is still untrusted OS input and must be bounded before it
/// reaches a regex, so a pathological multi-megabyte "share" can't drive
/// resource consumption (OWASP: uncontrolled input). Comfortably fits a real
/// page title plus a `contradb.com/programs/N` link.
const int kMaxSharedImportTextLength = 8192;

/// Matches a single `https://…` token (whitespace-delimited) inside a raw share
/// payload. Deliberately **ReDoS-safe**: a single linear `\S+` quantifier with
/// no nesting/alternation/backtracking traps, run only over already
/// length-bounded input ([kMaxSharedImportTextLength]). Scheme match is
/// case-insensitive; the token itself is handed to
/// [validateSharedContraDbProgramUrl] for the real, strict checks.
final RegExp _sharedHttpsUrlToken = RegExp(
  r'https://\S+',
  caseSensitive: false,
);

/// OWASP-hardens raw text shared into the app from the OS **share sheet** /
/// `ACTION_SEND` intent (issue #343) and returns the canonical
/// `https://contradb.com/programs/N` URL, or throws a [UrlFetchException] whose
/// message is safe to show and **never echoes the raw shared string**.
///
/// Why this exists in front of [validateSharedContraDbProgramUrl]: the OS hands
/// us the sharing app's `EXTRA_TEXT` verbatim, and that is **not** always a bare
/// URL. Chrome and Samsung Internet share a bare URL (title travels separately
/// in `EXTRA_SUBJECT`), but Firefox for Android puts `"<page title>\n<url>"` in
/// `EXTRA_TEXT`. Validating the whole string would silently reject every share
/// from those browsers. So we first extract exactly one URL token, then run the
/// full strict validator on it.
///
/// The shared string is **untrusted input** — any app or user can share any
/// string here. Fail-closed, in order:
/// 1. **Length cap** — reject empty / whitespace-only / longer than
///    [kMaxSharedImportTextLength] before scanning (bounds the regex).
/// 2. **Single-candidate extraction** — collect `https://…` tokens with a
///    ReDoS-safe linear regex ([_sharedHttpsUrlToken]). Require **exactly one**:
///    zero candidates (a title with no link) and more than one candidate (an
///    ambiguous payload that could smuggle an attacker URL past a human) are
///    both rejected. `http`/other-scheme tokens are never candidates.
/// 3. **Full validation** — the single candidate is passed to
///    [validateSharedContraDbProgramUrl] (https-only, `contradb.com` host
///    allow-list, `/programs/<digits>` path, canonical rebuild), which remains
///    the single source of truth and front-runs — never replaces — the #332
///    SSRF guard applied at fetch time.
String extractSharedContraDbProgramUrl(String rawShared) {
  const rejected = UrlFetchException(
    UrlFetchFailureReason.contraDbInvalidProgramLink,
  );

  final trimmed = rawShared.trim();
  if (trimmed.isEmpty || trimmed.length > kMaxSharedImportTextLength) {
    throw rejected;
  }

  final candidates = _sharedHttpsUrlToken
      .allMatches(trimmed)
      .map((m) => m.group(0)!)
      .toList(growable: false);
  if (candidates.length != 1) {
    throw rejected;
  }

  // Delegates every real check (scheme/host/path/canonicalization) to the
  // strict validator — extraction only decides *which* token to validate.
  return validateSharedContraDbProgramUrl(candidates.first);
}

/// The ContraDB JSON search endpoint. ContraDB (a Rails app) exposes
/// `POST https://contradb.com/api/v1/dances` (Content-Type application/json);
/// the controller does `skip_before_action :verify_authenticity_token`, so no
/// CSRF token / login / cookie is required. The request body is built by
/// [buildContraDbSearchBody] and the JSON response is parsed by
/// [parseContraDbSearchResults]. Verified live 2026-07-17.
const String contraDbSearchUrl = 'https://contradb.com/api/v1/dances';

/// Fetches **ContraDB** title-search results and returns the raw JSON body, or
/// throws a [UrlFetchException] with a user-presentable message. See
/// [fetchContraDbSearch] for the default implementation; tests override this
/// seam to return a canned JSON response (or throw) so no real network call is
/// made.
///
/// Takes the raw title [query] (not a URL, unlike [CallersBoxSearchFetcher]):
/// ContraDB search is a POST to a single fixed endpoint whose JSON body carries
/// the query, so the transport — not the caller — assembles the request.
typedef ContraDbSearchFetcher = Future<String> Function(String query);

/// POSTs [body] to the ContraDB search endpoint [uri] with [client] and buffers
/// the response under a running [importMaxResponseBytes] cap, aborting with a
/// generic [UrlFetchException] the moment the body would exceed it (a single
/// oversized chunk, or a lying/absent Content-Length, can't push the allocation
/// past the cap).
///
/// Deliberately kept separate from the GET-oriented [_sendGuarded]: there is no
/// SSRF host guard because [uri] is the fixed public [contraDbSearchUrl], not a
/// user-controlled destination. The caller wraps the returned future in
/// [importFetchTimeout], so both the `send` and this body read are bounded by a
/// single deadline.
Future<http.Response> _sendContraDbSearch(
  Uri uri,
  String body,
  http.Client client,
) async {
  final request = http.Request('POST', uri)
    ..headers['Content-Type'] = 'application/json'
    ..body = body;
  final streamed = await client.send(request);
  final builder = BytesBuilder(copy: false);
  await for (final chunk in streamed.stream) {
    if (builder.length + chunk.length > importMaxResponseBytes) {
      throw const UrlFetchException(UrlFetchFailureReason.responseTooLarge);
    }
    builder.add(chunk);
  }
  return http.Response.bytes(
    builder.takeBytes(),
    streamed.statusCode,
    headers: streamed.headers,
    request: streamed.request,
    reasonPhrase: streamed.reasonPhrase,
  );
}

/// Default [ContraDbSearchFetcher]: POSTs the [query] as a ContraDB title-search
/// JSON body to [contraDbSearchUrl] (with an [importFetchTimeout]) and returns
/// the response body. Throws a [UrlFetchException] with a clear, user-presentable
/// message for a network failure, a timeout, a non-2xx status, or an empty body.
///
/// [client] is an injection point for tests (e.g. `package:http`'s
/// `MockClient`); production callers omit it and a one-shot client is used.
Future<String> fetchContraDbSearch(String query, {http.Client? client}) async {
  // Not subject to the SSRF host guard / _sendGuarded: this POSTs to the fixed
  // constant [contraDbSearchUrl] (a hard-coded public host), not a
  // user-controlled URL, so there is no untrusted destination to validate. The
  // response body is still read under the shared [importMaxResponseBytes] cap,
  // so a compromised / MITM'd / misbehaving ContraDB response cannot exhaust
  // memory (OWASP - uncontrolled resource consumption).
  final uri = Uri.parse(contraDbSearchUrl);
  final ownClient = client == null;
  final effectiveClient = client ?? http.Client();
  final http.Response response;
  try {
    // The timeout wraps the whole send + body-read (not just send), so a slow
    // or never-ending response body is bounded by [importFetchTimeout] too.
    response = await _sendContraDbSearch(
      uri,
      buildContraDbSearchBody(query),
      effectiveClient,
    ).timeout(importFetchTimeout);
  } on UrlFetchException {
    rethrow;
  } on TimeoutException {
    throw UrlFetchException(
      UrlFetchFailureReason.searchTimeout,
      timeoutSeconds: importFetchTimeout.inSeconds,
    );
  } on Object {
    // Never interpolate the error here: keep ContraDB's failure message generic
    // and free of internal detail (matching the other guarded fetchers).
    throw const UrlFetchException(UrlFetchFailureReason.contraDbUnreachable);
  } finally {
    if (ownClient) effectiveClient.close();
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw UrlFetchException(
      UrlFetchFailureReason.contraDbHttpStatus,
      statusCode: response.statusCode,
    );
  }
  final body = response.body;
  if (body.trim().isEmpty) {
    throw const UrlFetchException(UrlFetchFailureReason.contraDbEmptyResponse);
  }
  return body;
}

/// Hosts serving The Caller's Box directly.
const Set<String> _callersBoxHosts = {
  'thecallersbox.com',
  'www.thecallersbox.com',
};

/// Hosts serving the ibiblio.org mirror; a Caller's Box URL there lives under a
/// `/thecallersbox/` path segment (so host alone is not enough to recognize it).
const Set<String> _ibiblioHosts = {'ibiblio.org', 'www.ibiblio.org'};

/// Hosts serving ContraDB dance pages.
const Set<String> _contraDbHosts = {'contradb.com', 'www.contradb.com'};

/// The canonical, ordered list of selectable import sources
/// (`docs/ROADMAP.md` Phase 6.3/6.4/6.5): the generic [GenericJsonAdapter]
/// ("a Caller's Compendium JSON file", the default), the [CallersBoxAdapter]
/// ("The Caller's Box"), the [ContraDbHtmlAdapter] ("ContraDB"), and the
/// [CallersCompanionUsrAdapter] ("a Caller's Companion .USR file", a binary
/// FileMaker 12 migration that also imports the program history).
///
/// Extracted here so every launch point (Settings and the Collection blade)
/// shares one definition and the two can never drift. `picker`/`fetcher`
/// injection is handled separately by each caller via [ImportReviewScreen].
List<ImportSource> defaultImportSources() => [
  ImportSource(
    kind: ImportSourceKind.genericJson,
    adapterFactory: GenericJsonAdapter.new,
  ),
  ImportSource(
    kind: ImportSourceKind.callersBox,
    adapterFactory: CallersBoxAdapter.new,
    urlBuilder: buildCallersBoxJsonUrl,
    matchesUrl: (uri) =>
        _callersBoxHosts.contains(uri.host.toLowerCase()) ||
        (_ibiblioHosts.contains(uri.host.toLowerCase()) &&
            uri.path.toLowerCase().contains('/thecallersbox/')),
  ),
  ImportSource(
    kind: ImportSourceKind.contraDb,
    adapterFactory: ContraDbHtmlAdapter.new,
    urlBuilder: buildContraDbUrl,
    matchesUrl: (uri) => _contraDbHosts.contains(uri.host.toLowerCase()),
  ),
  ImportSource(
    kind: ImportSourceKind.callersCompanionUsr,
    adapterFactory: CallersCompanionUsrAdapter.new,
    bytePicker: pickImportUsrFile,
  ),
];

/// Auto-detects which [ImportSource] a URL-mode [input] belongs to, so the
/// review screen can flip the source selector for the user as they paste a
/// link. Returns the first source in [sources] whose [ImportSource.matchesUrl]
/// recognizes the parsed URL, or `null` when nothing matches.
///
/// Returns `null` (leaving the current selection unchanged — never forcing the
/// generic source) for:
/// - empty input;
/// - a **bare numeric id** (`"1"`) — it has no host to detect, which is exactly
///   why the explicit selector is retained;
/// - any input that is not a valid http(s) URL;
/// - a valid URL whose host no source recognizes.
ImportSource? detectSourceForUrl(String input, List<ImportSource> sources) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  // A bare id has no host — keep whatever the user selected.
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      (!uri.isScheme('http') && !uri.isScheme('https'))) {
    return null;
  }

  for (final source in sources) {
    if (source.matchesUrl?.call(uri) ?? false) return source;
  }
  return null;
}
