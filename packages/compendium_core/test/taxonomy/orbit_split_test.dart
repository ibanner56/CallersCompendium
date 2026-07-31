import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Issue #295 — promote `orbit` to a first-class move and retire the fused
/// `allemande_orbit`. The combined "X allemande while Y orbits" figure is now
/// modeled as a `meanwhile[allemande, orbit]` container: once `orbit` is
/// recognized standalone, the TCB `||` fan-out and the ContraDB `while` fan-out
/// both produce the container automatically. As of taxonomy v19 the legacy
/// `allemande_orbit` MoveDef is REMOVED; stored figures that reference it are
/// rewritten by the schema-v18 migration (see database.dart / migration_test).
/// This file asserts the new move, its conservative recognition, the two
/// meanwhile end-to-end paths, and that the legacy id is gone.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  group('taxonomy', () {
    test('orbit resolves and validates at its defaults', () {
      expect(tax.resolve('orbit')?.id, 'orbit');
      expect(tax.validateFigure(Figure(move: 'orbit')), isEmpty);
    });

    test('the fused allemande_orbit id is gone', () {
      expect(tax.resolve('allemande_orbit'), isNull);
    });

    test('orbit params validate across their domains', () {
      expect(
        tax.validateFigure(
          Figure(
            move: 'orbit',
            params: const {
              'who': 'role2s',
              'turn': 'counterclockwise',
              'amount': 0.75,
              'beats': 8,
            },
          ),
        ),
        isEmpty,
      );
    });
  });

  group('invertPairDancerSet (shared pair-inversion helper)', () {
    // Single source of truth reused by the display renderer, the schema-v18
    // migration, and the ContraDB structured-import decomposition (#295).
    test('inverts each nameable two-couple pairing (round-trip)', () {
      const pairs = {
        'role1s': 'role2s',
        'ones': 'twos',
        'firstCorners': 'secondCorners',
      };
      pairs.forEach((a, b) {
        expect(invertPairDancerSet(a), b);
        expect(invertPairDancerSet(b), a); // symmetric
      });
    });

    test('returns null for a dancer set with no nameable inverse', () {
      for (final who in const [
        'everyone',
        'partners',
        'neighbors',
        'shadows',
        'centers',
        'onesRole1',
        'not-a-token',
      ]) {
        expect(invertPairDancerSet(who), isNull, reason: who);
      }
    });
  });

  group('canonical rendering (golden)', () {
    final cases = <String, Figure>{
      'ones orbit clockwise ½': Figure(move: 'orbit'),
      'role1s orbit counterclockwise ¾': Figure(
        move: 'orbit',
        params: {'who': 'role1s', 'turn': 'counterclockwise', 'amount': 0.75},
      ),
    };
    cases.forEach((expected, figure) {
      test('"$expected"', () {
        expect(renderer.renderCanonical(figure), expected);
      });
    });
  });

  group('standalone recognition (TCB)', () {
    Figure parse(String text) {
      final f = parseFigureLine(text, frontEnd: tcbFigureFrontEnd);
      expect(f, isNotNull, reason: 'parse of "$text" returned null');
      return f!;
    }

    test('Men orbit clockwise 1/2', () {
      final f = parse('Men orbit clockwise 1/2');
      expect(f.move, 'orbit');
      expect(f.params['who'], 'role1s');
      expect(f.params['turn'], 'clockwise');
      expect(f.params['amount'], 0.5);
    });

    test('Women orbit counterclockwise 1/2', () {
      final f = parse('Women orbit counterclockwise 1/2');
      expect(f.move, 'orbit');
      expect(f.params['who'], 'role2s');
      expect(f.params['turn'], 'counterclockwise');
      expect(f.params['amount'], 0.5);
    });

    test('an omitted subject is flagged as assumed, not fabricated', () {
      final f = parse('orbit clockwise 1/2');
      expect(f.move, 'orbit');
      expect(f.assumedSubject, isTrue);
      expect(f.params['who'], 'ones');
    });

    test('a bare "orbit" degrades to custom (direction/amount required)', () {
      expect(parse('orbit').isCustom, isTrue);
    });

    test('an orbit with no amount degrades to custom', () {
      expect(parse('Men orbit clockwise').isCustom, isTrue);
    });

    test('an orbit with no direction degrades to custom', () {
      expect(parse('Men orbit 1/2').isCustom, isTrue);
    });
  });

  group('meanwhile[allemande, orbit] end-to-end', () {
    test('TCB || fans a combined line into the container', () {
      final f = parseFigureLineFanOut(
        'Women allemande left 1 || Men orbit clockwise 1/2',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isTrue);
      expect(f.beats, 8);
      final sides = f.subFigures;
      expect(sides.map((s) => s.move), ['allemande', 'orbit']);
      expect(sides[0].params['who'], 'role2s');
      expect(sides[0].params['hand'], 'left');
      expect(sides[0].params['turn'], 1.0);
      expect(sides[1].params['who'], 'role1s');
      expect(sides[1].params['turn'], 'clockwise');
      expect(sides[1].params['amount'], 0.5);
    });

    test('ContraDB combined "while the" line fans into the container', () {
      final f = parseContraDbFigureLine(
        'ladles allemande left 1½ around while the gentlespoons orbit '
        'clockwise ½ around',
        beats: 8,
      );
      expect(f, isNotNull);
      expect(f!.isMeanwhile, isTrue);
      final sides = f.subFigures;
      expect(sides.map((s) => s.move), ['allemande', 'orbit']);
      expect(sides[0].params['who'], 'role2s');
      expect(sides[0].params['hand'], 'left');
      expect(sides[0].params['turn'], 1.5);
      expect(sides[1].params['who'], 'role1s');
      expect(sides[1].params['turn'], 'clockwise');
      expect(sides[1].params['amount'], 0.5);
    });
  });
}
