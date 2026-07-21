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
      final gap = customFigure('kept verbatim', beats: 8);
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
}
