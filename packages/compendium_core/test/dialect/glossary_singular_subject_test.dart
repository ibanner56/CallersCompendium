import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Which "leads"/"follows" in user-glossary text is a verb (#709).
///
/// Under Leads/Follows `canonicalizeGlossaryText` keeps the plural form of the
/// calling verbs as typed when its subject is one dancer or thing, and stores
/// it as a plural role token otherwise. `glossary_canonicalize_test.dart`
/// pins the dancer subjects ("your partner leads"); this file pins the wider
/// class, so that "The caller follows the music" is not stored as "The caller
/// role2s the music" (and displayed as "The caller Robins the music"), and
/// pins the plural role nouns that must keep converting beside it.
///
/// The rule under test is a decision of the author session, not of the
/// maintainer; see "User-glossary text (#709)" in `docs/design/dialect.md`.
void main() {
  final lf = Dialect.leadsFollows;

  String stored(String text) => canonicalizeGlossaryText(text, lf);

  group('a singular subject makes the plural form a verb', () {
    // Determiner + a noun that is not a role or a dancer word, then a verb
    // complement (a direction, an object).
    const kept = [
      'The caller follows the music',
      'The line leads down the hall',
      'The set follows the music',
      'A figure that leads into a swing',
      'This figure follows the balance',
      'Each call leads into the next',
      'your caller leads the walk-through',
      'The swing leads into a balance',
      'the first leads down and the second follows the first',
      'the 1st follows their partner',
      // Markup does not hide the subject.
      'The *caller* follows the music',
      'The _caller_ follows the music',
      'The caller\u00A0follows the music',
    ];
    for (final text in kept) {
      test(text, () => expect(stored(text), text));
    }

    // A pronoun is a singular subject with no determiner.
    const pronouns = [
      'It leads into a swing',
      'Everyone follows the leader',
      'Someone follows the music',
      'Nobody leads down the hall',
      'Whoever follows their partner',
      'a call that follows the balance',
      'the figure which leads into a swing',
    ];
    for (final text in pronouns) {
      test(text, () => expect(stored(text), text));
    }

    test('role words elsewhere in the sentence still convert', () {
      expect(
        stored('The caller follows the lead across'),
        'The caller follows the role1 across',
      );
      expect(
        stored('It leads the ladies into a swing'),
        'It leads the role2s into a swing',
      );
    });
  });

  group('a plural role noun is still a role', () {
    // Everything here is stored the same on main before the rule: it guards
    // the rule against reading any word after a determiner as the subject.
    const roles = {
      // A plural role after a determiner, or after a determiner and an
      // adjective, a count or a quantity.
      'the leads follow the follows': 'the role1s follow the role2s',
      'the new leads follow the ones': 'the new role1s follow the ones',
      'swing the other leads cross': 'swing the other role1s cross',
      'the two leads down the hall': 'the two role1s down the hall',
      'the 2 follows into a swing': 'the 2 role2s into a swing',
      'the first two follows into a swing': 'the first two role2s into a swing',
      'the several leads across': 'the several role1s across',
      'all the leads cross': 'all the role1s cross',
      // No complement after it: nothing says it is a verb.
      'the active leads chain': 'the active role1s chain',
      'the inside leads, follows outside': 'the inside role1s, role2s outside',
      'with the outside follows': 'with the outside role2s',
      // A plural noun before it is no singular subject.
      'the ones leads down': 'the ones role1s down',
      'the robins follows down': 'the role2s role2s down',
      'the larks follows across': 'the role1s role2s across',
      'the neighbors follows across': 'the neighbors role2s across',
      // The word before it is a plural, a count, a role term or a
      // determiner, not the noun of a singular subject.
      'the callers leads down the hall': 'the callers role1s down the hall',
      'the 12 leads down the hall': 'the 12 role1s down the hall',
      'the other leads down the hall': 'the other role1s down the hall',
      // No determiner before the noun: more likely an object than a subject.
      'swing caller follows the music': 'swing caller role2s the music',
      'caller leads down the hall': 'caller role1s down the hall',
      'swing partner follows cross': 'swing partner role2s cross',
      // A role word in front is a plural subject or a singular one as before.
      'leads follows': 'role1s role2s',
      'leads cross follows loop': 'role1s cross role2s loop',
      'leads cross + follows loop': 'role1s cross + role2s loop',
      'Leads down the hall, follows up': 'role1s down the hall, role2s up',
      // A bare word, a possessive and a sentence of roles.
      'follows': 'role2s',
      "the caller's follows": "the caller's role2s",
      'leads and follows swap': 'role1s and role2s swap',
      'the leads and the follows swap': 'the role1s and the role2s swap',
      'Leads lead down the hall': 'role1s lead down the hall',
    };
    for (final e in roles.entries) {
      test(e.key, () => expect(stored(e.key), e.value));
    }
  });

  test('a verb complement that is also a role term is not a complement', () {
    // Text is canonicalized again on every save, and the first pass rewrites
    // the role term to a token, which is no complement. A verb decided on the
    // word would flip to a role on the second pass.
    final roles = RoleCanonicalizer(
      lf,
      extraRoleSynonyms: const {'neighbors': 'role1s'},
      subjectVerbException: true,
    );
    const text = 'The caller follows neighbors';
    final once = roles.canonicalize(text);
    expect(once, 'The caller role2s role1s');
    expect(roles.canonicalize(once), once);
  });

  test('a plural role term that does not end in "s" is no singular noun', () {
    final roles = RoleCanonicalizer(
      lf,
      extraRoleSynonyms: const {'leadfolk': 'role1s'},
      subjectVerbException: true,
    );
    expect(
      roles.canonicalize('the leadfolk follows down the hall'),
      'the role1s role2s down the hall',
    );
  });

  group('other dialects', () {
    test('where "leads" is not a role word the text is untouched', () {
      expect(
        canonicalizeGlossaryText(
          'The caller follows the music',
          Dialect.larksRobins,
        ),
        'The caller follows the music',
      );
    });
    test('plain canonicalizeText keeps its bytes', () {
      // The exception is for glossary text only.
      expect(
        canonicalizeText('The caller follows the music', lf),
        'The caller role2s the music',
      );
    });
  });

  group('idempotence', () {
    // Every glossary text is canonicalized again by each later save, so the
    // second pass must change nothing.
    final custom = Dialect(
      name: 'Ravens/Crows',
      roles: const {'role1': RoleTerm('Raven'), 'role2': RoleTerm('Crow')},
      discouragedTerms: Dialect.defaultDiscouragedTerms,
    );
    final dialects = [
      lf,
      Dialect.larksRobins,
      Dialect.canonical,
      custom,
      // Role words that are also complement words.
      Dialect(
        name: 'Ones/Twos',
        roles: const {'role1': RoleTerm('Ones'), 'role2': RoleTerm('Twos')},
        discouragedTerms: Dialect.defaultDiscouragedTerms,
      ),
    ];
    const prefixes = ['', 'Swing ', '*', 'and then '];
    const determiners = ['', 'the ', 'your ', 'this ', 'each ', 'the new '];
    const nouns = [
      'caller',
      'line',
      'set',
      'music',
      'class',
      'partner',
      'lead',
      'follow',
      'lark',
      'robin',
      'gypsy',
      'two',
      'first',
      'ones',
      'leads',
      'follows',
      'it',
      'everyone',
      'who',
      'that',
      'raven',
      'crow',
      'lady',
      'ladies',
      'role1',
      'role2s',
    ];
    const verbs = ['leads', 'follows', 'lead', 'follow', 'Leads', 'FOLLOWS'];
    const tails = [
      '',
      ' down the hall',
      ' the music',
      ',',
      ' cross',
      ' robins',
      ' ones',
      ' lead',
      ' role2s',
      ' crow',
      ' ladies',
      '_',
      '-up',
    ];

    test('canonicalizeGlossaryText(canonicalizeGlossaryText(x)) == it', () {
      final failures = <String>[];
      var count = 0;
      for (final dialect in dialects) {
        for (final prefix in prefixes) {
          for (final det in determiners) {
            for (final noun in nouns) {
              for (final verb in verbs) {
                for (final tail in tails) {
                  final text = '$prefix$det$noun $verb$tail';
                  count++;
                  final once = canonicalizeGlossaryText(text, dialect);
                  final twice = canonicalizeGlossaryText(once, dialect);
                  if (once != twice) {
                    failures.add(
                      '${dialect.name}: "$text" -> "$once" -> '
                      '"$twice"',
                    );
                  }
                }
              }
            }
          }
        }
      }
      expect(count, greaterThan(50000));
      expect(failures.take(20), isEmpty, reason: '${failures.length} failed');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
