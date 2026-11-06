import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/widgets/by_phrase_panel.dart';
import '../support/l10n_harness.dart';
import '../support/screen_size.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ByPhraseSelections selections,
  List<String> sectionLabels = const ['A1', 'A2', 'B1', 'B2'],
  // Only set when a test needs to exercise ResponsiveAutocomplete's narrow
  // layout; unset (default) tests rely on the default test window (800x600),
  // already above the compact breakpoints (600/480), so MoveTypeAheadField's
  // wide inline overlay behaves the same as before its ResponsiveAutocomplete
  // migration.
  Size? screenSize,
  required VoidCallback onChanged,
}) async {
  if (screenSize != null) {
    await setScreenSize(tester, screenSize);
  }
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: ByPhrasePanel(
              selections: selections,
              taxonomy: contraTaxonomy,
              sectionLabels: sectionLabels,
              onChanged: () {
                onChanged();
                setState(() {});
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ---------------------------------------------------------------------
  // Baseline coverage (this widget had none before the ResponsiveAutocomplete
  // migration added its first ValueKeys via MoveTypeAheadField.fieldKey).
  // ---------------------------------------------------------------------

  testWidgets('wide layout: adding a "match" move for A1 updates selections '
      'and shows a chip', (tester) async {
    final selections = ByPhraseSelections();
    var changes = 0;
    await _pump(tester, selections: selections, onChanged: () => changes++);

    final fieldKey = const ValueKey('match-A1-input');
    await tester.enterText(find.byKey(fieldKey), 'swing');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('match-A1-option-swing')));
    await tester.pumpAndSettle();

    expect(selections.match['A1'], ['swing']);
    expect(changes, 1);
    expect(find.byKey(const ValueKey('match-A1-chip-swing')), findsOneWidget);
  });

  testWidgets(
    'wide layout: "exclude" and "match" fields for the same phrase are '
    'independent',
    (tester) async {
      final selections = ByPhraseSelections();
      await _pump(tester, selections: selections, onChanged: () {});

      await tester.enterText(
        find.byKey(const ValueKey('match-A1-input')),
        'swing',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('match-A1-option-swing')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('exclude-A1-input')),
        'chain',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('exclude-A1-option-chain')));
      await tester.pumpAndSettle();

      expect(selections.match['A1'], ['swing']);
      expect(selections.exclude['A1'], ['chain']);
    },
  );

  // ---------------------------------------------------------------------
  // Narrow-mode coverage (#716): MoveTypeAheadField's new fieldKey threads
  // straight through to ResponsiveAutocomplete's keyboard-safe sheet.
  // ---------------------------------------------------------------------

  testWidgets(
    'narrow layout: adding a "match" move for A1 via the keyboard-safe '
    'sheet updates selections and closes the sheet, with the option fully '
    'visible above a simulated keyboard inset',
    (tester) async {
      final selections = ByPhraseSelections();
      var changes = 0;
      await _pump(
        tester,
        selections: selections,
        screenSize: const Size(360, 720),
        onChanged: () => changes++,
      );

      final fieldKey = const ValueKey('match-A1-input');
      await tester.tap(find.byKey(fieldKey), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      // Simulate a software keyboard inset, as issue #716 describes.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(fieldKey), 'swing');
      await tester.pumpAndSettle();

      final option = find.byKey(const ValueKey('match-A1-option-swing'));
      expect(option, findsOneWidget);
      final optionRect = tester.getRect(option);
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(optionRect.bottom, lessThanOrEqualTo(screenHeight - 300));

      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(selections.match['A1'], ['swing']);
      expect(changes, 1);
      // Picking always closes the sheet (owner's Q1 decision, uniform
      // across all seven call sites).
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(const ValueKey('match-A1-chip-swing')), findsOneWidget);
    },
  );
}
