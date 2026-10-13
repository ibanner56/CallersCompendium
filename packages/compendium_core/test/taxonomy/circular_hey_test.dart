import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// Taxonomy v36 — the contra `circular_hey` move (ADR-006 §7.4, redefined for
/// contra: `who` names the group that passes first, `changes` is 3 or 4).
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  Figure hey({String? changes, String? who, String? shoulder, String? where}) =>
      testFigure(
        move: 'circular_hey',
        params: {
          'changes': ?changes,
          'who': ?who,
          'shoulder': ?shoulder,
          'where': ?where,
        },
      );

  test('taxonomy version is 36', () => expect(contraTaxonomyVersion, 36));

  group('definition', () {
    final def = tax.resolve('circular_hey')!;

    test('params and defaults', () {
      expect(def.params.keys, ['who', 'changes', 'shoulder', 'where', 'beats']);
      expect(def.params['who']!.defaultValue, 'neighbors');
      expect(def.params['changes']!.defaultValue, '4');
      expect(def.params['changes']!.choices, ['3', '4']);
      expect(def.params['shoulder']!.defaultValue, 'right');
      expect(def.params['where']!.defaultValue, 'across');
    });

    test('has no whom: who alone names the first pass', () {
      expect(def.params.containsKey('whom'), isFalse);
    });

    test('changes drives the beat count: 3 -> 8, 4 -> 12', () {
      expect(tax.effectiveParams(hey(changes: '3'))['beats'], 8);
      expect(tax.effectiveParams(hey(changes: '4'))['beats'], 12);
      expect(tax.effectiveParams(hey())['beats'], 12);
    });

    test('changes admits only 3 and 4', () {
      expect(def.params['changes']!.validate('3'), isTrue);
      expect(def.params['changes']!.validate('2'), isFalse);
      expect(def.params['changes']!.validate(3), isFalse);
    });
  });

  group('display', () {
    test('full circuit drops the fraction', () {
      expect(
        renderer.render(hey(), Dialect.canonical),
        'circular hey, neighbors pass right across',
      );
    });

    test('three changes reads 3/4', () {
      expect(
        renderer.render(hey(changes: '3'), Dialect.canonical),
        '3/4 circular hey, neighbors pass right across',
      );
    });

    test('who and shoulder inform the first pass', () {
      expect(
        renderer.render(
          hey(changes: '3', who: 'partners', shoulder: 'left'),
          Dialect.canonical,
        ),
        '3/4 circular hey, partners pass left across',
      );
    });
  });

  test('canonical text carries changes, so 3 and 4 never dedupe together', () {
    expect(
      renderer.renderCanonical(hey(changes: '3')),
      isNot(renderer.renderCanonical(hey(changes: '4'))),
    );
  });

  group('free-text recognizer', () {
    Figure? parse(String t) => parseFigureLine(t);

    test('its own display sentence round-trips (3/4)', () {
      final f = parse('3/4 circular hey, neighbors pass right across')!;
      expect(f.move, 'circular_hey');
      expect(f.params['who'], 'neighbors');
      expect(f.params['changes'], '3');
      expect(f.params['shoulder'], 'right');
      expect(f.params['where'], 'across');
    });

    test('full circuit, left shoulder, along; "square hey" alias', () {
      final f = parse('full square hey, ones pass left along')!;
      expect(f.move, 'circular_hey');
      expect(f.params['who'], 'ones');
      expect(f.params['changes'], '4');
      expect(f.params['shoulder'], 'left');
      expect(f.params['where'], 'along');
    });

    test('unstated facts are never defaulted: each degrades to custom', () {
      for (final line in [
        'circular hey, neighbors pass right across', // no extent
        '3/4 circular hey', // no who / shoulder / direction
        '3/4 circular hey, neighbors pass across', // no shoulder
        '3/4 circular hey, neighbors pass right', // no direction
        '1/2 circular hey, neighbors pass right across', // extent not modelled
        '3/4 circular hey, neighbors pass right across, then swing',
      ]) {
        expect(parse(line)?.move, 'custom', reason: line);
      }
    });
  });
}
