import 'package:compendium_core/compendium_core.dart';
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
      canonicalizeGlossaryText('partner leads down', lf),
      'partner leads down',
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

  test('the shared discouraged-term table drives the renderer too', () {
    // The renderer displays each term from the same meanings; this pins the
    // storage side against the display side so the two cannot drift.
    for (final entry in discouragedTermMeanings.entries) {
      final stored = canonicalDiscouragedTerms[entry.key]!;
      final shown = FigureRenderer(contraTaxonomy).renderFreeText(stored, lr);
      expect(stored, isNotEmpty, reason: entry.key);
      expect(shown, isNot(contains('role')), reason: entry.key);
    }
  });
}
