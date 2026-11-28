import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../figures_support.dart';

/// Three Caller's Box line shapes that used to stay free text (2026-11-24,
/// user-ruled): a neighbour number before a same-role pair, hey pass lists
/// naming same-role neighbours (plus `with hands` and a trailing `[with …]`),
/// and a pass the ocean whose wave sits in a nested bracket.
Figure _parse(String line) =>
    parseFigureLine(line, frontEnd: tcbFigureFrontEnd)!;

/// [line] imported through the whole adapter, so the role words are the
/// site's own (`men`, `women`) and the scrub turns them into role tokens.
Future<Figure> _import(String line) async {
  final payload = jsonEncode({
    'ID': '1',
    'Name': 'Numbered pair',
    'Permission': 'full',
    'phrases': [
      {
        'name': 'A1',
        'figures': [line],
      },
    ],
  });
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return figuresOf(adapter.parse(raw).dance).single;
}

void main() {
  group('N2 Men allemande: a neighbour number before a same-role pair', () {
    test('N2 reads as the next neighbours\' role, with no note', () {
      final f = _parse('N2 role1s allemande left 3/4');
      expect(f.move, 'allemande');
      // Taxonomy v40: the next larks (user-ruled 2026-11-26).
      expect(f.params['who'], 'nextRole1s');
      expect(f.params['hand'], 'left');
      expect(f.params['travel'], 0.75);
      expect(f.note, isNull);
    });

    test('N0 is the previous neighbours\' role, for either role', () {
      final larks = _parse('N0 role1s allemande left 1');
      expect(larks.move, 'allemande');
      expect(larks.params['who'], 'prevRole1s');
      expect(larks.note, isNull);
      final robins = _parse('N2 role2s allemande right 1/2');
      expect(robins.params['who'], 'nextRole2s');
      expect(robins.note, isNull);
    });

    test('the site\'s own role words read as the four role tokens', () async {
      // User-ruled 2026-11-26: N2 men, N2 women, N0 men and N0 women each read
      // as their gender-free counterpart when the pair does the figure
      // together, as an allemande is (user-ruled 2026-11-28).
      const expected = {
        '(8) N2 men allemande left 1': 'nextRole1s',
        '(8) N2 women allemande right 1': 'nextRole2s',
        '(8) N0 men allemande left 1': 'prevRole1s',
        '(8) N0 women allemande right 1': 'prevRole2s',
      };
      for (final MapEntry(key: line, value: token) in expected.entries) {
        final f = await _import(line);
        expect(f.move, 'allemande', reason: line);
        expect(f.params['who'], token, reason: line);
        expect(f.note, isNull, reason: line);
      }
    });

    test('a figure done with a neighbour numbers the neighbour instead', () {
      // The neighbour set is preferred where it can be used: the larks roll
      // away their next neighbours, so `who` stays the role.
      final next = _parse('N2 role1s roll away neighbor');
      expect(next.move, 'roll_away');
      expect(next.params['who'], 'role1s');
      expect(next.params['whom'], 'nextNeighbors');
      expect(next.note, isNull);
      final prev = _parse('N0 role2s roll away neighbor');
      expect(prev.params['who'], 'role2s');
      expect(prev.params['whom'], 'prevNeighbors');
      // A number with no role token reads this way too.
      expect(
        _parse('N3 role1s roll away neighbor').params['whom'],
        'thirdNeighbors',
      );
    });

    test('a figure another dancer takes part in keeps the number a note', () {
      // A bare roll away is done with partners, so it is not only the larks.
      for (final line in [
        'N2 role1s roll away',
        'N2 role1s roll away partners',
      ]) {
        final f = _parse(line);
        expect(f.move, 'roll_away', reason: line);
        expect(f.params['who'], 'role1s', reason: line);
        expect(f.note, contains('with N2'), reason: line);
      }
    });

    test('a counterpart that defaults to neighbours takes the number', () {
      // Cross trails is done with neighbours unless the line says otherwise.
      final f = _parse('N2 role1s cross trails');
      expect(f.move, 'cross_trails');
      expect(f.params['who'], 'role1s');
      expect(f.params['who2'], 'nextNeighbors');
      expect(f.note, isNull);
    });

    test(
      'an explicit current neighbour is kept, and the number names the role',
      () {
        // The counterpart is the current neighbours as written, so N2 cannot
        // name them: it names the larks, who roll away by themselves, so the
        // note says so in the source's notation (no contradicting note).
        for (final line in [
          'N2 role1s roll away N1',
          'N2 role1s roll away N',
          'N2 role1s roll away neighbor 1',
        ]) {
          final f = _parse(line);
          expect(f.params['who'], 'role1s', reason: line);
          expect(f.params['whom'], 'neighbors', reason: line);
          expect(f.note, 'N2 role1s', reason: line);
        }
      },
    );

    test('a numbered role still folds with the other role\'s fall back', () {
      final figures = parseFigureLines(
        'prev role2s form long wave in center || role1s fall back',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(figures, hasLength(1));
      expect(figures.single.move, 'form_a_long_wave');
      expect(figures.single.params['who'], 'prevRole2s');
      expect(figures.single.params['out'], isTrue);
      // The Caller's Box's own wording: the robins form the wave by
      // themselves, so the number is a note, and the line still folds.
      final tcb = parseFigureLines(
        'N0 role2s form long wave in center || role1s fall back',
        frontEnd: tcbFigureFrontEnd,
      ).single;
      expect(tcb.move, 'form_a_long_wave');
      expect(tcb.params['who'], 'role2s');
      expect(tcb.params['out'], isTrue);
      expect(tcb.note, contains('with N0'));
      // A numbered falling-back side is never folded away.
      for (final line in [
        'role2s form long wave in center || next role1s fall back',
        'next role2s form long wave in center || prev role1s fall back',
      ]) {
        final kept = parseFigureLines(line, frontEnd: tcbFigureFrontEnd);
        expect(kept.single.isContainer, isTrue, reason: line);
      }
    });

    test(
      'the role acting by itself keeps the role, with the number a note',
      () {
        // User-ruled 2026-11-28: the role token only for a pair doing the
        // figure together; larks acting by themselves are all the larks.
        const cases = {
          'N2 role1s turn alone': 'turn_alone',
          'N2 role1s shift left': 'shift',
          'N0 role2s form long wave in center': 'form_a_long_wave',
        };
        for (final MapEntry(key: line, value: move) in cases.entries) {
          final f = _parse(line);
          expect(f.move, move, reason: line);
          expect(
            f.params['who'],
            line.contains('role1s') ? 'role1s' : 'role2s',
            reason: line,
          );
          expect(
            f.note,
            line.startsWith('N0') ? 'with N0' : 'with N2',
            reason: line,
          );
        }
      },
    );

    test('a pair doing the figure together takes the role token', () {
      const cases = {
        'N2 role1s allemande left 3/4': 'nextRole1s',
        'N0 role2s swing': 'prevRole2s',
        'N2 role1s seesaw': 'nextRole1s',
        'N2 role2s trade by right': 'nextRole2s',
        'N2 role1s pull by right': 'nextRole1s',
        'N2 role2s balance': 'nextRole2s',
        'N2 role1s gypsy right': 'nextRole1s',
        'N2 role1s california twirl': 'nextRole1s',
        'N2 role1s two hand turn': 'nextRole1s',
        'N2 role2s box the gnat': 'nextRole2s',
        'N2 role2s swat the flea': 'nextRole2s',
        'N2 role1s star through': 'nextRole1s',
        'N2 role2s box circulate': 'nextRole2s',
      };
      for (final MapEntry(key: line, value: who) in cases.entries) {
        final f = _parse(line);
        expect(f.params['who'], who, reason: line);
        expect(f.note, isNull, reason: line);
      }
    });

    test('a chain takes the role named, among those neighbours', () {
      // User-ruled 2026-11-27: the role follows the word, with its hand.
      const cases = {
        'N2 role2s chain': (who: 'nextRole2s', hand: 'right'),
        'N2 role1s chain': (who: 'nextRole1s', hand: 'left'),
        'N0 role2s chain': (who: 'prevRole2s', hand: 'right'),
        'role2s chain [with N2]': (who: 'nextRole2s', hand: 'right'),
      };
      for (final MapEntry(key: line, value: want) in cases.entries) {
        final f = _parse(line);
        expect(f.move, 'chain', reason: line);
        expect(f.params['who'], want.who, reason: line);
        expect(f.params['hand'], want.hand, reason: line);
        expect(f.note, isNull, reason: line);
      }
      // A destination stays the chain's note, as it does without a number.
      final to = _parse('N2 role2s chain to neighbor');
      expect(to.params['who'], 'nextRole2s');
      expect(to.note, 'to neighbor');
      // N3 has no role token: the number stays a note.
      expect(_parse('N3 role2s chain').params['who'], 'role2s');
    });

    test('a courtesy turn keeps the number as its note', () {
      // User-ruled 2026-11-27: unchanged.
      final f = _parse('N2 role1s courtesy turn');
      expect(f.move, 'courtesy_turn');
      expect(f.params['who'], 'role1s');
      expect(f.note, 'with N2');
    });

    test('numbered neighbours already named are never contradicted', () {
      // The same set says the number twice: read as written, no note.
      for (final line in [
        'N2 role1s roll away next neighbor',
        'N2 role2s roll away N2',
      ]) {
        final f = _parse(line);
        expect(f.params['whom'], 'nextNeighbors', reason: line);
        expect(f.params['who'], line.contains('role1s') ? 'role1s' : 'role2s');
        expect(f.note, isNull, reason: line);
      }
      // Another set cannot be the one the number names, so it names the role;
      // a roll away is not done together, so the note names it.
      final prev = _parse('N2 role1s roll away prev neighbor');
      expect(prev.params['who'], 'role1s');
      expect(prev.params['whom'], 'prevNeighbors');
      expect(prev.note, 'N2 role1s');
      // A number with no role token names the role in the note instead.
      final third = _parse('N3 role1s roll away prev neighbor');
      expect(third.params['who'], 'role1s');
      expect(third.params['whom'], 'prevNeighbors');
      expect(third.note, 'N3 role1s');
      final next = _parse('N0 role1s roll away next neighbor');
      expect(next.params['who'], 'role1s');
      expect(next.params['whom'], 'nextNeighbors');
      expect(next.note, 'N0 role1s');
    });

    test('a numbered turn around is the role turning alone', () {
      for (final line in [
        'N2 role1s turn around',
        'role1s turn around [with N2]',
      ]) {
        final f = _parse(line);
        expect(f.move, 'turn_alone', reason: line);
        expect(f.params['who'], 'role1s', reason: line);
        expect(f.note, 'with N2', reason: line);
      }
    });

    test('a promenade destination is not a neighbour the figure is with', () {
      final f = _parse('N2 role1s promenade to neighbor');
      expect(f.params['destination'], isNot('nextNeighbors'));
      expect(f.params['who'], isNot('nextRole1s'));
    });

    test('a number with no role token keeps the pair and the note', () {
      // There is no third or fourth role token (taxonomy v40).
      final f = _parse('N3 role1s allemande left 3/4');
      expect(f.move, 'allemande');
      expect(f.params['who'], 'role1s');
      expect(f.note, 'with N3');
    });

    test('N1 keeps the role and notes the current neighbours', () {
      // Pinned to literal values: the bracket form now shares this reading,
      // so comparing the two would not catch a change to either.
      final f = _parse('N1 role2s allemande right 1 & 1/2');
      expect(f.move, 'allemande');
      expect(f.params, {'who': 'role2s', 'hand': 'right', 'travel': 1.5});
      expect(f.note, 'with N1');
    });

    test('robins too', () {
      final f = _parse('N1 role2s allemande right 1 & 1/2');
      expect(f.params['who'], 'role2s');
      expect(f.note, 'with N1');
    });

    test('a remainder with its own annotation stays custom', () {
      // `(RH)` is read by a recognizer that would drop the number.
      expect(_parse('N3 role1s balance (RH)').isCustom, isTrue);
    });

    test('an amount choice keeps the number and the choice as notes', () {
      // `_amountAlternativeAnnotation` writes the first amount into the line
      // and re-reads it through this recognizer, so neither note is lost.
      final f = _parse('N2 role2s allemande right (1 or 2)');
      expect(f.isCustom, isFalse);
      expect(f.params['who'], 'nextRole2s');
      expect(f.params['travel'], 1.0);
      expect(f.note, '1 or 2');
      final third = _parse('N3 role2s allemande right (1 or 2)');
      expect(third.params['who'], 'role2s');
      expect(third.note, 'with N3; 1 or 2');
    });

    test('mixed case and other moves read the number too', () {
      final f = _parse('n2 Role2s trade by right');
      expect(f.isCustom, isFalse);
      expect(f.params['who'], 'nextRole2s');
      expect(f.note, isNull);
      final fourth = _parse('n4 Role2s trade by right');
      expect(fourth.params['who'], 'role2s');
      expect(fourth.note, 'with N4');
    });

    test('a numbered same-role neighbour stays custom', () {
      expect(
        _parse('N0 same-role neighbor allemande right 1/2').isCustom,
        isTrue,
      );
    });

    test('a line that already has a bracket stays custom', () {
      expect(
        _parse('N2 role1s allemande left 3/4 [with shadow]').isCustom,
        isTrue,
      );
    });

    test('a remainder nothing reads stays custom', () {
      expect(_parse('N2 role1s frobnicate wildly').isCustom, isTrue);
    });

    test('a number the notation does not name stays custom', () {
      expect(_parse('N7 role1s allemande left 3/4').isCustom, isTrue);
    });
  });

  group('Men allemande … [with N2]: the bracket form of the same line', () {
    // User-ruled 2026-11-27: the bracket form follows the same rules as the
    // number in front.
    // The two forms share one reading, so this guards that the bracket entry
    // claims these lines (before `_bracketAnnotation` would keep the number
    // as a note); the next tests pin the values themselves.
    test('reads exactly as the number in front', () {
      for (final (bracket, numbered) in [
        ('role1s allemande left 3/4 [with N2]', 'N2 role1s allemande left 3/4'),
        ('role2s allemande right 1 [With N0]', 'N0 role2s allemande right 1'),
        ('role1s roll away neighbor [with N2]', 'N2 role1s roll away neighbor'),
        ('role1s roll away [with N2]', 'N2 role1s roll away'),
        ('role1s allemande left 3/4 [with N3]', 'N3 role1s allemande left 3/4'),
      ]) {
        final a = _parse(bracket);
        final b = _parse(numbered);
        expect(a.move, b.move, reason: bracket);
        expect(a.params, b.params, reason: bracket);
        expect(a.note, b.note, reason: bracket);
      }
    });

    test('the role tokens and the neighbour set', () {
      expect(
        _parse('role1s allemande left 3/4 [with N2]').params['who'],
        'nextRole1s',
      );
      expect(
        _parse('role2s allemande right 1 [with N0]').params['who'],
        'prevRole2s',
      );
      final roll = _parse('role1s roll away neighbor [with N2]');
      expect(roll.params['who'], 'role1s');
      expect(roll.params['whom'], 'nextNeighbors');
      expect(roll.note, isNull);
    });

    test('the site\'s own role words, through the whole adapter', () async {
      final f = await _import('(8) Men allemande left 3/4 [with N2]');
      expect(f.move, 'allemande');
      expect(f.params['who'], 'nextRole1s');
      expect(f.note, isNull);
    });

    test('an amount choice keeps the choice as the note', () {
      final f = _parse('role2s allemande right (1 or 2) [with N2]');
      expect(f.params['who'], 'nextRole2s');
      expect(f.note, '1 or 2');
    });

    test('another bracket or another subject is left as it was', () {
      final shadow = _parse('role1s allemande left 3/4 [with shadow]');
      expect(shadow.params['who'], 'role1s');
      expect(shadow.note, 'with shadow');
      final star = _parse('Star right 3/4 [with N2]');
      expect(star.move, 'star');
      expect(star.note, 'with N2');
    });
  });

  group('hey pass lists', () {
    test('SRN is same-role neighbours', () {
      // "ones pass right, same-role neighbours pass left, twos pass right,
      // neighbours pass left".
      final f = _parse('Hey 1/2 (1R;SRNL;2R;NL)');
      expect(f.move, 'hey');
      expect(f.params['length'], 'half');
      expect(f.params['pass1'], 'ones');
      expect(f.params['shoulder'], 'right');
      expect(f.params['pass2'], 'sameRoles');
      expect(f.note, isNull);
    });

    test('SRN in a later pass does not force the hey custom', () {
      // Only pass1 and pass2 are stored; later passes are checked to decode.
      final f = _parse('Hey (NR;2L;SRNR;1L;NR;2L;SRNR;1L)');
      expect(f.isCustom, isFalse);
      expect(f.params['pass1'], 'neighbors');
      expect(f.params['pass2'], 'twos');
    });

    test('SRN1 is the same dancers as SRN', () {
      expect(_parse('Hey 1/2 (1R;SRN1L;2R;N1L)').params['pass2'], 'sameRoles');
    });

    test('an unmapped SR code still keeps the hey custom', () {
      expect(_parse('Hey 1/2 (1R;SRN2L;2R;NL)').isCustom, isTrue);
    });

    test('with hands and a bracket together make one note each', () {
      final f = _parse('Hey 1/2 with hands (WL;PR;ML) [With N1]');
      expect(f.move, 'hey');
      expect(f.note, contains('with hands'));
      expect(f.note, contains('with N1'));
    });

    test('with hands said twice stays custom', () {
      expect(
        _parse('Hey 1/2 with hands with hands (WL;PR;ML)').isCustom,
        isTrue,
      );
    });

    test('with hands is a note on the same hey', () {
      final plain = _parse('Hey 1/2 (N2R;ML;PR;WL)');
      final hands = _parse('Hey 1/2 with hands (N2R;ML;PR;WL)');
      expect(hands.move, 'hey');
      expect(hands.params, plain.params);
      expect(hands.note, 'with hands');
    });

    test('a trailing [with N1] is a note on the same hey', () {
      final plain = _parse('Hey 1/2 (WL;PR;ML)');
      final bracket = _parse('Hey 1/2 (WL;PR;ML) [with N1]');
      expect(bracket.move, 'hey');
      expect(bracket.params, plain.params);
      expect(bracket.note, 'with N1');
    });

    test('a bracket that does not name dancers keeps the hey custom', () {
      expect(_parse('Hey 1/2 (WL;PR;ML) [with phantoms]').isCustom, isTrue);
    });

    test('SRN is not read outside a hey', () {
      expect(_parse('Grand right and left (SRNR;PL;SRNR)').isCustom, isTrue);
    });
  });

  group('pass the ocean to a stated wave', () {
    test('reads the nested wave as sides, centre and centre hand', () {
      final f = _parse('Pass the ocean (to wave of four (NR,WL))');
      expect(f.move, 'pass_the_ocean');
      expect(f.params['sides'], 'neighbors');
      expect(f.params['center'], 'role2s');
      expect(f.params['centerHand'], 'left');
    });

    test('next neighbours on the sides', () {
      final f = _parse('Pass the ocean (to wave of four (N2R,WL))');
      expect(f.params['sides'], 'nextNeighbors');
    });

    test('two hands the same is no wave of four, and stays custom', () {
      expect(
        _parse('Pass the ocean (to wave of four (NR,WR))').isCustom,
        isTrue,
      );
    });

    test('two relationship codes name no centre, and stay custom', () {
      expect(
        _parse('Pass the ocean (to wave of four (NR,PL))').isCustom,
        isTrue,
      );
    });
  });
}
