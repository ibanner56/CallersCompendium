// Test-only reference evaluator for ContraDB's filter language.
//
// A line-for-line PORT (not the original code) of the figure-filter subset of
// ContraDB's `lib/filter_dances.rb` and `lib/search_match.rb`
// (https://github.com/contradb/contra, read from `master` on 2026-11-05; both
// files are AGPL-3.0, as is this repository). Function names follow the Ruby so
// the two can be read side by side: `matching_figures_for_then` is
// [_forThen], `SearchMatch#abut` is [SearchMatch.abut], and so on.
//
// FIDELITY: checked against the Ruby by reading, and by hand-computed cases
// (`contradb_reference_test.dart`). It has NOT been cross-run against the real
// Ruby, so a slip common to the port and to those cases would go unseen: treat
// "the Collection agrees with this reference" as parity with ContraDB's
// SEMANTICS AS READ, not as a measurement of contradb.com.
//
// Modelled, not ported: libfigure's alias parameter tables (see
// [ContraDbDance.aliases]).
//
// Ruby conventions kept: a result is either `null` (Ruby `nil`: the dance does
// not match) or a `Set<SearchMatch>` that **may be empty** (a successful match
// that no particular figure index satisfies); every non-null result is truthy.
/// Raised where ContraDB would raise (an HTTP 500): an unknown operator, or a
/// `figure` filter naming a move that `defined_events` lacks.
class ContraDbReferenceError implements Exception {
  ContraDbReferenceError(this.message);
  final String message;
  @override
  String toString() => 'ContraDbReferenceError: $message';
}

/// One dance as ContraDB holds it: a flat list of **top-level** figures, each
/// reduced to its `move` key. (Parameters are not modelled: the translator
/// refuses every parameterised filter, so no reachable filter reads them.)
class ContraDbDance {
  ContraDbDance({
    required this.id,
    required this.moves,
    List<String?>? aliases,
    this.title = '',
    this.choreographer = '',
  }) : aliases = aliases ?? List<String?>.filled(moves.length, null);

  final String id;
  final List<String> moves;

  /// For a figure whose stored move is an alias's target with the alias's
  /// pinned parameter (a see saw is a `do si do` with left shoulders), the
  /// alias name; otherwise null. MODELLED, not ported: ContraDB answers an
  /// alias filter by `alias_filter(move)` (the pinned parameter values) against
  /// the figure's `parameter_values`, which needs libfigure's parameter tables;
  /// this abstracts that to "the figure carries that alias's pinned values".
  final List<String?> aliases;
  final String title;
  final String choreographer;

  int get nfigures => moves.length;
}

/// `search_match.rb`: a run of [count] consecutive figures starting at
/// [first], indices wrapping modulo [nfigures] (a "patch").
class SearchMatch {
  SearchMatch(this.first, this.nfigures, {this.count = 1}) {
    if (nfigures <= 0) {
      throw ContraDbReferenceError(
        'It does not make sense to make a SearchMatch on a zero-figure dance',
      );
    }
    if (count < 0) throw ContraDbReferenceError('count must be non-negative');
    if (first < 0 || first >= nfigures) {
      throw ContraDbReferenceError('first $first out of range');
    }
  }

  final int first;
  final int count;
  final int nfigures;

  /// Ruby `(first + count - 1) % nfigures` (Ruby's `%` is non-negative for a
  /// positive modulus, like Dart's).
  int get last => (first + count - 1) % nfigures;

  bool includes(int index) => indices.contains(index);

  List<int> get indices {
    final out = <int>[];
    var i = first;
    for (var n = 0; n < count; n++) {
      out.add(i);
      i += 1;
      if (i >= nfigures) i = 0;
    }
    return out;
  }

  bool abuts(SearchMatch other) => (last + 1) % nfigures == other.first;

  SearchMatch? abut(SearchMatch other) => abuts(other)
      ? SearchMatch(first, nfigures, count: count + other.count)
      : null;

  @override
  bool operator ==(Object other) =>
      other is SearchMatch &&
      other.first == first &&
      other.count == count &&
      other.nfigures == nfigures;

  @override
  int get hashCode => Object.hash(first, count, nfigures);

  @override
  String toString() => '|$first+$count%$nfigures|';
}

typedef Matches = Set<SearchMatch>;

/// The 52 move names ContraDB's `defined_events` holds (read from libfigure's
/// `figure.js`), with the three aliases mapped to their targets.
const Map<String, String> contraDbDefinedMoves = {
  'California twirl': 'California twirl',
  "Rory O'More": "Rory O'More",
  'allemande': 'allemande',
  'allemande orbit': 'allemande orbit',
  'arch & dive': 'arch & dive',
  'balance': 'balance',
  'balance the ring': 'balance the ring',
  'box circulate': 'box circulate',
  'box the gnat': 'box the gnat',
  'butterfly whirl': 'butterfly whirl',
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
  'slice': 'slice',
  'slide along set': 'slide along set',
  'square through': 'square through',
  'stand still': 'stand still',
  'star': 'star',
  'star promenade': 'star promenade',
  'swing': 'swing',
  'turn alone': 'turn alone',
  'up the hall': 'up the hall',
  'zig zag': 'zig zag',
  // Aliases (`defineFigureAlias`).
  'swat the flea': 'box the gnat',
  'see saw': 'do si do',
  'meltdown swing': 'swing',
};

