import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/glossary/compound_editor_screen.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// The editor for the user's own compound figures (#709).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final created = DateTime.utc(2026, 10, 14, 9);

  UserGlossaryEntry twoPullBys({
    List<CompoundParam> params = const [
      CompoundParam(key: 'hand', kind: ParamKind.handedness),
    ],
    List<CompoundSlotBinding> bindings = const [
      CompoundSlotBinding(figureIndex: 0, slotKey: 'hand', paramKey: 'hand'),
      CompoundSlotBinding(
        figureIndex: 1,
        slotKey: 'hand',
        paramKey: 'hand',
        source: CompoundBindingSource.opposite,
      ),
    ],
  }) {
    Figure pullBy() => Figure(
      move: 'pull_by',
      params: const {'who': 'neighbors', 'hand': 'right', 'beats': 2},
    );
    return UserGlossaryEntry(
      id: 'pb2',
      kindName: UserGlossaryEntryKind.compound.name,
      name: 'two pull bys',
      definition: 'Pull by, then pull by back.',
      description: 'Two pull-bys, alternating hands.',
      payload: CompoundDefinition(
        params: params,
        figures: [pullBy(), pullBy()],
        bindings: bindings,
      ).toJson(),
      createdAt: created,
    );
  }

  Future<CompendiumRepositories> pump(
    WidgetTester tester, {
    UserGlossaryEntry? initial,
  }) async {
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: dialect, child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<UserGlossaryEntry>(
                    builder: (_) => CompoundEditorScreen(initial: initial),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    return repos;
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('compound-editor-save')));
    await tester.pumpAndSettle();
  }

  testWidgets('a name, a definition and a description are required', (
    tester,
  ) async {
    final repos = await pump(tester);
    await save(tester);
    expect(
      find.text('Give the figure a name, a definition and a description.'),
      findsOneWidget,
    );
    expect(find.text('Required'), findsNWidgets(3));
    expect(await tester.runAsync(repos.userGlossary.listAll), isEmpty);
  });

  testWidgets('a name a built-in figure has is refused', (tester) async {
    await pump(tester, initial: twoPullBys());
    await tester.enterText(
      find.byKey(const ValueKey('compound-name')),
      'Pull By',
    );
    await save(tester);
    expect(
      find.text(
        '“Pull By” is already the name of a figure or shorthand. Choose '
        'another name.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('custom figures are not offered as parts', (tester) async {
    await pump(tester);
    expect(
      tester
          .widget<FigureListEditor>(find.byType(FigureListEditor))
          .allowCustom,
      isFalse,
    );
  });

  testWidgets('a parameter of another kind is shown, disabled, with the '
      'reason', (tester) async {
    await pump(tester, initial: twoPullBys());
    await tester.tap(find.byKey(const ValueKey('compound-binding-0-who')));
    await tester.pumpAndSettle();
    final item = find.text(
      'hand (unavailable: its kind is hand; this setting\'s is dancers)',
    );
    expect(item, findsWidgets);
    final menuItem = tester.widget<DropdownMenuItem<dynamic>>(
      find
          .ancestor(
            of: item.last,
            matching: find.byWidgetPredicate((w) => w is DropdownMenuItem),
          )
          .first,
    );
    expect(menuItem.enabled, isFalse);
  });

  testWidgets('an existing figure saves back unchanged in meaning, with its '
      'text stored canonically', (tester) async {
    final repos = await pump(tester, initial: twoPullBys());
    await tester.enterText(
      find.byKey(const ValueKey('compound-description')),
      'Two pull-bys; Larks start.',
    );
    await save(tester);

    final saved = (await tester.runAsync(
      () => repos.userGlossary.getById('pb2'),
    ))!;
    expect(saved.description, 'Two pull-bys; role1s start.');
    expect(saved.createdAt, created);
    final definition = decodeCompoundDefinition(saved.payload, contraTaxonomy)!;
    expect(definition.bindings, twoPullBysBindings);
    final expanded = expandCompound(definition, {
      'hand': 'left',
    }, contraTaxonomy)!;
    expect(expanded.map((f) => f.params['hand']), ['left', 'right']);
    expect(find.byType(CompoundEditorScreen), findsNothing, reason: 'closed');
  });

  testWidgets('an unused parameter warns, and the user can go back or save '
      'anyway', (tester) async {
    final repos = await pump(
      tester,
      initial: twoPullBys(
        params: const [
          CompoundParam(key: 'hand', kind: ParamKind.handedness),
          CompoundParam(key: 'who', kind: ParamKind.dancerSet),
        ],
      ),
    );
    await save(tester);
    expect(find.text('Some parameters aren\'t used'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('compound-unused-back')));
    await tester.pumpAndSettle();
    expect(find.byType(CompoundEditorScreen), findsOneWidget);
    expect(await tester.runAsync(repos.userGlossary.listAll), isEmpty);

    await save(tester);
    await tester.tap(find.byKey(const ValueKey('compound-unused-save')));
    await tester.pumpAndSettle();
    expect(find.byType(CompoundEditorScreen), findsNothing);
    expect(await tester.runAsync(repos.userGlossary.listAll), hasLength(1));
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await pump(tester, initial: twoPullBys());
    await tester.enterText(
      find.byKey(const ValueKey('compound-notes')),
      'something',
    );
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.text('You have unsaved changes to this figure.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('compound-discard')));
    await tester.pumpAndSettle();
    expect(find.byType(CompoundEditorScreen), findsNothing);
  });
}

const twoPullBysBindings = [
  CompoundSlotBinding(figureIndex: 0, slotKey: 'hand', paramKey: 'hand'),
  CompoundSlotBinding(
    figureIndex: 1,
    slotKey: 'hand',
    paramKey: 'hand',
    source: CompoundBindingSource.opposite,
  ),
];
