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

    group('chain hand (#976)', () {
      test('ladles left-hand chain → chain{who:role2s, hand:left}', () {
        // Guards the <side>-hand consumption: reverting it leaves "left-hand"
        // as an unconsumed token and s.eat('chain') fails, so the whole line
        // falls through to custom.
        final f = _parse('ladles left-hand chain');
        expect(f.isCustom, isFalse);
        expect(f.move, 'chain');
        expect(f.params['who'], 'role2s');
        expect(f.params['hand'], 'left');
      });

      test('gentlespoons right-hand chain → chain{who:role1s, hand:right}', () {
        final f = _parse('gentlespoons right-hand chain');
        expect(f.isCustom, isFalse);
        expect(f.move, 'chain');
        expect(f.params['who'], 'role1s');
        expect(f.params['hand'], 'right');
      });

      test('a bare ladles chain populates the role-implied side: right', () {
        // Guards the role-implied population: dropping it would leave
        // `hand` unset (reading as ParamVocab.unspecified at render time)
        // instead of the side the role word already states.
        final f = _parse('ladles chain');
        expect(f.params['hand'], 'right');
      });

      test(
        'a bare gentlespoons chain populates the role-implied side: left',
        () {
          final f = _parse('gentlespoons chain');
          expect(f.params['hand'], 'left');
        },
      );

      test('*-hand chain stays custom (ContraDB wildcard, no precedent '
          'recognizer accepts it)', () {
        // Guards against accepting "*" as a side: no ContraDB recognizer in
        // this dialect handles the wildcard hand today (_leftRight already
        // declines bare "*"), so chain must not be the first exception.
        final f = _parse('ladles *-hand chain');
        expect(f.isCustom, isTrue);
      });
    });

    test('circle left 3 places', () {
      final f = _parse('circle left 3 places');
      expect(f.move, 'circle');
      expect(f.params['turn'], 'left');
      expect(f.params['places'], 3);
      expect(f.params.containsKey('singleFile'), isFalse);
    });

    // Issue #634 — real render: Travels with Rick and Kim #455, A2 (8 beats).
    // ContraDB's own free text (auto-linked keywords on the live page: the
    // dance's "hook" field literally reads "promenade single file around the
    // circle") — a single-file circulation, not the `promenade` move. No
    // direction is stated, so `turn` takes the taxonomy default (`left`).
    test(
      'promenade single file around the circle N places → circle singleFile',
      () {
        final f = _parse('promenade single file around the circle 3 places');
        expect(f.isCustom, isFalse);
        expect(f.move, 'circle');
        expect(f.params['turn'], 'left');
        expect(f.params['places'], 3);
        expect(f.params['singleFile'], isTrue);
        expect(f.note, isNull);
      },
    );

    test('promenade single file around the ring (synonym, no places)', () {
      final f = _parse('promenade single file around the ring');
      expect(f.move, 'circle');
      expect(f.params['turn'], 'left');
      expect(f.params['singleFile'], isTrue);
      expect(f.params.containsKey('places'), isFalse);
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
      expect(f.params.containsKey('singleFile'), isFalse);
    });

    // Issue #634 / #749 — real render: Strange New Worlds #3107, A2 (8 beats).
    // No dancer subject precedes "single file" — a true single-file promenade
    // travels the whole major set. Since taxonomy v27 (#749 Part A), a bare
    // `along` direction token immediately after `promenade` is consumed into
    // `dir:'along'`; the descriptive tail ("major set to new neightbors") is
    // left as the note.
    test('single file promenade along → promenade singleFile, dir:along', () {
      final f = _parse(
        'single file promenade along major set to new neightbors',
      );
      expect(f.isCustom, isFalse);
      expect(f.move, 'promenade');
      expect(f.params['who'], 'everyone');
      expect(f.params['singleFile'], isTrue);
      // `along` is now captured as `dir` (v27 Part A change).
      expect(f.params['dir'], 'along');
      expect(f.note, 'major set to new neightbors');
    });

    test('single file promenade (no dir token) — no dir param stored', () {
      final f = _parse('single file promenade');
      expect(f.isCustom, isFalse);
      expect(f.move, 'promenade');
      expect(f.params['singleFile'], isTrue);
      expect(f.params.containsKey('dir'), isFalse);
      expect(f.note, isNull);
    });

    test('single file promenade across — dir:across captured', () {
      final f = _parse('single file promenade across');
      expect(f.params['singleFile'], isTrue);
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

    // Issue #634 — real renders: The Erik Effect #570 (2 beats) and Green
    // Lake Twirl #548 (4 beats), both "<who> take neighbors" with no "give &"
    // prefix at all. The take-only form requires `whom` to resolve to a known
    // subject (unlike the looser `give=true` branch above).
    test('take-only (ladles take neighbors) → give_and_take give=false', () {
      final f = _parse('ladles take neighbors');
      expect(f.isCustom, isFalse);
      expect(f.move, 'give_and_take');
      expect(f.params['who'], 'role2s');
      expect(f.params['give'], isFalse);
      expect(f.params['whom'], 'neighbors');
      expect(f.note, isNull);
    });

    test('take-only (gentlespoons take neighbors)', () {
      final f = _parse('gentlespoons take neighbors');
      expect(f.move, 'give_and_take');
      expect(f.params['who'], 'role1s');
      expect(f.params['give'], isFalse);
      expect(f.params['whom'], 'neighbors');
    });

    test('bare "<who> take" with no resolvable whom → falls to custom', () {
      final f = _parse('ladles take hands');
      expect(f.isCustom, isTrue);
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

    // Taxonomy v26 (#843): ContraDB star promenades DELIBERATELY fall to the
    // custom fallback. ContraDB's `who`+`hand` name, as a pair, the dancers
    // with a hand in the CENTER, while our `who` now names the dancer you PICK
    // UP on the side (owner ruling, 2026-08-06). The pick-up relationship is
    // not recoverable from the center role, so structuring the line would
    // assert the wrong dancers. Owner-accepted structure regression.
    //
    // Falsification target: re-register `_starPromenade` in
    // `contraDbHtmlFigureFrontEnd` and this test goes red.
    test('star promenade falls to custom (v26 — the hand names the center)', () {
      final f = _parse('star promenade left ½');
      expect(f.isCustom, isTrue);
      // Nothing is LOST by declining: the custom fallback keeps ContraDB's own
      // wording verbatim, hand included.
      expect(f.params['text'], contains('star promenade left'));
    });

    test('allemande orbit combined line -> meanwhile[allemande, orbit] '
        '(issue #295: fused allemande_orbit retired)', () {
      final f = parseContraDbFigureLine(
        'gentlespoons allemande left 1½ around while the ladles orbit clockwise ½ around',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isTrue);
      final sides = f.subFigures;
      expect(sides.map((s) => s.move), ['allemande', 'orbit']);
      expect(sides[0].params['who'], 'role1s');
      expect(sides[0].params['hand'], 'left');
      expect(sides[0].params['turn'], 1.5);
      expect(sides[1].params['who'], 'role2s');
      expect(sides[1].params['turn'], 'clockwise');
      expect(sides[1].params['amount'], 0.5);
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

    // issue #752 — bare ContraDB form: <subject> cross while <subject> loop
    test('bare box circulate — larks cross while robins loop (#752)', () {
      final f = _parse('larks cross while robins loop');
      expect(f.move, 'box_circulate');
      expect(f.params['who'], 'role1s');
      expect(f.params.containsKey('hand'), isFalse);
    });

    test(
      'bare box circulate — gentlespoons cross while ladles loop (#752)',
      () {
        final f = _parse('gentlespoons cross while ladles loop');
        expect(f.move, 'box_circulate');
        expect(f.params['who'], 'role1s');
        expect(f.params.containsKey('hand'), isFalse);
      },
    );

    test('bare box circulate — ladles cross while gentlespoons loop right '
        '(#752)', () {
      final f = _parse('ladles cross while gentlespoons loop right');
      expect(f.move, 'box_circulate');
      expect(f.params['who'], 'role2s');
      expect(f.params['hand'], 'right');
    });

    // Equivalence: headed and bare forms must produce identical params. Both
    // forms now support `balance &` via `_eatBalanceAmp`, but the two test
    // inputs here do NOT include that prefix — so the two
    // `containsKey('balance')` assertions below are asserting about the test
    // inputs, not a property of the code. They confirm this test is measuring
    // what it claims (neither form has an unexpected balance on these inputs);
    // the balance path itself is tested by the existing headed-form balance
    // test. The shared-grammar invariant is pinned by the move/who/hand
    // assertions: if _crossWhileLoopParams is ever split back into two sites
    // and one drifts, those will catch it.
    test(
      'headed and bare forms yield identical who/hand (#752 equivalence)',
      () {
        final headed = _parse(
          'box circulate - larks cross while robins loop right',
        );
        final bare = _parse('larks cross while robins loop right');
        expect(bare.move, headed.move);
        expect(bare.params['who'], headed.params['who']);
        expect(bare.params['hand'], headed.params['hand']);
        expect(bare.params.containsKey('balance'), isFalse);
        expect(headed.params.containsKey('balance'), isFalse);
      },
    );

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
      'form an ocean wave → form_short_waves (across, center/sides/hands)',
      () {
        final f = _parse(
          'form an ocean wave - ladles by right hands and neighbors by left hands',
        );
        expect(f.move, 'form_short_waves');
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
      expect(f.move, 'form_short_waves');
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

  // Regression coverage for #578. ContraDB's `bal` param renders `balance & `
  // before the move (libfigure `stringParamBalance`), so every balance-prefixed
  // figure arrives with an `&` the recognizer must consume; leaving it behind
  // used to demote an otherwise-matchable figure to custom. Strings here are the
  // ACTUAL renders (the two Rory O'More rows are captured verbatim from the repro
  // dance https://contradb.com/dances/2254).
  group('contraDbHtmlFigureFrontEnd — #578 balance & compounds', () {
    test("balance & Rory O'More right (in long waves) → recognized + note", () {
      final f = _parse("balance &  Rory O'More right (in long waves)");
      expect(f.isCustom, isFalse);
      expect(f.move, 'rory_o_more');
      expect(f.params['balance'], isTrue);
      expect(f.params['slide'], 'right');
      expect(f.note, '(in long waves)');
    });

    test("balance & Rory O'More left (in long waves) → recognized + note", () {
      final f = _parse("balance &  Rory O'More left (in long waves)");
      expect(f.move, 'rory_o_more');
      expect(f.params['balance'], isTrue);
      expect(f.params['slide'], 'left');
      expect(f.note, '(in long waves)');
    });

    test('balance & petronella → petronella with balance', () {
      final f = _parse('balance & petronella');
      expect(f.move, 'petronella');
      expect(f.params['balance'], isTrue);
    });

    test('<who> balance & pull by → pull_by_dancers with balance', () {
      final f = _parse('gentlespoons balance & pull by right');
      expect(f.move, 'pull_by_dancers');
      expect(f.params['who'], 'role1s');
      expect(f.params['balance'], isTrue);
      expect(f.params['hand'], 'right');
    });

    test('balance & pull by <hand> <dir> → pull_by_direction with balance', () {
      final f = _parse('balance & pull by right across');
      expect(f.move, 'pull_by_direction');
      expect(f.params['balance'], isTrue);
      expect(f.params['hand'], 'right');
      expect(f.params['dir'], 'across');
    });

    test('balance & box circulate → box_circulate with balance', () {
      final f = _parse(
        'balance & box circulate - gentlespoons cross while ladles loop right',
      );
      expect(f.move, 'box_circulate');
      expect(f.params['balance'], isTrue);
      expect(f.params['who'], 'role1s');
      expect(f.params['hand'], 'right');
    });

    test('square through with rendered "balance & " on the odd clause', () {
      final f = _parse(
        'square through four - partners balance & pull by right, then neighbors pull by left',
      );
      expect(f.move, 'square_through');
      expect(f.params['balance'], isTrue);
      expect(f.params['who'], 'partners');
      expect(f.params['hand'], 'right');
      expect(f.params['who2'], 'neighbors');
    });

    test('plain balance is unaffected (no trailing &)', () {
      final f = _parse('partners balance');
      expect(f.move, 'balance');
      expect(f.params['who'], 'partners');
      expect(f.note, isNull);
    });
  });

  // #578 parenthetical-note handling. A trailing parenthetical rides through as a
  // verbatim note on the recognized figure; a paren interrupting the template
  // stays custom; malformed/unbalanced parens are handled safely (no crash,
  // bounded parsing — the tokenizer never backtracks).
  group('contraDbHtmlFigureFrontEnd — #578 parenthetical notes', () {
    test('paren note on a matched figure → recognized + note attached', () {
      final f = _parse('neighbors swing (on the left diagonal)');
      expect(f.isCustom, isFalse);
      expect(f.move, 'swing');
      expect(f.params['who'], 'neighbors');
      expect(f.note, '(on the left diagonal)');
    });

    test('mid-phrase paren (not a clean trailing note) stays custom', () {
      final f = _parse('circle (left 3 places) around');
      expect(f.isCustom, isTrue);
    });

    test('unbalanced trailing paren is handled safely (no crash)', () {
      final f = _parse('neighbors swing (unbalanced');
      expect(f.move, 'swing');
      expect(f.params['who'], 'neighbors');
      expect(f.note, '(unbalanced');
    });

    test('nested / unbalanced parens do not crash the recognizer', () {
      final f = _parse('neighbors swing (a (nested note');
      expect(f.move, 'swing');
      expect(f.note, '(a (nested note');
    });
  });

  // #585 recognizer-coverage fix. Strings here are the ACTUAL ContraDB renders
  // captured live from the cited source dances (default dialect → role scrub,
  // `&`, unicode fractions), so the recognizers match the real libfigure output
  // rather than the issue's paraphrases.
  group('contraDbHtmlFigureFrontEnd — #585 recognizer coverage', () {
    test('star with wrist grip → grip param + places (dances/528)', () {
      final f = _parse('star left - wrist grip - 4 places');
      expect(f.isCustom, isFalse);
      expect(f.move, 'star');
      expect(f.params['hand'], 'left');
      expect(f.params['grip'], 'wristGrip');
      expect(f.params['places'], 4);
      expect(f.note, isNull);
    });

    test('star with hands-across grip → grip param + places (dances/2632)', () {
      final f = _parse('star right - hands across - 3 places');
      expect(f.move, 'star');
      expect(f.params['hand'], 'right');
      expect(f.params['grip'], 'handsAcross');
      expect(f.params['places'], 3);
    });

    test(
      'star grip with a trailing qualifier keeps it as a note (dances/1822)',
      () {
        final f = _parse(
          'star right - hands across - 4 places and walk along the set to find the next couple (ladles behind partner)',
        );
        expect(f.move, 'star');
        expect(f.params['grip'], 'handsAcross');
        expect(f.params['places'], 4);
        expect(
          f.note,
          'and walk along the set to find the next couple (role2s behind partner)',
        );
      },
    );

    test('plain star (no grip) still recognises (dances/777)', () {
      final f = _parse('star left 4 places');
      expect(f.move, 'star');
      expect(f.params['hand'], 'left');
      expect(f.params.containsKey('grip'), isFalse);
      expect(f.params['places'], 4);
    });

    test('box the gnat with balance prefix → hand + balance (dances/2950)', () {
      final f = _parse('partners right hand balance &  box the gnat');
      expect(f.isCustom, isFalse);
      expect(f.move, 'box_the_gnat');
      expect(f.params['who'], 'partners');
      expect(f.params['hand'], 'right');
      expect(f.params['balance'], isTrue);
      expect(f.note, isNull);
    });

    test('box the gnat balance prefix, neighbors subject (dances/777)', () {
      final f = _parse('neighbors right hand balance &  box the gnat');
      expect(f.move, 'box_the_gnat');
      expect(f.params['who'], 'neighbors');
      expect(f.params['hand'], 'right');
      expect(f.params['balance'], isTrue);
    });

    test('plain box the gnat is unaffected (no balance prefix)', () {
      final f = _parse('partners box the gnat');
      expect(f.move, 'box_the_gnat');
      expect(f.params['who'], 'partners');
      expect(f.params.containsKey('balance'), isFalse);
      expect(f.params.containsKey('hand'), isFalse);
    });

    test('bare pass through recognises (dances/777, 2632)', () {
      final f = _parse('pass through');
      expect(f.isCustom, isFalse);
      expect(f.move, 'pass_through');
      expect(f.note, isNull);
    });

    test('pass through by the left → note (dances/480)', () {
      final f = _parse('pass through by the left');
      expect(f.move, 'pass_through');
      expect(f.note, 'by the left');
    });

    test('pass through to next neighbors → note (dances/950)', () {
      final f = _parse('pass through to next neighbors');
      expect(f.move, 'pass_through');
      expect(f.note, 'to next neighbors');
    });

    test(
      'pass through to form an ocean wave with shadows → note (dances/2012)',
      () {
        final f = _parse('pass through to form an ocean wave with shadows');
        expect(f.move, 'pass_through');
        expect(f.note, 'to form an ocean wave with shadows');
      },
    );

    test('pass through past partners → note (The Young Adult Rose)', () {
      final f = _parse('pass through past partners');
      expect(f.move, 'pass_through');
      expect(f.note, 'past partners');
    });

    test('pass through across still consumes the direction (regression)', () {
      final f = _parse('pass through across');
      expect(f.move, 'pass_through');
      expect(f.params['dir'], 'across');
      expect(f.note, isNull);
    });

    test('left diagonal chain to shadow → dir + note (dances/2238)', () {
      final f = _parse('left diagonal ladles chain to shadow');
      expect(f.isCustom, isFalse);
      expect(f.move, 'chain');
      expect(f.params['who'], 'role2s');
      expect(f.params['dir'], 'leftDiagonal');
      expect(f.note, 'to shadow');
    });

    test('plain chain is unaffected (no diagonal)', () {
      final f = _parse('ladles chain');
      expect(f.move, 'chain');
      expect(f.params['who'], 'role2s');
      expect(f.params.containsKey('dir'), isFalse);
      expect(f.note, isNull);
    });

    test('prev neighbors subject recognises (dances/777)', () {
      final f = _parse('prev neighbors allemande left once');
      expect(f.isCustom, isFalse);
      expect(f.move, 'allemande');
      expect(f.params['who'], 'prevNeighbors');
      expect(f.params['hand'], 'left');
      expect(f.params['turn'], 1.0);
    });
  });

  group('parseContraDbFigureLine — `while`/`whiles` fan-out into `meanwhile` '
      '(#591/#572)', () {
    test('allemande orbit (dances/1717) resolves to meanwhile[allemande, '
        'orbit] via its dedicated combined handler (issue #295)', () {
      // Exact rendered text from ContraDB dance #1717 "Another Orbit for
      // Liz" (A1, 8 beats). This is the literal allemandeOrbitWords
      // template. The fused `allemande_orbit` move was RETIRED (#295); the
      // combined line is now resolved by `_allemandeOrbitMeanwhile` into a
      // `meanwhile[allemande, orbit]` container — preferred over the generic
      // parse, so it keeps the same first-crack precedence the fused
      // recognizer had, but emits a container instead of one fused figure.
      // The source states both the direction and the orbiting pair, so both
      // sides are built with full fidelity (no derivation).
      final f = parseContraDbFigureLine(
        'ladles allemande left 1½ around while the gentlespoons orbit '
        'clockwise ½ around',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isTrue);
      expect(f.beats, 8);
      final sides = f.subFigures;
      expect(sides.map((s) => s.move), ['allemande', 'orbit']);
      expect(sides[0].params['who'], 'role2s');
      expect(sides[0].params['hand'], 'left');
      expect(sides[0].params['turn'], 1.5);
      expect(sides[1].params['who'], 'role1s');
      expect(sides[1].params['turn'], 'clockwise');
      expect(sides[1].params['amount'], 0.5);
    });

    test('box circulate dual-clause (issue #585, Folklife Frolic A2/B1) '
        'resolves via its dedicated recognizer, NOT a meanwhile fan-out '
        '(precedence regression)', () {
      final f = parseContraDbFigureLine(
        'balance & box circulate - larks cross while robins loop right',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isFalse);
      expect(f.move, 'box_circulate');
      expect(f.params['balance'], isTrue);
      expect(f.params['who'], 'role1s');
      expect(f.params['hand'], 'right');
    });

    // issue #752 — bare form resolves to box_circulate, NOT a meanwhile container
    test('issue #752 — bare "larks cross while robins loop" resolves to '
        'box_circulate, not meanwhile', () {
      final f = parseContraDbFigureLine(
        'larks cross while robins loop',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isFalse);
      expect(f.move, 'box_circulate');
      expect(f.params['who'], 'role1s');
      expect(f.params.containsKey('hand'), isFalse);
      expect(f.beats, 8);
    });

    test('issue #752 — bare "gentlespoons cross while ladles loop" resolves '
        'to box_circulate', () {
      final f = parseContraDbFigureLine(
        'gentlespoons cross while ladles loop',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isFalse);
      expect(f.move, 'box_circulate');
      expect(f.params['who'], 'role1s');
      expect(f.params.containsKey('hand'), isFalse);
    });

    test('issue #752 — bare "ladles cross while gentlespoons loop right" '
        'resolves to box_circulate with hand', () {
      final f = parseContraDbFigureLine(
        'ladles cross while gentlespoons loop right',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isFalse);
      expect(f.move, 'box_circulate');
      expect(f.params['who'], 'role2s');
      expect(f.params['hand'], 'right');
    });

    // Guard test: without a `loop` token the recognizer must decline, so the
    // line falls through to the fan-out. This falsifies the loop guard: if
    // `s.eat('loop')` were removed from _boxCirculateBare, this line would
    // match as box_circulate(who: role1s, note: "- all balance") instead of
    // fanning into meanwhile.
    test('issue #752 guard — "larks cross while robins - all balance" (no '
        '"loop") does NOT resolve to box_circulate (loop guard)', () {
      final f = parseContraDbFigureLine(
        'larks cross while robins - all balance',
        beats: 8,
      );
      expect(f, isNotNull);
      // Must NOT be a structured box_circulate — the `loop` word is absent.
      // The line fans into a meanwhile container (two custom sides) instead.
      expect(f!.isMeanwhile, isTrue);
    });

    // Second-subject null-check: when the token between `cross while` and
    // `loop` is not a dancer set, _crossWhileLoopParams returns null and the
    // line falls through. This tests the guard in isolation; it is untested
    // by the #326 control (which fails before reaching this check because
    // `eatPhrase('cross while')` rejects it).
    test('issue #752 guard — unknown second subject declines (second-subject '
        'null-check)', () {
      // `something` is not in _subjectPhrases → _crossWhileLoopParams
      // returns null → _boxCirculateBare returns null → fan-out fires.
      final f = parseContraDbFigureLine(
        'role1s cross while something loop',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isTrue);
    });

    test('dances/1603 "Eye Of The Tiger" A1 — "whiles" spelling fans into '
        'a meanwhile container (neither side is a ContraDB template)', () {
      // Exact rendered text from ContraDB dance #1603 (A1 cont'd, 8 beats).
      // Confirms the word-boundary splitter recognises "whiles" (a
      // substring of which is "while") as its own connective, not a
      // literal-substring cut mid-word. The first side happens to
      // structure via the generic `_balance` recognizer; the second stays
      // custom (prefer-custom) — the container is still built either way.
      final f = parseContraDbFigureLine(
        'balance Wave-gentlespoons move straight to next wave -- whiles '
        'ladles slide left in center other to meet new neighbor',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isTrue);
      expect(f.params['beats'], 8);
      final sides = f.subFigures;
      expect(sides, hasLength(2));
      expect(sides[0].move, 'balance');
      expect(sides[0].isCustom, isFalse);
      expect(sides[1].isCustom, isTrue);
      expect(
        sides[1].params['text'],
        'role2s slide left in center other to meet new neighbor',
      );
      // Shared beats ride on the container only.
      expect(sides.every((s) => !s.params.containsKey('beats')), isTrue);
    });

    test('dances/326 "Snake in the Garden" A2 — "while" fans into a '
        'meanwhile container (one side structures, one stays custom)', () {
      // Exact rendered text from ContraDB dance #326 (A2, 8 beats).
      final f = parseContraDbFigureLine(
        'gentlespoons dance out while ladles dance in to a long wave in '
        'the center - balance the wave',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isTrue);
      expect(f.params['beats'], 8);
      final sides = f.subFigures;
      expect(sides, hasLength(2));
      expect(sides[0].isCustom, isTrue);
      expect(sides[0].params['text'], 'role1s dance out');
      expect(sides[1].isCustom, isFalse);
      expect(sides[1].move, 'form_a_long_wave');
    });

    test('issue #585 (Rock Creek Reel A1) — "while" fans into a meanwhile '
        'container', () {
      final f = parseContraDbFigureLine(
        'larks dance out while robins dance in to a long wave in the '
        'center - balance the wave',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isTrue);
      expect(f.params['beats'], 8);
      expect(f.subFigures[0].isCustom, isTrue);
      expect(f.subFigures[0].params['text'], 'role1s dance out');
      expect(f.subFigures[1].move, 'form_a_long_wave');
    });

    test('a note that swallowed the connective is treated like custom: the '
        'fan-out still runs (mirrors `_noteSwallowedCompound`)', () {
      // "balance" alone (no stated subject, no "the") greedily captures
      // everything after it as a verbatim note — including a top-level
      // "whiles" the recognizer has no business absorbing. Reusing
      // dances/1603's exact text: without the note-swallow guard this
      // would incorrectly return a structured `balance` figure whose note
      // silently contains the whole second clause.
      final f = parseContraDbFigureLine(
        'balance Wave-gentlespoons move straight to next wave -- whiles '
        'ladles slide left in center other to meet new neighbor',
      );
      expect(f!.isMeanwhile, isTrue);
    });

    test('no top-level `while`/`whiles` → unchanged (today\'s behaviour)', () {
      final f = parseContraDbFigureLine('neighbors swing');
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isFalse);
      expect(f.move, 'swing');
    });

    test('"whilex" is not a whole-word match (word-boundary correctness)', () {
      final f = parseContraDbFigureLine(
        'this word has whilex in it not a connective',
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isFalse);
      expect(f.isCustom, isTrue);
    });

    test('a degenerate leading connective (`while B`, empty first side) '
        'declines to fan out and stays custom', () {
      final f = parseContraDbFigureLine('while robins loop');
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isFalse);
      expect(f.isCustom, isTrue);
    });

    test('a degenerate trailing connective (`A while`, empty second side) '
        'declines to fan out and stays custom', () {
      final f = parseContraDbFigureLine('larks cross while');
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isFalse);
      expect(f.isCustom, isTrue);
    });

    test('a security bound: only the FIRST top-level connective splits, so a '
        'line with many `while`s never produces more than 2 sides', () {
      final f = parseContraDbFigureLine(
        'a while b while c while d while e while f while g',
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isTrue);
      expect(f.subFigures, hasLength(2));
      expect(f.subFigures[0].params['text'], 'a');
      expect(
        f.subFigures[1].params['text'],
        'b while c while d while e while f while g',
      );
    });

    test('empty after scrubbing yields null (front-end-independent)', () {
      expect(parseContraDbFigureLine('   '), isNull);
    });
  });
}
