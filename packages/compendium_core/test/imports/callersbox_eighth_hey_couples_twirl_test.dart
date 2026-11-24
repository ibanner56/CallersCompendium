import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Three Caller's Box line shapes that used to stay free text (2026-11-24,
/// user-ruled): an eighth of a hey (one pass by), a do si do danced as
/// couples, and a Jersey twirl (a California twirl). The double slice that
/// names neighbours is covered with the other double-slice tests in
/// `callersbox_clause_note_test.dart`.
Figure _parse(String line) =>
    parseFigureLine(line, frontEnd: tcbFigureFrontEnd)!;

void main() {
  group('Hey 1/8: one pass by', () {
    test('robins passing right shoulder', () {
      final f = _parse('Hey 1/8 (WR)');
      expect(f.move, 'pass_by');
      expect(f.params['who'], 'role2s');
      expect(f.params['shoulder'], 'right');
      expect(f.note, '1/8 hey');
    });

    test('larks passing left shoulder', () {
      final f = _parse('Hey 1/8 (ML)');
      expect(f.move, 'pass_by');
      expect(f.params['who'], 'role1s');
      expect(f.params['shoulder'], 'left');
    });

    test('a relationship code names the pair', () {
      final f = _parse('Hey 1/8 (NR)');
      expect(f.move, 'pass_by');
      expect(f.params['who'], 'neighbors');
    });

    test(
      'a progression mark, a second cell or an unknown code stays custom',
      () {
        expect(_parse('Hey 1/8 (WR~)').isCustom, isTrue);
        expect(_parse('Hey 1/8 (WR;ML)').isCustom, isTrue);
        expect(_parse('Hey 1/8 (PhR)').isCustom, isTrue);
        expect(_parse('Hey 1/8 (WR) [with phantoms]').isCustom, isTrue);
      },
    );

    test('other hey fractions still read as a hey', () {
      final f = _parse('Hey 1/4 (WR;PL)');
      expect(f.move, 'hey');
      expect(f.params['length'], 'lessThanHalf');
    });
  });

  group('As couples: a do si do danced as couples', () {
    test('reads as the do si do, with the note', () {
      final f = _parse('As couples, neighbor do si do');
      expect(f.move, 'do_si_do');
      expect(f.params['who'], 'neighbors');
      expect(f.note, 'as couples');
    });

    test('keeps the amount', () {
      final f = _parse('As couples, neighbor do si do 1 & 1/2');
      expect(f.move, 'do_si_do');
      expect(f.params['travel'], 1.5);
      expect(f.note, 'as couples');
    });

    test('a move other than a do si do stays custom', () {
      expect(_parse('As couples, partner swing').isCustom, isTrue);
      expect(_parse('As couples, go forward and back').isCustom, isTrue);
    });
  });

  group('Jersey twirl: a California twirl', () {
    test('reads as the California twirl, with the note', () {
      final f = _parse('Partner Jersey twirl');
      expect(f.move, 'california_twirl');
      expect(f.params['who'], 'partners');
      expect(f.note, 'Jersey twirl');
    });

    test('matches the California twirl line, apart from the note', () {
      final jersey = _parse('N2 neighbor Jersey twirl');
      final california = _parse('N2 neighbor California twirl');
      expect(jersey.move, california.move);
      expect(jersey.params, california.params);
      expect(jersey.note, 'Jersey twirl');
    });

    test('a qualified twirl stays custom', () {
      expect(_parse('Partner modified Jersey twirl').isCustom, isTrue);
      expect(
        _parse('[Center four] Opposite neighbor Jersey twirl').isCustom,
        isTrue,
      );
    });
  });
}
