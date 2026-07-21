import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('ParseQuality', () {
    test('empty figure list scores perfect (no penalty for stubs)', () {
      const q = ParseQuality.perfect;
      expect(q.score, 1.0);
      expect(q.isFullyCustom, isFalse);
      expect(ParseQuality.ofFigures(const []).score, 1.0);
    });

    test('all structured scores 1.0', () {
      final figures = [
        Figure(move: 'swing', params: {'beats': 16}),
        Figure(move: 'circle', params: {'beats': 8}),
      ];
      final q = ParseQuality.ofFigures(figures);
      expect(q.score, 1.0);
      expect(q.structuredFigures, 2);
      expect(q.isFullyCustom, isFalse);
    });

    test('half custom scores 0.5', () {
      final figures = [
        Figure(move: 'swing', params: {'beats': 16}),
        customFigure('give and take', beats: 8),
      ];
      final q = ParseQuality.ofFigures(figures);
      expect(q.score, 0.5);
      expect(q.customFigures, 1);
    });

    test('fully custom scores 0.0 but is valid', () {
      final figures = [
        customFigure('do the thing', beats: 8),
        customFigure('do the other thing', beats: 8),
      ];
      final q = ParseQuality.ofFigures(figures);
      expect(q.score, 0.0);
      expect(q.isFullyCustom, isTrue);
    });
  });

  group('customFigure fallback', () {
    test('preserves text in params[text] (searchable) and beats', () {
      final f = customFigure('balance the ring', beats: 8, progression: true);
      expect(f.isCustom, isTrue);
      expect(f.params['text'], 'balance the ring');
      expect(f.beats, 8);
      expect(f.progression, isTrue);
    });

    test('zero beats omits the beats param', () {
      final f = customFigure('formation note');
      expect(f.params.containsKey('beats'), isFalse);
      expect(f.beats, 0);
    });

    test('rejects negative beats', () {
      expect(() => customFigure('x', beats: -1), throwsArgumentError);
    });

    test('defaults to CustomOrigin.userEntered (safe, less-privileged)', () {
      expect(
        customFigure('mystery move').customOrigin,
        CustomOrigin.userEntered,
      );
    });

    test('stamps CustomOrigin.importGap when the caller opts in', () {
      expect(
        customFigure(
          'mystery move',
          origin: CustomOrigin.importGap,
        ).customOrigin,
        CustomOrigin.importGap,
      );
    });
  });

  group('StructuredDraft', () {
    test('derives quality from the dance figures by default', () {
      final dance = Dance(
        id: 'd1',
        title: 'Mixed',
        figures: [
          Figure(move: 'swing', params: {'beats': 16}),
          customFigure('mystery move', beats: 16),
        ],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final raw = RawRecord(source: ProvenanceSource.json, payload: '{}');
      final draft = StructuredDraft(dance: dance, raw: raw);
      expect(draft.quality.score, 0.5);
      expect(draft.issues, isEmpty);
    });

    test('a 100%-custom dance is a valid draft', () {
      final dance = Dance(
        id: 'd2',
        title: 'All Custom',
        figures: [customFigure('a'), customFigure('b')],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final raw = RawRecord(source: ProvenanceSource.json, payload: '{}');
      final draft = StructuredDraft(dance: dance, raw: raw);
      expect(draft.quality.isFullyCustom, isTrue);
      expect(draft.dance.title, 'All Custom');
    });
  });
}
