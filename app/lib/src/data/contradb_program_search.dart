import 'package:compendium_core/compendium_core.dart';

import 'import_io.dart';

/// The canonical public ContraDB **program index** URL (`contradb.com/programs`).
///
/// This is a fixed, hard-coded public host — never user-supplied — so fetching
/// it through [fetchImportUrl] carries no user-controlled-destination (SSRF)
/// risk; the shared guard, redirect re-validation, size cap, and non-leaking
/// errors still apply. ContraDB has no JSON program-search API (`POST
/// /api/v1/programs` → 404) and no server-side program search, so this one page
/// (which lists every program as a `/programs/{id}` anchor) is the whole search
/// corpus.
final String contraDbProgramIndexUrl = Uri.https(
  contraDbHost,
  '/programs',
).toString();

/// Fetches the ContraDB program index once and filters it by name **client-side**.
///
/// Wraps the existing hardened [fetchImportUrl] (SSRF guard, 8 MiB cap,
/// non-leaking errors) — no new request path — and the pure-core
/// [parseContraDbProgramIndex]. The parsed list is cached on the instance after
/// the first successful [loadIndex] so typing in the search box filters an
/// in-memory list instead of re-fetching ~370 KB on every keystroke.
///
/// The fetcher is injectable so widget/unit tests supply a seam-backed fetcher
/// (or `package:http`'s `MockClient`) and never touch the network.
class ContraDbProgramSearch {
  ContraDbProgramSearch({UrlFetcher? fetch}) : _fetch = fetch ?? fetchImportUrl;

  final UrlFetcher _fetch;

  List<ContraDbProgramIndexEntry>? _cache;

  /// Whether the index has been fetched + parsed at least once this session.
  bool get isLoaded => _cache != null;

  /// Loads (and caches) the full program index. Fetches via [fetchImportUrl]
  /// on the first call; later calls return the cached list without re-fetching.
  ///
  /// Throws a [UrlFetchException] (message safe to show) if the fetch fails. A
  /// successfully-fetched-but-empty/malformed page yields an empty list (the
  /// core parser never throws), which is cached so it is not re-fetched.
  Future<List<ContraDbProgramIndexEntry>> loadIndex() async {
    final cached = _cache;
    if (cached != null) return cached;
    final html = await _fetch(contraDbProgramIndexUrl);
    final entries = parseContraDbProgramIndex(html);
    _cache = entries;
    return entries;
  }

  /// Loads the index if needed, then returns entries whose [name] matches
  /// [query] by case-insensitive substring. A blank query returns an empty list
  /// (we don't dump all ~845 programs before the user has typed anything).
  Future<List<ContraDbProgramIndexEntry>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final entries = await loadIndex();
    return filterProgramIndex(entries, trimmed);
  }
}

/// Case-insensitive substring filter over [entries] by name. A blank [query]
/// returns an empty list. Pure (no I/O) so it is trivial to unit-test and can be
/// called on every keystroke against a cached list.
List<ContraDbProgramIndexEntry> filterProgramIndex(
  List<ContraDbProgramIndexEntry> entries,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  return entries
      .where((e) => e.name.toLowerCase().contains(needle))
      .toList(growable: false);
}
