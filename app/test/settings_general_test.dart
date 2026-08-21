import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/soft_delete_retention.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

/// Pumps the [SettingsScreen] on a wide (side-by-side) surface with the scopes
/// it depends on, backed by [repos], and opens the General section.
Future<void> _pumpGeneral(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  // Tall enough that every General row (including the Deleted items section
  // near the bottom) renders without scrolling — a ListView only builds
  // children within its viewport + cache extent, so a short surface can leave
  // a lower row unbuilt and unreachable by finders.
  // Matches the convention already used by settings_screen_test.dart.
  await tester.binding.setSurfaceSize(const Size(1200, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(customThemes.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: const SettingsScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
  await tester.pumpAndSettle();
}

CompendiumRepositories _openRepos() => openTestRepositories();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('soft-delete retention defaults to 30 days and is reachable', (
    tester,
  ) async {
    final repos = _openRepos();

    await _pumpGeneral(tester, repos);

    final dropdown = find.byKey(
      const ValueKey('general-soft-delete-retention'),
    );
    expect(dropdown, findsOneWidget);
    expect(
      tester.widget<DropdownButton<int>>(dropdown).value,
      kSoftDeleteRetentionDefaultDays,
      reason: 'retention defaults to 30 days when unset (ROADMAP G.4)',
    );
  });

  testWidgets('changing retention to Never persists the sentinel', (
    tester,
  ) async {
    final repos = _openRepos();

    await _pumpGeneral(tester, repos);

    await tester.tap(
      find.byKey(const ValueKey('general-soft-delete-retention')),
    );
    await tester.pumpAndSettle();
    // The dropdown menu overlays duplicate item labels; tap the last "Never".
    await tester.tap(find.text('Never').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const ValueKey('general-soft-delete-retention')),
          )
          .value,
      kSoftDeleteRetentionNever,
    );
    expect(
      await repos.settings.get(kSoftDeleteRetentionKey),
      kSoftDeleteRetentionNever,
    );
  });

  testWidgets('retention reflects the persisted value on reload', (
    tester,
  ) async {
    final repos = _openRepos();
    await repos.settings.set(kSoftDeleteRetentionKey, 90);

    await _pumpGeneral(tester, repos);
    // Let the lazy one-time read resolve.
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const ValueKey('general-soft-delete-retention')),
          )
          .value,
      90,
    );
  });
}
