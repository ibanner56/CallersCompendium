import 'dart:convert';

import 'package:meta/meta.dart';

/// One row of a **ContraDB** online title-search result.
///
/// Unlike The Caller's Box (which has no JSON search surface — see
/// `callersbox_search.dart`), ContraDB exposes a JSON search API at
/// `POST https://contradb.com/api/v1/dances` (the Rails controller skips CSRF
/// verification, so no token/login/cookie is needed). [buildContraDbSearchBody]
/// builds the request body for a title query and [parseContraDbSearchResults]
/// turns the JSON response into these lightweight rows.
///
/// The [id] is the ContraDB dance id; the app turns it into the per-dance
/// `contradb.com/dances/N` page URL (via `buildContraDbUrl`) and imports the
/// full dance by scraping that HTML with `ContraDbHtmlAdapter` (ContraDB serves
/// no per-dance JSON — `dances/N.json` → HTTP 406).
@immutable
class ContraDbSearchResult {
  const ContraDbSearchResult({
    required this.id,
    required this.name,
    required this.author,
    required this.formation,
  });

  /// ContraDB dance id (numeric string), from the response row's `id`.
  final String id;

  /// Dance title (the response row's `title`).
  final String name;

  /// Choreographer name (`choreographer_name`); may be empty.
  final String author;

  /// Formation / start type (`formation`); may be empty.
  final String formation;

  @override
  bool operator ==(Object other) =>
      other is ContraDbSearchResult &&
      other.id == id &&
      other.name == name &&
      other.author == author &&
      other.formation == formation;

  @override
  int get hashCode => Object.hash(id, name, author, formation);

  @override
  String toString() =>
      'ContraDbSearchResult(id: $id, name: $name, author: $author, '
      'formation: $formation)';
}

/// Default number of results to request per ContraDB search call.
///
/// The endpoint does an O(n) server-side scan of every dance (~2300) per call,
/// so this is deliberately modest to stay polite while still surfacing enough
/// matches for a title query.
const int contraDbSearchCount = 20;

/// Builds the JSON request body for a ContraDB **title** search.
///
/// ContraDB's array query DSL (`lib/filter_dances.rb`) treats `["title", q]` as
/// a case-insensitive substring match on the dance title. The endpoint accepts
/// `count` (page size), `offset` (page start), and an optional `sort_by`
/// (`"titleA"` sorts by title ascending).
///
/// Returns the body as a JSON-encoded string ready to POST. The [query] is sent
/// verbatim (ContraDB lower-cases both sides for the match); an empty [query]
/// still produces a valid body (ContraDB returns its default page), but callers
/// should avoid searching on empty input.
String buildContraDbSearchBody(
  String query, {
  int count = contraDbSearchCount,
  int offset = 0,
  String sortBy = 'titleA',
}) {
  return jsonEncode(<String, Object?>{
    'filter': <Object?>['title', query],
    'count': count,
    'offset': offset,
    'sort_by': sortBy,
  });
}

/// Parses a **ContraDB** search response ([body], JSON) into its result rows.
///
/// The response is shaped
/// `{ numberSearched, numberMatching, dances: [ { id, title,
/// choreographer_name, formation, … }, … ] }`. This reads the `dances` array and
/// maps each entry to a [ContraDbSearchResult].
///
/// This is **pure** (no I/O): the app layer performs the POST and passes the
/// decoded JSON string here.
///
/// Robustness (mirrors the tolerant TCB parser): malformed JSON, a non-object
/// payload, a missing/`non-list `dances`, or individual non-object/idless rows
/// are skipped rather than throwing — the caller renders an empty list as "no
/// results". Extra fields are ignored and missing string fields default to
/// empty, so a partial row still imports its title/id.
List<ContraDbSearchResult> parseContraDbSearchResults(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map) return const [];

  final dances = decoded['dances'];
  if (dances is! List) return const [];

  final results = <ContraDbSearchResult>[];
  for (final entry in dances) {
    if (entry is! Map) continue;

    final id = _asString(entry['id']);
    final name = _asString(entry['title']);
    // A row with neither an id nor a title is unusable (can't bridge to import,
    // nothing to show), so skip it.
    if (id.isEmpty || name.isEmpty) continue;

    results.add(
      ContraDbSearchResult(
        id: id,
        name: name,
        author: _asString(entry['choreographer_name']),
        formation: _asString(entry['formation']),
      ),
    );
  }
  return results;
}

/// Coerces a JSON scalar to a trimmed string: `null` → empty, numbers (e.g. the
/// integer `id`) → their canonical string, strings → trimmed. Non-scalars (a
/// nested object/list where a scalar was expected) → empty.
String _asString(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  if (value is num || value is bool) return value.toString();
  return '';
}
