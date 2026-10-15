import 'dialect.dart';

/// What each built-in discouraged term stands for (#709): a canonical role
/// token, possibly possessive, or a move's display name.
///
/// One table, two readers that must not drift:
/// - the renderer, which displays a discouraged term in the active dialect
///   ("ladies" → "Robins") when canonicalizing them for display is on, and
/// - [storedDiscouragedTerms], which stores user-glossary text canonically
///   ("ladies" → `role2s`).
///
/// A possessive entry is written with the possessive ending of the term it
/// renders as, so "gents'" displays as "Larks'" and stores as `role1s'`.
const Map<String, ({String canonical, bool possessive})>
discouragedTermMeanings = {
  'gypsy': (canonical: 'shoulder round', possessive: false),
  'gyre': (canonical: 'shoulder round', possessive: false),
  'gent': (canonical: 'role1', possessive: false),
  "gent's": (canonical: 'role1', possessive: true),
  'gents': (canonical: 'role1s', possessive: false),
  "gents'": (canonical: 'role1s', possessive: true),
  'men': (canonical: 'role1s', possessive: false),
  "men's": (canonical: 'role1s', possessive: true),
  'men’s': (canonical: 'role1s', possessive: true),
  'lady': (canonical: 'role2', possessive: false),
  "lady's": (canonical: 'role2', possessive: true),
  'ladies': (canonical: 'role2s', possessive: false),
  "ladies'": (canonical: 'role2s', possessive: true),
  'women': (canonical: 'role2s', possessive: false),
  "women's": (canonical: 'role2s', possessive: true),
  'women’s': (canonical: 'role2s', possessive: true),
  'ravens': (canonical: 'role2s', possessive: false),
  "ravens'": (canonical: 'role2s', possessive: true),
};

/// [term] with the possessive ending its spelling takes: `'` after a final
/// `s`, `'s` otherwise.
String possessiveSpelling(String term) =>
    term.endsWith('s') ? "$term'" : "$term's";

/// [discouragedTermMeanings] as stored text: each term mapped to its canonical
/// token or move name, possessive where the term is.
final Map<String, String> storedDiscouragedTerms = {
  for (final e in discouragedTermMeanings.entries)
    e.key: e.value.possessive
        ? possessiveSpelling(e.value.canonical)
        : e.value.canonical,
};

/// [dialect]'s own role words (singular and plural, lowercase) that are one
/// of the built-in discouraged terms, or hold one as a word: "ravens" in a
/// dialect whose role1 is "Raven", "lady birds" in one whose role1 is "Lady
/// Bird". Words are split as [Substitutor] splits them, so "Lady-Bird"
/// counts too.
///
/// User-glossary canonicalization keeps these as the dialect's roles rather
/// than reading them by the table, which would invert a "ravens" role1 into
/// `role2s`, and the renderer's display conversion shows them as written for
/// the same reason (see `docs/design/dialect.md`).
Set<String> claimedRoleWords(Dialect dialect) {
  final bases = {
    for (final term in discouragedTermMeanings.keys) _withoutPossessive(term),
  };
  return {
    for (final role in dialect.roles.values)
      for (final word in [role.singular, role.plural])
        if (word
            .toLowerCase()
            .split(_nonWord)
            .any((w) => w.isNotEmpty && bases.contains(w)))
          word.toLowerCase(),
  };
}

/// What [Substitutor] treats as a word boundary.
final RegExp _nonWord = RegExp(r'[^\p{L}\p{M}\p{N}\p{Pc}]+', unicode: true);

/// [term] without a possessive ending (`'s`, `’s`, or a bare `'` or `’`).
String _withoutPossessive(String term) {
  for (final ending in const ["'s", '’s', "'", '’']) {
    if (term.endsWith(ending)) {
      return term.substring(0, term.length - ending.length);
    }
  }
  return term;
}
