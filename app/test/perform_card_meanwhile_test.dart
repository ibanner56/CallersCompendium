import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';

/// Perform-view display of a `meanwhile` container figure (#594, layered on
/// the #590 core model): both concurrent sides render together on **one**
/// card row, joined with "while", on the container's single shared beat span
/// — never split into two rows and never double-counted.
final _renderer = FigureRenderer(contraTaxonomy);
final _now = DateTime.utc(2026, 1, 1);

Future<void> _pump(WidgetTester tester, List<Figure> figures) async {
  final dance = Dance(
    id: 'd1',
    title: 'Test Dance',
    figures: figures,
    createdAt: _now,
    updatedAt: _now,
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: PerformCard(
          dance: dance,
          renderer: _renderer,
          dialect: Dialect.larksRobins,
          textScale: 1.0,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final sideA = Figure(
    move: 'allemande',
    params: const {'who': 'role1s', 'hand': 'left', 'turn': 1.5},
  );
  final sideB = Figure(
    move: 'orbit',
    params: const {'who': 'role2s', 'turn': 'clockwise', 'amount': 0.5},
  );

  testWidgets('shows both concurrent sides joined by "while" on one card row', (
    tester,
  ) async {
    final container = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
    await _pump(tester, [container]);

    final expected = _renderer.renderSummary(container, Dialect.larksRobins);
    expect(expected, contains(' while '));
    expect(find.text(expected), findsOneWidget);
  });

  testWidgets(
    'shows exactly one beat label for the whole container (shared count, '
    'not double-counted)',
    (tester) async {
      final container = Figure.meanwhile(figures: [sideA, sideB], beats: 8);
      await _pump(tester, [container]);

      expect(find.textContaining('8 beats'), findsOneWidget);
      expect(find.textContaining('16 beats'), findsNothing);
    },
  );
}
