import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/screens/glossary/glossary_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// The Glossary's choice of dance form (ADR-006 W5, S6).
void main() {
  final created = DateTime.utc(2026, 1, 1);

  /// Pumps the Glossary as the app shell keeps it: alive, shown while
  /// [active] is true. Contra reads in larks and robins and English in the
  /// canonical dialect, so the two word a role differently.
  Future<({CompendiumRepositories repos, ValueNotifier<bool> active})> pump(
    WidgetTester tester, {
    List<UserGlossaryEntry> entries = const [],
    bool startActive = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    for (final e in entries) {
      await tester.runAsync(() => repos.userGlossary.upsert(e));
    }
    final dialects = ValueNotifier(
      DialectsByForm({
        DanceForm.contra: Dialect.larksRobins,
        DanceForm.ecd: Dialect.canonical,
      }),
    );
    final glossary = ValueNotifier(true);
    final custom = ValueNotifier(true);
    final active = ValueNotifier(startActive);
    for (final n in <ChangeNotifier>[dialects, glossary, custom, active]) {
      addTearDown(n.dispose);
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope.byForm(
            dialects: dialects,
            child: ShowGlossaryScope(
              notifier: glossary,
              child: ShowCustomFiguresScope(notifier: custom, child: child!),
            ),
          ),
        ),
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (_, isActive, _) => GlossaryScreen(isActive: isActive),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (repos: repos, active: active);
  }

  Future<void> setNewDanceForm(
    WidgetTester tester,
    CompendiumRepositories repos,
    DanceForm form,
  ) => tester.runAsync(
    () => repos.settings.set(kDefaultDanceFormKey, form.name),
  );

  /// Hides the Glossary and shows it again, as moving to another destination
  /// and back does.
  Future<void> leaveAndReturn(
    WidgetTester tester,
    ValueNotifier<bool> active,
  ) async {
    active.value = false;
    await tester.pumpAndSettle();
    active.value = true;
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const ValueKey('glossary-search')),
      query,
    );
    await tester.pumpAndSettle();
  }

  bool selected(WidgetTester tester, DanceForm form) => tester
      .widget<SegmentedButton<DanceForm>>(
        find.byKey(const ValueKey('glossary-form')),
      )
      .selected
      .contains(form);

  testWidgets('kept alive, it opens on the form a new dance now starts as '
      'each time it is shown', (tester) async {
    final (:repos, :active) = await pump(tester);
    expect(selected(tester, DanceForm.contra), isTrue);

    await setNewDanceForm(tester, repos, DanceForm.ecd);
    await leaveAndReturn(tester, active);

    expect(selected(tester, DanceForm.ecd), isTrue);
  });

  testWidgets('a form the user picked stays when it is shown again', (
    tester,
  ) async {
    final (:repos, :active) = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('glossary-form-ecd')));
    await tester.pumpAndSettle();
    await setNewDanceForm(tester, repos, DanceForm.contra);
    await leaveAndReturn(tester, active);

    expect(selected(tester, DanceForm.ecd), isTrue);
  });

  testWidgets('a term added while English is shown is an English one, '
      'listed there', (tester) async {
    final (:repos, active: _) = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('glossary-form-ecd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('glossary-add-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('compound-name')),
      'zesty corners',
    );
    await tester.enterText(
      find.byKey(const ValueKey('compound-definition')),
      'A lively turn.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('compound-description')),
      'Corners, with a flourish.',
    );
    await tester.pumpAndSettle();
    final termChoice = find.descendant(
      of: find.byKey(const ValueKey('glossary-entry-kind')),
      matching: find.text('Term'),
    );
    await tester.ensureVisible(termChoice);
    await tester.tap(termChoice);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('compound-editor-save')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final saved = (await tester.runAsync(repos.userGlossary.listAll))!;
    expect(glossaryEntryForm(saved.single.payload), 'ecd');
    await search(tester, 'zesty');
    expect(
      find.byKey(ValueKey('glossary-entry-custom:${saved.single.id}')),
      findsOneWidget,
    );
  });

  testWidgets('an English entry of the user\'s reads in English\'s dialect, in '
      'the list and in its detail (#2294)', (tester) async {
    await pump(
      tester,
      entries: [
        UserGlossaryEntry(
          id: 't1',
          kindName: UserGlossaryEntryKind.term.name,
          name: 'zesty corners',
          definition: 'role1s turn their corners.',
          description: '',
          payload: glossaryTermPayload('ecd'),
          createdAt: created,
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('glossary-form-ecd')));
    await tester.pumpAndSettle();
    await search(tester, 'zesty');
    final row = find.byKey(const ValueKey('glossary-entry-custom:t1'));
    final renderer = FigureRenderer(contraTaxonomy);
    final contra = renderer.renderFreeText(
      'role1s turn their corners.',
      Dialect.larksRobins,
    );
    final english = renderer.renderFreeText(
      'role1s turn their corners.',
      Dialect.canonical,
    );
    // A control: the two dialects word the role differently, so the reading
    // below can tell them apart.
    expect(english, isNot(contra));
    expect(
      find.descendant(of: row, matching: find.textContaining(english)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining(contra)),
      findsNothing,
    );

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.textContaining(english), findsWidgets);
    expect(find.textContaining(contra), findsNothing);
  });
}
