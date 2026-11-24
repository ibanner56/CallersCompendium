import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';

/// Perform shows a free-form square (ADR-007 §8.1) with no phrase headings:
/// its figures follow no phrasing, so there is no A1 or A2 to call from.
final _renderer = FigureRenderer(shippedTaxonomies.anyForm);
final _now = DateTime.utc(2026, 1, 1);

Future<void> _pump(WidgetTester tester, {required SquareKind kind}) async {
  final dance = Dance(
    id: 'd1',
    title: 'Patter',
    form: DanceForm.square,
    squareKind: kind,
    figures: [
      customFigure('Allemande left your corner', beats: 12),
      customFigure('Grand right and left', beats: 8),
    ],
    createdAt: _now,
    updatedAt: _now,
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PerformCard(
            dance: dance,
            renderer: _renderer,
            dialect: Dialect.larksRobins,
            textScale: 1.0,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a phrased square heads its figures with their phrase', (
    tester,
  ) async {
    await _pump(tester, kind: SquareKind.main);
    expect(find.text('A1'), findsOneWidget);
  });

  testWidgets('a free-form square has no phrase headings', (tester) async {
    await _pump(tester, kind: SquareKind.patter);
    expect(find.text('A1'), findsNothing);
    expect(find.textContaining('Grand right and left'), findsOneWidget);
  });
}
