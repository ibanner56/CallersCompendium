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
  'its',
  'another',
  'any',
  'no',
  'either',
  'neither',
  'which',
  'whose',
  'these',
  'those',
};

/// Singular dancer nouns that, directly before a plural role/verb homograph
/// and after a determiner, make it a verb under `subjectVerbException`
/// ("your partner leads"). Without the determiner the noun is more likely an
/// object than a subject ("swing partner, follows cross"), so it is not one.
const Set<String> _singularSubjectNouns = {
  'partner',
  'neighbor',
  'neighbour',
  'shadow',
  'corner',
  'couple',
  'dancer',
  'person',
};

/// Words that are a singular subject on their own, with no determiner before
/// them: "It leads into a swing", "Everyone follows the leader", "a call that
/// follows the balance".
const Set<String> _subjectPronouns = {
  'it',
  'he',
  'she',
  'this',
  'that',
  'which',
  'who',
  'whoever',
  'everyone',
  'everybody',
  'someone',
  'somebody',
  'anyone',
  'anybody',
  'nobody',
};

/// Ordinals: determiners (for the base form: "second follow") that also name
/// one item as the subject ("the second follows the first").
const Set<String> _ordinals = {'first', 'second', 'third', '1st', '2nd', '3rd'};

/// Counts and quantities. After a determiner they make the following plural
/// role a noun ("the two leads down the hall"), never a singular subject.
const Set<String> _quantities = {
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'few',
  'many',
  'several',
  'some',
  'more',
  'most',
  'fewer',
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
  // Possessive and quantifying objects: "follow their partners", "lead both
  // couples".
  'their',
  'his',
  'her',
  'our',
  'my',
  'its',
  'both',
  'all',
  'each',
  'every',
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

/// Any Unicode whitespace (`\s`, as [_whitespaceRun] uses).
final RegExp _whitespaceChar = RegExp(r'\s');

/// What may separate two words of one clause: whitespace, and the editor's
/// bold marker `*` (`figure_list_editor.dart`'s emphasis toolbar), which is
/// display markup, not punctuation.
bool _isGap(String ch) => ch == '*' || _whitespaceChar.hasMatch(ch);

/// The separator allowed between the words of a shielded move name.
const String _phraseGap = r'[\s*]+';

/// [word] without the editor's underline marker (an underscore,
/// `util/inline_emphasis.dart`) at its edges. The underscore is a word
/// character to the boundary patterns, so an underlined "down" is read as
/// "down".
String? _unmarked(String? word) {
  if (word == null) return null;
  var a = 0;
  var b = word.length;
  while (a < b && word.codeUnitAt(a) == 0x5F) {
    a++;
  }
  while (b > a && word.codeUnitAt(b - 1) == 0x5F) {
    b--;
  }
  return a == b ? null : word.substring(a, b);
}

/// The canonicalisation chokepoint's role rewriter, aware of words that are
/// both role terms and move words.
///
/// Each word-boundary match of a role term (the active [Dialect]'s terms,
/// [legacyRoleSynonyms], and any `extraRoleSynonyms`) is classified before it
/// is rewritten:
///
/// 1. Inside a multi-word move name from the [MoveWordLexicon] — "mad
///    robin(s)" — it is a
///    [RoleSpanKind.moveName]: not rewritten to a role, and the move name is
///    written lowercase and single-spaced.
/// 2. A form of a [roleHomographVerbs] entry ("lead"/"leads",
///    "follow"/"follows") is decided from its neighbours in the same clause
///    (Unicode whitespace and the editor's bold and underline markers,
///    `util/inline_emphasis.dart`, do not separate words):
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
/// With `subjectVerbException` (user-glossary text only, #709), rule 2a has
/// one exception: the plural form directly after a singular subject in the
/// same clause is the verb. A singular subject is a singular role term or
/// token ("the robin follows the lark", "role2 follows"), a singular dancer
/// noun after a determiner ("your partner leads"), a pronoun ("it leads into
/// a swing"), or any other singular noun after a determiner when a verb
/// complement comes next ("the caller follows the music"; see
/// [_followsSingularSubject]).
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
    this.subjectVerbException = false,
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

    // Only genuine move names. A dialect's own move substitutions are display
    // wording: a role word in one ("robins chain") comes from the dialect's
    // expansion, and shielding it would store the literal word on a no-edit
    // save of `role2s chain …`.
    final phrases = (lexicon ?? MoveWordLexicon.contra).phrases;
    final shielded = <String>{};
    final suspect = <String>{};
    for (final words in phrases) {
      if (words.length < 2) continue;
      final joined = words.join(' ');
      if (subjectBearingMovePhrases.contains(joined)) continue;
      final roleWords = words.where(reverse.containsKey).toList();
      if (roleWords.isEmpty) continue;
      suspect.addAll(roleWords);
      shielded.add(words.map(RegExp.escape).join(_phraseGap));
      // The plural of the head noun: "mad robins".
      final plural = [...words.take(words.length - 1), '${words.last}s'];
      if (reverse.containsKey(plural.last)) suspect.add(plural.last);
      shielded.add(plural.map(RegExp.escape).join(_phraseGap));
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

  /// Whether the plural form of a role/verb homograph directly after a
  /// singular subject is read as the verb (#709). Off everywhere but
  /// user-glossary text, so notes, custom figures, imports and search keep
  /// their bytes.
  final bool subjectVerbException;

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
    if (plural) {
      if (subjectVerbException && _followsSingularSubject(text, start, end)) {
        return (RoleSpanKind.verb, '2a-subject');
      }
      return (RoleSpanKind.role, '2a');
    }
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

  /// Whether the word directly before [start] names one dancer or thing as
  /// the subject of the plural form at [start]..[end]:
  ///
  /// - a singular role term of this canonicalizer ("robin", "lead") or a
  ///   singular role token typed directly;
  /// - a pronoun ([_subjectPronouns]): "it leads", "everyone follows";
  /// - after a determiner, a singular dancer noun ([_singularSubjectNouns]):
  ///   "your partner leads";
  /// - after a determiner, any other word that cannot be a plural role or a
  ///   function word ([_isOpenSubjectNoun]), but only when a verb complement
  ///   comes next: "the caller follows the music", "the line leads down".
  ///
  /// The last rule asks for the complement because the word may be an
  /// adjective, not the noun ("the new leads follow the ones"), and the
  /// complement is what separates "the new leads into a swing" from a plural
  /// role. Without a determiner the word is more likely an object than a
  /// subject ("swing caller follows the music"), so it is not one.
  bool _followsSingularSubject(String text, int start, int end) {
    final previous = _previousWordAt(text, start);
    if (previous == null) return false;
    final (word, at) = previous;
    if (word == 'role1' || word == 'role2') return true;
    final token = _reverse[word];
    if (token == 'role1' || token == 'role2') return true;
    if (_subjectPronouns.contains(word)) return true;
    final isDancerNoun = _singularSubjectNouns.contains(word);
    if (!isDancerNoun && !_isOpenSubjectNoun(word)) return false;
    final before = _previousWord(text, at);
    if (before == null || !_determiners.contains(before)) return false;
    if (isDancerNoun) return true;
    final next = _nextWord(text, end);
    return next != null &&
        _verbComplements.contains(next) &&
        !_reverse.containsKey(next);
  }

  /// Whether [word] may be the singular noun of a subject: not a plural
  /// (ending in "s", so "the ones leads down" and "the class follows" stay
  /// roles), a role term, a determiner other than an ordinal, a count, an
  /// auxiliary or a verb complement (a direction, a dancer word).
  bool _isOpenSubjectNoun(String word) {
    if (word.length < 2 || word.endsWith('s')) return false;
    final first = word.codeUnitAt(0);
    if (first >= 0x30 && first <= 0x39 && !_ordinals.contains(word)) {
      return false;
    }
    if (_reverse.containsKey(word) || _quantities.contains(word)) return false;
    if (_determiners.contains(word) && !_ordinals.contains(word)) return false;
    return !_auxiliaries.contains(word) && !_verbComplements.contains(word);
  }

  /// The lowercase word directly before [start] in the same clause: only
  /// whitespace and bold markers may separate them. Underline markers at the
  /// word's edges are dropped.
  static String? _previousWord(String text, int start) =>
      _previousWordAt(text, start)?.$1;

  /// [_previousWord], with the offset in [text] where its match starts.
  static (String, int)? _previousWordAt(String text, int start) {
    var i = start;
    while (i > 0 && _isGap(text[i - 1])) {
      i--;
    }
    if (i == start && i > 0) return null; // punctuation or no gap: no word
    final from = i < 64 ? 0 : i - 64;
    final m = _wordAtEnd.firstMatch(text.substring(from, i));
    if (m == null) return null;
    final word = _unmarked(m[0]!.toLowerCase());
    return word == null ? null : (word, from + m.start);
  }

  /// The lowercase word directly after [end] in the same clause: whitespace,
  /// bold markers or a hyphen ("follow-up") may separate them; any other
  /// character — a comma, a possessive apostrophe — means there is none.
  /// Underline markers at the word's edges are dropped.
  static String? _nextWord(String text, int end) {
    var i = end;
    if (i < text.length && text.codeUnitAt(i) == 0x2D) {
      i++;
    } else {
      while (i < text.length && _isGap(text[i])) {
        i++;
      }
      if (i == end) return null;
    }
    final to = i + 64 > text.length ? text.length : i + 64;
    final m = _wordAtStart.firstMatch(text.substring(i, to));
    return _unmarked(m?[0]!.toLowerCase());
  }
}
