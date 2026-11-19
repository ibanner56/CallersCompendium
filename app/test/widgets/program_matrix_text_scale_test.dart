import 'package:compendium_app/src/widgets/program_matrix_table.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// The wide matrix at 1× and 2× text (WCAG 1.4.4 Resize Text, 1.4.10
/// Reflow): rows and the header strip grow with the text, the hide-column
/// button never covers a move name, and a clipped title or move name can be
/// read in full with a long-press.
void main() {
  final now = DateTime.utc(2026, 7, 13);

  Dance dance(String id, String title, List<Figure> figures) => Dance(
    id: id,
    title: title,
    figures: figures,
    createdAt: now,
    updatedAt: now,
    formation: const Formation(FormationShape.dupleImproper),
  );

  Future<void> pump(
    WidgetTester tester, {
    required double textScale,
    required String title,
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(1400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: ProgramMatrixTable(
            matrix: buildProgramMatrix([
              dance('d1', title, [
                testFigure(move: 'swing', params: {'beats': 16}),
                testFigure(move: 'balance', params: {'beats': 16}),
              ]),
            ]),
            taxonomy: contraTaxonomy,
            dialect: Dialect.canonical,
            onHideColumn: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Size heightOfBoxAround(WidgetTester tester, Finder text) => tester.getSize(
    find
        .ancestor(of: text, matching: find.byType(Container))
        .evaluate()
        .map((e) => find.byWidget(e.widget))
        .first,
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('rows and the header strip grow with the text at ${scale}x', (
      tester,
    ) async {
      await pump(tester, textScale: scale, title: 'Butterfly');
      expect(
        heightOfBoxAround(tester, find.text('Butterfly')).height,
        ProgramMatrixTable.rowHeight * scale,
      );
      // 48dp for the hide button, three scaled lines, and padding.
      expect(
        heightOfBoxAround(tester, find.text('partner swing')).height,
        kMinInteractiveDimension +
            ProgramMatrixTable.headerLineHeight *
                ProgramMatrixTable.headerMaxLines *
                scale +
            16,
      );
    });

    testWidgets(
      'the hide-column button does not cover a three-line move name at ${scale}x',
      (tester) async {
        await pump(tester, textScale: scale, title: 'Butterfly');
        final eye = tester.getRect(
          find.byKey(const ValueKey('program-matrix-hide-column-0')),
        );
        final label = tester.getRect(find.text('partner swing'));
        expect(
          eye.overlaps(label),
          isFalse,
          reason: 'eye $eye must sit clear of the label $label',
        );
      },
    );
  }

  testWidgets('a clipped dance title is shown in full on long-press', (
    tester,
  ) async {
    const title = 'The Extremely Long Dance Title';
    await pump(tester, textScale: 2.0, title: title);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.longPress(find.textContaining('The Extremely'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(title, findRichText: true),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a clipped move name is shown in full on long-press', (
    tester,
  ) async {
    await pump(tester, textScale: 2.0, title: 'A');
    await tester.longPress(find.textContaining('partner'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('partner swing', findRichText: true),
      ),
      findsOneWidget,
    );
  });

  testWidgets('text that fits claims no long-press', (tester) async {
    await pump(tester, textScale: 1.0, title: 'A');
    await tester.longPress(find.text('A'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
