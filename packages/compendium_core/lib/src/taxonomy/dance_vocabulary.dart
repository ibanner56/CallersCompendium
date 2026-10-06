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
  // TCB explicit-dancer codes map to the single-dancer identities: M/W are the
  // roles, 1 = the active couple (ones), 2 = the inactive couple (twos). So
  // M1 = active role1 (onesRole1), W1 = active role2 (onesRole2), M2 = inactive
  // role1 (twosRole1), W2 = inactive role2 (twosRole2). Bare codes only —
  // line-order annotations like "(M1-W2-M2-W1)" are stripped before recognition.
  'm1': 'onesRole1',
  'w1': 'onesRole2',
  'm2': 'twosRole1',
  'w2': 'twosRole2',
};

/// Filler words that carry no structural meaning and may be dropped anywhere.
const Set<String> fillerWords = {'your', 'the', 'a', 'an'};

/// The verb the hall recognizers consume after a dancer subject ("Ones lead
/// down the hall", `_downTheHall` / `_upTheHall`). It is also the Leads/Follows
/// role term, which is why free-text entry parses a line raw before it
/// canonicalises it.
const String leadVerb = 'lead';
