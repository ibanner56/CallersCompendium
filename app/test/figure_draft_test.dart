import 'package:compendium_app/src/editor/figure_draft.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FigureDraft.toFigure customOrigin', () {
    test('a manually created custom commits as userEntered', () {
      final draft = FigureDraft(move: customMove, params: {'text': 'my call'});
      expect(draft.toFigure()!.customOrigin, CustomOrigin.userEntered);
    });

    test('an importGap custom round-trips through the editor preserving its '
        'origin (stays reparse-eligible)', () {
      final gap = customFigure(
        'kept verbatim',
        beats: 8,
        origin: CustomOrigin.importGap,
      );
      expect(gap.customOrigin, CustomOrigin.importGap);

      // Merely loading a parser-gap custom into a draft and committing it back
      // (an open/save round-trip, or the #419 free-text insert path) must NOT
      // launder off the importGap marker — otherwise a locally-typed or
      // imported gap would silently lose its #398 badge and reparse
      // eligibility the moment the dance is saved. Ownership is only taken when
      // the user makes an explicit authoring choice in the structured editor
      // (picking a move or re-authoring the custom), which resets it to
      // userEntered (covered in figure_list_editor_test.dart).
      final draft = FigureDraft.fromFigure(gap);
      expect(draft.toFigure()!.customOrigin, CustomOrigin.importGap);
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
      // provenance marker — the same open/save-preserving contract now applies
      // to customOrigin too (see the importGap round-trip test above); both are
      // reset only on an explicit authoring choice.
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
