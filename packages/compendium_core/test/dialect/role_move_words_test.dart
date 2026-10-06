// Role words that are also move words (post-audit parser-1 / parser-6, #715).
//
// The canonicalisation chokepoint maps the active dialect's role terms back to
// `role1`/`role2`. Some of those words are also move words: "robin" in the move
// name "mad robin", and — under Leads/Follows — the verbs "lead" and "follow"
// ("Ones lead down the hall"). Those must be kept as typed, while the same
// words used as roles are still canonicalised.
import 'package:compendium_core/compendium_core.dart';
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
    // The move name "mad robin(s)", in every dialect, as typed.
    for (final d in [canonical, lr, lf]) ...[
      (d, 'Mad robin twice', null),
      (d, 'mad robins, larks in front', 'mad robins, role1s in front'),
      (d, 'MAD ROBIN, LADIES IN', 'MAD ROBIN, role2s IN'),
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

  group('move words are kept as typed', () {
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
      'ones role1 down the hall',
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
}
