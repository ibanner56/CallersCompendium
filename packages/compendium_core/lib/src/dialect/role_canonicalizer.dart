import '../model/figure.dart' show customMoveId;
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/dance_vocabulary.dart';
import '../taxonomy/taxonomy.dart';
import 'dialect.dart';
import 'substitution.dart';

/// What one role-word occurrence in free text turned out to be.
enum RoleSpanKind {
  /// A dancer role: rewritten to its canonical token.
  role,

  /// Part of a move name such as "mad robin": not a role; the move name is
  /// written in lowercase.
  moveName,

  /// A calling verb that is also a role term ("Ones lead down"): kept as typed.
  verb,
}

/// The decision for one occurrence of a role term in a piece of text.
final class RoleSpanDecision {
  const RoleSpanDecision({
    required this.start,
    required this.text,
    required this.kind,
    required this.rule,
    this.canonical,
  });

  /// Offset of the occurrence in the input.
  final int start;

  /// The occurrence as typed.
  final String text;

  final RoleSpanKind kind;

  /// The canonical role token it is rewritten to; `null` unless [kind] is
  /// [RoleSpanKind.role].
  final String? canonical;

  /// Which rule decided it (see [RoleCanonicalizer]); for tests and
  /// diagnostics.
  final String rule;

  int get end => start + text.length;
}

/// The multi-word move names of a [Taxonomy] (each `MoveDef`/`MoveAlias`
/// display name and search keyword), lowercased and split into words.
///
/// A role word inside one of these ("robin" in "mad robin") names the move,
/// not a dancer.
final class MoveWordLexicon {
  MoveWordLexicon._(this.phrases);

  factory MoveWordLexicon.fromTaxonomy(Taxonomy taxonomy) {
    final phrases = <String, List<String>>{};
    void add(String name) {
      final words = _words(name);
      if (words.length >= 2) phrases[words.join(' ')] = words;
    }

    for (final move in taxonomy.moves.values) {
      if (move.id == customMoveId) continue;
      add(move.displayName);
      move.searchKeywords.forEach(add);
    }
    for (final alias in taxonomy.aliases.values) {
      add(alias.displayName);
      alias.searchKeywords.forEach(add);
    }
    return MoveWordLexicon._(List.unmodifiable(phrases.values));
  }

  /// Built once from [contraTaxonomy].
  static final MoveWordLexicon contra = MoveWordLexicon.fromTaxonomy(
    contraTaxonomy,
  );

  /// Each phrase as its lowercase words.
  final List<List<String>> phrases;
}

/// Move names that contain a role word *as the dancer* (a hypothetical
/// "ladies chain" keyword). These are not shielded: the role word in them is
/// rewritten like any other. Empty today; `role_move_words_test.dart` fails if
/// the taxonomy gains a role-bearing name that is in neither this set nor the
/// test's list of shielded move names.
const Set<String> subjectBearingMovePhrases = {};

/// Legacy and synonym role terms that always map back to canonical role
/// tokens, independent of the active dialect. Keys are lowercase.
const Map<String, String> legacyRoleSynonyms = {
  'gent': 'role1',
  'gents': 'role1s',
  'gentlespoon': 'role1',
  'gentlespoons': 'role1s',
  'lark': 'role1',
  'larks': 'role1s',
  'man': 'role1',
  'men': 'role1s',
  'lady': 'role2',
  'ladies': 'role2s',
  'ladle': 'role2',
  'ladles': 'role2s',
  'robin': 'role2',
  'robins': 'role2s',
  'woman': 'role2',
  'women': 'role2s',
};

/// Words that, directly before a role/verb homograph, make it a noun ("the
/// lead", "second follow"). The parser's own filler words plus quantifiers,
/// ordinals and possessives.
final Set<String> _determiners = {
  ...fillerWords,
  'each',
  'every',
  'first',
  'second',
  'third',
  '1st',
  '2nd',
  '3rd',
  'other',
  'my',
  'his',
  'her',
  'their',
  'our',
  'this',
  'that',
  'next',
  'opposite',
};

/// Words that, directly before the base form, make it a verb ("to lead",
/// "do not follow").
const Set<String> _auxiliaries = {
  'to',
  'not',
  'will',
  'can',
  'must',
  'should',
  'may',
  'shall',
  'would',
  'could',
  'never',
  'always',
};

/// Words that, directly after the base form, make it a verb: a direction
/// ("lead down", "lead out"), an object determiner ("follow your partner",
/// "follow the ones") or a non-role dancer word ("follow neighbors").
final Set<String> _verbComplements = {
  'down',
  'up',
  'out',
  'off',
  'through',
  'forward',
  'back',
  'into',
  'across',
  'around',
  'along',
  'to',
  'them',
  ...fillerWords,
  // The parser's dancer words, minus the role tokens and the one- and
  // two-letter Caller's Box codes (`n`, `p1`, `m2`, …).
  for (final e in dancerWords.entries)
    if (e.key.length > 2 && !e.key.startsWith('role')) e.key,
};

