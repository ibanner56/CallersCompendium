import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/set_list_color_coding_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';

import 'package:compendium_app/l10n/app_localizations.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

/// Pumps the [SettingsScreen] (Appearance is the default section) with the
/// scopes it depends on, including a [SetListColorCodingScope] seeded from
/// [initialColorCoding].
Future<ValueNotifier<bool>> _pumpAppearance(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool initialColorCoding = true,
  Locale? locale,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final colorCoding = ValueNotifier<bool>(initialColorCoding);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(colorCoding.dispose);
  addTearDown(customThemes.dispose);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
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
              child: SetListColorCodingScope(
                notifier: colorCoding,
                child: const SettingsScreen(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('settings-nav-appearance')));
  await tester.pumpAndSettle();
  // The toggle sits below the theme gallery in a lazily-built ListView; scroll
  // it into view so it is built and hit-testable.
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('appearance-set-list-color-coding')),
    240,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  return colorCoding;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('colour-code toggle defaults on and is AT-reachable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repos = openTestRepositories();

    await _pumpAppearance(tester, repos);

    final toggle = find.byKey(
      const ValueKey('appearance-set-list-color-coding'),
    );
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(
      tester.getSemantics(
        find.descendant(of: toggle, matching: find.byType(Switch)),
      ),
      isSemantics(
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
        isEnabled: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('toggling colour-coding off persists and flips the scope', (
    tester,
  ) async {
    final repos = openTestRepositories();

    final notifier = await _pumpAppearance(tester, repos);

    await tester.tap(
      find.byKey(const ValueKey('appearance-set-list-color-coding')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('appearance-set-list-color-coding')),
          )
          .value,
      isFalse,
    );
    expect(notifier.value, isFalse);
    expect(await repos.settings.get(kSetListColorCodingKey), isFalse);
  });

  group('theme gallery labels are localized (CS-47)', () {
    final de = lookupAppLocalizations(const Locale('de'));

    Future<void> pumpDe(WidgetTester tester) async {
      await _pumpAppearance(
        tester,
        openTestRepositories(),
        locale: const Locale('de'),
      );
      // The gallery sits above the toggle the harness scrolled to; bring the
      // top of the list back so its cards are built.
      tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
    }

    testWidgets('group headings and generic theme names are German', (
      tester,
    ) async {
      await pumpDe(tester);

      expect(find.text('Light'), findsNothing);
      expect(find.text('High contrast'), findsNothing);
      expect(find.text('Soft Dark'), findsNothing);
      expect(find.text(de.appThemeGroupLight), findsWidgets);
      expect(find.text(de.appThemeGroupDark), findsWidgets);
      expect(find.text(de.appThemeLabelHighContrast), findsOneWidget);
      expect(find.text(de.appThemeLabelSoftDark), findsOneWidget);
      // Brand palette names are proper nouns and stay literal.
      expect(find.text('Dracula'), findsOneWidget);
    });

    testWidgets('card semantics read the localized "name. description"', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpDe(tester);

      Finder cardLabel(String label) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      );
      expect(
        cardLabel(
          '${de.appThemeLabelHighContrast}. '
          '${de.appThemeDescriptionHighContrast}',
        ),
        findsOneWidget,
      );
      expect(
        cardLabel(
          '${de.appThemeLabelSoftDark}. ${de.appThemeDescriptionSoftDark}',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
