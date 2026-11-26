/// Word vocabularies of the figure parser's grammar
/// (`imports/figure_parser.dart`), kept outside `imports/` so that code in other
/// layers can read a line with the same words the grammar uses.
///
/// Every key is lowercase: the parser lowercases a line, splits it on
/// whitespace and strips edge punctuation before it looks a word up here.
library;

/// Single words → canonical dancer-set token. Post-scrub, gendered terms are
/// already `role1`/`role2`; this maps relationship words + those tokens.
const Map<String, String> dancerWords = {
  'neighbor': 'neighbors',
  'neighbors': 'neighbors',
  // Free-text shorthand ("N swing") and the British spelling. Distinct tokens
  // from the TCB `n0..n4` codes below, which keep their own entries.
  'n': 'neighbors',
  'neighbour': 'neighbors',
  'neighbours': 'neighbors',
  'partner': 'partners',
  'partners': 'partners',
  'role1': 'role1s',
  'role1s': 'role1s',
  'role2': 'role2s',
  'role2s': 'role2s',
  'everyone': 'everyone',
  'ones': 'ones',
  'twos': 'twos',
  // v40: the third and fourth couples ("Threes cast up").
  'threes': 'threes',
  'fours': 'fours',
  // Tier B: TCB writes "Shadow allemande"; taxonomy supports `shadows`.
  'shadow': 'shadows',
  'shadows': 'shadows',
  // Tier B: TCB N-prefix relationship shorthand ("N2 neighbor", "N1", …).
  // Ni maps to the taxonomy's pair dancer-set convention.
  'n0': 'prevNeighbors',
  'n1': 'neighbors',
  'n2': 'nextNeighbors',
  'n3': 'thirdNeighbors',
  'n4': 'fourthNeighbors',
  // Tier B: TCB P-prefix partner-series shorthand ("P1 partner", "P2 partner",
  // …). P/P1 = current partner; P0 = previous; P2–P5 = successive next
  // partners (taxonomy v24, issue #732). P6+ and P-n have no taxonomy token
  // and are absent from this map so they decline the whole line to custom.
  'p': 'partners',
  'p1': 'partners',
  'p0': 'prevPartners',
  'p2': 'nextPartners',
  'p3': 'thirdPartners',
  'p4': 'fourthPartners',
  'p5': 'fifthPartners',
  // Tier B: TCB S-prefix shadow shorthand ("S1 shadow allemande left 1", "S2
  // shadow swing"). Glossary: S1 is the first shadow, S2 the next hands-four
  // beyond it (the same mapping the hey pass-list decoder's `tcbPassPeople`
  // uses). `S-1` is read as the bare shadow — a maintainer ruling recorded in
  // the PR that added it, not a glossary fact. `S3`+ and every other `S-n`
  // have no taxonomy token and are absent from this map, so a line using one
  // as its subject is left with an unconsumed word and stays custom.
  's1': 'shadows',
  's-1': 'shadows',
  's2': 'secondShadows',
  // TCB explicit-dancer codes map to the single-dancer identities: M/W are the
  // roles, 1 = the active couple (ones), 2 = the inactive couple (twos). So
  // M1 = active role1 (onesRole1), W1 = active role2 (onesRole2), M2 = inactive
  // role1 (twosRole1), W2 = inactive role2 (twosRole2). Bare codes only —
  // line-order annotations like "(M1-W2-M2-W1)" are stripped before recognition.
  // M3/W3 and M4/W4 are the third and fourth couples' dancers in the same way
  // (taxonomy v39, maintainer decision).
  'm1': 'onesRole1',
  'w1': 'onesRole2',
  'm2': 'twosRole1',
  'w2': 'twosRole2',
  'm3': 'threesRole1',
  'w3': 'threesRole2',
  'm4': 'foursRole1',
  'w4': 'foursRole2',
};

/// The neighbour, partner and shadow series as the figure display names them
/// (#2121): an ordinal, then the relationship (`prev neighbor`, `third
/// partner`, `second shadow`), and since v40 a role (`next role1s`). Keyed by
/// the relationship's singular, then by the ordinal; a role is keyed by its
/// plural (`role1s`), which is the only form that names a set. Read with
/// [seriesDancer], which also takes the plural of the others and the British
/// spelling.
///
/// These are two-word names: neither word alone names the set, and `next`,
/// `third` and `second` are ordinary words elsewhere in a call. `previous` is
/// read as `prev` (ContraDB's JSON API spells the previous neighbors that
/// way). `second neighbor` and `second partner` are
/// not listed: the display never writes them, and which set they mean is not
/// settled (ContraDB's `2nd neighbors` is the next neighbours).
const Map<String, Map<String, String>> seriesDancerWords = {
  'neighbor': {
    'prev': 'prevNeighbors',
    'previous': 'prevNeighbors',
    'next': 'nextNeighbors',
    'third': 'thirdNeighbors',
    'fourth': 'fourthNeighbors',
  },
  'partner': {
    'prev': 'prevPartners',
    'previous': 'prevPartners',
    'next': 'nextPartners',
    'third': 'thirdPartners',
    'fourth': 'fourthPartners',
    'fifth': 'fifthPartners',
  },
  'shadow': {'second': 'secondShadows'},
  // v40: the role1s and role2s among the previous and next neighbors. The
  // role words are canonical by the time a figure is read (`next larks`
  // arrives as `next role1s`). PLURAL ONLY: the display writes a role in the
  // plural, never `next lark`, and the maintainer ruled that `next lark roll
  // away neighbor` still reads as role1s with nextNeighbors, as it did before
  // these tokens. A key ending in `s` is read as it stands; the others take
  // the plural too ([seriesDancer], [seriesDancerPhrases]). There are no third
  // or fourth: the display never writes them.
  'role1s': {
    'prev': 'prevRole1s',
    'previous': 'prevRole1s',
    'next': 'nextRole1s',
  },
  'role2s': {
    'prev': 'prevRole2s',
    'previous': 'prevRole2s',
    'next': 'nextRole2s',
  },
};

