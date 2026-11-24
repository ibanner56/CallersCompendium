// A dance's text is parsed only into its own form's calls (Hudson,
// 24 November 2026: "we should not parse out figures from the wrong taxonomy -
// we need to match the selected dance type"). Contra's grammar reads a
// square's line into contra's calls, so until squares have a grammar of their
// own (ADR-007 phase 3) such a line stays custom: in free-text entry and in the
// re-read of import-gap lines.
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

final _square = shippedTaxonomies.forForm(DanceForm.square);
final _contra = shippedTaxonomies.forForm(DanceForm.contra);

Figure _gap(String text, {int beats = 8}) =>
    customFigure(text, beats: beats, origin: CustomOrigin.importGap);

void main() {
  group('figureFitsForm', () {
    test("each form's own moves fit only it", () {
      final swing = Figure(move: 'swing');
      final sqSwing = Figure(move: 'sq_swing');
      final ecdSet = Figure(move: 'ecd_set');
      expect(figureFitsForm(swing, DanceForm.contra), isTrue);
      expect(figureFitsForm(swing, DanceForm.square), isFalse);
      expect(figureFitsForm(swing, DanceForm.ecd), isFalse);
      expect(figureFitsForm(sqSwing, DanceForm.square), isTrue);
      expect(figureFitsForm(sqSwing, DanceForm.contra), isFalse);
      expect(figureFitsForm(ecdSet, DanceForm.ecd), isTrue);
      expect(figureFitsForm(ecdSet, DanceForm.square), isFalse);
    });

    test('a custom line fits every form, and a stand still a square too', () {
      for (final form in DanceForm.values) {
        expect(figureFitsForm(_gap('zoom'), form), isTrue, reason: '$form');
      }
      final standStill = testFigure(move: standStillMove);
      expect(figureFitsForm(standStill, DanceForm.square), isTrue);
      expect(figureFitsForm(standStill, DanceForm.contra), isTrue);
      expect(figureFitsForm(standStill, DanceForm.ecd), isFalse);
    });

    test('a container fits when every figure in it does', () {
      Figure group(Figure second) => Figure.sequence(
        figures: [
          Figure(move: 'sq_forward_and_back', params: const {'beats': 8}),
          second,
        ],
        beats: 16,
      );
      expect(
        figureFitsForm(
          group(Figure(move: 'sq_swing', params: const {'beats': 8})),
          DanceForm.square,
        ),
        isTrue,
      );
      expect(
        figureFitsForm(
          group(Figure(move: 'swing', params: const {'beats': 8})),
          DanceForm.square,
        ),
        isFalse,
      );
    });
  });

  group('free-text entry', () {
    test("a square's line that only contra's grammar reads stays custom, "
        'with its count', () {
      final read = parseFreeTextFigureEntry(
        'swing your partner (8)',
        taxonomy: _square,
      );
      expect(read.single.isCustom, isTrue);
      expect(read.single.params['text'], 'swing your partner (8)');
      expect(read.single.beats, 8);
      expect(read.single.customOrigin, CustomOrigin.importGap);
      // A `;` line too.
      final clauses = parseFreeTextFigureEntry(
        'box the gnat; swing',
        taxonomy: _square,
      );
      expect(clauses.single.isCustom, isTrue);
    });

    test('contra reads the same line as ever', () {
      expect(
        parseFreeTextFigureEntry(
          'swing your partner (8)',
          taxonomy: _contra,
        ).single.move,
        'swing',
      );
    });
  });

  group('the re-read of import-gap lines', () {
    test("leaves a square's lines that only contra's grammar reads, inside "
        'containers too', () {
      final figures = [
        _gap('box the gnat'),
        Figure.sequence(
          figures: [
            _gap('square through two'),
            Figure(move: 'sq_swing', params: const {'beats': 8}),
          ],
          beats: 16,
        ),
      ];
      final outcome = reparseImportGapFigures(figures, taxonomy: _square);
      expect(outcome.upgradedCount, 0);
      expect(outcome.figures, same(figures));
    });

    test('upgrades the same lines in a contra dance', () {
      final outcome = reparseImportGapFigures([
        _gap('box the gnat'),
      ], taxonomy: _contra);
      expect(outcome.upgradedCount, 1);
      expect(outcome.figures.single.move, 'box_the_gnat');
    });
  });
}
