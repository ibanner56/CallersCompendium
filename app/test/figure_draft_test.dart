import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FigureDraft.toFigure customOrigin', () {
    test('a manually created custom commits as userEntered', () {
      final draft = FigureDraft(move: customMove, params: {'text': 'my call'});
      expect(draft.toFigure()!.customOrigin, CustomOrigin.userEntered);
    });

    test('editing an importGap custom in the editor takes ownership '
        '(commits as userEntered)', () {
      final gap = customFigure(
        'kept verbatim',
        beats: 8,
        origin: CustomOrigin.importGap,
      );
      expect(gap.customOrigin, CustomOrigin.importGap);

      // Loading it into the editor and committing = taking ownership.
      final draft = FigureDraft.fromFigure(gap);
      expect(draft.toFigure()!.customOrigin, CustomOrigin.userEntered);
    });

    test('a structured figure is unaffected (userEntered)', () {
      final draft = FigureDraft.fromFigure(
        Figure(move: 'swing', params: const {'beats': 8}),
      );
      expect(draft.toFigure()!.customOrigin, CustomOrigin.userEntered);
    });
  });

  group('FigureDraft.toFigure assumedSubject (#460)', () {
    test('defaults to false for a freshly built draft', () {
      final draft = FigureDraft(move: 'swing', params: {'who': 'partners'});
      expect(draft.assumedSubject, isFalse);
      expect(draft.toFigure()!.assumedSubject, isFalse);
    });

    test('fromFigure → toFigure preserves an assumed subject', () {
      // Merely opening and saving an imported dance must NOT launder off the
      // provenance marker (unlike customOrigin, which is user-owned on edit).
      final imported = Figure(
        move: 'allemande',
        params: const {'who': 'neighbors', 'hand': 'left'},
        assumedSubject: true,
      );
      final draft = FigureDraft.fromFigure(imported);
      expect(draft.assumedSubject, isTrue);
      expect(draft.toFigure()!.assumedSubject, isTrue);
    });

    test('a stated subject round-trips as not assumed', () {
      final draft = FigureDraft.fromFigure(
        Figure(move: 'swing', params: const {'who': 'partners'}),
      );
      expect(draft.assumedSubject, isFalse);
      expect(draft.toFigure()!.assumedSubject, isFalse);
    });
  });

  group('FigureDraft.clone (#460)', () {
    test('preserves the assumed-subject marker and other fields', () {
      final source = FigureDraft(
        move: 'allemande',
        params: {'who': 'neighbors', 'hand': 'left', 'beats': 8},
        note: 'from CallersBox',
        progression: true,
        beatsTouched: true,
        assumedSubject: true,
      );
      final copy = source.clone();

      // Provenance + ownership flags survive the clone (the #460 bug lost these).
      expect(copy.assumedSubject, isTrue);
      expect(copy.beatsTouched, isTrue);
      expect(copy.move, 'allemande');
      expect(copy.note, 'from CallersBox');
      expect(copy.progression, isTrue);
      expect(copy.params, source.params);
      expect(copy.toFigure()!.assumedSubject, isTrue);
    });

    test('gives the copy a fresh id and an independent params map', () {
      final source = FigureDraft(
        move: 'swing',
        params: {'who': 'partners'},
        assumedSubject: true,
      );
      final copy = source.clone();
      expect(copy.id, isNot(source.id));
      // Deep copy: mutating the copy must not bleed into the source.
      copy.params['who'] = 'neighbors';
      expect(source.params['who'], 'partners');
    });

    test('a stated subject clones as not assumed', () {
      final copy = FigureDraft(
        move: 'swing',
        params: {'who': 'partners'},
      ).clone();
      expect(copy.assumedSubject, isFalse);
      expect(copy.toFigure()!.assumedSubject, isFalse);
    });
  });
}
