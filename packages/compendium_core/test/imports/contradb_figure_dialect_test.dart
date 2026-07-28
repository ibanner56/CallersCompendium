import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Tests for the ContraDB-HTML figure front-end
/// (`contradb_figure_dialect.dart`, [contraDbHtmlFigureFrontEnd]): the
/// reverse-parsers that map ContraDB's rendered figure prose back to structured
/// taxonomy figures and split off a verbatim note tail.
///
/// Inputs are the actual strings ContraDB renders (default dialect →
/// `gentlespoons`/`ladles`, unicode fractions, `&`); the default
/// [scrubFigureText] runs first (roles → `role1s`/`role2s`), exactly as the live
/// adapter drives it.
Figure _parse(String text) {
  final f = parseFigureLine(text, frontEnd: contraDbHtmlFigureFrontEnd);
  expect(f, isNotNull, reason: 'parse of "$text" returned null');
  return f!;
}

void main() {
  group('contraDbHtmlFigureFrontEnd — structured recognition', () {
    test('plain swing', () {
      final f = _parse('neighbors swing');
      expect(f.isCustom, isFalse);
      expect(f.move, 'swing');
      expect(f.params['who'], 'neighbors');
      expect(f.note, isNull);
    });

    test('balance & swing → swing with balance prefix', () {
      final f = _parse('partners balance & swing');
      expect(f.move, 'swing');
      expect(f.params['who'], 'partners');
      expect(f.params['prefix'], 'balance');
    });

    test('long swing → 16 beats', () {
      final f = _parse('partners long swing');
      expect(f.move, 'swing');
      expect(f.params['who'], 'partners');
      expect(f.params['beats'], 16);
    });

    test('long lines forward & back → goBack true', () {
      final f = _parse('long lines forward & back');
      expect(f.move, 'long_lines');
      expect(f.params['goBack'], isTrue);
    });

    test('long lines forward → goBack false', () {
      final f = _parse('long lines forward');
      expect(f.move, 'long_lines');
      expect(f.params['goBack'], isFalse);
    });

    test('ladles chain → chain role2s', () {
      final f = _parse('ladles chain');
      expect(f.move, 'chain');
      expect(f.params['who'], 'role2s');
    });

    test('circle left 3 places', () {
      final f = _parse('circle left 3 places');
      expect(f.move, 'circle');
      expect(f.params['turn'], 'left');
      expect(f.params['places'], 3);
    });

    test('slide left along set (the canonical-core gap)', () {
      final f = _parse('slide left along set');
      expect(f.isCustom, isFalse);
      expect(f.move, 'slide_along_set');
      expect(f.params['slide'], 'left');
    });

    test('bare balance → everyone', () {
      final f = _parse('balance');
      expect(f.move, 'balance');
      expect(f.params['who'], 'everyone');
    });

    test('subject balance → that subject', () {
      final f = _parse('neighbors balance');
      expect(f.move, 'balance');
      expect(f.params['who'], 'neighbors');
    });

    test('balance the ring is its own move', () {
      final f = _parse('balance the ring');
      expect(f.move, 'balance_the_ring');
    });

    test('do si do (shoulder not rendered)', () {
      final f = _parse('neighbors do si do');
      expect(f.move, 'do_si_do');
      expect(f.params['who'], 'neighbors');
    });

    test('do si do with rotation', () {
      final f = _parse('neighbors do si do 1½');
      expect(f.move, 'do_si_do');
      expect(f.params['turn'], 1.5);
    });

    group('allemande (generic renderer: who allemande hand rotation)', () {
      test('gentlespoons allemande left once', () {
        final f = _parse('gentlespoons allemande left once');
        expect(f.move, 'allemande');
        expect(f.params['who'], 'role1s');
        expect(f.params['hand'], 'left');
        expect(f.params['turn'], 1.0);
      });

      test('next neighbors allemande right ¾', () {
        final f = _parse('next neighbors allemande right ¾');
        expect(f.move, 'allemande');
        expect(f.params['who'], 'nextNeighbors');
        expect(f.params['hand'], 'right');
        expect(f.params['turn'], 0.75);
      });
    });
  });

  group('contraDbHtmlFigureFrontEnd — batch 2 moves', () {
    test('form long waves keeps the face-in subject', () {
      final f = _parse(
        'form long waves - ladles face in, gentlespoons face out',
      );
      expect(f.move, 'form_long_waves');
      expect(f.params['who'], 'role2s');
    });

    test('balance petronella → balance true', () {
      final f = _parse('balance petronella');
      expect(f.move, 'petronella');
      expect(f.params['balance'], isTrue);
    });

    test('bare petronella → balance false', () {
      final f = _parse('petronella');
      expect(f.move, 'petronella');
      expect(f.params['balance'], isFalse);
    });

    test('right left through', () {
      final f = _parse('right left through');
      expect(f.move, 'right_left_through');
    });

    test('star right 4 places', () {
      final f = _parse('star right 4 places');
      expect(f.move, 'star');
      expect(f.params['hand'], 'right');
      expect(f.params['places'], 4);
    });

    test('promenade across', () {
      final f = _parse('partners promenade across');
      expect(f.move, 'promenade');
      expect(f.params['who'], 'partners');
      expect(f.params['dir'], 'across');
    });

    test('box the gnat', () {
      final f = _parse('partners box the gnat');
      expect(f.move, 'box_the_gnat');
      expect(f.params['who'], 'partners');
    });

    test('California twirl', () {
      final f = _parse('partners California twirl');
      expect(f.move, 'california_twirl');
      expect(f.params['who'], 'partners');
    });

    test('butterfly whirl (no subject)', () {
      final f = _parse('butterfly whirl');
      expect(f.move, 'butterfly_whirl');
    });

    test('stand still', () {
      final f = _parse('stand still');
      expect(f.move, 'stand_still');
    });

    test('gyre → shoulder_round (ContraDB term the scrub leaves intact)', () {
      final f = _parse('neighbors gyre once');
      expect(f.isCustom, isFalse);
      expect(f.move, 'shoulder_round');
      expect(f.params['who'], 'neighbors');
      expect(f.params['turn'], 1.0);
    });

    test('gyre left shoulders', () {
      final f = _parse('neighbors gyre left shoulders 1½');
      expect(f.move, 'shoulder_round');
      expect(f.params['shoulder'], 'left');
      expect(f.params['turn'], 1.5);
    });

    test('arch & dive', () {
      final f = _parse('ones arch twos dive');
      expect(f.move, 'arch_and_dive');
      expect(f.params['who'], 'ones');
    });

    test('give & take', () {
      final f = _parse('gentlespoons give & take ladles');
      expect(f.move, 'give_and_take');
      expect(f.params['who'], 'role1s');
      expect(f.params['give'], isTrue);
      expect(f.params['whom'], 'role2s');
    });

    test('roll away', () {
      final f = _parse('gentlespoons roll away ladles');
      expect(f.move, 'roll_away');
      expect(f.params['who'], 'role1s');
      expect(f.params['whom'], 'role2s');
    });

    test('turn alone → everyone', () {
      final f = _parse('turn alone');
      expect(f.move, 'turn_alone');
      expect(f.params['who'], 'everyone');
    });

    test('pass by right shoulders', () {
      final f = _parse('neighbors pass by right shoulders');
      expect(f.move, 'pass_by');
      expect(f.params['who'], 'neighbors');
      expect(f.params['shoulder'], 'right');
    });

    test('mad robin (move name protected from robin→role2 scrub)', () {
      final f = _parse('mad robin, gentlespoons in front');
      expect(f.isCustom, isFalse);
      expect(f.move, 'mad_robin');
      expect(f.params['who'], 'role1s');
    });

    test('pass through across', () {
      final f = _parse('pass through across');
      expect(f.move, 'pass_through');
      expect(f.params['dir'], 'across');
    });

    test('pull by dancers', () {
      final f = _parse('neighbors pull by right');
      expect(f.move, 'pull_by_dancers');
      expect(f.params['who'], 'neighbors');
      expect(f.params['hand'], 'right');
    });

    test('pull by direction', () {
      final f = _parse('pull by right along');
      expect(f.move, 'pull_by_direction');
      expect(f.params['hand'], 'right');
      expect(f.params['dir'], 'along');
    });

    test('gate', () {
      final f = _parse('ones gate neighbors to face up the set');
      expect(f.move, 'gate');
      expect(f.params['who'], 'ones');
      expect(f.params['whom'], 'neighbors');
      expect(f.params['face'], 'up');
    });

    test('contra corners', () {
      final f = _parse('ones contra corners');
      expect(f.move, 'contra_corners');
      expect(f.params['who'], 'ones');
    });

    test("Rory O'More", () {
      final f = _parse("balance rory o'more right");
      expect(f.move, 'rory_o_more');
      expect(f.params['balance'], isTrue);
      expect(f.params['slide'], 'right');
    });

    test('star promenade', () {
      final f = _parse('star promenade left ½');
      expect(f.move, 'star_promenade');
      expect(f.params['hand'], 'left');
      expect(f.params['turn'], 0.5);
    });

    test('allemande orbit (not read as a plain allemande)', () {
      final f = _parse(
        'gentlespoons allemande left 1½ around while the ladles orbit clockwise ½ around',
      );
      expect(f.move, 'allemande_orbit');
      expect(f.params['who'], 'role1s');
      expect(f.params['hand'], 'left');
      expect(f.params['inner'], 1.5);
      expect(f.params['outer'], 0.5);
    });

    test('zig zag', () {
      final f = _parse('partners zig left zag right');
      expect(f.move, 'zig_zag');
      expect(f.params['turn'], 'left');
    });

    test('box circulate', () {
      final f = _parse(
        'box circulate - gentlespoons cross while ladles loop right',
      );
      expect(f.move, 'box_circulate');
      expect(f.params['who'], 'role1s');
      expect(f.params['hand'], 'right');
    });

    test('slice', () {
      final f = _parse('slice left');
      expect(f.move, 'slice');
      expect(f.params['slice'], 'left');
    });
  });

  group('contraDbHtmlFigureFrontEnd — complex detail-clause moves', () {
    test('revolving door', () {
      final f = _parse(
        'revolving door - ladles take left hands and drop off partners on other side',
      );
      expect(f.move, 'revolving_door');
      expect(f.params['who'], 'role2s');
      expect(f.params['hand'], 'left');
      expect(f.params['whom'], 'partners');
    });

    test('facing star', () {
      final f = _parse(
        'facing star clockwise 3 places with ones putting their right hands in and backing up',
      );
      expect(f.move, 'facing_star');
      expect(f.params['turn'], 'clockwise');
      expect(f.params['places'], 3);
      expect(f.params['who'], 'ones');
    });

    test('poussette', () {
      final f = _parse('half poussette - ones pull neighbors back then right');
      expect(f.move, 'poussette');
      expect(f.params['half'], 'half');
      expect(f.params['who'], 'ones');
      expect(f.params['whom'], 'neighbors');
      expect(f.params['turn'], 'clockwise');
    });

    test('cross trails', () {
      final f = _parse(
        'cross trails - partners across the set right shoulders, neighbors along the set left shoulders',
      );
      expect(f.move, 'cross_trails');
      expect(f.params['who'], 'partners');
      expect(f.params['dir'], 'across');
      expect(f.params['shoulder'], 'right');
      expect(f.params['who2'], 'neighbors');
    });

    test('down the hall', () {
      final f = _parse('down the hall forward');
      expect(f.move, 'down_the_hall');
      expect(f.params['moving'], 'all');
      expect(f.params['facing'], 'forward');
    });

    test('up the hall', () {
      final f = _parse('up the hall forward');
      expect(f.move, 'up_the_hall');
      expect(f.params['moving'], 'all');
    });

    test('figure 8', () {
      final f = _parse('ones figure 8 above');
      expect(f.move, 'figure_8');
      expect(f.params['who'], 'ones');
      expect(f.params['dir'], 'above');
    });

    test('square through', () {
      final f = _parse(
        'square through four - partners balance pull by right, then neighbors pull by left',
      );
      expect(f.move, 'square_through');
      expect(f.params['places'], 4);
      expect(f.params['who'], 'partners');
      expect(f.params['balance'], isTrue);
      expect(f.params['hand'], 'right');
      expect(f.params['who2'], 'neighbors');
    });

    test('form a long wave', () {
      final f = _parse(
        'ladles dance in to a long wave in the center - balance the wave',
      );
      expect(f.move, 'form_a_long_wave');
      expect(f.params['who'], 'role2s');
      expect(f.params['in'], isTrue);
      expect(f.params['balance'], isTrue);
    });

    test('dolphin hey (single-dancer whom)', () {
      final f = _parse(
        'dolphin hey - start with ones passing the first ladle by right shoulders',
      );
      expect(f.move, 'dolphin_hey');
      expect(f.params['who'], 'ones');
      expect(f.params['whom'], 'onesRole2');
      expect(f.params['shoulder'], 'right');
    });
  });

  group('contraDbHtmlFigureFrontEnd — ocean wave family', () {
    test(
      'form an ocean wave → form_a_short_wave (across, center/sides/hands)',
      () {
        final f = _parse(
          'form an ocean wave - ladles by right hands and neighbors by left hands',
        );
        expect(f.move, 'form_a_short_wave');
        expect(f.params['dir'], 'across');
        expect(f.params['center'], 'role2s');
        expect(f.params['centerHand'], 'right');
        expect(f.params['sides'], 'neighbors');
      },
    );

    test('form an ocean wave & balance → short wave with NO balance param', () {
      // The balance is split into a separate figure by the ADAPTER; the
      // recognizer just consumes `& balance` and never sets the balance param.
      final f = _parse(
        'form an ocean wave & balance - ladles by right hands and neighbors by left hands',
      );
      expect(f.move, 'form_a_short_wave');
      expect(f.params.containsKey('balance'), isFalse);
    });

    test('pass through to an ocean wave → pass_the_ocean', () {
      final f = _parse(
        'pass through to an ocean wave - ladles by right in the center, neighbors by left on the sides',
      );
      expect(f.move, 'pass_the_ocean');
      expect(f.params['center'], 'role2s');
      expect(f.params['centerHand'], 'right');
      expect(f.params['sides'], 'neighbors');
      expect(f.params.containsKey('balance'), isFalse);
    });

    test('pass through to an ocean wave & balance → balance kept inline', () {
      final f = _parse(
        'pass through to an ocean wave & balance - ladles by right in the center, neighbors by left on the sides',
      );
      expect(f.move, 'pass_the_ocean');
      expect(f.params['balance'], isTrue);
    });
  });

  group('contraDbHtmlFigureFrontEnd — hey', () {
    test('full hey with shoulder/place clause (dances/94 shape)', () {
      final f = _parse(
        'ladles start a full hey - rights in center, lefts on ends',
      );
      expect(f.isCustom, isFalse);
      expect(f.move, 'hey');
      expect(f.params['pass1'], 'role2s');
      expect(f.params['length'], 'full');
      expect(f.params['shoulder'], 'right');
      expect(f.note, isNull);
    });

    test('half hey, left shoulders', () {
      final f = _parse(
        'gentlespoons start a half hey - lefts in center, rights on ends',
      );
      expect(f.move, 'hey');
      expect(f.params['pass1'], 'role1s');
      expect(f.params['length'], 'half');
      expect(f.params['shoulder'], 'left');
    });
  });

  group('contraDbHtmlFigureFrontEnd — note splitting (verbatim tail)', () {
    test('allemande with a trailing note keeps the figure and the note', () {
      final f = _parse('ladles allemande right 1½ - don\'t let go');
      expect(f.move, 'allemande');
      expect(f.params['who'], 'role2s');
      expect(f.params['hand'], 'right');
      expect(f.params['turn'], 1.5);
      expect(f.note, "- don't let go");
    });

    test('allemande note without a dash separator', () {
      final f = _parse('neighbors allemande left ¾ to long wavy lines');
      expect(f.move, 'allemande');
      expect(f.params['turn'], 0.75);
      expect(f.note, 'to long wavy lines');
    });

    test('a fully-consumed template has no note', () {
      final f = _parse('neighbors swing');
      expect(f.note, isNull);
    });
  });
}
