import 'dart:async';

import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/data/user_figures_scope.dart';
import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/widgets/advanced_query_builder.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/screen_size.dart';
import '../support/test_repositories.dart';

/// The query builder's "has figure" row and the user's own figures (#1023):
/// one can be asked for by name, as the dance index stores a use of it.
void main() {
  UserGlossaryEntry figure(
    String id,
    String name, {
    Map<String, Object?>? payload,
  }) => UserGlossaryEntry(
    id: id,
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: name,
    definition: 'A figure.',
    description: 'Of your own.',
    payload:
        payload ??
        {'template': '{move}', 'defaultBeats': 8, 'params': const <Object?>[]},
    createdAt: DateTime.utc(2026, 10, 16),
  );

  Future<BuilderFigure> pump(
    WidgetTester tester, {
    required List<UserGlossaryEntry> entries,
    bool customFigures = true,
    BuilderFigure? row,
  }) async {
    final repos = openTestRepositories();
    for (final entry in entries) {
      await tester.runAsync(() => repos.userGlossary.upsert(entry));
    }
    final userFigures = UserFiguresController(repos.userGlossary);
    addTearDown(userFigures.dispose);
    unawaited(userFigures.start());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final glossary = ValueNotifier(true);
    final custom = ValueNotifier(customFigures);
    addTearDown(glossary.dispose);
    addTearDown(custom.dispose);
    final figure = row ?? BuilderFigure();
    final root = BuilderGroup(children: [figure]);
    await setScreenSize(tester, const Size(900, 1600));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: ShowGlossaryScope(
          notifier: glossary,
          child: ShowCustomFiguresScope(
            notifier: custom,
            child: UserFiguresScope(
              controller: userFigures,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: StatefulBuilder(
                    builder: (context, setState) => AdvancedQueryBuilder(
                      root: root,
                      taxonomy: contraTaxonomy,
                      dialect: Dialect.larksRobins,
                      sectionLabels: const [],
                      tags: const [],
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return figure;
  }

  Future<void> type(WidgetTester tester, BuilderFigure row, String text) async {
    await tester.enterText(
      find.byKey(ValueKey('has-figure-${row.id}-input')),
      text,
    );
    await tester.pumpAndSettle();
  }

  Finder option(BuilderFigure row, String suffix) =>
      find.byKey(ValueKey('has-figure-${row.id}-option-$suffix'));

  testWidgets('one of your figures is offered first, marked as yours, and '
      'picking it asks for its uses', (tester) async {
    final row = await pump(
      tester,
      entries: [figure('zoom-id', 'role1s swoop')],
    );
    // "sw" also finds the built-in swings: yours is listed before them.
    await type(tester, row, 'sw');

    final mine = option(row, 'userFigure:zoom-id');
    expect(mine, findsOneWidget);
    expect(option(row, 'swing'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.byType(ListTile).first).key,
      ValueKey('has-figure-${row.id}-option-userFigure:zoom-id'),
    );
    expect(
      find.descendant(of: mine, matching: find.text('larks swoop')),
      findsOneWidget,
      reason: 'named in the dialect',
    );
    final marker = tester.widget<Icon>(
      find.descendant(of: mine, matching: find.byType(Icon)),
    );
    expect(marker.semanticLabel, 'Custom', reason: 'marked in words');

    await tester.tap(mine);
    await tester.pumpAndSettle();
    expect(row.move, customMove);
    expect(row.params, {userFigureRefKey: 'zoom-id'});
    final leaf = row.toFigureQuery()!;
    expect(leaf.move, customMove);
    expect(leaf.params, {userFigureRefKey: 'zoom-id'});
  });

  testWidgets('a row asking for one of your figures shows its name', (
    tester,
  ) async {
    final row = BuilderFigure(
      move: customMove,
      params: {userFigureRefKey: 'zoom-id'},
    );
    await pump(
      tester,
      entries: [figure('zoom-id', 'role1s swoop')],
      row: row,
      customFigures: false,
    );
    final field = tester.widget<TextField>(
      find.byKey(ValueKey('has-figure-${row.id}-input')),
    );
    expect(field.controller!.text, 'larks swoop');
  });

  testWidgets('your figures are not offered while Custom Figures is off', (
    tester,
  ) async {
    final row = await pump(
      tester,
      entries: [figure('zoom-id', 'swoop')],
      customFigures: false,
    );
    await type(tester, row, 'swo');
    expect(option(row, 'userFigure:zoom-id'), findsNothing);
  });

  testWidgets('a figure that no longer decodes is not offered', (tester) async {
    final row = await pump(
      tester,
      entries: [
        figure('zoom-id', 'swoop', payload: const {'template': 42}),
      ],
    );
    await type(tester, row, 'swo');
    expect(option(row, 'userFigure:zoom-id'), findsNothing);
  });

  testWidgets('picking a move after one of your figures clears its id', (
    tester,
  ) async {
    final row = BuilderFigure(
      move: customMove,
      params: {userFigureRefKey: 'zoom-id'},
    );
    await pump(tester, entries: [figure('zoom-id', 'swoop')], row: row);
    await type(tester, row, 'custom');
    await tester.tap(option(row, customMove));
    await tester.pumpAndSettle();
    expect(row.move, customMove);
    expect(row.params, isEmpty);
  });
}
