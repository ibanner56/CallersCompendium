import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// Taxonomy v36 — the contra `circular_hey` move (ADR-006 §7.4, redefined for
/// contra: `who` names the group that passes first, `changes` is any whole number 1..10).
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  Figure hey({int? changes, String? who, String? shoulder, String? where}) =>
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
      expect(def.params['changes']!.kind, ParamKind.places);
      expect(def.params['changes']!.defaultValue, 4);
      expect(def.params['shoulder']!.defaultValue, 'right');
      expect(def.params['where']!.defaultValue, 'across');
    });

    test('has no whom: who alone names the first pass', () {
      expect(def.params.containsKey('whom'), isFalse);
    });

    test('changes drives the beat count', () {
      const expected = {1: 2, 2: 4, 3: 8, 4: 12, 5: 16, 6: 16, 7: 16, 10: 16};
      expected.forEach((changes, beats) {
        expect(
          tax.effectiveParams(hey(changes: changes))['beats'],
          beats,
          reason: '$changes changes',
        );
      });
      expect(tax.effectiveParams(hey())['beats'], 12);
    });

    test('an explicit beats value wins above six changes', () {
      final f = testFigure(
        move: 'circular_hey',
        params: {'changes': 8, 'beats': 24},
      );
      expect(tax.effectiveParams(f)['beats'], 24);
    });

    test('changes is any whole number 1..10, like circle', () {
      final spec = def.params['changes']!;
      expect(spec.validate(1), isTrue);
      expect(spec.validate(10), isTrue);
      expect(spec.validate(0), isFalse);
      expect(spec.validate(11), isFalse);
      expect(spec.validate('3'), isFalse);
    });
  });

  group('display', () {
    test('full circuit drops the fraction', () {
      expect(
        renderer.render(hey(), Dialect.canonical),
        'circular hey, neighbors pass right across',
      );
    });

    test('other counts read as quarters of the circuit', () {
      for (final (changes, text) in [
        (1, '1/4'),
        (2, '2/4'),
        (3, '3/4'),
        (5, '5/4'),
      ]) {
        expect(
          renderer.render(hey(changes: changes), Dialect.canonical),
          '$text circular hey, neighbors pass right across',
        );
      }
    });

    test('verbose spells the extent out instead of a spoken "3 slash 4"', () {
      expect(
        renderer.renderVerbose(hey(changes: 3), Dialect.canonical),
        'three changes of a circular hey, neighbors pass right across',
      );
      expect(
        renderer.renderVerbose(hey(changes: 1), Dialect.canonical),
        'one change of a circular hey, neighbors pass right across',
      );
      expect(
        renderer.renderVerbose(hey(), Dialect.canonical),
        'circular hey, neighbors pass right across',
      );
    });

    test('who and shoulder inform the first pass', () {
      expect(
        renderer.render(
          hey(changes: 3, who: 'partners', shoulder: 'left'),
          Dialect.canonical,
        ),
        '3/4 circular hey, partners pass left across',
      );
    });
  });

  test('canonical text names the count, so counts never dedupe together', () {
    expect(
      renderer.renderCanonical(hey(changes: 3)),
      'neighbors circular hey 3 changes right across',
    );
    expect(
      renderer.renderCanonical(hey(changes: 1)),
      'neighbors circular hey 1 change right across',
    );
  });

  group('free-text recognizer', () {
    Figure? parse(String t) => parseFigureLine(t);

    test('its own display sentence round-trips (3/4)', () {
      final f = parse('3/4 circular hey, neighbors pass right across')!;
      expect(f.move, 'circular_hey');
      expect(f.params['who'], 'neighbors');
      expect(f.params['changes'], 3);
      expect(f.params['shoulder'], 'right');
      expect(f.params['where'], 'across');
    });

    test('full circuit, left shoulder, along; "square hey" alias', () {
      final f = parse('full square hey, ones pass left along')!;
      expect(f.move, 'circular_hey');
      expect(f.params['who'], 'ones');
      expect(f.params['changes'], 4);
      expect(f.params['shoulder'], 'left');
      expect(f.params['where'], 'along');
    });

    test('other extents: 1/2 is two changes, 5/4 is five', () {
      expect(
        parse('1/2 circular hey, ones pass left along')!.params['changes'],
        2,
      );
      expect(
        parse('5/4 circular hey, ones pass left along')!.params['changes'],
        5,
      );
    });

    test('unstated facts are never defaulted: each degrades to custom', () {
      for (final line in [
        'circular hey, neighbors pass right across', // no extent
        '3/4 circular hey', // no who / shoulder / direction
        '3/4 circular hey, neighbors pass across', // no shoulder
        '3/4 circular hey, neighbors pass right', // no direction
        '11/4 circular hey, neighbors pass right across', // beyond 10 changes
        '3/4 circular hey, neighbors pass right across, then swing',
      ]) {
        expect(parse(line)?.move, 'custom', reason: line);
      }
    });
  });
}
