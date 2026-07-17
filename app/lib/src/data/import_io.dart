import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

import '../search/collection_query.dart' show ByPhraseSelections;

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
    this.matchesUrl,
  });

  /// Human-readable name, e.g. "Caller's Compendium JSON" or "The Caller's Box".
  final String label;

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
    throw const UrlFetchException(
      "Enter a Caller's Box dance URL or id to import from.",
    );
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
    throw const UrlFetchException(
      "Enter a title or by-phrase figures to search The Caller's Box.",
    );
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
  final trimmed = url.trim();
  final uri = Uri.tryParse(trimmed);
  if (trimmed.isEmpty ||
      uri == null ||
      !uri.hasScheme ||
      (!uri.isScheme('http') && !uri.isScheme('https'))) {
    throw const UrlFetchException("Couldn't build a valid search URL.");
  }

  final ownClient = client == null;
  final effectiveClient = client ?? http.Client();
  final http.Response response;
  try {
    response = await effectiveClient.get(uri).timeout(importFetchTimeout);
  } on TimeoutException {
    throw UrlFetchException(
      'The search timed out after ${importFetchTimeout.inSeconds}s. Check your '
      'connection, then try again.',
    );
  } on Object catch (e) {
    throw UrlFetchException("Couldn't reach The Caller's Box: $e");
  } finally {
    if (ownClient) effectiveClient.close();
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw UrlFetchException(
      "The Caller's Box responded with HTTP ${response.statusCode}.",
    );
  }
  final body = decodeWindows1252(response.bodyBytes);
  if (body.trim().isEmpty) {
    throw const UrlFetchException("The Caller's Box returned an empty page.");
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
  // query/fragment. User-info (credentials) is intentionally dropped — it is
  // never needed to fetch /dances/N and could leak via logs or the UI.
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '/dances/$id',
  ).toString();
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
/// (`docs/ROADMAP.md` Phase 6.3/6.4): the generic [GenericJsonAdapter]
/// ("a Caller's Compendium JSON file", the default), the [CallersBoxAdapter]
/// ("The Caller's Box"), and the [ContraDbHtmlAdapter] ("ContraDB").
///
/// Extracted here so every launch point (Settings and the Collection blade)
/// shares one definition and the two can never drift. `picker`/`fetcher`
/// injection is handled separately by each caller via [ImportReviewScreen].
List<ImportSource> defaultImportSources() => [
  ImportSource(
    label: "a Caller's Compendium JSON file",
    adapterFactory: GenericJsonAdapter.new,
  ),
  ImportSource(
    label: "The Caller's Box",
    adapterFactory: CallersBoxAdapter.new,
    urlBuilder: buildCallersBoxJsonUrl,
    matchesUrl: (uri) =>
        _callersBoxHosts.contains(uri.host.toLowerCase()) ||
        (_ibiblioHosts.contains(uri.host.toLowerCase()) &&
            uri.path.toLowerCase().contains('/thecallersbox/')),
  ),
  ImportSource(
    label: 'ContraDB',
    adapterFactory: ContraDbHtmlAdapter.new,
    urlBuilder: buildContraDbUrl,
    matchesUrl: (uri) => _contraDbHosts.contains(uri.host.toLowerCase()),
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
