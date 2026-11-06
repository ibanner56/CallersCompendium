import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/widgets/advanced_query_builder.dart';
import 'package:compendium_app/src/widgets/by_phrase_panel.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/screen_size.dart';

/// FIND-4: Advanced's "has figure" move picker and By phrase offer the same
/// suggestions as the dance editor's move entry, including the active
/// dialect's own move names.
void main() {
  final buzz = Dialect(name: 'Buzz', moves: {'swing': 'buzz'});

  Future<void> pumpHost(
    WidgetTester tester,
    Widget child, {
    double textScale = 1.0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: c!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Advanced "has figure" row', () {
    Future<BuilderFigure> pumpRow(
      WidgetTester tester, {
      Dialect? dialect,
      double textScale = 1.0,
    }) async {
      final row = BuilderFigure();
      await pumpHost(
        tester,
        AdvancedQueryBuilder(
          root: BuilderGroup(children: [row]),
          taxonomy: contraTaxonomy,
          dialect: dialect ?? Dialect.canonical,
          sectionLabels: const [],
          tags: const [],
          onChanged: () {},
        ),
        textScale: textScale,
      );
      return row;
    }

    testWidgets('typing a dialect move name offers it and stores the canonical '
        'id', (tester) async {
      final row = await pumpRow(tester, dialect: buzz);
      await tester.enterText(
        find.byKey(ValueKey('has-figure-${row.id}-input')),
        'buzz',
      );
      await tester.pumpAndSettle();
      final option = find.byKey(ValueKey('has-figure-${row.id}-option-swing'));
      expect(option, findsOneWidget);
      expect(
        find.descendant(of: option, matching: find.text('buzz')),
        findsOneWidget,
      );
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(row.move, 'swing');
    });

    testWidgets('with no dialect, a dialect-only name finds nothing', (
      tester,
    ) async {
      final row = await pumpRow(tester);
      await tester.enterText(
        find.byKey(ValueKey('has-figure-${row.id}-input')),
        'buzz',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('has-figure-${row.id}-option-swing')),
        findsNothing,
      );
    });

    testWidgets('at 360 dp and 200% text the dialect option is reachable', (
      tester,
    ) async {
      await setScreenSize(tester, const Size(360, 720));
      final row = await pumpRow(tester, dialect: buzz, textScale: 2.0);
      await tester.tap(
        find.byKey(ValueKey('has-figure-${row.id}-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ValueKey('has-figure-${row.id}-input')),
        'buzz',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('has-figure-${row.id}-option-swing')),
      );
      await tester.pumpAndSettle();
      expect(row.move, 'swing');
      expect(tester.takeException(), isNull);
    });
  });

  group('By phrase', () {
    testWidgets('typing a dialect move name offers it; the chip reads in the '
        'dialect and the selection is the canonical id', (tester) async {
      final selections = ByPhraseSelections();
      await pumpHost(
        tester,
        StatefulBuilder(
          builder: (context, setState) => ByPhrasePanel(
            selections: selections,
            taxonomy: contraTaxonomy,
            dialect: buzz,
            sectionLabels: const ['A1', 'A2', 'B1', 'B2'],
            onChanged: () => setState(() {}),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('match-A1-input')),
        'buzz',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('match-A1-option-swing')));
      await tester.pumpAndSettle();
      expect(selections.match['A1'], ['swing']);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('match-A1-chip-swing')),
          matching: find.text('buzz'),
        ),
        findsOneWidget,
      );
    });
  });
}
