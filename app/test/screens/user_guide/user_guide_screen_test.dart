import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/user_guide/user_guide_screen.dart';

import '../../support/fake_url_launcher.dart';

Future<void> _pumpGuide(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: UserGuideScreen()));
  await tester.pumpAndSettle();
}

/// Invokes the current guide's link handler as if the user tapped a link with
/// [href], exercising the real classify-and-act wiring without depending on the
/// Markdown renderer's internal tap hit-testing.
void _tapLink(WidgetTester tester, String href) {
  final markdown = tester.widget<Markdown>(find.byType(Markdown));
  markdown.onTapLink!('link', href, '');
}

void main() {
  // The root asset bundle caches parsed results (the asset manifest and each
  // guide's string) as `SynchronousFuture`s after the first load. Under the
  // test binding that cached-synchronous path stalls the guide's FutureBuilders
  // on every test after the first, so clear the cache before each test to make
  // each one load the guides fresh.
  setUp(rootBundle.clear);

  testWidgets('opens on the documentation hub', (tester) async {
    await _pumpGuide(tester);

    // The panel title reads "User guide" at the hub, and the guide renders.
    expect(find.widgetWithText(AppBar, 'User guide'), findsOneWidget);
    expect(find.byType(Markdown), findsOneWidget);
    // At the root of the in-panel stack the leading affordance is a close icon.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('user-guide-back')),
        matching: find.byIcon(Icons.close),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an internal link navigates within the panel and back returns', (
    tester,
  ) async {
    await _pumpGuide(tester);

    _tapLink(tester, 'imports.md');
    await tester.pumpAndSettle();

    // Navigated to the Imports guide; the leading affordance is now a back arrow.
    expect(find.widgetWithText(AppBar, 'Imports'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('user-guide-back')),
        matching: find.byIcon(Icons.arrow_back),
      ),
      findsOneWidget,
    );

    // Back returns to the hub (still inside the panel, not popped away).
    await tester.tap(find.byKey(const ValueKey('user-guide-back')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'User guide'), findsOneWidget);
  });

  testWidgets('a not-yet-written guide surfaces a message, not navigation', (
    tester,
  ) async {
    await _pumpGuide(tester);

    _tapLink(tester, './perform.md');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining("Perform"), findsWidgets);
    expect(find.textContaining("isn't available yet"), findsOneWidget);
    // Still on the hub — no navigation happened.
    expect(find.widgetWithText(AppBar, 'User guide'), findsOneWidget);
  });

  testWidgets('an external link opens in the browser', (tester) async {
    final launcher = installFakeUrlLauncher();
    await _pumpGuide(tester);

    _tapLink(tester, 'https://example.com/help');
    await tester.pumpAndSettle();

    expect(launcher.lastLaunchedUrl, 'https://example.com/help');
    // The panel stays put on the hub.
    expect(find.widgetWithText(AppBar, 'User guide'), findsOneWidget);
  });

  testWidgets('a link to a repo doc outside the bundle opens on GitHub', (
    tester,
  ) async {
    final launcher = installFakeUrlLauncher();
    await _pumpGuide(tester);

    _tapLink(tester, '../design/dialect.md');
    await tester.pumpAndSettle();

    expect(launcher.lastLaunchedUrl, isNotNull);
    expect(
      launcher.lastLaunchedUrl,
      contains('/blob/main/docs/design/dialect.md'),
    );
  });
}
