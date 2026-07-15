import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/date_format_scope.dart';
import 'package:compendium_app/src/data/first_day_of_week_scope.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';

import 'support/test_repositories.dart';

/// Pumps the [SettingsScreen] with the regional-format scopes wired (seeded from
/// the persisted keys) and opens the Language & region section.
Future<void> _pumpRegional(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  final dateFormat = ValueNotifier<DateFormatPref>(
    dateFormatPrefFromStored(await repos.settings.get(kDateFormatKey)),
  );
  final firstDay = ValueNotifier<FirstDayOfWeekPref>(
    firstDayOfWeekPrefFromStored(await repos.settings.get(kFirstDayOfWeekKey)),
  );
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(customThemes.dispose);
  addTearDown(dateFormat.dispose);
  addTearDown(firstDay.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: DateFormatScope(
                notifier: dateFormat,
                child: FirstDayOfWeekScope(
                  notifier: firstDay,
                  child: const SettingsScreen(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('settings-nav-regional')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('regional section renders both dropdowns and the disabled '
      'language row', (tester) async {
    final repos = openTestRepositories();
    await _pumpRegional(tester, repos);

    expect(find.byKey(const ValueKey('regional-date-format')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('regional-first-day-of-week')),
      findsOneWidget,
    );

    final languageRow = find.byKey(
      const ValueKey('regional-language-placeholder'),
    );
    expect(languageRow, findsOneWidget);
    expect(tester.widget<ListTile>(languageRow).enabled, isFalse);
    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('dropdowns show the persisted values', (tester) async {
    final repos = openTestRepositories();
    await repos.settings.set(kDateFormatKey, DateFormatPref.ymd.token);
    await repos.settings.set(
      kFirstDayOfWeekKey,
      FirstDayOfWeekPref.monday.token,
    );
    await _pumpRegional(tester, repos);

    expect(
      tester
          .widget<DropdownButton<DateFormatPref>>(
            find.byKey(const ValueKey('regional-date-format')),
          )
          .value,
      DateFormatPref.ymd,
    );
    expect(
      tester
          .widget<DropdownButton<FirstDayOfWeekPref>>(
            find.byKey(const ValueKey('regional-first-day-of-week')),
          )
          .value,
      FirstDayOfWeekPref.monday,
    );
  });

  testWidgets('changing the date format persists its key', (tester) async {
    final repos = openTestRepositories();
    await _pumpRegional(tester, repos);

    await tester.tap(find.byKey(const ValueKey('regional-date-format')));
    await tester.pumpAndSettle();
    // The menu shows the option label; pick the year-month-day option.
    await tester.tap(find.text('Year-month-day (2026-07-15)').last);
    await tester.pumpAndSettle();

    expect(await repos.settings.get(kDateFormatKey), DateFormatPref.ymd.token);
    expect(
      tester
          .widget<DropdownButton<DateFormatPref>>(
            find.byKey(const ValueKey('regional-date-format')),
          )
          .value,
      DateFormatPref.ymd,
    );
  });

  testWidgets('changing the first day of week persists its key', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpRegional(tester, repos);

    await tester.tap(find.byKey(const ValueKey('regional-first-day-of-week')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monday').last);
    await tester.pumpAndSettle();

    expect(
      await repos.settings.get(kFirstDayOfWeekKey),
      FirstDayOfWeekPref.monday.token,
    );
  });
}
