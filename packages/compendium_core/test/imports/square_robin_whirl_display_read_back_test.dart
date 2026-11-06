import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The square through, mad robin and butterfly whirl read back from the app's
/// own display wording (#2121); the round-trip ratchet covers each value
/// alone, these pin whole figures and the lines the readers refuse.
void main() {
  Figure only(String line) {
    final figures = parseFreeTextFigureEntry(line);
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  group('square through', () {
    test('reads both pairs, the hands and a stated or missing balance', () {
      expect(
        only(
          'square through two - neighbor balance & pull by left, then '
          'shadow pull by right',
        ).params,
        {
          'places': 2,
          'who': 'neighbors',
          'balance': true,
          'hand': 'left',
          'who2': 'shadows',
        },
      );
      expect(
        only(
          'square through two - partner pull by right, then neighbor pull '
          'by left',
        ).params['balance'],
        isFalse,
      );
    });

    test('reads three and four places', () {
      expect(
        only(
          'square through three - partner balance & pull by right, then '
          'neighbor pull by left, then partner balance & pull by right',
        ).params['places'],
        3,
      );
      expect(
        only(
          'square through four - partner balance & pull by right, then '
          'neighbor pull by left, then repeat',
        ).params['places'],
        4,
      );
    });

    test('a second pull by the same hand is not this wording', () {
      final f = only(
        'square through two - partner balance & pull by right, then '
        'neighbor pull by right',
      );
      expect(f.isCustom, isTrue);
    });
  });

  group('mad robin', () {
    test('reads the spin, the turn around whom and who is in front', () {
      expect(
        only('mad robin clockwise 1½ around neighbor, role2s in front').params,
        {
          'direction': 'clockwise',
          'travel': 1.5,
          'whom': 'neighbors',
          'who': 'role2s',
        },
      );
    });

    test('no in-front clause states who is unspecified', () {
      expect(only('mad robin counterclockwise').params, {
        'direction': 'counterclockwise',
        'who': 'unspecified',
      });
    });

    test('a bare mad robin is still read by name, with its defaults', () {
      expect(only('mad robin').params, isEmpty);
    });
  });

  test('a butterfly whirl reads its displayed spin', () {
    final f = only('butterfly whirl counterclockwise');
    expect(f.params, {'direction': 'counterclockwise'});
    expect(f.note, isNull);
  });
}
