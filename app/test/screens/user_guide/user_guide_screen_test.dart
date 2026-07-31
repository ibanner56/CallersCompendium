import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/reduce_motion_scope.dart';
import 'package:compendium_app/src/screens/user_guide/user_guide_screen.dart';
import 'package:compendium_app/src/screens/user_guide/user_guide_doc_view.dart';

import '../../support/fake_url_launcher.dart';
import '../../support/l10n_harness.dart';

Future<void> _pumpGuide(WidgetTester tester) async {
  // The guide is embeddable now (no self-Scaffold), so host it in a Scaffold —
  // the ScaffoldMessenger target for its "coming soon" SnackBars.
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: const Scaffold(body: UserGuideScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumps frames until [finder] matches at least one widget, or the bounded
/// budget of [maxAttempts] × [step] elapses. Returns as soon as the match
/// appears rather than waiting a fixed duration, so an async-triggered widget
/// (e.g. a SnackBar whose entrance frame timing varies across CI runners) is
/// awaited robustly without waiting its full display window. Fails fast if the
/// widget never appears (the caller's expectation then reports the miss).
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 40,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < maxAttempts; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
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

  testWidgets('reserves the safe-area insets around the guide', (tester) async {
    const topInset = 100.0;
    const bottomInset = 40.0;
    // Host the guide without an AppBar (the in-shell IndexedStack path) under
    // nonzero insets, mimicking iOS's status bar / Dynamic Island and home
    // indicator. The guide must inset itself so the header stops below the top
    // inset rather than sliding under it, and its body stays clear of the home
    // indicator on hosts without a bottom nav bar.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
        ),
        child: MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: const Scaffold(body: UserGuideScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Exactly one SafeArea wraps the guide — no double-insetting from a host or
    // a stray inner SafeArea. Count both ancestors and descendants of the
    // guide's Column so an extra wrapper anywhere around it would fail here.
    final guide = find.byKey(const ValueKey('user-guide-screen'));
    final ancestorSafeAreas = find.ancestor(
      of: guide,
      matching: find.byType(SafeArea),
    );
    final descendantSafeAreas = find.descendant(
      of: guide,
      matching: find.byType(SafeArea),
    );
    expect(ancestorSafeAreas, findsOneWidget);
    expect(descendantSafeAreas, findsNothing);
    final wrappingSafeArea = tester.widget<SafeArea>(ancestorSafeAreas);
    expect(wrappingSafeArea.top, isTrue);

    // The header title is pushed below the top inset rather than overlapping it.
    final titleTop = tester
        .getTopLeft(find.byKey(const ValueKey('user-guide-title')))
        .dy;
    expect(titleTop, greaterThanOrEqualTo(topInset));
  });

  testWidgets('an internal link navigates within the panel and back returns', (
    tester,
  ) async {
    await _pumpGuide(tester);

    _tapLink(tester, 'imports.md');
    await tester.pumpAndSettle();

    // Navigated to the Imports guide; an in-content back affordance appears.
    // The header takes the guide's own H1, not a name derived from the file.
    expect(_title(tester), 'Imports & migration');
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
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
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
      expect(_title(tester), 'Imports & migration');

      // A system back press is blocked by the sibling PopScope; the inactive
      // guide keeps its stack rather than rewinding to the hub.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_title(tester), 'Imports & migration');
    },
  );

  testWidgets('a not-yet-written guide surfaces a message, not navigation', (
    tester,
  ) async {
    await _pumpGuide(tester);

    // Use a sibling guide that is guaranteed never to be bundled, rather than a
    // real-but-not-yet-written filename: this test loads the *actual* asset
    // bundle, so any guide a future docs PR adds (as #239 did for perform.md)
    // would otherwise silently turn this "missing" case into a navigation and
    // break the test. `labelForDoc` renders it in sentence case ("Not a real
    // guide") for the coming-soon message.
    _tapLink(tester, './not-a-real-guide.md');
    // The "coming soon" SnackBar is shown when the tap is handled, but its
    // build/entrance frame timing varies across CI runners — a fixed-duration
    // pump can miss it. Wait until the message is actually present (bounded, so
    // a genuine failure still fails fast) instead.
    await _pumpUntilFound(tester, find.textContaining("isn't available yet"));

    expect(find.textContaining('Not a real guide'), findsWidgets);
    expect(find.textContaining("isn't available yet"), findsOneWidget);
    // Still on the hub — no navigation happened.
    expect(_title(tester), 'User guide');
  });

  testWidgets(
    'the header titles a guide by its own heading, not its file name',
    (tester) async {
      // `faq.md` would read as "Faq" if the title came from the file name; the
      // header takes the guide's H1 instead so it reads the way the guide does.
      await _pumpGuide(tester);

      _tapLink(tester, 'faq.md');
      await tester.pumpAndSettle();

      expect(_title(tester), 'FAQ & troubleshooting');
    },
  );

  testWidgets('an in-page anchor link scrolls to that heading', (tester) async {
    // A guide with enough prose that the target heading starts well below the
    // fold, so a successful scroll is unambiguous.
    const target = 'The far heading';
    final source = StringBuffer('# A guide\n\n[Jump](#the-far-heading)\n\n');
    for (var i = 0; i < 60; i++) {
      source.writeln('Filler paragraph $i.\n');
    }
    source.writeln('## $target\n\nYou made it.\n');

    Widget build(String? anchor) => MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: UserGuideDocView(
          docId: 'demo.md',
          data: source.toString(),
          anchor: anchor,
          onTapLink: (_) {},
        ),
      ),
    );

    await tester.pumpWidget(build(null));
    await tester.pumpAndSettle();

    double offset() => tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!
        .offset;
    final viewportHeight = tester.getSize(find.byType(UserGuideDocView)).height;
    final heading = find.text(target);

    // The heading is laid out even though it is off screen — that is what makes
    // it reachable at all, since a lazy list would never have built it.
    expect(offset(), 0);
    expect(heading, findsOneWidget);
    expect(tester.getTopLeft(heading).dy, greaterThan(viewportHeight));

    // Following the link scrolls the heading into view.
    await tester.pumpWidget(build('the-far-heading'));
    await tester.pumpAndSettle();

    expect(offset(), greaterThan(0));
    expect(tester.getTopLeft(heading).dy, lessThan(viewportHeight));
  });

  testWidgets('anchor scrolling jumps instantly when Reduce motion is on', (
    tester,
  ) async {
    // WCAG 2.3.3: a motion-sensitive reader following an "on this page" link
    // should land on the heading rather than be flung there.
    const target = 'The far heading';
    final source = StringBuffer('# A guide\n\n[Jump](#the-far-heading)\n\n');
    for (var i = 0; i < 60; i++) {
      source.writeln('Filler paragraph $i.\n');
    }
    source.writeln('## $target\n\nYou made it.\n');

    Widget build({required bool reduceMotion}) => MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: ReduceMotionScope(
        notifier: ValueNotifier<bool?>(reduceMotion),
        child: Scaffold(
          body: UserGuideDocView(
            // A fresh key per case so each starts from a new, unscrolled state.
            key: ValueKey('reduce-motion-$reduceMotion'),
            docId: 'demo.md',
            data: source.toString(),
            anchor: 'the-far-heading',
            onTapLink: (_) {},
          ),
        ),
      ),
    );

    double offset() => tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!
        .offset;

    // Reduce motion on: the scroll has already landed on the frame after the
    // one that laid the guide out — no animation to settle.
    await tester.pumpWidget(build(reduceMotion: true));
    await tester.pump();
    final jumped = offset();
    expect(jumped, greaterThan(0));

    // Reduce motion off: the same frame is still at the top because the 250ms
    // animation has yet to advance; it arrives at the same place once settled.
    await tester.pumpWidget(build(reduceMotion: false));
    await tester.pump();
    expect(offset(), 0);
    await tester.pumpAndSettle();
    expect(offset(), moreOrLessEquals(jumped, epsilon: 1));
  });

  testWidgets('an anchor that matches no heading leaves the guide at the top', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: UserGuideDocView(
            docId: 'demo.md',
            data: '# A guide\n\n## Real heading\n\nBody.\n',
            anchor: 'no-such-heading',
            onTapLink: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No exception, and the reader simply starts where the guide starts.
    expect(find.text('Real heading'), findsOneWidget);
    expect(
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!
          .offset,
      0,
    );
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
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
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
