import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The remaining moves read back from the app's own display wording (#2121);
/// the round-trip ratchet covers each value alone, these pin whole figures and
/// the lines the readers refuse.
void main() {
  Figure only(String line) {
    final figures = parseFreeTextFigureEntry(line);
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  group('poussette', () {
    test('reads the fraction, both pairs and the turn', () {
      expect(
        only(
          'three quarter poussette - shadows pull opposites back then right',
        ).params,
        {
          'fraction': 'threeQuarter',
          'who': 'shadows',
          'whom': 'opposites',
          'direction': 'counterclockwise',
        },
      );
    });

    test('back then left is clockwise, as ContraDB writes it', () {
      expect(
        only(
          'half poussette - role1s pull neighbor back then left',
        ).params['direction'],
        'clockwise',
      );
    });
  });

  group('zig-zag', () {
    test('reads the pair and the ender', () {
      expect(
        only(
          'zig right zag left with neighbor, trailing two catching hands',
        ).params,
        {'slide': 'right', 'who': 'neighbors', 'ender': 'allemande'},
      );
      expect(only('zig left zag right with partner into a ring').params, {
        'slide': 'left',
        'who': 'partners',
        'ender': 'ring',
      });
    });

    test('a zag that is not the mirror of the zig is not this wording', () {
      expect(only('zig left zag left with partner').params['who'], isNull);
    });
  });

  group('figure 8', () {
    test('reads the fraction, the direction and who leads', () {
      expect(
        only(
          'twos three quarter figure 8 down between ones, first lark '
          'leading',
        ).params,
        {
          'who': 'twos',
          'fraction': 'threeQuarter',
          'where': 'below',
          'lead': 'onesRole1',
        },
      );
    });

    test('a figure 8 with no direction is left to the existing readers', () {
      // The display writes it for `where: none`; ContraDB's meaning is not
      // established, so it is not read as none.
      expect(only('ones half figure 8').params['where'], isNot('none'));
    });
  });

  test('a box circulate reads the display\'s subjects and its others', () {
    expect(
      only(
        'balance & box circulate - partners cross while others loop left',
      ).params,
      {'balance': true, 'who': 'partners', 'hand': 'left'},
    );
  });
}
