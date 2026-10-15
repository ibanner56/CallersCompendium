import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/dialect/discouraged_terms.dart';
import 'package:test/test.dart';

/// User-glossary text canonicalization (#709): today's role rules, plus the
/// singular-subject verb exception and stored discouraged terms, decided by
/// the maintainer for this text only (2026-10-14).
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

  test('a discouraged term the dialect uses as its own role word is that '
      'role, stored and shown', () {
    // "ravens" is discouraged (role2s) in the built-in table, but this
    // dialect calls role1 "raven": storing role2s would invert the role.
    final birds = _birds;
    expect(
      FigureRenderer(
        contraTaxonomy,
      ).renderFreeTextWithCanonicalDiscouragedTerms('ravens cross', birds),
      'ravens cross',
      reason: 'shown as written, not as the other role',
    );
    // A word within a role term counts too.
    expect(
      canonicalizeGlossaryText('lady birds cross', _ladyBirds),
      'role1s cross',
    );
    expect(canonicalizeGlossaryText('ravens cross', birds), 'role1s cross');
    expect(
      canonicalizeGlossaryText('the raven leads', birds),
      'the role1 leads',
    );
    // The rest of the table still applies.
    expect(canonicalizeGlossaryText('ladies chain', birds), 'role2s chain');
    expect(canonicalizeGlossaryText('gypsy', birds), 'shoulder round');
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
    // that the two readers agree, so neither can drift from the other.
    final renderer = FigureRenderer(contraTaxonomy);
    for (final dialect in [...Dialect.presets, _birds, _ladyBirds]) {
      for (final term in discouragedTermMeanings.keys) {
        // A term the dialect claims is its own role word, read by the role
        // rules on both sides; the next test covers it.
        if (discouragedTermClaimedBy(dialect, term)) continue;
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
