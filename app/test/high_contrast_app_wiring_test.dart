import 'package:compendium_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/full_app_harness.dart';

/// The OS high-contrast setting must swap in the app's High contrast theme,
/// which is dark: `setListAccentsBright` (and anything else that reads the
/// theme's brightness) relies on that to treat High contrast as dark.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('both high-contrast slots carry the dark High contrast theme', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appData = openTestAppData();
    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.highContrastTheme?.brightness, Brightness.dark);
    expect(app.highContrastDarkTheme?.brightness, Brightness.dark);
  });
}
