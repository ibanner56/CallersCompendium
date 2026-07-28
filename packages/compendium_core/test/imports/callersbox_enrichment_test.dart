import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Coverage for the CallersBox/TCB figure-recognition enrichment (issue #553):
/// the additive Gap-1 recognizers (roll away, cross trails, figure eight, form
/// long wave, trade→pass_by), the resolved-to-existing mappings (lead down/up →
/// down/up the hall `moving`, circulate → box_circulate), and the Gap-2 dialect
/// fixes (weave-the-line `with <dancer>`, relationship N-suffix, `(A-B)` beat
/// ranges). Every case runs through the real `tcbFigureFrontEnd` and asserts the
/// exact structured move + params, plus the conservative custom fallbacks that
/// guard against over-claiming.
Figure? _parse(String rawText, {int beats = 0}) => parseFigureLine(
  rawText,
  beats: beats,
  frontEnd: tcbFigureFrontEnd,
);

List<Figure> _parseAll(String rawText, {int beats = 0}) => parseFigureLines(
  rawText,
  beats: beats,
  frontEnd: tcbFigureFrontEnd,
);

void main() {
  group('roll away', () {
    test('TCB "Neighbor roll away" → who=neighbors (annotation dropped)', () {
      final f = _parse('Neighbor roll away (W roll R, M side-step L)');
      expect(f!.move, 'roll_away');
      expect(f.params['who'], 'neighbors');
    });

    test('"Partner roll away (across)" → who=partners, dir dropped', () {
      final f = _parse('Partner roll away (across)');
      expect(f!.move, 'roll_away');
      expect(f.params['who'], 'partners');
    });

    test('canonical "role1s roll away neighbors with a half sashay along"', () {
      final f = _parse('role1s roll away neighbors with a half sashay along');
      expect(f!.move, 'roll_away');
      expect(f.params['who'], 'role1s');
      expect(f.params['whom'], 'neighbors');
      expect(f.params['halfSashay'], true);
    });

    test('bare "roll away" defaults who and flags assumedSubject', () {
      final f = _parse('roll away');
      expect(f!.move, 'roll_away');
      expect(f.assumedSubject, isTrue);
    });
  });

  group('trade → pass_by', () {
    test('"Men trade" → pass_by who=role1s (default right shoulder)', () {
      final f = _parse('Men trade');
      expect(f!.move, 'pass_by');
      expect(f.params['who'], 'role1s');
    });

    test('"Women trade" → pass_by who=role2s', () {
      expect(_parse('Women trade')!.params['who'], 'role2s');
    });

    test('"Neighbor trade left shoulder" → shoulder=left', () {
      final f = _parse('Neighbor trade left shoulder');
      expect(f!.move, 'pass_by');
      expect(f.params['who'], 'neighbors');
      expect(f.params['shoulder'], 'left');
    });

    test('"trade by" stays custom (no taxonomy model)', () {
      expect(_parse('Partners trade by the left')!.isCustom, isTrue);
    });

    test('"trade the wave" stays custom', () {
      expect(_parse('Trade the wave')!.isCustom, isTrue);
    });
  });

  group('cross trails', () {
    test('"Cross trail through (PR;NL)" → cross_trails (annotation dropped)', () {
      final f = _parse('Cross trail through (PR;NL)');
      expect(f!.move, 'cross_trails');
    });

    test('plural "Cross trails" recognised', () {
      expect(_parse('Cross trails')!.move, 'cross_trails');
    });
  });

  group('figure eight', () {
    test('"Ones figure eight 1/2 up" → who=ones, half, dir=above', () {
      final f = _parse('Ones figure eight 1/2 up');
      expect(f!.move, 'figure_8');
      expect(f.params['who'], 'ones');
      expect(f.params['half'], 'half');
      expect(f.params['dir'], 'above');
    });

    test('"Twos figure eight down" → dir=below, default fraction', () {
      final f = _parse('Twos figure eight down');
      expect(f!.move, 'figure_8');
      expect(f.params['who'], 'twos');
      expect(f.params['dir'], 'below');
    });

    test('"Ones figure 8 1 up" (full) → half=full', () {
      expect(_parse('Ones figure 8 1 up')!.params['half'], 'full');
    });
  });

  group('form long wave', () {
    test('"Form long waves" → form_long_waves', () {
      expect(_parse('Form long waves')!.move, 'form_long_waves');
    });

    test('"Form a long wave" → form_a_long_wave', () {
      expect(_parse('Form a long wave')!.move, 'form_a_long_wave');
    });

    test('"Form long wave in center" → form_a_long_wave (locator dropped)', () {
      expect(_parse('Form long wave in center')!.move, 'form_a_long_wave');
    });

    test('compound "Star left 1; form long wave" → star + long wave', () {
      final figs = _parseAll('Star left 1; form long wave');
      expect(figs.map((f) => f.move), ['star', 'form_a_long_wave']);
    });
  });

  group('lead down/up → hall moving param', () {
    test('"Ones lead down" → down_the_hall who=ones moving=center', () {
      final f = _parse('Ones lead down');
      expect(f!.move, 'down_the_hall');
      expect(f.params['who'], 'ones');
      expect(f.params['moving'], 'center');
    });

    test('"Ones lead up" → up_the_hall moving=center', () {
      final f = _parse('Ones lead up');
      expect(f!.move, 'up_the_hall');
      expect(f.params['moving'], 'center');
    });

    test('"Ones go down outside" → down_the_hall moving=outsides', () {
      final f = _parse('Ones go down outside');
      expect(f!.move, 'down_the_hall');
      expect(f.params['moving'], 'outsides');
    });

    test('plain "Go down the hall" keeps default moving (unset)', () {
      final f = _parse('Go down the hall');
      expect(f!.move, 'down_the_hall');
      expect(f.params.containsKey('moving'), isFalse);
    });
  });

  group('circulate → box_circulate', () {
    test('"Circulate: women cross, men loop right" → box_circulate + note', () {
      final f = _parse('Circulate: women cross, men loop right');
      expect(f!.move, 'box_circulate');
      expect(f.note, isNotNull);
      expect(f.note, contains('cross'));
    });

    test('balance ring + circulate folds balance into box_circulate', () {
      // The adapter cross-line merge folds a preceding balance line; here we
      // assert the circulate clause itself structures so the fold has a target.
      expect(_parse('Circulate: role2s cross, role1s loop right')!.move,
          'box_circulate');
    });

    test('"box circulate" is NOT claimed by the circulate pre-recognizer', () {
      // Bare "box circulate" (no colon) routes through the normal recognizer.
      expect(_parse('Box circulate')!.move, 'box_circulate');
    });

    test('"Diagonal circulate: ..." declines (head not exactly circulate)', () {
      expect(_parse('Diagonal circulate: men cross')!.isCustom, isTrue);
    });
  });

  group('weave the line "with <dancer>"', () {
    test('"Weave the line with partner (L;R to N2)" → zig_zag who=partners', () {
      final f = _parse('Weave the line with partner (L;R to N2)');
      expect(f!.move, 'zig_zag');
      expect(f.params['who'], 'partners');
    });

    test('bare "Weave the line" → zig_zag (default who)', () {
      expect(_parse('Weave the line')!.move, 'zig_zag');
    });
  });

  group('relationship N-suffix', () {
    test('"Right and left through with neighbor N2" structures', () {
      final f = _parse('Right and left through with neighbor N2');
      expect(f!.move, 'right_left_through');
    });

    test('"Ladies chain to neighbor N2" → chain with N-tagged note', () {
      final f = _parse('Ladies chain to neighbor N2');
      expect(f!.move, 'chain');
      expect(f.params['who'], 'role2s');
      expect(f.note, contains('n2'));
    });
  });

  group('diagonal figures → dir', () {
    test('"On left diagonal, right and left through with partner"', () {
      final f = _parse('On left diagonal, right and left through with partner');
      expect(f!.move, 'right_left_through');
      expect(f.params['dir'], 'leftDiagonal');
    });

    test('"On right diagonal, ladies chain to neighbor N2"', () {
      final f = _parse('On right diagonal, ladies chain to neighbor N2');
      expect(f!.move, 'chain');
      expect(f.params['who'], 'role2s');
      expect(f.params['dir'], 'rightDiagonal');
      expect(f.note, contains('n2'));
    });

    test('diagonal hey: "On left diagonal, hey 1/2 (WR;PL)"', () {
      final f = _parse('On left diagonal, hey 1/2 (WR;PL)');
      expect(f!.move, 'hey');
      expect(f.params['dir'], 'leftDiagonal');
      expect(f.params['pass1'], 'role2s');
    });

    test('non-diagonal chain keeps default dir (no diagonal)', () {
      final f = _parse('Ladies chain to partner');
      expect(f!.move, 'chain');
      expect(f.params.containsKey('dir'), isFalse);
    });
  });

  group('same-role right and left through', () {
    test('preserves the same-role variant as a note', () {
      final f = _parse('Same-role right and left through with neighbor');
      expect(f!.move, 'right_left_through');
      expect(f.note, 'same-role');
    });
  });

  group('pass / cross by → pass_by', () {
    test('"Men pass left" → pass_by who=role1s shoulder=left', () {
      final f = _parse('Men pass left');
      expect(f!.move, 'pass_by');
      expect(f.params['who'], 'role1s');
      expect(f.params['shoulder'], 'left');
    });

    test('"Women cross by right" → pass_by who=role2s shoulder=right', () {
      final f = _parse('Women cross by right');
      expect(f!.move, 'pass_by');
      expect(f.params['who'], 'role2s');
      expect(f.params['shoulder'], 'right');
    });

    test('"Partner pass right" → pass_by who=partners', () {
      expect(_parse('Partner pass right')!.params['who'], 'partners');
    });

    test('"pass through across" is NOT claimed as pass_by (no side)', () {
      expect(_parse('Pass through across')!.move, 'pass_through');
    });

    test('"pass the ocean" is NOT claimed as pass_by', () {
      expect(_parse('Pass the ocean')!.move, 'pass_the_ocean');
    });
  });

  group('explicit dancer codes', () {
    test('M1/W2 map to the ones/twos single-dancer identities', () {
      // figure_8 accepts a single-dancer `who`, so "M1 figure eight" exercises
      // the M1 → onesRole1 mapping end to end.
      final f = _parse('M1 figure eight up');
      expect(f!.move, 'figure_8');
      expect(f.params['who'], 'onesRole1');
    });
  });

  group('(A-B) beat range', () {
    test('range prefix parses to inclusive duration and structures', () {
      // "(9-16) Threes swing" → 8 beats; "threes" is not a taxonomy dancer set
      // so this particular line stays custom, but a range-prefixed swing that
      // names a known set structures with the right beats.
      final figs = CallersBoxAdapter().parse(
        RawRecord(
          source: ProvenanceSource.callersbox,
          externalId: 't',
          permission: 'full',
          payload:
              '{"ID":"t","Name":"t","Permission":"full","phrases":'
              '[{"name":"A1","figures":["(1-8) Neighbor swing","(9-16) Partner swing"]}]}',
        ),
      );
      final swings =
          figs.dance.figures.where((f) => f.move == 'swing').toList();
      expect(swings, hasLength(2));
      expect(swings[0].params['beats'], 8);
      expect(swings[1].params['beats'], 8);
    });
  });

  group('hall + turn as couples fold', () {
    Dance importA2(List<String> figures) => CallersBoxAdapter()
        .parse(
          RawRecord(
            source: ProvenanceSource.callersbox,
            externalId: 't',
            permission: 'full',
            payload:
                '{"ID":"t","Name":"t","Permission":"full","phrases":'
                '[{"name":"A2","figures":${_json(figures)}}]}',
          ),
        )
        .dance;

    test('down hall / turn as couples / up hall / bend folds enders', () {
      final d = importA2([
        '(6) In a line of four, go down the hall',
        '(2) Neighbor turn as couples',
        '(6) Go up the hall',
        '(2) Bend the line',
      ]);
      expect(d.figures.map((f) => f.move), ['down_the_hall', 'up_the_hall']);
      expect(d.figures[0].params['ender'], 'turnCouple');
      expect(d.figures[0].params['beats'], 8); // 6 + 2 summed
      expect(d.figures[1].params['ender'], 'bendTheLine');
    });

    test('standalone turn as couples (no hall) stays custom', () {
      final d = importA2(['(8) Neighbor turn as couples']);
      expect(d.figures.single.isCustom, isTrue);
    });
  });
}

String _json(List<String> lines) =>
    '[${lines.map((l) => '"${l.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"').join(',')}]';
