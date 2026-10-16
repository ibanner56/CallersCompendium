import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/dialect/discouraged_terms.dart';
import 'package:test/test.dart';

/// User-glossary text canonicalization (#709): today's role rules, plus the
/// singular-subject verb exception and stored discouraged terms, for this text
/// only. The maintainer decided the stored terms and the singular-role-term
/// exception (2026-10-14); what else counts as a subject is the implementer's
/// choice (`docs/design/dialect.md`).
void main() {
  final lf = Dialect.leadsFollows;
  final lr = Dialect.larksRobins;

  test('a plural homograph after a singular subject is the verb', () {
    expect(
      canonicalizeGlossaryText('The robin follows the lark across', lf),
      'The role2 follows the role1 across',
    );
    expect(
      canonicalizeGlossaryText('the lead follows', lf),
      'the role1 follows',
    );
    expect(
      canonicalizeGlossaryText('your partner leads down', lf),
      'your partner leads down',
    );
    expect(
      canonicalizeGlossaryText('each neighbor follows', lf),
      'each neighbor follows',
    );
    expect(canonicalizeGlossaryText('role2 follows', lf), 'role2 follows');
  });

  test('a plural role in front of a homograph is not a singular subject', () {
    // A plural role term or token in front is not a singular subject: "leads"
    // and "robins" are plural, so the word after them stays a role.
    expect(canonicalizeGlossaryText('leads follows', lf), 'role1s role2s');
    expect(
      canonicalizeGlossaryText('the robins follows', lf),
      'the role2s role2s',
    );
  });

  group('each singular dancer noun after a determiner is a subject', () {
    for (final noun in [
      'partner',
      'neighbor',
      'neighbour',
      'shadow',
      'corner',
      'couple',
      'dancer',
      'person',
    ]) {
      test('"the $noun leads down"', () {
        expect(
          canonicalizeGlossaryText('the $noun leads down', lf),
          'the $noun leads down',
        );
      });
    }
  });

  test('the subject is found past 64 characters of preceding text', () {
    // The subject's offset is into the whole text, not into the 64-character
    // window searched for it: the determiner in front of it is read from
    // there.
    const lead =
        'Everyone dances the first half of the figure facing across, then ';
    expect(lead.length, greaterThan(64));
    expect(
      canonicalizeGlossaryText('${lead}your partner leads down', lf),
      '${lead}your partner leads down',
    );
  });

  test('a dancer noun with no determiner is not taken for a subject', () {
    // "swing partner" makes partner the object, so what follows starts the
    // next call: the plural role.
    expect(
      canonicalizeGlossaryText('swing partner follows cross', lf),
      'swing partner role2s cross',
    );
    expect(
      canonicalizeGlossaryText('partner leads down', lf),
      'partner role1s down',
    );
  });

  test('with no subject in front it is still the plural role', () {
    expect(
      canonicalizeGlossaryText('leads cross + follows loop', lf),
      'role1s cross + role2s loop',
    );
    expect(
      canonicalizeGlossaryText('Leads down the hall, follows up', lf),
      'role1s down the hall, role2s up',
    );
  });

  test('the same sentence in another dialect is unaffected', () {
    expect(
      canonicalizeGlossaryText('The robin follows the lark across', lr),
      'The role2 follows the role1 across',
    );
  });

  test('discouraged terms are stored canonically, possessives included', () {
    expect(canonicalizeGlossaryText('Ladies chain', lf), 'role2s chain');
    expect(canonicalizeGlossaryText('ravens chain', lr), 'role2s chain');
    expect(canonicalizeGlossaryText("ravens' turn", lr), "role2s' turn");
    expect(canonicalizeGlossaryText("gent's hand", lr), "role1's hand");
    expect(
      canonicalizeGlossaryText('gypsy with partner', lr),
      'shoulder round with partner',
    );
  });

  test('a role word of the dialect that is or holds a discouraged term '
      'keeps the dialect\'s meaning', () {
    // "ravens" is discouraged (role2s) in the built-in table, but this
    // dialect calls role1 "raven": storing role2s would invert the role.
    expect(canonicalizeGlossaryText('ravens cross', _birds), 'role1s cross');
    expect(canonicalizeGlossaryText("ravens' turn", _birds), "role1s' turn");
    expect(
      canonicalizeGlossaryText('the raven leads', _birds),
      'the role1 leads',
    );
    // A role word holding a term is kept whole, however it is split.
    expect(
      canonicalizeGlossaryText('lady birds cross', _ladyBirds),
      'role1s cross',
    );
    expect(
      canonicalizeGlossaryText('Lady-Birds cross', _hyphenBirds),
      'role1s cross',
    );
    // Possessives too, where the table has its own possessive key.
    expect(canonicalizeGlossaryText("lady's hand", _swapped), "role1's hand");
    expect(canonicalizeGlossaryText("gent's hand", _swapped), "role2's hand");
    expect(
      canonicalizeGlossaryText('women’s hands', _womenMen),
      'role1s’s hands',
    );
    expect(
      canonicalizeGlossaryText("men's hands", _womenMen),
      "role2s's hands",
    );
    // The term on its own still reads by the table, as the role rules'
    // legacy synonyms read it too.
    expect(canonicalizeGlossaryText('lady chain', _ladyBirds), 'role2 chain');
    expect(canonicalizeText('lady chain', _ladyBirds), 'role2 chain');
    // The rest of the table still applies.
    expect(canonicalizeGlossaryText('ladies chain', _birds), 'role2s chain');
    expect(canonicalizeGlossaryText('gypsy', _birds), 'shoulder round');
  });

  test('the stored discouraged-term table, pinned term by term', () {
    // The round-trip test below derives its expectations from the table it
    // is checking, so it cannot notice a term whose meaning changed or
    // went missing. This pins the concrete table; adding a term means adding
    // it here.
    const stored = {
      'gypsy': 'shoulder round',
      'gyre': 'shoulder round',
      'gent': 'role1',
      "gent's": "role1's",
      'gents': 'role1s',
      "gents'": "role1s'",
      'men': 'role1s',
      "men's": "role1s'",
      'men’s': "role1s'",
      'lady': 'role2',
      "lady's": "role2's",
      'ladies': 'role2s',
      "ladies'": "role2s'",
      'women': 'role2s',
      "women's": "role2s'",
      'women’s': "role2s'",
      'ravens': 'role2s',
      "ravens'": "role2s'",
    };
    expect(storedDiscouragedTerms, stored);
    for (final e in stored.entries) {
      expect(canonicalizeGlossaryText(e.key, lr), e.value, reason: e.key);
    }
  });

  test('move names stay protected', () {
    expect(canonicalizeGlossaryText('Mad Robin', lr), 'mad robin');
  });

  test('the default path keeps today\'s bytes for the same inputs', () {
    expect(
      canonicalizeText('The robin follows the lark across', lf),
      'The role2 role2s the role1 across',
    );
    expect(canonicalizeText('partner leads down', lf), 'partner role1s down');
    expect(canonicalizeText("ravens' turn", lr), "ravens' turn");
    expect(canonicalizeText('gypsy with partner', lr), 'gypsy with partner');
  });

  test('a stored discouraged term displays as the renderer displays the term '
      'itself, in every preset dialect and in custom ones', () {
    // Storage and display read one table (discouraged_terms.dart); this pins
    // that the two readers agree, so neither can drift from the other. Not
    // the Ravens dialect: there "ravens" is its own role1, which storage
    // keeps and display conversion does not know (docs/design/dialect.md).
    final renderer = FigureRenderer(contraTaxonomy);
    for (final dialect in [...Dialect.presets, _ladyBirds, _hyphenBirds]) {
      for (final term in discouragedTermMeanings.keys) {
        final stored = canonicalizeGlossaryText(term, dialect);
        expect(stored, storedDiscouragedTerms[term], reason: term);
        expect(
          renderer.renderFreeText(stored, dialect),
          renderer.renderFreeTextWithCanonicalDiscouragedTerms(term, dialect),
          reason: '${dialect.name}: $term',
        );
      }
    }
  });
}

