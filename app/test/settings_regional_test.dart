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
  ValueNotifier<DateFormatSetting> dateFormat,
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
  final dateFormat = ValueNotifier<DateFormatSetting>(
    dateFormatSettingFromStored(
      await repos.settings.get(kDateFormatKey),
      await repos.settings.get(kDateFormatCustomPatternKey),
    ),
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

  testWidgets('renders two live controls and a disabled first-day-of-week row', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpRegional(tester, repos);

    // Language and date format are real, enabled controls.
    expect(find.byKey(const ValueKey('regional-language')), findsOneWidget);
    expect(find.byKey(const ValueKey('regional-date-format')), findsOneWidget);
    // First day of week is present but disabled with a "Coming soon" badge: its
    // plumbing ships, but no consumer applies it yet.
    expect(
      find.byKey(const ValueKey('regional-first-day-of-week')),
      findsOneWidget,
    );
    expect(find.text('Coming soon'), findsOneWidget);
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
    expect(notifiers.dateFormat.value, DateFormatSetting(DateFormatPref.ymd));
  });

  testWidgets('selecting Custom reveals the pattern field + legend and a valid '
      'pattern persists and takes effect (#584)', (tester) async {
    final repos = openTestRepositories();
    final notifiers = await _pumpRegional(tester, repos);

    await tester.tap(find.byKey(const ValueKey('regional-date-format')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…').last);
    await tester.pumpAndSettle();

    // The pattern field and its always-visible token legend are revealed.
    expect(
      find.byKey(const ValueKey('regional-date-format-custom-pattern')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('regional-date-format-custom-legend')),
      findsOneWidget,
    );
    // The custom token persists immediately on selection.
    expect(
      await repos.settings.get(kDateFormatKey),
      DateFormatPref.custom.token,
    );

    // Typing a valid pattern persists it and drives the live setting.
    await tester.enterText(
      find.byKey(const ValueKey('regional-date-format-custom-pattern')),
      'MM.DD.YY',
    );
    await tester.pumpAndSettle();
    expect(await repos.settings.get(kDateFormatCustomPatternKey), 'MM.DD.YY');
    expect(
      notifiers.dateFormat.value,
      DateFormatSetting(DateFormatPref.custom, customPattern: 'MM.DD.YY'),
    );
    expect(notifiers.dateFormat.value.effectivePattern, isNotNull);
  });

  testWidgets('an invalid stored custom pattern shows the inline warning and '
      'stays effective-system until corrected (#584)', (tester) async {
    final repos = openTestRepositories();
    await repos.settings.set(kDateFormatKey, DateFormatPref.custom.token);
    await repos.settings.set(kDateFormatCustomPatternKey, 'nope');
    final notifiers = await _pumpRegional(tester, repos);

    const warning =
        "Unrecognized pattern — using the system default until it's corrected.";
    expect(find.text(warning), findsOneWidget);
    expect(notifiers.dateFormat.value.hasInvalidCustomPattern, isTrue);
    expect(notifiers.dateFormat.value.effectivePattern, isNull);

    // Correcting the pattern clears the warning and validates.
    await tester.enterText(
      find.byKey(const ValueKey('regional-date-format-custom-pattern')),
      'yyyy-MM-dd',
    );
    await tester.pumpAndSettle();
    expect(find.text(warning), findsNothing);
    expect(notifiers.dateFormat.value.effectivePattern, isNotNull);
  });

  testWidgets('a persisted valid custom pattern loads into the dropdown and '
      'field (#584)', (tester) async {
    final repos = openTestRepositories();
    await repos.settings.set(kDateFormatKey, DateFormatPref.custom.token);
    await repos.settings.set(kDateFormatCustomPatternKey, 'MM.DD.YY');
    final notifiers = await _pumpRegional(tester, repos);

    expect(
      tester
          .widget<DropdownButton<DateFormatPref>>(
            find.byKey(const ValueKey('regional-date-format')),
          )
          .value,
      DateFormatPref.custom,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('regional-date-format-custom-pattern')),
          )
          .controller
          ?.text,
      'MM.DD.YY',
    );
    expect(notifiers.dateFormat.value.effectivePattern, isNotNull);
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

  testWidgets('the first-day-of-week row is disabled and does not persist', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final notifiers = await _pumpRegional(tester, repos);

    // The row is a disabled ListTile (not an interactive control): tapping it
    // opens no menu and writes nothing, and the notifier keeps its default.
    final tile = tester.widget<ListTile>(
      find.byKey(const ValueKey('regional-first-day-of-week')),
    );
    expect(tile.enabled, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('regional-first-day-of-week')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(await repos.settings.get(kFirstDayOfWeekKey), isNull);
    expect(notifiers.firstDayOfWeek.value, FirstDayOfWeekPref.system);
  });
}
