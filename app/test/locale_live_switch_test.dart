import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/locale_scope.dart';
import 'support/full_app_harness.dart';

Locale? _appLocale(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).locale;

void main() {
  // The shell keeps the User Guide alive, so its doc FutureBuilder builds
  // offstage on startup; the root-bundle cache turns repeat loads into
  // SynchronousFutures that stall pumpAndSettle. Clearing it each test makes the
  // guide load fresh and settle.
  setUp(rootBundle.clear);

  testWidgets(
    'the App language selector switches MaterialApp.locale live and persists '
    'both a chosen locale and the return to System default',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appData = openTestAppData();
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
        ),
      );
      await tester.pumpAndSettle();

      // No stored preference yet: the app follows the system locale.
      expect(_appLocale(tester), isNull);

      // Navigate to Settings ▸ Language & region.
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-regional')));
      await tester.pumpAndSettle();

      // Select English from the language dropdown.
      await tester.tap(find.byKey(const ValueKey('regional-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();

      // The ListenableBuilder rebuilds MaterialApp.locale live, and the choice
      // is persisted as a BCP-47 tag.
      expect(_appLocale(tester), const Locale('en'));
      expect(await appData.repositories.settings.get(kLocaleKey), 'en');

      // Selecting the nullable System-default option clears the locale live and
      // persists the follow-system sentinel (empty tag).
      await tester.tap(find.byKey(const ValueKey('regional-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('System default').last);
      await tester.pumpAndSettle();

      expect(_appLocale(tester), isNull);
      expect(await appData.repositories.settings.get(kLocaleKey), '');
    },
  );

  // `_appLocale` reads the stored preference (null = follow system); the locale
  // the UI actually resolved to is only visible through Localizations.
  group('System default resolution', () {
    Future<Locale> resolvedFor(
      WidgetTester tester,
      List<Locale> deviceLocales,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.localesTestValue = deviceLocales;
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final appData = openTestAppData();
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
        ),
      );
      await tester.pumpAndSettle();
      expect(_appLocale(tester), isNull);
      return Localizations.localeOf(
        tester.element(find.byType(Scaffold).first),
      );
    }

    testWidgets('system locale es_ES falls back to English', (tester) async {
      expect(
        await resolvedFor(tester, const [Locale('es', 'ES')]),
        const Locale('en'),
      );
    });

    testWidgets('an undetermined (C/POSIX) locale falls back to English', (
      tester,
    ) async {
      expect(
        await resolvedFor(tester, const [Locale('und')]),
        const Locale('en'),
      );
    });

    testWidgets('a later supported entry in the preference list wins', (
      tester,
    ) async {
      expect(
        await resolvedFor(tester, const [
          Locale('es', 'ES'),
          Locale('de', 'DE'),
        ]),
        const Locale('de'),
      );
    });

    testWidgets('a regional English locale still resolves to English', (
      tester,
    ) async {
      expect(
        await resolvedFor(tester, const [Locale('en', 'GB')]),
        const Locale('en'),
      );
    });
  });
}
