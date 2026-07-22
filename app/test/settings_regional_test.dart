import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/date_format_scope.dart';
import 'package:compendium_app/src/data/first_day_of_week_scope.dart';
import 'package:compendium_app/src/data/locale_scope.dart';
import 'package:compendium_app/src/data/regional_formats.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

/// The live notifiers the Language & region controls read and mutate, seeded
/// (with validation) from persisted settings — mirroring how `main.dart` wires
/// them so the section behaves in tests exactly as it does in the running app.
typedef _RegionalNotifiers = ({
  ValueNotifier<Locale?> locale,
  ValueNotifier<DateFormatPref> dateFormat,
  ValueNotifier<FirstDayOfWeekPref> firstDayOfWeek,
});

/// Pumps the [SettingsScreen] with the Language & region scopes wired (each
/// seeded from its persisted key, validated), the l10n delegates installed, and
/// opens the Language & region section. Returns the live notifiers so tests can
/// assert that a control change flows through to app-wide state.
Future<_RegionalNotifiers> _pumpRegional(
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
  final firstDayOfWeek = ValueNotifier<FirstDayOfWeekPref>(
    firstDayOfWeekPrefFromStored(await repos.settings.get(kFirstDayOfWeekKey)),
  );
  final locale = ValueNotifier<Locale?>(
    localeFromStored(
      await repos.settings.get(kLocaleKey),
      AppLocalizations.supportedLocales,
    ),
  );
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(customThemes.dispose);
  addTearDown(dateFormat.dispose);
  addTearDown(firstDayOfWeek.dispose);
  addTearDown(locale.dispose);

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
              child: DateFormatScope(
                notifier: dateFormat,
                child: FirstDayOfWeekScope(
                  notifier: firstDayOfWeek,
                  child: LocaleScope(
                    notifier: locale,
                    child: const SettingsScreen(),
                  ),
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

  return (
    locale: locale,
    dateFormat: dateFormat,
    firstDayOfWeek: firstDayOfWeek,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('regional section renders three live format/language controls', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpRegional(tester, repos);

    // All three controls are real, enabled dropdowns (no "Coming soon").
    expect(find.byKey(const ValueKey('regional-language')), findsOneWidget);
    expect(find.byKey(const ValueKey('regional-date-format')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('regional-first-day-of-week')),
      findsOneWidget,
    );
    expect(find.text('Coming soon'), findsNothing);
    // The platform-picker limitation note is surfaced to the user.
    expect(
      find.text(
        "The system date picker follows the app's active language, so this "
        "setting doesn't change it.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('the date-format dropdown shows the persisted value', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kDateFormatKey, DateFormatPref.ymd.token);
    await _pumpRegional(tester, repos);

    expect(
      tester
          .widget<DropdownButton<DateFormatPref>>(
            find.byKey(const ValueKey('regional-date-format')),
          )
          .value,
      DateFormatPref.ymd,
    );
  });

  testWidgets('changing the date format persists its key and updates state', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final notifiers = await _pumpRegional(tester, repos);

    await tester.tap(find.byKey(const ValueKey('regional-date-format')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year-month-day (2026-07-15)').last);
    await tester.pumpAndSettle();

    expect(await repos.settings.get(kDateFormatKey), DateFormatPref.ymd.token);
    expect(notifiers.dateFormat.value, DateFormatPref.ymd);
  });

  testWidgets('the language dropdown defaults to System default (null)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final notifiers = await _pumpRegional(tester, repos);

    expect(
      tester
          .widget<DropdownButton<Locale?>>(
            find.byKey(const ValueKey('regional-language')),
          )
          .value,
      isNull,
    );
    expect(notifiers.locale.value, isNull);
    // A null value renders the dropdown's hint, so the closed button must still
    // display the localized "System default" label rather than being blank.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('regional-language')),
        matching: find.text('System default'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('selecting a language persists its tag and updates the notifier '
      'live', (tester) async {
    final repos = openTestRepositories();
    final notifiers = await _pumpRegional(tester, repos);

    await tester.tap(find.byKey(const ValueKey('regional-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    // Persisted as a BCP-47 tag and reflected in the live notifier.
    expect(await repos.settings.get(kLocaleKey), 'en');
    expect(notifiers.locale.value, const Locale('en'));
    expect(
      tester
          .widget<DropdownButton<Locale?>>(
            find.byKey(const ValueKey('regional-language')),
          )
          .value,
      const Locale('en'),
    );
  });

  testWidgets('a persisted locale tag is validated and shown on load', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kLocaleKey, 'en');
    final notifiers = await _pumpRegional(tester, repos);

    expect(notifiers.locale.value, const Locale('en'));
    expect(
      tester
          .widget<DropdownButton<Locale?>>(
            find.byKey(const ValueKey('regional-language')),
          )
          .value,
      const Locale('en'),
    );
  });

  testWidgets('a garbage persisted locale tag falls back to System default', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kLocaleKey, 'zz-not-a-locale');
    final notifiers = await _pumpRegional(tester, repos);

    // Unknown tag ⇒ null (follow system), never throws or selects it.
    expect(notifiers.locale.value, isNull);
  });

  testWidgets('changing first day of week persists its key and updates state', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final notifiers = await _pumpRegional(tester, repos);

    await tester.tap(find.byKey(const ValueKey('regional-first-day-of-week')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monday').last);
    await tester.pumpAndSettle();

    expect(
      await repos.settings.get(kFirstDayOfWeekKey),
      FirstDayOfWeekPref.monday.token,
    );
    expect(notifiers.firstDayOfWeek.value, FirstDayOfWeekPref.monday);
  });
}
