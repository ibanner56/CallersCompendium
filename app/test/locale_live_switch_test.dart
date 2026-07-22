import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/locale_scope.dart';
import 'package:compendium_app/src/data/window_service.dart';

/// A [WindowService] whose restore is a no-op: the plugin glue is untestable
/// under `flutter test`, and these tests only care about the running app.
class _NoopWindowService extends WindowService {
  _NoopWindowService(super.settings);

  @override
  Future<void> initialize() async {}

  @override
  void dispose() {}
}

AppData _openAppData() {
  final appData = AppData(CompendiumDatabase(NativeDatabase.memory()));
  addTearDown(appData.close);
  return appData;
}

Locale? _appLocale(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).locale;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

      final appData = _openAppData();
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: _NoopWindowService(appData.repositories.settings),
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
}
