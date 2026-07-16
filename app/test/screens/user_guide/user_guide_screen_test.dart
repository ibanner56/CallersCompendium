import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/user_guide/user_guide_screen.dart';
import 'package:compendium_app/src/screens/user_guide/user_guide_doc_view.dart';

import '../../support/fake_url_launcher.dart';

Future<void> _pumpGuide(WidgetTester tester) async {
  // The guide is embeddable now (no self-Scaffold), so host it in a Scaffold —
  // the ScaffoldMessenger target for its "coming soon" SnackBars.
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: UserGuideScreen())),
  );
  await tester.pumpAndSettle();
}

/// The current in-content header title.
String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('user-guide-title'))).data!;

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

    // The in-content header title reads "User guide" at the hub, and the guide
    // renders in the shell content area (no self-hosted AppBar).
    expect(_title(tester), 'User guide');
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(Markdown), findsOneWidget);
    // At the hub there is no back/close affordance — the guide is a shell
    // destination, so the shell nav (not this header) is how you leave it.
    expect(find.byKey(const ValueKey('user-guide-back')), findsNothing);
  });

  testWidgets('an internal link navigates within the panel and back returns', (
    tester,
  ) async {
    await _pumpGuide(tester);

    _tapLink(tester, 'imports.md');
    await tester.pumpAndSettle();

    // Navigated to the Imports guide; an in-content back affordance appears.
    expect(_title(tester), 'Imports');
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
    expect(_title(tester), 'User guide');
  });

  testWidgets(
    'an offscreen (inactive) guide ignores a back press handled elsewhere',
    (tester) async {
      // Reproduces the kept-alive-guide hazard: a sibling PopScope that blocks
      // the pop makes the route report didPop == false to *every* registered
      // PopScope — including an offscreen guide's. An inactive guide must not
      // rewind its in-panel stack in that case.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (_, _) {},
                  child: const SizedBox.shrink(),
                ),
                const Expanded(child: UserGuideScreen(isActive: false)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Build in-panel history on the (visible but inactive) guide.
      _tapLink(tester, 'imports.md');
      await tester.pumpAndSettle();
      expect(_title(tester), 'Imports');

      // A system back press is blocked by the sibling PopScope; the inactive
      // guide keeps its stack rather than rewinding to the hub.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_title(tester), 'Imports');
    },
  );

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
    expect(_title(tester), 'User guide');
  });

  testWidgets('an external link opens in the browser', (tester) async {
    final launcher = installFakeUrlLauncher();
    await _pumpGuide(tester);

    _tapLink(tester, 'https://example.com/help');
    await tester.pumpAndSettle();

    expect(launcher.lastLaunchedUrl, 'https://example.com/help');
    // The panel stays put on the hub.
    expect(_title(tester), 'User guide');
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

  testWidgets('an image reference renders its alt text as a caption', (
    tester,
  ) async {
    // The guide ships text-only: instead of loading an asset, an image renders
    // its alt text as a subtle caption so the prose stays readable and nothing
    // is fetched. Exercise the doc view directly with an inline image so the
    // caption is built regardless of where it falls in a scrolled guide.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserGuideDocView(
            docId: 'getting-started.md',
            data: '![A wireframe of the Collection screen](../design/x.svg)',
            onTapLink: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('A wireframe of the Collection screen'),
      findsOneWidget,
    );
    // Text-only: no image widgets are ever built for the reference.
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the bundle ships text-only (no image assets)', (tester) async {
    // Proves the offline bundle carries only Markdown guides — no SVGs or
    // raster images — so the text-only guide can never depend on a bundled
    // image asset.
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final docAssets = manifest
        .listAssets()
        .where((key) => key.startsWith('assets/docs/'))
        .toList();

    expect(docAssets, isNotEmpty);
    for (final key in docAssets) {
      expect(
        key.toLowerCase().endsWith('.md'),
        isTrue,
        reason: 'Bundled doc asset should be Markdown-only, found: $key',
      );
    }
  });
}
