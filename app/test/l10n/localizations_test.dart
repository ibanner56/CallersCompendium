import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/locale_scope.dart';
import 'package:compendium_app/src/data/window_service.dart';
import 'package:compendium_app/src/screens/app_shell.dart';
import '../support/test_repositories.dart';

/// A [WindowService] whose restore does nothing — the plugin glue is untestable
/// under `flutter test`, and these tests only exercise the locale wiring that
/// follows the restore.
class _NoopWindowService extends WindowService {
  _NoopWindowService(super.settings);

  @override
  Future<void> initialize() async {}

  @override
  void dispose() {}
}

AppData _openAppData() {
  final appData = AppData(openWidgetTestDatabase(closeOnTearDown: false));
  addTearDown(appData.close);
  return appData;
}

Locale? _materialAppLocale(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).locale;

void main() {
  // Booting the full app mounts [AppShell] (whose kept-alive User Guide loads a
  // cached doc); clearing the bundle cache before each test lets that
  // FutureBuilder settle. Mirrors startup_sequence_test.
  setUp(rootBundle.clear);

  testWidgets('the app resolves AppLocalizations and renders English by '
      'default', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return Text(l10n.appTitle);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(l10n.appTitle, "Caller's Compendium");
    expect(find.text("Caller's Compendium"), findsOneWidget);
    // English is a supported locale (the source locale for this PR).
    expect(AppLocalizations.supportedLocales, contains(const Locale('en')));
  });

  testWidgets('a persisted, supported locale is applied on startup', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final appData = _openAppData();
    await appData.repositories.settings.set(kLocaleKey, 'en');

    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: _NoopWindowService(appData.repositories.settings),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(_materialAppLocale(tester), const Locale('en'));
  });

  testWidgets('a garbage persisted locale falls back to system (null) without '
      'crashing startup', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final appData = _openAppData();
    // Untrusted/corrupted value: must never select an unsupported locale or
    // throw — the app boots in the system locale (null).
    await appData.repositories.settings.set(kLocaleKey, 'zz-not-a-locale');

    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: _NoopWindowService(appData.repositories.settings),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(_materialAppLocale(tester), isNull);
  });
}
