import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/perform_card.dart';
import '../support/l10n_harness.dart';

/// UX review 6.3 / 6.8: the Perform "Show canonical terms" toggle uses the
/// app's Dialect glyph family (`Icons.groups`), following the outlined-idle /
/// filled-active convention, and never `Icons.translate` (reserved for the app
/// locale in Settings › Language & region).
void main() {
  Future<void> pump(WidgetTester tester, {required bool canonical}) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,

        home: Scaffold(
          appBar: AppBar(
            actions: [
              PerformDialectToggle(canonical: canonical, onChanged: (_) {}),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('shows the outlined Dialect glyph when idle (dialect terms)', (
    tester,
  ) async {
    await pump(tester, canonical: false);

    expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    expect(find.byIcon(Icons.groups), findsNothing);
    expect(find.byIcon(Icons.translate), findsNothing);
  });

  testWidgets('shows the filled Dialect glyph when active (canonical terms)', (
    tester,
  ) async {
    await pump(tester, canonical: true);

    expect(find.byIcon(Icons.groups), findsOneWidget);
    expect(find.byIcon(Icons.groups_outlined), findsNothing);
    expect(find.byIcon(Icons.translate), findsNothing);
  });
}