final RegExp _wordAtEnd = RegExp(r'[\p{L}\p{M}\p{N}\p{Pc}]+$', unicode: true);
final RegExp _wordAtStart = RegExp(r'^[\p{L}\p{M}\p{N}\p{Pc}]+', unicode: true);
final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _wordRe = RegExp(r'[\p{L}\p{M}\p{N}\p{Pc}]+', unicode: true);

List<String> _words(String text) => [
  for (final m in _wordRe.allMatches(text.toLowerCase())) m[0]!,
];

bool _isGap(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

/// The canonicalisation chokepoint's role rewriter, aware of words that are
/// both role terms and move words.
///
/// Each word-boundary match of a role term (the active [Dialect]'s terms,
/// [legacyRoleSynonyms], and any `extraRoleSynonyms`) is classified before it
/// is rewritten:
///
/// 1. Inside a multi-word move name from the [MoveWordLexicon] (or the
///    dialect's own move substitutions) — "mad robin(s)" — it is a
///    [RoleSpanKind.moveName]: not rewritten to a role, and the move name is
///    written lowercase and single-spaced.
/// 2. A form of a [roleHomographVerbs] entry ("lead"/"leads",
///    "follow"/"follows") is decided from its neighbours in the same clause:
///    - a. the plural form is a role ("Leads chain");
///    - b. after a determiner it is a role ("the lead", "second follow");
///    - c. after an auxiliary it is a verb ("to lead", "not follow");
///    - d. followed by a verb complement it is a verb ("lead down", "follow
///      your partner");
///    - e. otherwise it is a role. A dancer word in front is NOT verb
///      evidence: "twos follow swing" is the renderer's own spelling of the
///      `twosRole2` dancer.
/// 3. Anything else is a role, rewritten exactly as before.
///
/// Rewritten roles are lowercase canonical tokens (`role1s`), whatever case
/// they were typed in. A move name from rule 1 is written lowercase and
/// single-spaced ("mad robin"), as the import scrub stores it (maintainer
/// choice B, 2026-10-06). A verb from rule 2 is left exactly as typed.
final class RoleCanonicalizer {
  RoleCanonicalizer(
    Dialect dialect, {
    Map<String, String> extraRoleSynonyms = const {},
    MoveWordLexicon? lexicon,
  }) {
    // Union enrichment first (lowest precedence); then legacy synonyms; then
    // the active dialect — so legacy and the active dialect always win where
    // they overlap, and the union only fills terms they leave unclaimed.
    final reverse = <String, String>{
      for (final e in extraRoleSynonyms.entries) e.key.toLowerCase(): e.value,
      ...legacyRoleSynonyms,
    };
    for (final entry in dialect.roles.entries) {
      reverse[entry.value.singular.toLowerCase()] = entry.key;
      reverse[entry.value.plural.toLowerCase()] = '${entry.key}s';
    }
    _reverse = reverse;
    _roles = Substitutor(reverse, caseInsensitive: true);

    final phrases = <List<String>>[
      ...(lexicon ?? MoveWordLexicon.contra).phrases,
      for (final display in dialect.moves.values)
        if (!display.contains('%S')) _words(display),
    ];
    final shielded = <String>{};
    final suspect = <String>{};
    for (final words in phrases) {
      if (words.length < 2) continue;
      final joined = words.join(' ');
      if (subjectBearingMovePhrases.contains(joined)) continue;
      final roleWords = words.where(reverse.containsKey).toList();
      if (roleWords.isEmpty) continue;
      suspect.addAll(roleWords);
      shielded.add(words.map(RegExp.escape).join(r'\s+'));
      // The plural of the head noun: "mad robins".
      final plural = [...words.take(words.length - 1), '${words.last}s'];
      if (reverse.containsKey(plural.last)) suspect.add(plural.last);
      shielded.add(plural.map(RegExp.escape).join(r'\s+'));
    }
    _shieldedPhrases = shielded.isEmpty
        ? null
        : RegExp(
            r'(?<![\p{L}\p{M}\p{N}\p{Pc}])(?:' +
                (shielded.toList()..sort((a, b) => b.length - a.length)).join(
                  '|',
                ) +
                r')(?![\p{L}\p{M}\p{N}\p{Pc}])',
            caseSensitive: false,
            unicode: true,
          );
    for (final e in roleHomographVerbs.entries) {
      if (reverse.containsKey(e.key)) {
        suspect.add(e.key);
        _verbForms[e.key] = false;
      }
      if (reverse.containsKey(e.value)) {
        suspect.add(e.value);
        _verbForms[e.value] = true;
      }
    }
    _suspect = suspect;
  }

  late final Map<String, String> _reverse;
  late final Substitutor _roles;
  late final RegExp? _shieldedPhrases;
  late final Set<String> _suspect;

  /// Verb-homograph form → whether it is the plural/third-person form.
  final Map<String, bool> _verbForms = {};

  /// Rewrites [text]'s role terms to canonical tokens, keeping move words.
  ///
  /// A move name that contains a role word ("Mad  Robins") is written in its
  /// canonical spelling — lowercase, single-spaced ("mad robins") — the same
  /// bytes the import scrub stores, so typed and imported text deduplicate
  /// (`figureCanonicalKey`).
  String canonicalize(String text) {
    if (text.isEmpty) return text;
    final shielded = _shieldedPhrases;
    if (shielded != null) {
      text = text.replaceAllMapped(
        shielded,
        (m) => m[0]!.toLowerCase().split(_whitespaceRun).join(' '),
      );
    }
    List<RegExpMatch>? moveSpans;
    return _roles.apply(
      text,
      where: (start, end) {
        final lower = text.substring(start, end).toLowerCase();
        if (!_suspect.contains(lower)) return true;
        moveSpans ??= _shieldedPhrases?.allMatches(text).toList() ?? const [];
        return _classify(text, start, end, lower, moveSpans!).$1 ==
            RoleSpanKind.role;
      },
    );
  }

  /// Every occurrence of a role term in [text], with its decision.
  List<RoleSpanDecision> analyze(String text) {
    if (text.isEmpty) return const [];
    final moveSpans =
        _shieldedPhrases?.allMatches(text).toList() ?? const <RegExpMatch>[];
    return [
      for (final m in _roles.matches(text))
        _decision(text, m.start, m.start + m.text.length, moveSpans),
    ];
  }

  RoleSpanDecision _decision(
    String text,
    int start,
    int end,
    List<RegExpMatch> moveSpans,
  ) {
    final typed = text.substring(start, end);
    final lower = typed.toLowerCase();
    final (kind, rule) = _suspect.contains(lower)
        ? _classify(text, start, end, lower, moveSpans)
        : (RoleSpanKind.role, '3');
    return RoleSpanDecision(
      start: start,
      text: typed,
      kind: kind,
      rule: rule,
      canonical: kind == RoleSpanKind.role ? _reverse[lower] : null,
    );
  }

  (RoleSpanKind, String) _classify(
    String text,
    int start,
    int end,
    String lower,
    List<RegExpMatch> moveSpans,
  ) {
    for (final m in moveSpans) {
      if (start >= m.start && end <= m.end) return (RoleSpanKind.moveName, '1');
    }
    final plural = _verbForms[lower];
    if (plural == null) return (RoleSpanKind.role, '3');
    if (plural) return (RoleSpanKind.role, '2a');
    final prev = _previousWord(text, start);
    if (prev != null && _determiners.contains(prev)) {
      return (RoleSpanKind.role, '2b');
    }
    if (prev != null && _auxiliaries.contains(prev)) {
      return (RoleSpanKind.verb, '2c');
    }
    final next = _nextWord(text, end);
    if (next != null && _verbComplements.contains(next)) {
      return (RoleSpanKind.verb, '2d');
    }
    return (RoleSpanKind.role, '2e');
  }

  /// The lowercase word directly before [start] in the same clause: only
  /// whitespace may separate them.
  static String? _previousWord(String text, int start) {
    var i = start;
    while (i > 0 && _isGap(text.codeUnitAt(i - 1))) {
      i--;
    }
    if (i == start && i > 0) return null; // punctuation or no gap: no word
    final from = i < 64 ? 0 : i - 64;
    final m = _wordAtEnd.firstMatch(text.substring(from, i));
    return m?[0]!.toLowerCase();
  }

  /// The lowercase word directly after [end] in the same clause: whitespace or
  /// a hyphen ("follow-up") may separate them; any other character — a
  /// comma, a possessive apostrophe — means there is none.
  static String? _nextWord(String text, int end) {
    var i = end;
    if (i < text.length && text.codeUnitAt(i) == 0x2D) {
      i++;
    } else {
      while (i < text.length && _isGap(text.codeUnitAt(i))) {
        i++;
      }
      if (i == end) return null;
    }
    final to = i + 64 > text.length ? text.length : i + 64;
    final m = _wordAtStart.firstMatch(text.substring(i, to));
    return m?[0]!.toLowerCase();
  }
}
