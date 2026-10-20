import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/screens/glossary/compound_editor_screen.dart';
import 'package:compendium_app/src/screens/glossary/custom_figures_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// The user's own figures on their own screen, reached from the Experimental
/// settings, which work with the Glossary off.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  UserGlossaryEntry entry({
    required String id,
    required String name,
    String kindName = 'customFigure',
  }) => UserGlossaryEntry(
    id: id,
    kindName: kindName,
    name: name,
    definition: 'A definition of $name.',
    description: 'A description of $name.',
    payload: kindName == 'customFigure'
        ? userFigureSeedFromMove(contraTaxonomy, 'swing')!.toJson()
        : const {},
    createdAt: DateTime.utc(2026, 10, 19),
  );

  Future<void> pump(
    WidgetTester tester, {
    List<UserGlossaryEntry> entries = const [],
    bool glossary = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    for (final e in entries) {
      await tester.runAsync(() => repos.userGlossary.upsert(e));
    }
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    final show = ValueNotifier<bool>(glossary);
    final custom = ValueNotifier<bool>(true);
    for (final n in [show, custom]) {
      addTearDown(n.dispose);
    }
    addTearDown(dialect.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: ShowGlossaryScope(
              notifier: show,
              child: ShowCustomFiguresScope(notifier: custom, child: child!),
            ),
          ),
        ),
        home: const CustomFiguresScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('says so when there are no figures of your own', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('custom-figures-empty')), findsOneWidget);
  });

  testWidgets('lists your figures with the Glossary off, without terms', (
    tester,
  ) async {
    await pump(
      tester,
      entries: [
        entry(id: 'a', name: 'zig zag'),
        entry(id: 'b', name: 'a word', kindName: 'term'),
      ],
    );
    expect(find.byKey(const ValueKey('custom-figure-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-figure-b')), findsNothing);
    expect(find.byKey(const ValueKey('custom-figures-empty')), findsNothing);
  });

  testWidgets('a figure opens to its page, which can be edited', (
    tester,
  ) async {
    await pump(
      tester,
      entries: [entry(id: 'a', name: 'zig zag')],
    );
    await tester.tap(find.byKey(const ValueKey('custom-figure-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glossary-custom-edit')));
    await tester.pumpAndSettle();
    expect(find.byType(CompoundEditorScreen), findsOneWidget);
  });

  testWidgets('+ opens the editor on a new figure', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('custom-figures-add')));
    await tester.pumpAndSettle();
    expect(find.byType(CompoundEditorScreen), findsOneWidget);
  });

  testWidgets('+ offers figures only: a term would be hidden with the '
      'Glossary off', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('custom-figures-add')));
    await tester.pumpAndSettle();
    final kinds = find.byKey(const ValueKey('glossary-entry-kind'));
    expect(
      find.descendant(of: kinds, matching: find.text('New figure')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: kinds, matching: find.text('Term')),
      findsNothing,
    );
  });

  testWidgets('Custom Figures needs only its own setting, not the Glossary', (
    tester,
  ) async {
    final show = ValueNotifier<bool>(false);
    final custom = ValueNotifier<bool>(true);
    addTearDown(show.dispose);
    addTearDown(custom.dispose);
    bool? shown;
    await tester.pumpWidget(
      ShowGlossaryScope(
        notifier: show,
        child: ShowCustomFiguresScope(
          notifier: custom,
          child: Builder(
            builder: (context) {
              shown = customFiguresShown(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(shown, isTrue);
    custom.value = false;
    await tester.pump();
    expect(shown, isFalse);
  });
}
