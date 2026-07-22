import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('Figure', () {
    test('defaults: current schema version, empty params, no progression', () {
      final f = Figure(move: 'swing');
      expect(f.schemaVersion, figureSchemaVersion);
      expect(f.params, isEmpty);
      expect(f.progression, isFalse);
      expect(f.note, isNull);
      expect(f.beats, 0);
    });

    test('rejects empty and whitespace-only move ids', () {
      expect(() => Figure(move: ''), throwsArgumentError);
      expect(() => Figure(move: '   '), throwsArgumentError);
    });

    test('rejects negative and non-integer beats', () {
      expect(
        () => Figure(move: 'swing', params: {'beats': -1}),
        throwsArgumentError,
      );
      expect(
        () => Figure(move: 'swing', params: {'beats': 8.5}),
        throwsArgumentError,
      );
      expect(
        () => Figure(move: 'swing', params: {'beats': '8'}),
        throwsArgumentError,
      );
    });

    test('accepts zero beats (formation labels)', () {
      expect(Figure(move: 'form_long_waves', params: {'beats': 0}).beats, 0);
    });

    test('params are unmodifiable and defensively copied', () {
      final source = <String, Object?>{'who': 'partners', 'beats': 16};
      final f = Figure(move: 'swing', params: source);
      source['who'] = 'neighbors';
      expect(f.params['who'], 'partners');
      expect(() => f.params['x'] = 1, throwsUnsupportedError);
    });

    test('isCustom only for the custom move', () {
      expect(
        Figure(move: customMove, params: {'text': 'weave'}).isCustom,
        isTrue,
      );
      expect(Figure(move: 'swing').isCustom, isFalse);
    });

    test('value equality is deep over params', () {
      Figure make() => Figure(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'right', 'turn': 1.5},
      );
      expect(make(), equals(make()));
      expect(make().hashCode, make().hashCode);
      expect(make(), isNot(equals(make().copyWith(params: {'hand': 'left'}))));
      expect(
        Figure(move: 'swing'),
        isNot(equals(Figure(move: 'swing', progression: true))),
      );
    });

    test('copyWith preserves untouched fields and applies changes', () {
      final f = Figure(
        move: 'swing',
        params: {'who': 'partners', 'beats': 16},
        note: 'scoop',
        progression: true,
      );
      final g = f.copyWith(note: 'gently');
      expect(g.move, 'swing');
      expect(g.params, f.params);
      expect(g.progression, isTrue);
      expect(g.note, 'gently');
    });

    group('customOrigin', () {
      test('defaults to userEntered', () {
        expect(Figure(move: 'swing').customOrigin, CustomOrigin.userEntered);
        expect(
          Figure(move: customMove, params: {'text': 'x'}).customOrigin,
          CustomOrigin.userEntered,
        );
      });

      test('copyWith sets and overrides the origin', () {
        final f = Figure(move: customMove, params: {'text': 'x'});
        final g = f.copyWith(customOrigin: CustomOrigin.importGap);
        expect(g.customOrigin, CustomOrigin.importGap);
        // Untouched copyWith preserves the origin.
        expect(g.copyWith(note: 'hi').customOrigin, CustomOrigin.importGap);
      });

      test('== and hashCode distinguish origins', () {
        final user = Figure(move: customMove, params: {'text': 'x'});
        final gap = user.copyWith(customOrigin: CustomOrigin.importGap);
        expect(user, isNot(equals(gap)));
        expect(user.hashCode, isNot(equals(gap.hashCode)));
      });
    });

    group('assumedSubject', () {
      test('defaults to false', () {
        expect(Figure(move: 'swing').assumedSubject, isFalse);
        expect(
          Figure(move: 'balance', params: {'who': 'neighbors'}).assumedSubject,
          isFalse,
        );
      });

      test('copyWith sets and overrides the flag', () {
        final stated = Figure(move: 'swing', params: {'who': 'neighbors'});
        final assumed = stated.copyWith(assumedSubject: true);
        expect(assumed.assumedSubject, isTrue);
        // An untouched copyWith preserves the assumed flag (e.g. the
        // reparse-custom flow copyWith(note:) must not launder provenance).
        expect(assumed.copyWith(note: 'hi').assumedSubject, isTrue);
        // It can be cleared back to false explicitly.
        expect(assumed.copyWith(assumedSubject: false).assumedSubject, isFalse);
      });

      test('== and hashCode distinguish an assumed from a stated subject', () {
        final stated = Figure(move: 'swing', params: {'who': 'partners'});
        final assumed = stated.copyWith(assumedSubject: true);
        expect(stated, isNot(equals(assumed)));
        expect(stated.hashCode, isNot(equals(assumed.hashCode)));
      });
    });
  });
}
