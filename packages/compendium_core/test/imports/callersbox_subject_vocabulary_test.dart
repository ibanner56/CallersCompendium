import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The Caller's Box subject vocabulary: same-role neighbors and the S-prefix
/// shadow codes.
///
/// Maintainer rulings these pin:
/// - "Same-role neighbor" (and the older "same-sex neighbor") names the
///   taxonomy's `sameRoles` set.
/// - `S-1` is the bare shadow; `S1` is the bare shadow (glossary); `S2` is
///   `secondShadows`. `S3`+, `S-2`, … have no token and stay custom.
///
/// Every line below is a verbatim corpus wording unless marked otherwise.
void main() {
  Figure parse(String line) =>
      parseFigureLine(line, frontEnd: tcbFigureFrontEnd)!;

  group('same-role neighbor → sameRoles', () {
    const cases = <String, String>{
      'Same-role neighbor allemande left 1 & 1/2': 'allemande',
      'Same-role neighbor allemande left 1': 'allemande',
      'Same-role neighbor do-si-do': 'do_si_do',
      'Same-role neighbor swing': 'swing',
      'Same-role neighbor balance': 'balance',
      '[Twos and threes] Same-role neighbor seesaw': 'see_saw',
    };
    cases.forEach((line, move) {
      test('"$line" structures as $move(who: sameRoles)', () {
        final f = parse(line);
        expect(f.isCustom, isFalse, reason: f.params['text']?.toString());
        expect(f.move, move);
        expect(f.params['who'], 'sameRoles');
      });
    });

    test('allemande keeps its hand and turn amount', () {
      final f = parse('Same-role neighbor allemande left 1 & 1/2');
      expect(f.params['hand'], 'left');
      expect(f.params['travel'], 1.5);
    });

    test('"same-sex neighbor" is the same pairing (not corpus wording)', () {
      final f = parse('Same-sex neighbor swing');
      expect(f.move, 'swing');
      expect(f.params['who'], 'sameRoles');
    });

    test('the pair is read whole: never neighbors with a stray qualifier', () {
      // Without the pair reader, "neighbor" alone resolves to `neighbors`,
      // which would assert the opposite-role neighbor.
      expect(parse('Same-role neighbor do-si-do').params['who'], 'sameRoles');
    });

    test('a [who] bracket survives as the note', () {
      final f = parse(
        'Same-role neighbor allemande left 1 [M with N1, W with N2]',
      );
      expect(f.params['who'], 'sameRoles');
      expect(f.note, 'M with N1, W with N2');
    });

    test('the qualifier alone is not a dancer set', () {
      expect(parse('Same-role person swing').isCustom, isTrue);
    });

    test(
      'an N-prefixed same-role neighbor stays custom (no ordinal token)',
      () {
        final f = parse('N2 same-role neighbor do-si-do');
        expect(f.isCustom, isTrue);
        expect(f.params['text'], contains('N2 same-role neighbor'));
      },
    );

    test('right and left through still carries same-role as a note', () {
      // right_left_through has no who slot; the variant stays a note.
      final f = parse('Same-role right and left through with neighbor');
      expect(f.move, 'right_left_through');
      expect(f.note, 'same-role');
      expect(f.params.containsKey('who'), isFalse);
    });
  });

  group('a per-role turn amount keeps the line custom', () {
    // No move models a per-role amount; structuring would render the
    // allemande's default travel (1), which neither role dances.
    for (final line in const [
      'Same-role neighbor allemande left (M 1 & 1/2, W 2)',
      'Same-role neighbor allemande left (M 1 & 1/4, W 1 & 3/4)',
      'Same-role neighbor left shoulder round [M with N2, W with N1] '
          '(M 1, W 1 & 1/2)',
      // Not corpus wording: the veto is not subject-specific.
      'Neighbor allemande left (W 2, M 1 & 1/2)',
    ]) {
      test('"$line" stays custom with its text intact', () {
        final f = parse(line);
        expect(f.isCustom, isTrue);
        expect(f.params['text'], contains('M 1'));
      });
    }
  });

  group('S-prefix shadow codes', () {
    const cases = <String, String>{
      'S-1 shadow allemande left 1': 'shadows',
      'S1 shadow allemande left 1': 'shadows',
      'S1 shadow pull by right': 'shadows',
      'S2 shadow swing': 'secondShadows',
      'S2 shadow do-si-do': 'secondShadows',
    };
    cases.forEach((line, who) {
      test('"$line" → who: $who', () {
        final f = parse(line);
        expect(f.isCustom, isFalse, reason: f.params['text']?.toString());
        expect(f.params['who'], who);
      });
    });

    for (final line in const [
      'S3 shadow allemande left 1',
      'S4 shadow swing',
      'S-2 shadow allemande left 1',
    ]) {
      test('"$line" has no token and stays custom', () {
        expect(parse(line).isCustom, isTrue);
      });
    }
  });

  test('N3 neighbor is the third neighbor', () {
    expect(
      parse('N3 neighbor allemande right 1').params['who'],
      'thirdNeighbors',
    );
  });
}
