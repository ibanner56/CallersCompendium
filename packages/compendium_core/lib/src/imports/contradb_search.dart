import 'dart:convert';

import 'package:meta/meta.dart';

/// One row of a **ContraDB** online title-, choreographer-, or figure-search
/// result.
///
/// Unlike The Caller's Box (which has no JSON search surface — see
/// `callersbox_search.dart`), ContraDB exposes a JSON search API at
/// `POST https://contradb.com/api/v1/dances` (the Rails controller skips CSRF
/// verification, so no token/login/cookie is needed). [buildContraDbSearchBody]
/// builds the request body for a title, choreographer, or figure query and
/// [parseContraDbSearchResults]
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

/// Canonical Figure names exposed by ContraDB's `/figures` index.
///
/// ContraDB's `figure` operator resolves an exact, case-sensitive
/// `defined_events` key rather than performing a text search. The app accepts
/// case and whitespace variants from the user, then sends the source spelling
/// from this map. Keep this vocabulary aligned with the live ContraDB figure
/// index; `custom` is included because it is a valid source figure key even
/// though it is not a seeded app taxonomy move.
const Map<String, String> _contraDbFigureNames = {
  'allemande': 'allemande',
  'allemande orbit': 'allemande orbit',
  'arch & dive': 'arch & dive',
  'balance': 'balance',
  'balance the ring': 'balance the ring',
  'box circulate': 'box circulate',
  'box the gnat': 'box the gnat',
  'butterfly whirl': 'butterfly whirl',
  'california twirl': 'California twirl',
  'chain': 'chain',
  'circle': 'circle',
  'contra corners': 'contra corners',
  'cross trails': 'cross trails',
  'custom': 'custom',
  'do si do': 'do si do',
  'dolphin hey': 'dolphin hey',
  'down the hall': 'down the hall',
  'facing star': 'facing star',
  'figure 8': 'figure 8',
  'form a long wave': 'form a long wave',
  'form an ocean wave': 'form an ocean wave',
  'form long waves': 'form long waves',
  'gate': 'gate',
  'give & take': 'give & take',
  'gyre': 'gyre',
  'hey': 'hey',
  'long lines': 'long lines',
  'mad robin': 'mad robin',
  'meltdown swing': 'meltdown swing',
  'pass by': 'pass by',
  'pass through': 'pass through',
  'petronella': 'petronella',
  'poussette': 'poussette',
  'promenade': 'promenade',
  'pull by dancers': 'pull by dancers',
  'pull by direction': 'pull by direction',
  'revolving door': 'revolving door',
  'right left through': 'right left through',
  'roll away': 'roll away',
  "rory o'more": "Rory O'More",
  'see saw': 'see saw',
  'slice': 'slice',
  'slide along set': 'slide along set',
  'square through': 'square through',
  'stand still': 'stand still',
  'star': 'star',
  'star promenade': 'star promenade',
  'swat the flea': 'swat the flea',
  'swing': 'swing',
  'turn alone': 'turn alone',
  'up the hall': 'up the hall',
  'zig zag': 'zig zag',
};

String _normalizeContraDbFigureQuery(String query) =>
    query.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Resolves user-entered Figure text to ContraDB's exact source spelling.
///
/// Returns `null` for partial, unknown, or empty text. The endpoint would
/// return an error for those values, so callers must reject them before making
/// a request.
String? canonicalContraDbFigureQuery(String query) =>
    _contraDbFigureNames[_normalizeContraDbFigureQuery(query)];

/// Builds the JSON request body for a ContraDB **title**, **choreographer**, or
/// **figure** search.
///
/// ContraDB's array query DSL accepts title and choreographer text, but its
/// `figure` operator requires an exact canonical move key. Figure input is
/// normalized through [canonicalContraDbFigureQuery] before serialization.
/// The endpoint accepts `count` (page size), `offset` (page start), and an
/// optional `sort_by` (`"titleA"` sorts by title ascending).
///
/// Returns the body as a JSON-encoded string ready to POST. Title and
/// choreographer [query] text is sent verbatim; an invalid Figure query throws
/// [ArgumentError]. An empty [query] still produces a valid non-Figure body,
/// but callers should avoid searching on empty input.
String buildContraDbSearchBody(
  String query, {
  String filter = 'title',
  int count = contraDbSearchCount,
  int offset = 0,
  String sortBy = 'titleA',
}) {
  if (filter != 'title' && filter != 'choreographer' && filter != 'figure') {
    throw ArgumentError.value(filter, 'filter');
  }
  var bodyQuery = query;
  if (filter == 'figure') {
    final canonical = canonicalContraDbFigureQuery(query);
    if (canonical == null) {
      throw ArgumentError.value(
        query,
        'query',
        'must be an exact ContraDB figure name',
      );
    }
    bodyQuery = canonical;
  }
  return jsonEncode(<String, Object?>{
    'filter': <Object?>[filter, bodyQuery],
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
/// raw JSON response body here.
///
/// Robustness (mirrors the tolerant TCB parser): malformed JSON, a non-object
/// payload, a missing/non-list `dances` array, or individual non-object/idless rows
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
