import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/widgets/figure_table.dart';
import 'package:compendium_app/src/widgets/import_gap_badge.dart';
import '../support/l10n_harness.dart';

Future<void> _pump(WidgetTester tester, List<Figure> figures) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: FigureTable(
          figures: figures,
          phraseStructure: PhraseStructure.parse(''),
          renderer: FigureRenderer(contraTaxonomy),
          dialect: Dialect.larksRobins,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the import-gap badge only for importGap customs', (
    tester,
  ) async {
    await _pump(tester, [
      customFigure(
        'kept verbatim',
        beats: 8,
        origin: CustomOrigin.importGap,
      ), // importGap
      Figure(move: customMove, params: const {'text': 'hand-written'}),
      Figure(move: 'swing', params: const {'beats': 8}),
    ]);

    // Exactly one badge, for the single importGap custom.
    expect(find.byType(ImportGapBadge), findsOneWidget);
    // The row folds the explanation into its Semantics label (the row uses
    // excludeSemantics, so the accessible signal lives on the row, not the
    // glyph's own — excluded — node).
    expect(find.bySemanticsLabel(RegExp('parse this call')), findsOneWidget);
  });

  testWidgets('shows no badge for userEntered customs or structured figures', (
    tester,
  ) async {
    await _pump(tester, [
      Figure(move: customMove, params: const {'text': 'hand-written'}),
      Figure(move: 'swing', params: const {'beats': 8}),
    ]);

    expect(find.byType(ImportGapBadge), findsNothing);
    expect(find.bySemanticsLabel(RegExp('parse this call')), findsNothing);
  });

  testWidgets('tapping the badge opens the explanation dialog', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pump(tester, [
      customFigure('kept verbatim', beats: 8, origin: CustomOrigin.importGap),
    ]);

    await tester.tap(find.byType(ImportGapBadge));
    await tester.pumpAndSettle();

    expect(find.text(l10n.importGapDialogTitle), findsOneWidget);
    expect(find.text(l10n.importGapMessage), findsWidgets);
  });
}
