import 'dart:async';

import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/data/user_figures_scope.dart';
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
    DialectsByForm? dialects,
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
                      dialects: dialects,
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
    final leaf = row.toFigureQuery()! as FigureLeaf;
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

  group('each figure in its own form\'s dialect (#2294)', () {
    // Contra's dialect words the first role "larks"; English leaves it as the
    // canonical dialect writes it, so the two read differently.
    final contra = Dialect.larksRobins;
    final english = Dialect.canonical;
    final dialects = DialectsByForm({
      DanceForm.contra: contra,
      DanceForm.ecd: english,
    });
    final renderer = FigureRenderer(contraTaxonomy);
    String inContra(String text) => renderer.renderFreeText(text, contra);
    String inEnglish(String text) => renderer.renderFreeText(text, english);

    Map<String, Object?> madeFor(String form) => {
      'form': form,
      'template': '{move}',
      'defaultBeats': 8,
      'params': const <Object?>[],
    };

    Finder labelOf(BuilderFigure row, String id) => find.descendant(
      of: option(row, 'userFigure:$id'),
      matching: find.byType(Text),
    );

    String restingText(WidgetTester tester, BuilderFigure row) => tester
        .widget<TextField>(find.byKey(ValueKey('has-figure-${row.id}-input')))
        .controller!
        .text;

    test('controls: the two dialects read a role word differently', () {
      expect(inEnglish('role1s swoop'), isNot(inContra('role1s swoop')));
    });

    testWidgets('an option reads in the dialect of the figure\'s form, and is '
        'found by it', (tester) async {
      final row = await pump(
        tester,
        dialects: dialects,
        entries: [
          figure('e', 'role1s swoop', payload: madeFor('ecd')),
          figure('c', 'role1s swoop dive', payload: madeFor('contra')),
        ],
      );
      await type(tester, row, 'swoop');
      expect(
        find.descendant(
          of: option(row, 'userFigure:e'),
          matching: find.text(inEnglish('role1s swoop')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: option(row, 'userFigure:c'),
          matching: find.text(inContra('role1s swoop dive')),
        ),
        findsOneWidget,
      );
      // Each is found by the words of its own form's dialect, and not by the
      // other form's.
      await type(tester, row, inContra('role1s swoop dive'));
      expect(option(row, 'userFigure:c'), findsOneWidget);
      await type(tester, row, inEnglish('role1s swoop'));
      expect(option(row, 'userFigure:e'), findsOneWidget);
      expect(option(row, 'userFigure:c'), findsNothing);
      await type(tester, row, inContra('role1s swoop'));
      expect(option(row, 'userFigure:e'), findsNothing);
    });

    testWidgets('a row asking for a figure rests as the option that set it '
        'read', (tester) async {
      final row = BuilderFigure(
        move: customMove,
        params: {userFigureRefKey: 'e'},
      );
      await pump(
        tester,
        dialects: dialects,
        row: row,
        entries: [figure('e', 'role1s swoop', payload: madeFor('ecd'))],
      );
      expect(restingText(tester, row), inEnglish('role1s swoop'));
    });

    testWidgets('two figures of different forms that read alike are told '
        'apart by their form', (tester) async {
      final row = await pump(
        tester,
        dialects: dialects,
        entries: [
          figure('e', 'swoop', payload: madeFor('ecd')),
          figure('c', 'swoop', payload: madeFor('contra')),
        ],
      );
      await type(tester, row, 'swoop');
      expect(
        find.descendant(
          of: option(row, 'userFigure:e'),
          matching: find.text('swoop · English (ECD)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: option(row, 'userFigure:c'),
          matching: find.text('swoop · Contra'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a row for one of two alike figures rests with its form too, '
        'as the option read', (tester) async {
      final row = BuilderFigure(
        move: customMove,
        params: {userFigureRefKey: 'e'},
      );
      await pump(
        tester,
        dialects: dialects,
        row: row,
        entries: [
          figure('e', 'swoop', payload: madeFor('ecd')),
          figure('c', 'swoop', payload: madeFor('contra')),
        ],
      );
      expect(restingText(tester, row), 'swoop · English (ECD)');
    });

    testWidgets('with no dialects every figure reads in the search\'s dialect, '
        'and none is told apart, as before', (tester) async {
      final row = await pump(
        tester,
        entries: [
          figure('e', 'role1s swoop', payload: madeFor('ecd')),
          figure('c', 'swoop', payload: madeFor('contra')),
          figure('d', 'swoop', payload: madeFor('ecd')),
        ],
      );
      await type(tester, row, 'swoop');
      expect(
        find.descendant(
          of: option(row, 'userFigure:e'),
          matching: find.text(inContra('role1s swoop')),
        ),
        findsOneWidget,
      );
      expect(labelOf(row, 'c'), findsWidgets);
      expect(find.textContaining('·'), findsNothing);
    });
  });
}
