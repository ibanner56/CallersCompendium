import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// (De)serialization of the `meanwhile` container figure (#590): recursive,
/// additive round-tripping through the figure codec plus the tolerant, defensive
/// decode rules (prefer-custom fallback, flat-only flattening, side-count cap,
/// legacy tolerance).
void main() {
  final swing = Figure(
    move: 'swing',
    params: const {'who': 'partners', 'beats': 16},
  );
  final allemande = Figure(
    move: 'allemande',
    params: const {'who': 'role1', 'hand': 'left', 'turn': 1.5},
  );
  final orbit = Figure(move: 'orbit', params: const {'who': 'role2'});

  group('round-trip', () {
    test('a two-sided container round-trips losslessly', () {
      final container = Figure.meanwhile(figures: [allemande, orbit], beats: 8);
      final dance = [swing, container];
      final decoded = decodeFigures(encodeFigures(dance));
      expect(decoded, dance);
      expect(decoded[1].isMeanwhile, isTrue);
      expect(decoded[1].beats, 8);
      expect(decoded[1].subFigures, [allemande, orbit]);
    });

    test('a >2-sided container round-trips losslessly', () {
      final third = Figure(move: 'custom', params: const {'text': 'gaze'});
      final container = Figure.meanwhile(
        figures: [allemande, orbit, third],
        beats: 8,
      );
      final decoded = decodeFigures(encodeFigures([container]));
      expect(decoded.single, container);
    });

    test('sub-figures reuse the same codec shape (recursive)', () {
      final container = Figure.meanwhile(figures: [allemande, orbit], beats: 8);
      final json = figureToJson(container);
      final sides = (json['params'] as Map)['figures'] as List;
      // Each side is encoded exactly like a top-level figure.
      expect(sides.first, figureToJson(allemande));
      // No schema-version bump — the container carries the same version.
      expect(json['schemaVersion'], figureSchemaVersion);
    });
  });

  group('defensive / tolerant decode', () {
    Map<String, Object?> meanwhileJson(List<Map<String, Object?>> sides) => {
      'schemaVersion': 1,
      'move': meanwhileMove,
      'params': {'beats': 8, 'figures': sides},
    };

    test('clamps the side count to the cap (drops the pathological tail)', () {
      final sides = [
        for (var i = 0; i < kMaxMeanwhileSides + 4; i++)
          {
            'move': 'custom',
            'params': {'text': 'side $i'},
          },
      ];
      final decoded = figureFromJson(meanwhileJson(sides));
      expect(decoded.subFigures, hasLength(kMaxMeanwhileSides));
    });

    test('flattens a nested meanwhile side (flat only)', () {
      final nested = {
        'move': meanwhileMove,
        'params': {
          'beats': 4,
          'figures': [
            {'move': 'orbit'},
            {
              'move': 'custom',
              'params': {'text': 'loop'},
            },
          ],
        },
      };
      final decoded = figureFromJson(
        meanwhileJson([
          {'move': 'allemande'},
          nested,
        ]),
      );
      // The nested container's sides are hoisted up; nothing is dropped and no
      // meanwhile survives inside a meanwhile.
      expect(decoded.subFigures.map((f) => f.move), [
        'allemande',
        'orbit',
        'custom',
      ]);
      expect(decoded.subFigures.every((f) => !f.isMeanwhile), isTrue);
    });

    test('ignores non-object junk sides without fabricating', () {
      final decoded = figureFromJson({
        'move': meanwhileMove,
        'params': {
          'beats': 8,
          'figures': [
            {'move': 'orbit'},
            'not-an-object',
            42,
          ],
        },
      });
      expect(decoded.subFigures.map((f) => f.move), ['orbit']);
    });

    test('an unknown-move side rides along verbatim (prefer-custom)', () {
      // An unrecognized side is kept as-is; the parse never fails and nothing is
      // fabricated. (Mapping unknown import lines to `custom` is the import
      // child's job; the codec must at least preserve them losslessly.)
      final decoded = figureFromJson(
        meanwhileJson([
          {
            'move': 'a_move_from_the_future',
            'params': {'beats': 6},
          },
          {'move': 'orbit'},
        ]),
      );
      expect(decoded.subFigures.first.move, 'a_move_from_the_future');
      expect(decoded.subFigures.first.params['beats'], 6);
    });

    test('an empty/absent figures list decodes as no sides', () {
      expect(
        figureFromJson({
          'move': meanwhileMove,
          'params': {'beats': 8},
        }).subFigures,
        isEmpty,
      );
      expect(figureFromJson(meanwhileJson([])).subFigures, isEmpty);
    });
  });

  group('legacy tolerance', () {
    test('a bare meanwhile move without figures loads without crashing', () {
      // Simulates a reader that predates full meanwhile support meeting a
      // meanwhile figure: it decodes as an opaque figure and never throws.
      final decoded = decodeFigures(
        jsonEncode([
          {'schemaVersion': 1, 'move': meanwhileMove},
        ]),
      );
      expect(decoded.single.move, meanwhileMove);
      expect(decoded.single.subFigures, isEmpty);
    });
  });
}