/// `FilterDances.matching_figures` over [filter] (a decoded JSON array).
Matches? matchingFigures(List<Object?> filter, ContraDbDance dance) {
  final operator = filter.first as String;
  final name = operator == '&'
      ? 'figurewise_and'
      : operator.replaceAll('-', '_');
  switch (name) {
    case 'figure':
      return _forFigure(filter, dance);
    case 'no':
      return _forNo(filter, dance);
    case 'or':
      return _forOr(filter, dance);
    case 'and':
      return _forAnd(filter, dance);
    case 'figurewise_and':
      final a = _forAnd(filter, dance);
      return (a != null && a.isNotEmpty) ? a : null; // `a.present? ? a : nil`
    case 'not':
      return _forNot(filter, dance);
    case 'then':
      return _forThen(filter, dance);
    case 'title':
      return dance.title.toLowerCase().contains(
            (filter[1] as String).toLowerCase(),
          )
          ? <SearchMatch>{}
          : null;
    case 'choreographer':
      return dance.choreographer.toLowerCase().contains(
            (filter[1] as String).toLowerCase(),
          )
          ? <SearchMatch>{}
          : null;
  }
  throw ContraDbReferenceError(
    '${jsonLike(operator)} is not a valid operator in ${jsonLike(filter)}',
  );
}

/// Whether [dance] is in the result of [filter] (`filter_dances`'s `if mf`).
bool danceMatches(List<Object?> filter, ContraDbDance dance) =>
    matchingFigures(filter, dance) != null;

String jsonLike(Object? o) => o.toString();

Matches _allFiguresMatch(int nfigures) => {
  for (var i = 0; i < nfigures; i++) SearchMatch(i, nfigures),
};

Matches _allEmptyMatches(int nfigures) => {
  for (var i = 0; i < nfigures; i++) SearchMatch(i, nfigures, count: 0),
};

/// `dice_search_matches`: one count-1 match per index covered by any member.
Matches _diceSearchMatches(Matches set) => {
  for (final m in set)
    for (final i in m.indices) SearchMatch(i, m.nfigures),
};

Matches? _forFigure(List<Object?> filter, ContraDbDance dance) {
  final filterMove = filter[1] as String;
  final nfigures = dance.nfigures;
  if (filterMove == '*') {
    return nfigures > 0 ? _allFiguresMatch(nfigures) : null;
  }
  final paramFilters = filter.skip(2).toList();
  final searchMatches = <SearchMatch>{};
  for (var index = 0; index < nfigures; index++) {
    // `JSLibFigure.de_alias_move` is `defined_events[move].name`, which THROWS
    // for an undefined move. It sits inside the per-figure loop, so a
    // zero-figure dance never reaches it.
    final canonical = contraDbDefinedMoves[filterMove];
    if (canonical == null) {
      throw ContraDbReferenceError(
        'defined_events[${jsonLike(filterMove)}] is undefined (TypeError)',
      );
    }
    if (paramFilters.isNotEmpty) {
      // Explicit parameter filters need libfigure's per-move parameter tables,
      // which this reference does not carry; no translator output reaches here.
      throw ContraDbReferenceError('parameter filters are not modelled');
    }
    final isAlias = canonical != filterMove;
    // `param_filters = alias_filter(filter_move) if filter_is_alias`: an alias
    // filter selects the target move with the alias's pinned parameters.
    final passesParams = !isAlias || dance.aliases[index] == filterMove;
    if (dance.moves[index] == canonical && passesParams) {
      searchMatches.add(SearchMatch(index, nfigures));
    }
  }
  return searchMatches.isNotEmpty ? searchMatches : null;
}

Matches? _forNo(List<Object?> filter, ContraDbDance dance) {
  final sub = filter[1] as List<Object?>;
  if (matchingFigures(sub, dance) != null) return null;
  return _allFiguresMatch(dance.nfigures);
}

Matches? _forOr(List<Object?> filter, ContraDbDance dance) {
  var matches = <SearchMatch>{};
  var foundNone = true;
  for (final sub in filter.skip(1)) {
    final mf = matchingFigures(sub as List<Object?>, dance);
    if (mf != null) {
      matches = {...matches, ...mf};
      foundNone = false;
    }
  }
  return foundNone ? null : matches;
}

Matches? _forAnd(List<Object?> filter, ContraDbDance dance) {
  final subs = filter.skip(1).toList();
  if (subs.isEmpty) return <SearchMatch>{};
  final results = <Matches>[];
  for (final sub in subs) {
    final m = matchingFigures(sub as List<Object?>, dance);
    if (m == null) return null;
    results.add(m);
  }
  var m = results.first;
  for (final x in results.skip(1)) {
    m = m.intersection(x); // naive intersection, as in the Ruby
  }
  return m;
}

Matches? _forNot(List<Object?> filter, ContraDbDance dance) {
  final sub = filter[1] as List<Object?>;
  final matched = matchingFigures(sub, dance) ?? <SearchMatch>{};
  final matches = _allFiguresMatch(
    dance.nfigures,
  ).difference(_diceSearchMatches(matched));
  return matches.isNotEmpty ? matches : null;
}

Matches? _forThen(List<Object?> filter, ContraDbDance dance) {
  var goingConcerns = _allEmptyMatches(dance.nfigures);
  for (final sub in filter.skip(1)) {
    final m = matchingFigures(sub as List<Object?>, dance);
    if (m == null) return null;
    final newConcerns = <SearchMatch>{};
    for (final head in goingConcerns) {
      for (final tail in m) {
        final c = head.abut(tail);
        if (c != null) newConcerns.add(c);
      }
    }
    goingConcerns = newConcerns;
    if (goingConcerns.isEmpty) return null;
  }
  return goingConcerns;
}

/// Convenience for tests: ids of the [dances] [filter] selects.
List<String> contraDbMatchingIds(
  List<Object?> filter,
  Iterable<ContraDbDance> dances,
) => [
  for (final d in dances)
    if (danceMatches(filter, d)) d.id,
];
