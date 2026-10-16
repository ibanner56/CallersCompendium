import 'dart:async';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/program_auto_commit_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_custom_figures_scope.dart';
import 'package:compendium_app/src/data/show_glossary_scope.dart';
import 'package:compendium_app/src/data/user_figures_scope.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// The program matrix and the user's own figures (#1023): a column per figure
/// while Custom Figures is on, the one custom column while it is off.
void main() {
  final now = DateTime.utc(2026, 10, 16);
  final zoom = UserGlossaryEntry(
    id: 'zoom-id',
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: 'role1s zoom',
    definition: 'A zoom.',
    description: 'Fast.',
    payload: const {
      'template': '{move}',
      'defaultBeats': 8,
      'params': <Object?>[],
    },
    createdAt: now,
  );

  testWidgets('a figure of your own has its own column while Custom Figures '
      'is on, and joins the custom column while it is off', (tester) async {
    final repos = openTestRepositories();
    await tester.runAsync(() async {
      await repos.userGlossary.upsert(zoom);
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Zoomy',
          figures: [
            userFigureUseFigure(
              id: 'zoom-id',
              args: const {},
              text: 'role1s zoom',
              beats: 8,
            ),
          ],
          formation: const Formation(FormationShape.dupleImproper),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Night',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
    final userFigures = UserFiguresController(repos.userGlossary);
    addTearDown(userFigures.dispose);
    unawaited(userFigures.start());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    final autoCommit = ValueNotifier(false);
    final glossary = ValueNotifier(true);
    final custom = ValueNotifier(true);
    for (final n in [dialect, autoCommit, glossary, custom]) {
      addTearDown(n.dispose);
    }
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: ProgramAutoCommitScope(
              notifier: autoCommit,
              child: ShowGlossaryScope(
                notifier: glossary,
                child: ShowCustomFiguresScope(
                  notifier: custom,
                  child: UserFiguresScope(
                    controller: userFigures,
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        ),
        home: ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('program-matrix-tab')));
    await tester.pumpAndSettle();

    final table = find.byKey(const ValueKey('program-matrix-table'));
    expect(table, findsOneWidget);
    expect(
      find.descendant(of: table, matching: find.text('larks zoom')),
      findsOneWidget,
      reason: 'its own column, named in the dialect',
    );
    expect(
      find.descendant(of: table, matching: find.text('Custom')),
      findsNothing,
    );

    custom.value = false;
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: table, matching: find.text('larks zoom')),
      findsNothing,
    );
    expect(
      find.descendant(of: table, matching: find.text('Custom')),
      findsOneWidget,
    );
  });
}
