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
/// What counts as a singular subject beyond a role term is the implementer's
/// choice; see "User-glossary text (#709)" in `docs/design/dialect.md`.
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
      'This follows the balance',
      'This leads into a swing',
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

  group('every pronoun and quantifier the rule names', () {
    // Each member of the closed lists, so that dropping one is caught.
    const verbs = [
      'He leads down the hall',
      'She follows the music',
      'Who leads into a swing',
      'Whoever leads down the hall',
      'Somebody follows the music',
      'Everybody leads down the hall',
      'Anyone follows the music',
      'Anybody leads into a swing',
      'the third leads down the hall',
      'the 2nd follows the first',
      'the 3rd leads down the hall',
      // A hyphen before the complement ("lead-up") is read like a space.
      'The line leads-up to a swing',
    ];
    for (final text in verbs) {
      test(text, () => expect(stored(text), text));
    }

    for (final q in [
      'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', //
      'nine', 'ten', 'few', 'many', 'several', 'some', 'more', 'most',
      'fewer',
    ]) {
      test('the $q leads down the hall is a count of roles', () {
        expect(stored('the $q leads down'), 'the $q role1s down');
      });
    }

    // Function words are never the noun of a subject.
    for (final w in [
      'up', 'down', 'to', 'all', 'not', 'will', 'can', 'must', 'should',
      'may', 'shall', 'would', 'could', 'never', 'always', //
    ]) {
      test('the $w leads down the hall', () {
        expect(stored('the $w leads down'), 'the $w role1s down');
      });
    }

    test('a one-letter word is no noun', () {
      expect(stored('the x follows the ones'), 'the x role2s the ones');
    });
  });

  group('that, this and which can also introduce a plural role', () {
    // "that" is a conjunction here, "this" a determiner: the roles that
    // follow are plural nouns, and the verb that follows them is a plural one.
    // The words are only a subject when a complement comes next ("a call that
    // follows the balance").
    const roles = {
      'Remember that follows go second': 'Remember that role2s go second',
      'so that follows can prepare': 'so that role2s can prepare',
      'Call early so that leads know when to go':
          'Call early so that role1s know when to go',
      'Make sure that leads cross first': 'Make sure that role1s cross first',
      'It is important that follows wait': 'It is important that role2s wait',
      'Callers say that leads go down the hall':
          'Callers say that role1s go down the hall',
      'Note that leads and follows trade places':
          'Note that role1s and role2s trade places',
      'Do this leads cross first': 'Do this role1s cross first',
      'the figure which leads cross first':
          'the figure which role1s cross first',
      // A role term next is no complement either.
      'a call that follows ladies': 'a call that role2s role2s',
    };
    for (final e in roles.entries) {
      test(e.key, () => expect(stored(e.key), e.value));
    }
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

  test('a role term after that/this/which is no complement either', () {
    // The role term is rewritten to a token, which is no complement, so a verb
    // decided on the word would flip to a role on the next save.
    final roles = RoleCanonicalizer(
      lf,
      extraRoleSynonyms: const {'neighbors': 'role1s'},
      subjectVerbException: true,
    );
    for (final (text, once) in [
      ('a call that follows neighbors', 'a call that role2s role1s'),
      ('the figure which leads neighbors', 'the figure which role1s role1s'),
      ('This follows neighbors', 'This role2s role1s'),
    ]) {
      expect(roles.canonicalize(text), once, reason: text);
      expect(roles.canonicalize(once), once, reason: 'again: $text');
    }
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
    // A no-edit save canonicalizes the stored text again, so the second pass
    // must change nothing: canonicalize(canonicalize(x)) == canonicalize(x).
    // This is not the render round trip (canonicalize(render(canonicalize(x)))),
    // which can differ, see "known limitations" in `docs/design/dialect.md`.
    //
    // Only Leads/Follows has "leads"/"follows" as role words, so only it
    // exercises the verb rule; the other dialects are controls that must stay
    // unchanged by it.
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
