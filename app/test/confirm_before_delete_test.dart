import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/confirm_before_delete_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/sort_ignore_articles_scope.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/screens/programs_shell.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: const [],
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: _now,
  updatedAt: _now,
);

Program _program(String id, String title) => Program(
  id: id,
  title: title,
  status: ProgramStatus.draft,
  slots: const [],
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pumpDanceList(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required bool confirmBeforeDelete,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  final sortIgnore = ValueNotifier<bool>(true);
  final confirm = ValueNotifier<bool>(confirmBeforeDelete);
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(customThemes.dispose);
  addTearDown(sortIgnore.dispose);
  addTearDown(confirm.dispose);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: SortIgnoreArticlesScope(
                notifier: sortIgnore,
                child: ConfirmBeforeDeleteScope(
                  notifier: confirm,
                  child: child!,
                ),
              ),
            ),
          ),
        ),
      ),
      home: const DanceListScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpProgramsList(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required bool confirmBeforeDelete,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final confirm = ValueNotifier<bool>(confirmBeforeDelete);
  addTearDown(confirm.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ConfirmBeforeDeleteScope(notifier: confirm, child: child!),
      ),
      home: const ProgramsListScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpProgramsShell(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required bool confirmBeforeDelete,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final dialect = ValueNotifier<Dialect>(Dialect.canonical);
  final confirm = ValueNotifier<bool>(confirmBeforeDelete);
  addTearDown(dialect.dispose);
  addTearDown(confirm.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(
          notifier: dialect,
          child: ConfirmBeforeDeleteScope(notifier: confirm, child: child!),
        ),
      ),
      home: const ProgramsShell(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('dance list', () {
    testWidgets('with confirm OFF, swipe deletes immediately (today)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'Swipe Me'));
      await _pumpDanceList(tester, repos, confirmBeforeDelete: false);

      await tester.fling(
        find.byKey(const ValueKey('dismissible-d1')),
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('confirm-delete-dialog')), findsNothing);
      expect(find.text('Swipe Me'), findsNothing);
      final deleted = await repos.dances.getById('d1', includeDeleted: true);
      expect(deleted!.deletedAt, isNotNull);
    });

    testWidgets('with confirm ON, Cancel keeps the dance', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'Swipe Me'));
      await _pumpDanceList(tester, repos, confirmBeforeDelete: true);

      await tester.fling(
        find.byKey(const ValueKey('dismissible-d1')),
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('confirm-delete-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('confirm-delete-cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsOneWidget);
      final dance = await repos.dances.getById('d1');
      expect(dance!.deletedAt, isNull);
    });

    testWidgets('with confirm ON, Delete soft-deletes the dance', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'Swipe Me'));
      await _pumpDanceList(tester, repos, confirmBeforeDelete: true);

      await tester.fling(
        find.byKey(const ValueKey('dismissible-d1')),
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('confirm-delete-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsNothing);
      final deleted = await repos.dances.getById('d1', includeDeleted: true);
      expect(deleted!.deletedAt, isNotNull);
    });
  });

  group('programs list', () {
    testWidgets('with confirm OFF, swipe deletes immediately (today)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('p1', 'Swipe Me'));
      await _pumpProgramsList(tester, repos, confirmBeforeDelete: false);

      await tester.drag(find.text('Swipe Me'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('confirm-delete-dialog')), findsNothing);
      expect(find.text('Swipe Me'), findsNothing);
      expect(await repos.programs.listAll(), isEmpty);
    });

    testWidgets('with confirm ON, Cancel keeps the program', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('p1', 'Swipe Me'));
      await _pumpProgramsList(tester, repos, confirmBeforeDelete: true);

      await tester.drag(find.text('Swipe Me'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('confirm-delete-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('confirm-delete-cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsOneWidget);
      expect(await repos.programs.listAll(), hasLength(1));
    });

    testWidgets('with confirm ON, Delete soft-deletes the program', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('p1', 'Swipe Me'));
      await _pumpProgramsList(tester, repos, confirmBeforeDelete: true);

      await tester.drag(find.text('Swipe Me'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('confirm-delete-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsNothing);
      expect(await repos.programs.listAll(), isEmpty);
    });
  });

  group('programs shell summary pane', () {
    testWidgets('with confirm OFF, delete removes the program immediately', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('p1', 'Barn Dance'));
      await _pumpProgramsShell(tester, repos, confirmBeforeDelete: false);

      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('summary-delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('confirm-delete-dialog')), findsNothing);
      expect(await repos.programs.listAll(), isEmpty);
    });

    testWidgets('with confirm ON, Cancel keeps the program', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('p1', 'Barn Dance'));
      await _pumpProgramsShell(tester, repos, confirmBeforeDelete: true);

      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('summary-delete')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('confirm-delete-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('confirm-delete-cancel')));
      await tester.pumpAndSettle();

      expect(await repos.programs.listAll(), hasLength(1));
    });

    testWidgets('with confirm ON, Delete soft-deletes the program', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('p1', 'Barn Dance'));
      await _pumpProgramsShell(tester, repos, confirmBeforeDelete: true);

      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('summary-delete')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('confirm-delete-confirm')));
      await tester.pumpAndSettle();

      expect(await repos.programs.listAll(), isEmpty);
    });
  });
}
