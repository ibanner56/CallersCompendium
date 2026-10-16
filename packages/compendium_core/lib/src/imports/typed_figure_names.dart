import '../dialect/dialect.dart';
import '../model/figure.dart';
import '../taxonomy/taxonomy.dart';
import '../validation/validation.dart';
import 'figure_text_scrub.dart';

/// The "typed by a caller" grammar of free-text entry (#1826): what a caller
/// types that the import grammar, which follows how source sites write calls,
/// does not read. Free-text entry only; imports and the "Re-parse custom
/// figures" upgrade never consult it.
///
/// Two parts, both bounded by the free-text line cap and never throwing:
/// - [rewriteTypedSpellings], spoken turn amounts rewritten to the numerals the
///   grammar reads, tried before the line is parsed;
/// - [figureFromTypedName], a whole-line lookup of a move's name, tried only
///   when every parse of the line has failed.

/// `once and a half`, `one & a quarter`, `1 and three quarters`.
final RegExp _spokenTurns = RegExp(
  r'\b(?:once|one|1)\s+(?:and|&)\s+(a\s+half|a\s+quarter|(?:a\s+)?three\s+quarters)\b',
  caseSensitive: false,
);

/// [text] with each spoken turn amount written as the mixed number the import
/// grammar reads (`once and a half` → `1 1/2`). The grammar reads `once` and
/// leaves `and a half` as a note, which is the wrong amount, so the rewrite
/// runs before the parse rather than after a miss. Returns [text] itself when
/// nothing is rewritten.
String rewriteTypedSpellings(String text) {
  if (!_spokenTurns.hasMatch(text)) return text;
  return text.replaceAllMapped(_spokenTurns, (m) {
    final part = m.group(1)!.toLowerCase();
    if (part.contains('half')) return '1 1/2';
    if (part.contains('three')) return '1 3/4';
    return '1 1/4';
  });
}

/// A name's target: a move or alias id and the params the name itself states.
typedef _Named = ({String move, Map<String, Object?> params});

/// Caller phrasings that name a move but are not a taxonomy name. Each states
/// only what its words say.
const Map<String, _Named> _typedPhrasings = {
  'hey for four': (move: 'hey', params: {}),
  'half hey': (move: 'hey', params: {'length': 'half'}),
  'half hey for four': (move: 'hey', params: {'length': 'half'}),
  'full hey': (move: 'hey', params: {'length': 'full'}),
  'full hey for four': (move: 'hey', params: {'length': 'full'}),
  'turn as a couple': (move: 'turn_as_couples', params: {}),
};

final RegExp _ampersand = RegExp(r'\s*&\s*');
final RegExp _hyphen = RegExp(r'\s*-\s*');
final RegExp _spaces = RegExp(r'\s+');

/// The lookup key of a typed or listed name: scrubbed as the parser scrubs a
/// line, lowercased, `&` read as `and`, a hyphen as a space.
String _nameKey(String text) => scrubFigureText(text)
    .toLowerCase()
    .replaceAll(_ampersand, ' and ')
    .replaceAll(_hyphen, ' ')
    .replaceAll(_spaces, ' ')
    .trim();

/// The name table of each taxonomy, built once.
final Expando<Map<String, _Named>> _tables = Expando();

/// Every move display name, then every alias display name, then
/// [_typedPhrasings]; an earlier entry wins a shared key (`pull by` is the
/// move's name and two aliases' names, and the move states nothing the caller
/// did not type).
Map<String, _Named> _tableFor(Taxonomy taxonomy) =>
    _tables[taxonomy] ??= Map.unmodifiable(() {
      final table = <String, _Named>{};
      for (final move in taxonomy.moves.values) {
        if (move.id == customMoveId) continue;
        table.putIfAbsent(
          _nameKey(move.displayName),
          () => (move: move.id, params: const {}),
        );
      }
      for (final alias in taxonomy.aliases.values) {
        table.putIfAbsent(
          _nameKey(alias.displayName),
          () => (move: alias.id, params: const {}),
        );
      }
      for (final entry in _typedPhrasings.entries) {
        if (taxonomy.resolve(entry.value.move) == null) continue;
        table.putIfAbsent(_nameKey(entry.key), () => entry.value);
      }
      return table;
    }());

/// The move [dialect] displays as [key], when it names one. A dialect's
/// wording with a `%S` side placeholder is a template, not a name.
_Named? _dialectName(String key, Dialect dialect, Taxonomy taxonomy) {
  for (final entry in dialect.moves.entries) {
    if (entry.key == customMoveId || entry.value.contains('%')) continue;
    if (taxonomy.resolve(entry.key) == null) continue;
    if (_nameKey(entry.value) == key) {
      return (move: entry.key, params: const {});
    }
  }
  return null;
}

/// The figure [text] names when the whole line is a move's name, else `null`.
///
/// Names are, in order: a taxonomy display name, an alias display name, a
/// caller phrasing ([_typedPhrasings]), and the active [dialect]'s own name
/// for a move. A name shared by two of these reads as the first, so a dialect
/// that renames a move to another move's taxonomy name does not shadow that
/// move. Matching is whole-line, case-insensitive, with `&` for `and` and a
/// hyphen for a space; anything else on the line is a miss.
///
/// The figure states only what the name states plus [beats]: every other
/// param reads as the taxonomy default, as for any bare name the import
/// grammar reads (`chain`, `circle`). A move with a subject is marked
/// [Figure.assumedSubject] (#460), since the caller did not state one.
///
/// A candidate the taxonomy rejects is a miss, as in `parseFigureLine`; any
/// error is a miss, never a throw.
Figure? figureFromTypedName(
  String text, {
  int beats = 0,
  required Taxonomy taxonomy,
  Dialect? dialect,
}) {
  try {
    final key = _nameKey(text);
    if (key.isEmpty) return null;
    final named =
        _tableFor(taxonomy)[key] ??
        (dialect == null ? null : _dialectName(key, dialect, taxonomy));
    if (named == null) return null;
    final def = taxonomy.resolve(named.move);
    if (def == null) return null;
    final figure = Figure(
      move: named.move,
      params: {...named.params, if (beats > 0) 'beats': beats},
      assumedSubject:
          def.params.containsKey('who') && !named.params.containsKey('who'),
    );
    final rejected = taxonomy
        .validateFigure(figure)
        .any((i) => i.severity == ValidationSeverity.error);
    return rejected ? null : figure;
  } catch (_) {
    return null;
  }
}
