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
        Figure(
          move: 'swing',
          params: const {'beats': 8},
          wordingOverride: 'Use the other hand.',
        ),
      );
      expect(draft.toFigure()!.customOrigin, CustomOrigin.userEntered);
      expect(draft.wordingOverride, 'Use the other hand.');
      expect(draft.toFigure()!.wordingOverride, 'Use the other hand.');
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

  group('FigureDraft meanwhile round-trip (#590/#593)', () {
    test(
      'fromFigure seeds meanwhileSides and shared beats from a container',
      () {
        final container = Figure.meanwhile(
          figures: [
            Figure(move: 'swing', params: const {'who': 'partners'}),
            Figure(move: 'allemande', params: const {'who': 'neighbors'}),
          ],
          beats: 16,
        );
        final draft = FigureDraft.fromFigure(container);
        expect(draft.isMeanwhileGroup, isTrue);
        expect(draft.meanwhileSides, hasLength(2));
        expect(draft.meanwhileSides![0].move, 'swing');
        expect(draft.meanwhileSides![1].move, 'allemande');
        expect(draft.beats, 16);
        // Sides are always flat — never themselves groups.
        expect(draft.meanwhileSides![0].isMeanwhileGroup, isFalse);
        expect(draft.meanwhileSides![1].isMeanwhileGroup, isFalse);
      },
    );

    test('toFigure rebuilds an equivalent Figure.meanwhile container', () {
      final draft = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing', params: {'who': 'partners'}),
          FigureDraft(move: 'allemande', params: {'who': 'neighbors'}),
        ],
      );
      draft.params['beats'] = 16;
      final figure = draft.toFigure()!;
      expect(figure.isMeanwhile, isTrue);
      expect(figure.beats, 16);
      expect(figure.subFigures, hasLength(2));
      expect(figure.subFigures[0].move, 'swing');
      expect(figure.subFigures[1].move, 'allemande');
    });

    test('a fully round-tripped meanwhile is unchanged', () {
      final original = Figure.meanwhile(
        figures: [
          Figure(move: 'swing', params: const {'who': 'partners', 'beats': 8}),
          Figure(
            move: 'allemande',
            params: const {'who': 'neighbors', 'hand': 'left'},
          ),
        ],
        beats: 16,
        note: 'watch your spacing',
      );
      final roundTripped = FigureDraft.fromFigure(original).toFigure();
      expect(roundTripped, original);
    });

    test('toFigure returns null while fewer than 2 sides are ready', () {
      final draft = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing'),
          FigureDraft(),
        ],
      );
      draft.params['beats'] = 8;
      expect(draft.toFigure(), isNull);
    });

    test('preserves an in-progress side (no move, but a note) as a best-effort '
        'custom figure rather than silently dropping it (#679 review)', () {
      final inProgress = FigureDraft()..note = 'still deciding the move';
      final draft = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing', params: {'who': 'partners'}),
          FigureDraft(move: 'allemande', params: {'who': 'neighbors'}),
          inProgress,
        ],
      );
      draft.params['beats'] = 16;
      final figure = draft.toFigure()!;
      expect(figure.subFigures, hasLength(3));
      final third = figure.subFigures[2];
      expect(third.isCustom, isTrue);
      expect(third.note, 'still deciding the move');
    });

    test('still drops a genuinely untouched blank side once at least 2 sides '
        'are ready (#679 review)', () {
      final draft = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing'),
          FigureDraft(move: 'allemande'),
          FigureDraft(), // freshly added placeholder — nothing entered.
        ],
      );
      draft.params['beats'] = 16;
      final figure = draft.toFigure()!;
      expect(figure.subFigures, hasLength(2));
    });

    test('clone deep-copies meanwhileSides with fresh ids', () {
      final source = FigureDraft(
        meanwhileSides: [
          FigureDraft(move: 'swing', params: {'who': 'partners'}),
          FigureDraft(move: 'allemande', params: {'who': 'neighbors'}),
        ],
      );
      source.params['beats'] = 16;
      final copy = source.clone();
      expect(copy.id, isNot(source.id));
      expect(copy.meanwhileSides![0].id, isNot(source.meanwhileSides![0].id));
      copy.meanwhileSides![0].params['who'] = 'someone else';
      expect(source.meanwhileSides![0].params['who'], 'partners');
    });

    test('defensively clamps an over-cap side list rather than throwing', () {
      final draft = FigureDraft(
        meanwhileSides: [
          for (var i = 0; i < 8; i++) FigureDraft(move: 'swing'),
        ],
      );
      draft.params['beats'] = 8;
      final figure = draft.toFigure()!;
      expect(figure.subFigures, hasLength(kMaxMeanwhileSides));
    });
  });
}
