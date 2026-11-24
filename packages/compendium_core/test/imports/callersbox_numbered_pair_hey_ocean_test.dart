import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Three Caller's Box line shapes that used to stay free text (2026-11-24,
/// user-ruled): a neighbour number before a same-role pair, hey pass lists
/// naming same-role neighbours (plus `with hands` and a trailing `[with …]`),
/// and a pass the ocean whose wave sits in a nested bracket.
Figure _parse(String line) =>
    parseFigureLine(line, frontEnd: tcbFigureFrontEnd)!;

void main() {
  group('N2 Men allemande: a neighbour number before a same-role pair', () {
    test('reads as the role pair, with the number as a note', () {
      final f = _parse('N2 role1s allemande left 3/4');
      expect(f.move, 'allemande');
      // Still the two larks, never next neighbours.
      expect(f.params['who'], 'role1s');
      expect(f.params['hand'], 'left');
      expect(f.params['travel'], 0.75);
      expect(f.note, 'with nextNeighbors');
    });

    test('matches the bracket form the importer already read', () {
      final bracket = _parse('role2s allemande right 1 & 1/2 [with N1]');
      final numbered = _parse('N1 role2s allemande right 1 & 1/2');
      expect(numbered.move, bracket.move);
      expect(numbered.params, bracket.params);
      expect(numbered.note, bracket.note);
    });

    test('robins too', () {
      final f = _parse('N1 role2s allemande right 1 & 1/2');
      expect(f.params['who'], 'role2s');
      expect(f.note, 'with neighbors');
    });

    test('a numbered same-role neighbour is not read here', () {
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

    test('SRN in a later pass still decodes', () {
      final f = _parse('Hey (NR;2L;SRNR;1L;NR;2L;SRNR;1L)');
      expect(f.params['pass1'], 'neighbors');
      expect(f.params['pass2'], 'twos');
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
      expect(bracket.note, 'with neighbors');
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
