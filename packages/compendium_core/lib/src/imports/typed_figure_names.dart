import '../dialect/dialect.dart';
import '../model/figure.dart';
import '../taxonomy/taxonomy.dart';
import '../validation/validation.dart';
import 'contradb_dancer_vocab.dart';
import 'figure_text_scrub.dart';

/// The "typed by a caller" grammar of free-text entry (#1826): what a caller
/// types that the import grammar, which follows how source sites write calls,
/// does not read. Free-text entry only; imports and the "Re-parse custom
/// figures" upgrade never consult it.
///
/// Two parts, both bounded by the free-text line cap and never throwing:
/// - [rewriteTypedSpellings], spoken turn amounts rewritten to the numerals the
///   grammar reads, tried before the line is parsed;
/// - [figureFromTypedName], a lookup of a move's name, alone or after a
///   dancer, tried only when every parse of the line has failed; the same
///   lookup after a dancer's discouraged term has been read by its meaning is
///   [figureFromTypedDancerName].

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

/// Characters a caller ends a line with that are not part of a name.
final RegExp _trailingPunctuation = RegExp(r'[\s.,;:!]+$');

/// The key of a typed line: [_nameKey] without the punctuation that ends it
/// (`hey.`, `mad robin!`, `hey ...`). Only the end of the line is trimmed, so
/// a question mark, a quote or punctuation inside the line is still a miss.
String _typedKey(String text) =>
    _nameKey(text).replaceFirst(_trailingPunctuation, '');

/// The dancer words a line may start with, each mapped to the canonical set it
/// names. A subset of [contradbDancerVocab], whose tokens it reuses: the role
/// words (`gents`, `ravens`, …) are left out because they are discouraged
/// terms whose meaning the active dialect may claim, which free text resolves
/// by [canonicalizeGlossaryText] (see [figureFromTypedDancerName]), and the
/// multi-word and corner sets because no move name is typed after one.
final Map<String, String> _dancerWords = {
  for (final word in const [
    'everyone',
    'ones',
    'twos',
    'partners',
    'partner',
    'neighbors',
    'neighbor',
    'role1s',
    'role2s',
  ])
    word: contradbDancerVocab[word]!,
};

/// The figure [text] names when the whole line is a move's name, or a dancer
/// and a move's name, else `null`.
///
/// Names are, in order: a taxonomy display name, an alias display name, a
/// caller phrasing ([_typedPhrasings]), and the active [dialect]'s own name
/// for a move. A name shared by two of these reads as the first, so a dialect
/// that renames a move to another move's taxonomy name does not shadow that
/// move. Matching is whole-line, case-insensitive, with `&` for `and` and a
/// hyphen for a space, and punctuation at the end of the line ignored (`hey.`);
/// anything else on the line is a miss. A name read whole wins over the same
/// words read as a dancer and a name.
///
/// The dancer form is one of [_dancerWords] then a name (`neighbor pass by`,
/// `ones arch and dive`): the figure's `who` is that dancer set. A move with no
/// `who` (`neighbor slice`), or a set the taxonomy rejects for the move, is a
/// miss (validation rejects the unknown param), and so is an unknown word in
/// the dancer's place; nothing is guessed.
///
/// The figure states only what the name and the dancer state plus [beats]:
/// every other param reads as the taxonomy default, as for any bare name the
/// import grammar reads (`chain`, `circle`). A move with a subject is marked
/// [Figure.assumedSubject] (#460) unless the line stated a dancer, since the
/// caller did not state one otherwise.
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
    final key = _typedKey(text);
    if (key.isEmpty) return null;
    final whole = _lookup(key, taxonomy, dialect);
    if (whole != null) return _figureFor(whole, beats, taxonomy);
    return _dancerFigure(key, beats, taxonomy, dialect);
  } catch (_) {
    return null;
  }
}

/// The figure [text] names as a dancer and a move's name (`ravens hey`), else
/// `null`; [text] is a line that a dialect or the built-in role terms have
/// already been read out of, such as the result of `canonicalizeGlossaryText`
/// (`ravens hey` → `role2s hey`). Unlike [figureFromTypedName] it never reads
/// the whole line as a name, so it cannot change a name that line reads.
Figure? figureFromTypedDancerName(
  String text, {
  int beats = 0,
  required Taxonomy taxonomy,
  Dialect? dialect,
}) {
  try {
    final key = _typedKey(text);
    return key.isEmpty ? null : _dancerFigure(key, beats, taxonomy, dialect);
  } catch (_) {
    return null;
  }
}

_Named? _lookup(String key, Taxonomy taxonomy, Dialect? dialect) =>
    _tableFor(taxonomy)[key] ??
    (dialect == null ? null : _dialectName(key, dialect, taxonomy));

Figure? _dancerFigure(
  String key,
  int beats,
  Taxonomy taxonomy,
  Dialect? dialect,
) {
  final space = key.indexOf(' ');
  if (space < 0) return null;
  final who = _dancerWords[key.substring(0, space)];
  if (who == null) return null;
  final named = _lookup(key.substring(space + 1), taxonomy, dialect);
  if (named == null || named.params.containsKey('who')) return null;
  return _figureFor(
    (move: named.move, params: {...named.params, 'who': who}),
    beats,
    taxonomy,
  );
}

Figure? _figureFor(_Named named, int beats, Taxonomy taxonomy) {
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
}
