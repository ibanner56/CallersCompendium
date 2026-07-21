import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('figure JSON round-trip', () {
    final samples = <Figure>[
      Figure(move: 'swing', params: {'who': 'partners', 'beats': 16}),
      Figure(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'right', 'turn': 1.5},
        progression: true,
      ),
      Figure(move: 'balance_the_ring', params: {'beats': 4}, note: 'gently'),
      Figure(move: customMove, params: {'text': 'weave the ring', 'beats': 8}),
      Figure(move: 'petronella'),
      Figure(
        move: customMove,
        params: {'text': 'kept verbatim', 'beats': 8},
        customOrigin: CustomOrigin.importGap,
      ),
    ];

    test('encode then decode preserves every figure', () {
      final decoded = decodeFigures(encodeFigures(samples));
      expect(decoded, samples);
    });

    test('single-figure map round-trip', () {
      for (final f in samples) {
        expect(figureFromJson(figureToJson(f)), f);
      }
    });
  });

  group('figure JSON shape', () {
    test('omits empty params, absent note, and false progression', () {
      final json = figureToJson(Figure(move: 'petronella'));
      expect(json.containsKey('params'), isFalse);
      expect(json.containsKey('note'), isFalse);
      expect(json.containsKey('progression'), isFalse);
      expect(json['schemaVersion'], figureSchemaVersion);
    });

    test('includes progression only when true', () {
      expect(
        figureToJson(Figure(move: 'swing', progression: true))['progression'],
        isTrue,
      );
    });

    test('omits customOrigin for the default userEntered', () {
      final json = figureToJson(
        Figure(move: customMove, params: {'text': 'x'}),
      );
      expect(json.containsKey('customOrigin'), isFalse);
    });

    test('writes customOrigin only for importGap', () {
      final json = figureToJson(
        Figure(
          move: customMove,
          params: {'text': 'x'},
          customOrigin: CustomOrigin.importGap,
        ),
      );
      expect(json['customOrigin'], 'importGap');
    });
  });

  group('customOrigin decoding', () {
    test('missing key defaults to userEntered (backward compatible)', () {
      final f = figureFromJson({
        'move': customMove,
        'params': {'text': 'x'},
      });
      expect(f.customOrigin, CustomOrigin.userEntered);
    });

    test('unknown value falls back to userEntered', () {
      final f = figureFromJson({'move': customMove, 'customOrigin': 'bogus'});
      expect(f.customOrigin, CustomOrigin.userEntered);
    });

    test('parses importGap by name', () {
      final f = figureFromJson({
        'move': customMove,
        'customOrigin': 'importGap',
      });
      expect(f.customOrigin, CustomOrigin.importGap);
    });
  });

  group('decoding tolerance and errors', () {
    test('missing schemaVersion defaults to 1', () {
      final f = figureFromJson({'move': 'swing'});
      expect(f.schemaVersion, 1);
    });

    test('ignores unknown keys (forward compatibility)', () {
      final f = figureFromJson({'move': 'swing', 'futureField': 42});
      expect(f.move, 'swing');
    });

    test('rejects a missing or non-string move', () {
      expect(() => figureFromJson({'params': {}}), throwsFormatException);
      expect(() => figureFromJson({'move': 7}), throwsFormatException);
    });

    test('rejects wrong types for note/progression/params', () {
      expect(
        () => figureFromJson({'move': 'x', 'note': 5}),
        throwsFormatException,
      );
      expect(
        () => figureFromJson({'move': 'x', 'progression': 'yes'}),
        throwsFormatException,
      );
      expect(
        () => figureFromJson({'move': 'x', 'params': []}),
        throwsFormatException,
      );
    });

    test('rejects a non-array figures_json root', () {
      expect(() => decodeFigures('{}'), throwsFormatException);
      expect(() => decodeFigures('not json'), throwsFormatException);
    });

    test('rejects non-object figure entries', () {
      expect(() => decodeFigures(jsonEncode([1, 2])), throwsFormatException);
    });

    test('empty array decodes to no figures', () {
      expect(decodeFigures('[]'), isEmpty);
    });
  });
}
