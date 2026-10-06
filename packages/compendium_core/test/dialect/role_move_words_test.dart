// Role words that are also move words (post-audit parser-1 / parser-6, #715).
//
// The canonicalisation chokepoint maps the active dialect's role terms back to
// `role1`/`role2`. Some of those words are also move words: "robin" in the move
// name "mad robin", and — under Leads/Follows — the verbs "lead" and "follow"
// ("Ones lead down the hall"). Those must not become role tokens: a verb is
// kept as typed, and the move name is written in lowercase, as the import
// scrub writes it. The same words used as roles are still canonicalised.
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/taxonomy/dance_vocabulary.dart';
import 'package:test/test.dart';

void main() {
  final lf = Dialect.leadsFollows;
  final lr = Dialect.larksRobins;
  final canonical = Dialect.canonical;

  // (dialect, typed, stored)
  final kept = [
    // Verbs under Leads/Follows: a complement follows the singular form.
    (lf, 'Ones lead down the hall four abreast', null),
    (lf, 'Ones lead up', null),
    (lf, 'lead down, turn alone', null),
    (lf, 'Lead up the hall', null),
    (lf, 'Twos follow the ones down', null),
    (lf, 'follow your partner up the hall', null),
    (lf, 'learn to lead', null),
    (lf, 'The larks lead out.', 'The role1s lead out.'),
    (lf, 'Leads lead down the hall', 'role1s lead down the hall'),
    (lf, 'Follows follow the leads', 'role2s follow the role1s'),
    // The move name "mad robin(s)", in every dialect, written in lowercase
    // as the import scrub writes it (maintainer choice B, 2026-10-06).
    for (final d in [canonical, lr, lf]) ...[
      (d, 'Mad robin twice', 'mad robin twice'),
      (d, 'mad robins, larks in front', 'mad robins, role1s in front'),
      (d, 'MAD ROBIN, LADIES IN', 'mad robin, role2s IN'),
      (d, 'then Mad  Robins', 'then mad robins'),
      (d, 'then mad robin', null),
    ],
  ];

  // The same words used as roles are still canonicalised.
  final rewritten = [
    (lf, 'Leads chain', 'role1s chain'),
    (lf, 'Follows chain wide', 'role2s chain wide'),
    (lf, 'Leads allemande left 1½', 'role1s allemande left 1½'),
    (lf, "lead's right hand", "role1's right hand"),
    (lf, 'the lead on the left', 'the role1 on the left'),
    (lf, 'second follow swing', 'second role2 swing'),
    (lf, 'each follow turns alone', 'each role2 turns alone'),
    // The renderer's own single-dancer compounds (`twosRole2` → "twos
    // follow"): a dancer word before the role term is not verb evidence.
    (lf, 'twos follow swing', 'twos role2 swing'),
    (lf, 'ones lead', 'ones role1'),
    (lf, 'lead swings follow', 'role1 swings role2'),
    (lf, 'Leads down the hall, follows up', 'role1s down the hall, role2s up'),
    // A bare term (a search bind, a role-valued param) is a role.
    (lf, 'lead', 'role1'),
    (lf, 'follows', 'role2s'),
    (lr, 'Larks chain wide', 'role1s chain wide'),
    (lr, 'robins in the middle', 'role2s in the middle'),
    (lr, 'Ladies chain', 'role2s chain'),
  ];

  group('move words are not rewritten to roles', () {
    for (final (dialect, typed, stored) in kept) {
      test('"$typed" in ${dialect.name}', () {
        expect(canonicalizeText(typed, dialect), stored ?? typed);
      });
    }
  });

  group('role words are still canonicalised', () {
    for (final (dialect, typed, stored) in rewritten) {
      test('"$typed" in ${dialect.name}', () {
        expect(canonicalizeText(typed, dialect), stored);
      });
    }
  });

  group('round trip: stored text survives a load and save unchanged', () {
    // Stored canonical text, rendered into each dialect for editing and
    // canonicalised again on save, must come back byte-identical — including
    // the forms the renderer itself produces for single-dancer tokens.
    final stored = <String>{
      for (final (d, typed, s) in [...kept, ...rewritten])
        if (identical(d, lf) || identical(d, lr))
          s ?? canonicalizeText(typed, d),
      'twos role2 swing',
      'role2s mad robin once',
      'role1s lead out',
    };
    final renderer = FigureRenderer(contraTaxonomy);
    for (final dialect in [lr, lf]) {
      for (final s in stored) {
        test('"$s" in ${dialect.name}', () {
          final shown = renderer.renderFreeText(s, dialect);
          expect(canonicalizeText(shown, dialect), s, reason: 'shown "$shown"');
        });
      }
    }
  });

  // Not repaired (maintainer decision D4, 2026-10-06): a note stored by the
  // old canonicaliser as "Ones role1 down the hall" reads "Ones lead down the
  // hall" under Leads/Follows, so the next save there keeps the verb. Under
  // Larks/Robins it reads "Ones lark down the hall" and stays as stored.
  test('legacy "Ones role1 down the hall" heals on a Leads/Follows save', () {
    const legacy = 'Ones role1 down the hall';
    final renderer = FigureRenderer(contraTaxonomy);
    expect(
      canonicalizeText(renderer.renderFreeText(legacy, lf), lf),
      'Ones lead down the hall',
    );
    expect(canonicalizeText(renderer.renderFreeText(legacy, lr), lr), legacy);
  });

  // Copilot review of #1699: possessive objects, Unicode spaces and the
  // editor's inline markup (`*bold*`, `_underline_`) must not change how a
  // neighbour word is read.
  group('neighbour words across possessives, Unicode spaces and markup', () {
    for (final (typed, stored) in [
      ('Twos follow their partners up the hall', null),
      ('Ones lead his partner down', null),
      ('Twos follow her partner up', null),
      ('Ones lead our neighbors down', null),
      ('Ones lead down the hall', null),
      ('Ones lead down the hall', null),
      ('Ones lead down the hall', null),
      ('the lead down', 'the role1 down'),
      ('Ones *lead* down the hall', null),
      ('Ones lead *down* the hall', null),
      ('*Ones lead down the hall*', null),
      ('Ones lead _down the hall_', null),
      ('the *lead down*', 'the *role1 down*'),
      ('_the_ lead down', '_the_ role1 down'),
      ('*Leads* chain', '*role1s* chain'),
      ('*mad* Robin twice', '*mad* robin twice'),
      ('*Mad Robin*, *robins* in', '*mad robin*, *role2s* in'),
    ]) {
      test('"$typed"', () {
        expect(canonicalizeText(typed, lf), stored ?? typed);
      });
    }
    test('the role underline agrees on a bolded verb', () {
      expect(roleSpans('Ones *lead* down the hall', lf), isEmpty);
      expect(roleSpans('the lead down', lf), [(text: 'lead', start: 4)]);
    });
  });

  // A custom dialect's move substitution is display wording, not a move
  // name: its role words come from the dialect's own expansion, so they must
  // not be shielded. Otherwise a no-edit save of stored `role2s chain wide`
  // (shown as "robins chain wide") would store the literal word "robins".
  test('a no-edit save under a custom move substitution changes nothing', () {
    final custom = lr.copyWith(
      name: 'Custom',
      moves: {'chain': 'robins chain'},
    );
    const stored = 'role2s chain wide';
    final renderer = FigureRenderer(contraTaxonomy);
    final shown = renderer.renderFreeText(stored, custom);
    expect(shown, 'robins chain wide');
    final saved = canonicalizeText(shown, custom);
    expect(saved, stored);
    // And after a switch to another dialect it reads in that dialect.
    expect(renderer.renderFreeText(saved, lf), 'follows chain wide');
  });

  group('the lingo line underlines roles only', () {
    test('a verb lead is not a role span', () {
      expect(roleSpans('Ones lead down the hall', lf), isEmpty);
    });
    test('"mad robin" is not a role span', () {
      expect(roleSpans('Mad robin twice', lr), isEmpty);
    });
    test('the role in the same line still is', () {
      expect(roleSpans('Ones lead down, leads turn alone', lf), [
        (text: 'leads', start: 16),
      ]);
    });
  });

  group('import scrub', () {
    test('"madrobin" inside another word is left alone', () {
      expect(scrubFigureText('see madrobins.com'), 'see madrobins.com');
      expect(scrubFigureText('MadRobin'), 'MadRobin');
    });
    test('still writes the move name "mad robin" in lowercase', () {
      expect(
        scrubFigureText('Mad Robin, gents in front'),
        'mad robin, role1s in front',
      );
      expect(scrubFigureText('MAD ROBINS'), 'mad robins');
    });
  });

  group('vocabulary ratchets', () {
    test(
      'every taxonomy move name that contains a role word is classified',
      () {
        final roleWords = {
          ...legacyRoleSynonyms.keys,
          for (final d in Dialect.presets)
            for (final t in d.roles.values) ...[
              t.singular.toLowerCase(),
              t.plural.toLowerCase(),
            ],
        };
        final roleBearing = {
          for (final words in MoveWordLexicon.contra.phrases)
            if (words.any(roleWords.contains)) words.join(' '),
        };
        expect(
          roleBearing.difference(subjectBearingMovePhrases),
          {'mad robin'},
          reason:
              'A taxonomy name or keyword contains a role word. If the word '
              'names the move (like "mad robin"), add it here; if it names the '
              'dancer (like a "ladies chain" keyword), add it to '
              'subjectBearingMovePhrases so it is not shielded.',
        );
      },
    );

    test('the verb the hall grammar consumes is a role homograph', () {
      expect(roleHomographVerbs.keys, contains(leadVerb));
    });

    test('analyze reports which rule decided each occurrence', () {
      final decisions = RoleCanonicalizer(
        lf,
      ).analyze('Ones lead down, then mad robin; the lead swings');
      expect(
        [for (final d in decisions) (d.text, d.kind, d.rule, d.canonical)],
        [
          ('lead', RoleSpanKind.verb, '2d', null),
          ('robin', RoleSpanKind.moveName, '1', null),
          ('lead', RoleSpanKind.role, '2b', 'role1'),
        ],
      );
    });
  });
}
