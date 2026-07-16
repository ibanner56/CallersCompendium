import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

/// Prompts the user to choose a source file for an import and returns its
/// contents, or `null` if they cancelled. See [pickImportFile] for the default
/// implementation; widget tests override this seam to return canned text so no
/// real file/picker plugin is invoked.
///
/// Mirrors [BackupPicker] in `backup_io.dart` — the import experience reuses the
/// same file-picker / paste-fallback shape as backup restore (ROADMAP 6.3).
typedef ImportPicker = Future<String?> Function();

/// Default [ImportPicker]: opens the native open-file dialog (via
/// `file_selector`), restricted to `.json`, and reads the chosen file's text.
/// Returns `null` when the user cancels.
///
/// Currently the only wired source is the generic Caller's Compendium JSON
/// format (`GenericJsonAdapter`), so the picker accepts `.json`. The review
/// flow itself is adapter-agnostic; a future source (CallersBox/ContraDB/CC)
/// can supply its own picker/type group without changing the queue UI.
Future<String?> pickImportFile() async {
  const jsonGroup = XTypeGroup(
    label: 'Compendium JSON',
    extensions: ['json'],
    uniformTypeIdentifiers: ['public.json'],
    mimeTypes: ['application/json'],
  );
  final file = await openFile(acceptedTypeGroups: const [jsonGroup]);
  if (file == null) return null;
  return file.readAsString();
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

/// Raised by a [UrlFetcher] when a URL import cannot be fetched. The [message]
/// is safe to show directly to the user.
class UrlFetchException implements Exception {
  const UrlFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How long [fetchImportUrl] waits for a response before giving up.
const Duration importFetchTimeout = Duration(seconds: 30);

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
    throw const UrlFetchException('Enter a URL to import from.');
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      (!uri.isScheme('http') && !uri.isScheme('https'))) {
    throw const UrlFetchException(
      "That doesn't look like a valid http(s) URL.",
    );
  }

  final ownClient = client == null;
  final effectiveClient = client ?? http.Client();
  final http.Response response;
  try {
    response = await effectiveClient.get(uri).timeout(importFetchTimeout);
  } on TimeoutException {
    throw UrlFetchException(
      'The request timed out after ${importFetchTimeout.inSeconds}s. Check the '
      'URL and your connection, then try again.',
    );
  } on Object catch (e) {
    throw UrlFetchException("Couldn't reach that URL: $e");
  } finally {
    if (ownClient) effectiveClient.close();
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw UrlFetchException(
      'The server responded with HTTP ${response.statusCode}.',
    );
  }
  final body = response.body;
  if (body.trim().isEmpty) {
    throw const UrlFetchException('The URL returned an empty response.');
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
class ImportSource {
  const ImportSource({
    required this.label,
    required this.adapterFactory,
    this.urlBuilder,
  });

  /// Human-readable name, e.g. "Caller's Compendium JSON" or "The Caller's Box".
  final String label;

  /// Builds a fresh [SourceAdapter] for each planning run (adapters may hold
  /// per-discovery state).
  final SourceAdapter Function() adapterFactory;

  /// Rewrites URL-mode input into the URL actually fetched; `null` fetches the
  /// input verbatim (the generic-JSON case).
  final ImportUrlBuilder? urlBuilder;
}

/// The host used to build a Caller's Box JSON endpoint from a **bare id**.
/// Confirmed live: `dance.php?id=1&format=JSON` returns real TCB JSON. A pasted
/// full URL keeps its own host (so the surveyed `ibiblio.org` mirror also
/// works); only bare-id input needs a host supplied here.
const String callersBoxHost = 'www.thecallersbox.com';

/// Builds the Caller's Box per-dance JSON endpoint from what the user typed.
///
/// The Caller's Box serves per-dance JSON at `dance.php?id=N&format=JSON`. This
/// accepts either:
/// - a **bare numeric id** (`"1"`) → `https://www.thecallersbox.com/dance.php?id=1&format=JSON`;
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
    throw const UrlFetchException(
      "Enter a Caller's Box dance URL or id to import from.",
    );
  }

  // Bare numeric id: build the canonical endpoint from scratch.
  if (RegExp(r'^\d+$').hasMatch(trimmed)) {
    return Uri.https(callersBoxHost, '/dance.php', {
      'id': trimmed,
      'format': 'JSON',
    }).toString();
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      (!uri.isScheme('http') && !uri.isScheme('https'))) {
    throw const UrlFetchException(
      "That doesn't look like a Caller's Box dance URL or a numeric id.",
    );
  }

  final id = uri.queryParameters['id'];
  if (id == null || id.trim().isEmpty) {
    throw const UrlFetchException(
      "That Caller's Box URL is missing a dance id (…dance.php?id=N).",
    );
  }

  // Preserve the pasted host/path/other params; force format=JSON (overwrites
  // any existing value, case-insensitively, so it is never duplicated).
  final params = <String, String>{};
  uri.queryParameters.forEach((key, value) {
    if (key.toLowerCase() != 'format') params[key] = value;
  });
  params['format'] = 'JSON';
  return uri.replace(queryParameters: params).toString();
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
      'Enter a ContraDB dance URL or id to import from.',
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
      "That doesn't look like a ContraDB dance URL or a numeric id.",
    );
  }

  final match = RegExp(r'/dances/(\d+)').firstMatch(uri.path);
  if (match == null) {
    throw const UrlFetchException(
      'That ContraDB URL is missing a dance id (…/dances/N).',
    );
  }
  final id = match.group(1)!;
  // Preserve the pasted scheme/host/port; canonicalize the path and drop any
  // query/fragment so the fetched URL is exactly the dance page.
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '/dances/$id',
  ).toString();
}