/// The dancer set [ordinal] then [relationship] names in [seriesDancerWords],
/// or `null`. [relationship] may be singular or plural, except a plural-only
/// noun (`role1s`), which takes only the plural, and `neighbour` is read as
/// `neighbor`; both words are lowercase.
String? seriesDancer(String ordinal, String? relationship) {
  if (relationship == null) return null;
  var noun = relationship.replaceFirst('neighbour', 'neighbor');
  // A plural-only noun (`role1s`) is read as it stands: its singular is not
  // a key, so `next lark` names no set.
  final exact = seriesDancerWords[noun]?[ordinal];
  if (exact != null) return exact;
  if (noun.endsWith('s')) noun = noun.substring(0, noun.length - 1);
  return seriesDancerWords[noun]?[ordinal];
}

/// Every two-word phrase [seriesDancerWords] names, as (phrase, token): the
/// singular and the plural of each noun, or only the noun as written for a
/// plural-only one (`next role1s`). The ContraDB reader and the typed-name
/// reader build their dancer phrases from this, so they cannot disagree with
/// [seriesDancer] about which words name a set.
Iterable<MapEntry<String, String>> seriesDancerPhrases() sync* {
  for (final MapEntry(key: noun, value: byOrdinal)
      in seriesDancerWords.entries) {
    final pluralOnly = noun.endsWith('s');
    for (final MapEntry(key: ordinal, value: token) in byOrdinal.entries) {
      yield MapEntry('$ordinal $noun', token);
      if (!pluralOnly) yield MapEntry('$ordinal ${noun}s', token);
    }
  }
}

/// How the figure display words a set direction (`ParamKind.direction`) that
/// does not read as itself: a diagonal reads "on right diagonal" and a facing
/// direction "facing in". `across` and `along` read as themselves. The display
/// (`FigureRenderer`) writes these and the figure readers read them back
/// (#2121), so the two cannot drift apart.
const Map<String, String> displayDirectionPhrases = {
  'rightDiagonal': 'on right diagonal',
  'leftDiagonal': 'on left diagonal',
  'in': 'facing in',
  'out': 'facing out',
  'up': 'facing up',
  'down': 'facing down',
};

/// How the figure display words a set-relative facing (a gate's or a swing's
/// ending facing): "up the hall", "into the set". The display
/// (`FigureRenderer`) writes these and the figure readers read them back
/// (#2121).
const Map<String, String> displayFacingPhrases = {
  'in': 'into the set',
  'out': 'out of the set',
  'up': 'up the hall',
  'down': 'down the hall',
  'along': 'along the set',
};

/// Qualifiers that, followed by `neighbor`/`neighbors`, name the `sameRoles`
/// dancer set ("Same-role neighbor do-si-do" → `do_si_do(who: sameRoles)`).
///
/// They are not [dancerWords] entries because the qualifier alone is not a
/// dancer: "Same-role right and left through" and "trade with same-role
/// person" name no dancer set, and only the two-word pairing is read. The
/// parser checks the pair before it looks a word up in [dancerWords], so the
/// pairing never reads as plain `neighbors` with a stray qualifier.
/// `same-role` is The Caller's Box spelling; `same-sex` is the older term, which
/// the maintainer ruled names the same pairing.
const Set<String> sameRoleQualifiers = {'same-role', 'same-sex'};

/// Filler words that carry no structural meaning and may be dropped anywhere.
const Set<String> fillerWords = {'your', 'the', 'a', 'an'};

/// The verb the hall recognizers consume after a dancer subject ("Ones lead
/// down the hall", `_downTheHall` / `_upTheHall`). It is also the Leads/Follows
/// role term, which is why free-text entry parses a line raw before it
/// canonicalises it.
const String leadVerb = 'lead';

/// Calling verbs that are also role terms (base form → third-person/plural
/// form). Under Leads/Follows "lead" and "follow" are the role words, yet
/// "Ones lead down the hall" and "Twos follow the ones" use them as verbs, so
/// the role canonicaliser decides each occurrence from its neighbours instead
/// of always rewriting it (`dialect/role_canonicalizer.dart`).
///
/// [leadVerb] is here because the hall grammar consumes it; "follow" is not in
/// the grammar but is ordinary calling ("follow your partner up the hall").
const Map<String, String> roleHomographVerbs = {
  leadVerb: 'leads',
  'follow': 'follows',
};
