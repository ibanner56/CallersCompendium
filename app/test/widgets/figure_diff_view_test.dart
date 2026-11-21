import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/figure_diff_view.dart';

import '../support/l10n_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  FigureDiffResult result, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(body: FigureDiffView(result: result)),
    ),
  );
}

void main() {
  testWidgets('colors come from the palette and only tint the glyph; a '
      'removed line is struck through', (tester) async {
    const result = FigureDiffResult(
      identical: false,
      entries: [
        FigureDiffEntry(
          kind: FigureDiffKind.removed,
          displayText: 'Circle left once around',
          phraseLabel: '',
        ),
        FigureDiffEntry(
          kind: FigureDiffKind.added,
          displayText: 'Circle right once around',
          phraseLabel: '',
        ),
      ],
      truncated: false,
      omittedCount: 0,
    );
    final theme = AppTheme.dark;
    await _pump(tester, result, theme: theme);
    final scheme = theme.colorScheme;
    final bodyColor = Theme.of(
      tester.element(find.byType(FigureDiffView)),
    ).textTheme.bodyMedium?.color;

    expect(tester.widget<Text>(find.text('+')).style?.color, scheme.primary);
    expect(tester.widget<Text>(find.text('\u2212')).style?.color, scheme.error);

    final added = tester.widget<Text>(find.text('Circle right once around'));
    final removed = tester.widget<Text>(find.text('Circle left once around'));
    expect(added.style?.color, bodyColor);
    expect(removed.style?.color, bodyColor);
    expect(added.style?.decoration, isNot(TextDecoration.lineThrough));
    expect(removed.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('renders added and removed lines with their glyphs', (
    tester,
  ) async {
    const result = FigureDiffResult(
      identical: false,
      entries: [
        FigureDiffEntry(
          kind: FigureDiffKind.removed,
          displayText: 'Circle left once around',
          phraseLabel: '',
        ),
        FigureDiffEntry(
          kind: FigureDiffKind.added,
          displayText: 'Circle right once around',
          phraseLabel: '',
        ),
      ],
      truncated: false,
      omittedCount: 0,
    );
    await _pump(tester, result);

    expect(find.text('Circle left once around'), findsOneWidget);
    expect(find.text('Circle right once around'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);
    expect(find.text('\u2212'), findsOneWidget);
    // Color is never the only signal — a semantic label carries the
    // added/removed distinction too (accessibility).
    final semanticsLabels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((s) => s.properties.label)
        .toList();
    expect(
      semanticsLabels,
      containsAll(<String>[
        'Added: Circle right once around',
        'Removed: Circle left once around',
      ]),
    );
  });

  testWidgets('groups entries under their phrase label heading', (
    tester,
  ) async {
    const result = FigureDiffResult(
      identical: false,
      entries: [
        FigureDiffEntry(
          kind: FigureDiffKind.added,
          displayText: 'Neighbor swing',
          phraseLabel: 'A1',
        ),
        FigureDiffEntry(
          kind: FigureDiffKind.added,
          displayText: 'Partner swing',
          phraseLabel: 'B1',
        ),
      ],
      truncated: false,
      omittedCount: 0,
    );
    await _pump(tester, result);

    expect(find.text('A1'), findsOneWidget);
    expect(find.text('B1'), findsOneWidget);
    expect(find.text('Neighbor swing'), findsOneWidget);
    expect(find.text('Partner swing'), findsOneWidget);
  });

  testWidgets('shows a truncation footer with the omitted count', (
    tester,
  ) async {
    const result = FigureDiffResult(
      identical: false,
      entries: [
        FigureDiffEntry(
          kind: FigureDiffKind.added,
          displayText: 'Line one',
          phraseLabel: '',
        ),
      ],
      truncated: true,
      omittedCount: 42,
    );
    await _pump(tester, result);

    expect(find.byKey(const ValueKey('figure-diff-truncated')), findsOneWidget);
    expect(find.textContaining('42'), findsOneWidget);
  });

  testWidgets('renders nothing but the (empty) column when there are no '
      'entries and nothing was truncated', (tester) async {
    const result = FigureDiffResult(
      identical: false,
      entries: [],
      truncated: false,
      omittedCount: 0,
    );
    await _pump(tester, result);

    expect(find.byKey(const ValueKey('figure-diff-view')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-diff-truncated')), findsNothing);
  });
}
