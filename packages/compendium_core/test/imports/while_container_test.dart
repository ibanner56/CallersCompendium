import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

Figure _f(String move) => Figure(move: move);

void main() {
  group('whileModifierContainer', () {
    test('the four named pairings build a modifier', () {
      for (final core in ['long_lines', 'slice']) {
        for (final modifier in ['roll_away', 'give_and_take']) {
          final f = whileModifierContainer(
            [_f(core), _f(modifier)],
            beats: 8,
          );
          expect(f, isNotNull, reason: '$core + $modifier');
          expect(f!.isModifier, isTrue);
          expect(f.params['beats'], 8);
          expect(f.subFigures.map((s) => s.move), [core, modifier]);
        }
      }
    });

    test('progression rides on the container', () {
      final f = whileModifierContainer(
        [_f('long_lines'), _f('roll_away')],
        beats: 8,
        progression: true,
      );
      expect(f!.progression, isTrue);
    });

    test('anything else declines', () {
      final custom = customFigure(
        'x',
        beats: 0,
        origin: CustomOrigin.importGap,
      );
      final declined = <String, List<Figure>>{
        'reversed': [_f('roll_away'), _f('long_lines')],
        'two groups': [_f('swing'), _f('circle')],
        'core twice': [_f('long_lines'), _f('slice')],
        'custom modifier': [_f('long_lines'), custom],
        'custom core': [custom, _f('roll_away')],
        'one side': [_f('long_lines')],
        'three sides': [_f('long_lines'), _f('roll_away'), _f('give_and_take')],
        'container side': [
          _f('long_lines'),
          Figure.meanwhile(
            figures: [_f('roll_away'), _f('swing')],
            beats: 8,
          ),
        ],
      };
      declined.forEach((name, sides) {
        expect(whileModifierContainer(sides, beats: 8), isNull, reason: name);
      });
    });
  });
}
