import 'dart:async';

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
