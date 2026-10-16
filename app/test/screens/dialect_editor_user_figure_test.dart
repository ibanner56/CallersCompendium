import 'dart:async';

import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/data/user_figures_scope.dart';
import 'package:compendium_app/src/screens/dialect_editor_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// A dialect's name and wording for one of the user's own new figures
/// (#1023): offered in the dialect editor while Custom Figures is on, labelled
/// by the figure's name, and worded with the figure's own slots.
void main() {
  final key = userFigureKeyFor('zoom-id');

  UserGlossaryEntry zoom() => UserGlossaryEntry(
    id: 'zoom-id',
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: 'role1s zoom',
    definition: 'A zoom.',
    description: 'Fast.',
    payload: const {
      'template': '{who} {move} {hand}',
      'defaultBeats': 8,
      'params': [
        {'key': 'who', 'kind': 'dancerSet', 'default': 'role2s'},
        {'key': 'hand', 'kind': 'handedness', 'default': 'right'},
      ],
    },
    createdAt: DateTime.utc(2026, 10, 16),
  );

  /// Opens the editor on [initial]; returns what Save pops.
  Future<Dialect? Function()> pump(
    WidgetTester tester, {
    Dialect? initial,
    bool customFigures = true,
    bool storeFigure = true,
  }) async {
    final repos = openTestRepositories();
    if (storeFigure) {
      await tester.runAsync(() => repos.userGlossary.upsert(zoom()));
    }
    final userFigures = UserFiguresController(repos.userGlossary);
    addTearDown(userFigures.dispose);
    unawaited(userFigures.start());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final glossary = ValueNotifier(true);
    final custom = ValueNotifier(customFigures);
    addTearDown(glossary.dispose);
    addTearDown(custom.dispose);
    tester.view
      ..physicalSize = const Size(1200, 5000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Dialect? popped;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => ShowGlossaryScope(
          notifier: glossary,
          child: ShowCustomFiguresScope(
            notifier: custom,
            child: UserFiguresScope(controller: userFigures, child: child!),
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<Dialect>(
                    MaterialPageRoute(
                      builder: (_) => DialectEditorScreen(
                        initial:
                            initial ??
                            Dialect.larksRobins.copyWith(name: 'Mine'),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => popped;
  }

  Future<void> open(WidgetTester tester, String toggle) async {
    await tester.tap(find.byKey(ValueKey(toggle)));
    await tester.pumpAndSettle();
  }

  List<String?> offered(WidgetTester tester, String menuKey) => tester
      .widget<DropdownButton<String>>(find.byKey(ValueKey(menuKey)))
      .items!
      .map((item) => item.value)
      .toList();

  Future<void> pick(WidgetTester tester, String menuKey, String value) async {
    tester
        .widget<DropdownButton<String>>(find.byKey(ValueKey(menuKey)))
        .onChanged!(value);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('dialect-editor-save')));
    await tester.pumpAndSettle();
  }

  testWidgets('a figure of yours is offered to rename, by its name, and the '
      'name is saved under its key', (tester) async {
    final popped = await pump(tester);
    await open(tester, 'dialect-moves-toggle');
    expect(offered(tester, 'dialect-add-move'), contains(key));
    final item = tester
        .widget<DropdownButton<String>>(
          find.byKey(const ValueKey('dialect-add-move')),
        )
        .items!
        .firstWhere((item) => item.value == key);
    expect((item.child as Text).data, 'larks zoom');
    await pick(tester, 'dialect-add-move', key);
    await tester.enterText(find.byKey(ValueKey('dialect-move-$key')), 'whizz');
    await tester.pump();
    await save(tester);
    expect(popped()!.moves[key], 'whizz');
  });

  testWidgets('a new wording starts from the figure\'s own, lists its slots '
      'and previews with its defaults', (tester) async {
    final popped = await pump(tester);
    await open(tester, 'dialect-wordings-toggle');
    expect(offered(tester, 'dialect-add-move-wording'), contains(key));
    await pick(tester, 'dialect-add-move-wording', key);
    final field = find.byKey(ValueKey('dialect-wording-$key'));
    expect(
      tester.widget<TextField>(field).controller!.text,
      '{who} {move} {hand}',
    );
    await tester.enterText(field, '{move} for {who}, {hand} hand');
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('dialect-wording-preview-$key')))
          .data,
      contains('larks zoom for robins, right hand'),
    );
    await save(tester);
    expect(popped()!.moveWordings[key], '{move} for {who}, {hand} hand');
  });

  testWidgets('a wording with a slot the figure lacks says it keeps its own '
      'wording', (tester) async {
    await pump(
      tester,
      initial: Dialect.larksRobins.copyWith(
        name: 'Mine',
        moveWordings: {key: '{move} {gone}'},
      ),
    );
    await open(tester, 'dialect-wordings-toggle');
    expect(
      find.byKey(ValueKey('dialect-wording-unknown-$key')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('dialect-wording-preview-$key')))
          .data,
      contains('robins larks zoom right'),
      reason: 'the figure keeps its own wording',
    );
  });

  testWidgets('figures are not offered while Custom Figures is off, and one '
      'already named is still labelled by its name', (tester) async {
    await pump(
      tester,
      customFigures: false,
      initial: Dialect.larksRobins.copyWith(
        name: 'Mine',
        moves: {key: 'whizz'},
      ),
    );
    await open(tester, 'dialect-moves-toggle');
    expect(find.text('larks zoom'), findsWidgets);
    // The figure already has a name here, so it is checked where it has no
    // wording: a list that would offer it with Custom Figures on.
    await open(tester, 'dialect-wordings-toggle');
    expect(offered(tester, 'dialect-add-move-wording'), isNot(contains(key)));
  });

  testWidgets('a name for a figure not on this device says so', (tester) async {
    await pump(
      tester,
      storeFigure: false,
      initial: Dialect.larksRobins.copyWith(
        name: 'Mine',
        moves: {key: 'whizz'},
      ),
    );
    await open(tester, 'dialect-moves-toggle');
    expect(find.text('One of your figures, not on this device'), findsWidgets);
  });

  testWidgets('a validation message names the figure, not its key', (
    tester,
  ) async {
    await pump(
      tester,
      initial: Dialect.larksRobins.copyWith(
        name: 'Mine',
        moves: {key: 'twirl', 'swing': 'twirl'},
      ),
    );
    await save(tester);
    final error = tester.widget<Text>(
      find.byKey(const ValueKey('dialect-validation-error')).first,
    );
    expect(error.data, contains('larks zoom'));
    expect(error.data, isNot(contains('userFigure:')));
  });
}
