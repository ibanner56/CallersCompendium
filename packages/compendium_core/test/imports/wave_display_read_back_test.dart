import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The wave moves read back from the app's own display wording (#2121), which
/// differs from ContraDB's: the round-trip ratchet covers each value alone;
/// these pin a whole figure and the lines the readers must refuse.
void main() {
  Figure only(String line) {
    final figures = parseFreeTextFigureEntry(line);
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  group('pass the ocean', () {
    test('reads the direction, both pairs, the center hand and balance', () {
      final f = only(
        'pass through to an ocean wave on left diagonal - role1s catch right '
        'hands in the center, partners take left hands on the sides and '
        'balance',
      );
      expect(f.move, 'pass_the_ocean');
      expect(f.params, {
        'where': 'leftDiagonal',
        'balance': true,
        'center': 'role1s',
        'centerHand': 'right',
        'sides': 'partners',
      });
      expect(f.note, isNull);
    });

    test('a side hand that is not the other hand is not this wording', () {
      final f = only(
        'pass through to an ocean wave - role2s catch left hands in the '
        'center, neighbors take left hands on the sides',
      );
      // The shared grammar reads a pass through and keeps the rest as the
      // note, as it did before #2121.
      expect(f.move, 'pass_through');
      expect(f.note, startsWith('to an ocean wave'));
    });
  });

  group('form short waves', () {
    test('reads both pairs, the center hand and balance', () {
      final f = only(
        'form short waves - third corners by the right in the center, '
        'shadow by the left on the sides - and balance',
      );
      expect(f.move, 'form_short_waves');
      expect(f.params, {
        'balance': true,
        'center': 'thirdCorners',
        'centerHand': 'right',
        'sides': 'shadows',
      });
      expect(f.note, isNull);
    });

    test('a side hand that is not the other hand is not this wording', () {
      final f = only(
        'form short waves - role2s by the left in the center, neighbor by '
        'the left on the sides',
      );
      expect(f.isCustom, isTrue);
    });
  });

  group('form long waves', () {
    test('reads the pair held, who faces in, and balance', () {
      final f = only(
        'form long waves - neighbor by the right, ones facing in, twos facing '
        'out - and balance',
      );
      expect(f.move, 'form_long_waves');
      expect(f.params, {
        'whom': 'neighbors',
        'whomHand': 'right',
        'who': 'ones',
        'balance': true,
      });
      expect(f.note, isNull);
    });

    test('an "other" pair the display would not derive is not read', () {
      final f = only('form long waves - ones facing in, role2s facing out');
      // ContraDB's reader takes the move and keeps the clause as the note.
      expect(f.params, isEmpty);
      expect(f.note, '- ones facing in, role2s facing out');
    });
  });

  test('a long wave formed in place reads as neither in nor out', () {
    final f = only('role2s form a long wave in the center - balance the wave');
    expect(f.move, 'form_a_long_wave');
    expect(f.params, {
      'who': 'role2s',
      'in': false,
      'out': false,
      'balance': true,
    });
  });
}