final _birds = Dialect(
  name: 'Ravens/Crows',
  roles: const {'role1': RoleTerm('Raven'), 'role2': RoleTerm('Crow')},
  discouragedTerms: Dialect.defaultDiscouragedTerms,
);

final _ladyBirds = Dialect(
  name: 'Lady Birds/Jays',
  roles: const {'role1': RoleTerm('Lady Bird'), 'role2': RoleTerm('Jay')},
  discouragedTerms: Dialect.defaultDiscouragedTerms,
);

final _hyphenBirds = Dialect(
  name: 'Lady-Birds/Jays',
  roles: const {'role1': RoleTerm('Lady-Bird'), 'role2': RoleTerm('Jay')},
  discouragedTerms: Dialect.defaultDiscouragedTerms,
);

/// The table reads "lady" as role2 and "gent" as role1; this dialect swaps
/// them.
final _swapped = Dialect(
  name: 'Ladies/Gents swapped',
  roles: const {'role1': RoleTerm('Lady'), 'role2': RoleTerm('Gent')},
  discouragedTerms: Dialect.defaultDiscouragedTerms,
);

final _womenMen = Dialect(
  name: 'Women/Men swapped',
  roles: const {
    'role1': RoleTerm('Woman', plural: 'Women'),
    'role2': RoleTerm('Man', plural: 'Men'),
  },
  discouragedTerms: Dialect.defaultDiscouragedTerms,
);
