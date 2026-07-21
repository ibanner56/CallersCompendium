import 'dart:async';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/collection_refresh_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/screens/reparse_custom_figures_screen.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';

/// An import-gap custom figure carrying [text] as its stored scrubbed source.
Figure _importGap(String text) =>
    customFigure(text, origin: CustomOrigin.importGap);

Dance _dance({
  required String id,
  required String title,
  required List<Figure> figures,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Dance(
    id: id,
    title: title,
    figures: figures,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.pumpWidget(
    RepositoriesScope(
      repositories: repos,
      child: const MaterialApp(home: ReparseCustomFiguresScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the empty state when nothing can be upgraded', (
    tester,
  ) async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(
      _dance(id: 'a', title: 'Alpha', figures: [_importGap('hey for four')]),
    );

    await _pumpScreen(tester, repos);

    expect(find.byKey(const ValueKey('reparse-customs-empty')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reparse-customs-apply-button')),
      findsNothing,
    );
  });

  testWidgets('previews the dances that would be upgraded', (tester) async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(
      _dance(id: 'a', title: 'Alpha', figures: [_importGap('Neighbor swing')]),
    );
    await repos.dances.create(
      _dance(id: 'b', title: 'Bravo', figures: [_importGap('hey for four')]),
    );

    await _pumpScreen(tester, repos);

    // Only the upgradeable dance is listed.
    expect(find.byKey(const ValueKey('reparse-dance-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('reparse-dance-b')), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reparse-customs-apply-button')),
      findsOneWidget,
    );
  });

  testWidgets('applying requires confirmation and upgrades on confirm', (
    tester,
  ) async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(
      _dance(id: 'a', title: 'Alpha', figures: [_importGap('Neighbor swing')]),
    );

    await _pumpScreen(tester, repos);

    await tester.tap(
      find.byKey(const ValueKey('reparse-customs-apply-button')),
    );
    await tester.pumpAndSettle();

    // A confirmation dialog appears; nothing has changed yet.
    expect(find.byKey(const ValueKey('reparse-confirm-apply')), findsOneWidget);
    expect((await repos.dances.getById('a'))!.figures.single.isCustom, isTrue);

    await tester.tap(find.byKey(const ValueKey('reparse-confirm-apply')));
    await tester.pumpAndSettle();

    final figure = (await repos.dances.getById('a'))!.figures.single;
    expect(figure.isCustom, isFalse);
    expect(figure.move, 'swing');
  });

  testWidgets('cancelling the confirmation leaves figures untouched', (
    tester,
  ) async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(
      _dance(id: 'a', title: 'Alpha', figures: [_importGap('Neighbor swing')]),
    );

    await _pumpScreen(tester, repos);

    await tester.tap(
      find.byKey(const ValueKey('reparse-customs-apply-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect((await repos.dances.getById('a'))!.figures.single.isCustom, isTrue);
  });

  testWidgets('Settings → General shows the re-check entry and opens it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
    final customThemes = CustomThemesController(repos.settings);
    await customThemes.load();
    addTearDown(dialect.dispose);
    addTearDown(theme.dispose);
    addTearDown(customThemes.dispose);

    await tester.pumpWidget(
      RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: const MaterialApp(home: SettingsScreen()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('reparse-custom-figures-button'));
    expect(button, findsOneWidget);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('reparse-customs-appbar')),
      findsOneWidget,
    );
  });

  testWidgets('shows a retryable error state when the preview load fails', (
    tester,
  ) async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);

    var attempt = 0;
    await tester.pumpWidget(
      RepositoriesScope(
        repositories: repos,
        child: MaterialApp(
          home: ReparseCustomFiguresScreen(
            previewLoader: (r) async {
              attempt++;
              if (attempt == 1) throw StateError('boom');
              return const <CustomReparsePreview>[];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Error UI with retry, not a stuck spinner.
    expect(find.byKey(const ValueKey('reparse-customs-error')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('reparse-customs-retry-button')),
    );
    await tester.pumpAndSettle();

    // Second attempt succeeds → empty state (no lingering error).
    expect(find.byKey(const ValueKey('reparse-customs-error')), findsNothing);
    expect(find.byKey(const ValueKey('reparse-customs-empty')), findsOneWidget);
  });

  testWidgets('apply failure re-enables the button and shows an error', (
    tester,
  ) async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(
      _dance(id: 'a', title: 'Alpha', figures: [_importGap('Neighbor swing')]),
    );

    await tester.pumpWidget(
      RepositoriesScope(
        repositories: repos,
        child: MaterialApp(
          home: ReparseCustomFiguresScreen(
            applier: (r, ids) async => throw StateError('write failed'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('reparse-customs-apply-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reparse-confirm-apply')));
    await tester.pumpAndSettle();

    // Still on the screen with an error snackbar, and the button is usable
    // again (not permanently disabled).
    expect(
      find.byKey(const ValueKey('reparse-customs-appbar')),
      findsOneWidget,
    );
    expect(
      find.text('Could not upgrade figures. Please try again.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('reparse-customs-apply-button')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('a commit after the screen is disposed still refreshes the '
      'collection', (tester) async {
    final repos = openTestRepositories();
    addTearDown(repos.db.close);
    await repos.dances.create(
      _dance(id: 'a', title: 'Alpha', figures: [_importGap('Neighbor swing')]),
    );

    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    final gate = Completer<int>();

    await tester.pumpWidget(
      CollectionRefreshScope(
        revision: revision,
        child: RepositoriesScope(
          repositories: repos,
          child: MaterialApp(
            home: ReparseCustomFiguresScreen(applier: (r, ids) => gate.future),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('reparse-customs-apply-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reparse-confirm-apply')));
    await tester.pump(); // apply is now awaiting the gate

    // Dispose the screen before the write completes.
    await tester.pumpWidget(const SizedBox());

    // The commit lands after dispose; the captured notifier must still fire so
    // a kept-alive Collection tab reloads.
    gate.complete(1);
    await tester.pump();

    expect(revision.value, 1);
  });
}
