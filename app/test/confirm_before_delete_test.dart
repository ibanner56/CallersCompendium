import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
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
import 'support/l10n_harness.dart';

/// A [SettingsRepository] whose reads wait on [gate] while it is set.
class _GatedReadSettings extends SettingsRepository {
  _GatedReadSettings(super.db);

  Completer<void>? gate;

  @override
  Future<Object?> get(String key) async {
    await gate?.future;
    return super.get(key);
  }
}

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
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
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

/// A draft holding [danceIds] as primary slots, so it sits in each dance's
/// calling history under the default settings.
Future<void> _programWithDances(
  CompendiumRepositories repos,
  String id,
  String title,
  List<String> danceIds,
) async {
  for (final danceId in danceIds) {
    await repos.dances.create(_dance(danceId, 'Dance $danceId'));
  }
  await repos.programs.create(
    Program(
      id: id,
      title: title,
      status: ProgramStatus.draft,
      slots: [
        for (var i = 0; i < danceIds.length; i++)
          ProgramSlot(id: '$id-$i', position: i, danceId: danceIds[i]),
      ],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
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
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
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
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
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
  group('dance list', () {
    testWidgets(
      'with confirm OFF, revealing + tapping Delete deletes (no dialog)',
      (tester) async {
        final repos = openTestRepositories();
        await repos.dances.create(_dance('d1', 'Swipe Me'));
        await _pumpDanceList(tester, repos, confirmBeforeDelete: false);

        await tester.drag(
          find.byKey(const ValueKey('slidable-d1')),
          const Offset(-300, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('slide-delete-d1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('confirm-delete-dialog')),
          findsNothing,
        );
        expect(find.text('Swipe Me'), findsNothing);
        final deleted = await repos.dances.getById('d1', includeDeleted: true);
        expect(deleted!.deletedAt, isNotNull);
      },
    );

    testWidgets(
      'with confirm ON, the revealed Delete tap is the confirmation (no '
      'dialog on the swipe path)',
      (tester) async {
        final repos = openTestRepositories();
        await repos.dances.create(_dance('d1', 'Swipe Me'));
        await _pumpDanceList(tester, repos, confirmBeforeDelete: true);

        await tester.drag(
          find.byKey(const ValueKey('slidable-d1')),
          const Offset(-300, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('slide-delete-d1')));
        await tester.pumpAndSettle();

        // The reveal + tap replaces the dialog: no AlertDialog appears even
        // with the "Confirm before delete" setting ON, and the dance is gone.
        expect(
          find.byKey(const ValueKey('confirm-delete-dialog')),
          findsNothing,
        );
        expect(find.text('Swipe Me'), findsNothing);
        final deleted = await repos.dances.getById('d1', includeDeleted: true);
        expect(deleted!.deletedAt, isNotNull);
      },
    );

    testWidgets('with confirm ON, the ⋮ menu Delete still shows the dialog; '
        'Cancel keeps the dance', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'Swipe Me'));
      await _pumpDanceList(tester, repos, confirmBeforeDelete: true);

      await tester.tap(find.byKey(const ValueKey('dance-actions-d1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dance-action-delete')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('confirm-delete-dialog')),
        findsOneWidget,
      );
      // Confirmations render as an AlertDialog (not a hand-built sheet), for
      // consistency across the app's destructive-action flows.
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsOneWidget);
      final dance = await repos.dances.getById('d1');
      expect(dance!.deletedAt, isNull);
    });

    testWidgets('the confirm button is styled as destructive, not as an '
        'ordinary primary action', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'Swipe Me'));
      await _pumpDanceList(tester, repos, confirmBeforeDelete: true);

      await tester.tap(find.byKey(const ValueKey('dance-actions-d1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dance-action-delete')));
      await tester.pumpAndSettle();

      final confirm = find.byKey(const ValueKey('confirm-delete-confirm'));
      final scheme = Theme.of(tester.element(confirm)).colorScheme;
      final style = tester.widget<FilledButton>(confirm).style;
      expect(style?.backgroundColor?.resolve(<WidgetState>{}), scheme.error);
      expect(style?.foregroundColor?.resolve(<WidgetState>{}), scheme.onError);
    });

    testWidgets('with confirm ON, the ⋮ menu Delete soft-deletes the dance', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'Swipe Me'));
      await _pumpDanceList(tester, repos, confirmBeforeDelete: true);

      await tester.tap(find.byKey(const ValueKey('dance-actions-d1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dance-action-delete')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('confirm-delete-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsNothing);
      final deleted = await repos.dances.getById('d1', includeDeleted: true);
      expect(deleted!.deletedAt, isNotNull);
    });
  });

  group('programs list', () {
    testWidgets(
      'with confirm OFF, revealing + tapping Delete deletes (no dialog)',
      (tester) async {
        final repos = openTestRepositories();
        await repos.programs.create(_program('p1', 'Swipe Me'));
        await _pumpProgramsList(tester, repos, confirmBeforeDelete: false);

        await tester.drag(
          find.byKey(const ValueKey('slidable-p1')),
          const Offset(-300, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('slide-delete-p1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('confirm-delete-dialog')),
          findsNothing,
        );
        expect(find.text('Swipe Me'), findsNothing);
        expect(await repos.programs.listAll(), isEmpty);
      },
    );

    testWidgets(
      'with confirm ON, the revealed Delete tap is the confirmation (no '
      'dialog on the swipe path)',
      (tester) async {
        final repos = openTestRepositories();
        await repos.programs.create(_program('p1', 'Swipe Me'));
        await _pumpProgramsList(tester, repos, confirmBeforeDelete: true);

        await tester.drag(
          find.byKey(const ValueKey('slidable-p1')),
          const Offset(-300, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('slide-delete-p1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('confirm-delete-dialog')),
          findsNothing,
        );
        expect(find.text('Swipe Me'), findsNothing);
        expect(await repos.programs.listAll(), isEmpty);
      },
    );

    testWidgets('with confirm ON, the ⋮ menu Delete still shows the dialog; '
        'Cancel keeps the program', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('p1', 'Swipe Me'));
      await _pumpProgramsList(tester, repos, confirmBeforeDelete: true);

      await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-action-delete')));
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

    testWidgets('with confirm ON, the ⋮ menu Delete soft-deletes the program', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('p1', 'Swipe Me'));
      await _pumpProgramsList(tester, repos, confirmBeforeDelete: true);

      await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-action-delete')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('confirm-delete-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Swipe Me'), findsNothing);
      expect(await repos.programs.listAll(), isEmpty);
    });
  });

  group('program delete warns about calling history (LIFE-6)', () {
    testWidgets('the list ⋮ menu names how many dances lose the program', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _programWithDances(repos, 'p1', 'Barn Dance', ['d1', 'd2', 'd3']);
      await _pumpProgramsList(tester, repos, confirmBeforeDelete: true);

      await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-action-delete')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '\u201cBarn Dance\u201d will be deleted. 3 dances will lose this '
          'program from their calling history. You can undo this.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('one dance reads in the singular', (tester) async {
      final repos = openTestRepositories();
      await _programWithDances(repos, 'p1', 'Barn Dance', ['d1']);
      await _pumpProgramsList(tester, repos, confirmBeforeDelete: true);

      await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-action-delete')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          '1 dance will lose this program from its calling history',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a program with no dances keeps the plain body', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('p1', 'Empty Night'));
      await _pumpProgramsList(tester, repos, confirmBeforeDelete: true);

      await tester.tap(find.byKey(const ValueKey('program-actions-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-action-delete')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '\u201cEmpty Night\u201d will be deleted. You can undo this.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a second tap while the count loads opens one dialog', (
      tester,
    ) async {
      final db = openWidgetTestDatabase();
      final settings = _GatedReadSettings(db);
      final repos = CompendiumRepositories(
        db,
        contraTaxonomy,
        settings: settings,
      );
      await _programWithDances(repos, 'p1', 'Barn Dance', ['d1', 'd2']);
      await _pumpProgramsShell(tester, repos, confirmBeforeDelete: true);
      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();

      // Hold the settings read the confirm makes before its dialog opens, so
      // the first tap is still in flight when the second lands.
      settings.gate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('summary-delete')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('summary-delete')));
      await tester.pump();
      settings.gate!.complete();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('confirm-delete-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('confirm-delete-confirm')));
      await tester.pumpAndSettle();
      expect(await repos.programs.listAll(), isEmpty);
    });

    testWidgets('the summary pane names the count too', (tester) async {
      final repos = openTestRepositories();
      await _programWithDances(repos, 'p1', 'Barn Dance', ['d1', 'd2']);
      await _pumpProgramsShell(tester, repos, confirmBeforeDelete: true);

      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('summary-delete')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('2 dances will lose this program'),
        findsOneWidget,
      );
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
