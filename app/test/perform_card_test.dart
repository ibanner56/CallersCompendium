import 'dart:math' as math;

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/canonical_discouraged_terms_scope.dart';
import 'package:compendium_app/src/data/formation_colors_controller.dart';
import 'package:compendium_app/src/data/formation_colors_scope.dart';
import 'package:compendium_app/src/data/reduce_motion_scope.dart';
import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_app/src/theme/set_list_accents.dart';
import 'package:compendium_app/src/widgets/formation_color_badge.dart';
import 'package:compendium_app/src/widgets/program_status_chip.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

final _renderer = FigureRenderer(contraTaxonomy);
final _now = DateTime.utc(2026, 1, 1);

Dance _dance() => Dance(
  id: 'd1',
  title: 'Test Dance',
  form: DanceForm.contra,
  formation: const Formation(FormationShape.becketCw),
  createdAt: _now,
  updatedAt: _now,
);

Future<FormationColorsController> _controllerWith(Color? override) async {
  final repos = openTestRepositories();
  await repos.ensureMigrated();
  final controller = FormationColorsController(repos.settings);
  await controller.load();
  if (override != null) {
    await controller.setColor(FormationShape.becketCw, override);
  }
  return controller;
}

Future<void> _pump(WidgetTester tester, FormationColorsController c) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,

      home: Scaffold(
        body: FormationColorsScope(
          controller: c,
          child: PerformCard(
            dance: _dance(),
            renderer: _renderer,
            dialect: Dialect.larksRobins,
            textScale: 1.0,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('formation label uses the contrast-safe foreground when '
      'overridden (issue #367, ruling 1)', (tester) async {
    const yellow = Color(0xFFFFEB3B); // light ⇒ expects a dark foreground
    final c = await _controllerWith(yellow);
    await _pump(tester, c);

    final label = tester.widget<Text>(find.text('Becket (CW)'));
    // The badge's readable foreground wins over the themed onSurface colour.
    expect(label.style?.color, readableForegroundOn(yellow));
    expect(label.style?.color, const Color(0xFF000000));
    // And the label is actually wrapped in the highlight badge.
    expect(
      find.ancestor(
        of: find.text('Becket (CW)'),
        matching: find.byType(FormationColorBadge),
      ),
      findsOneWidget,
    );
  });

  testWidgets('formation label is not badged when not overridden', (
    tester,
  ) async {
    final c = await _controllerWith(null);
    await _pump(tester, c);

    // No override ⇒ no highlight badge around the formation label.
    expect(
      find.ancestor(
        of: find.text('Becket (CW)'),
        matching: find.byType(FormationColorBadge),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'auto-size re-measures the fit when the system text scale changes '
    '(no stale converged scale / overflow)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final c = await _controllerWith(null);
      // A dance tall enough that the auto-fit converges to an *interior* scale
      // (strictly between min and max) that fills the viewport at text scale
      // 1.0 — so a text-scale change forces a real re-measure.
      final dance = Dance(
        id: 'd1',
        title: 'A Dance With Many Figures',
        figures: [
          for (var i = 0; i < 12; i++)
            Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
        ],
        status: DanceStatus.active,
        createdAt: _now,
        updatedAt: _now,
      );

      var systemScale = 1.0;
      late StateSetter setScale;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: StatefulBuilder(
            builder: (context, setState) {
              setScale = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(systemScale)),
                child: Scaffold(
                  body: FormationColorsScope(
                    controller: c,
                    child: PerformCard(
                      dance: dance,
                      renderer: _renderer,
                      dialect: Dialect.larksRobins,
                      textScale: 1.0,
                      autoSize: true,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      Size titleSize() =>
          tester.getSize(find.byKey(const ValueKey('perform-title')));

      expect(tester.takeException(), isNull);
      final before = titleSize();

      // Enlarge the OS text scale with the viewport dimensions unchanged. A
      // stale cache would keep the old (now too large) converged scale and skip
      // measurement, so the composed text would roughly double and overflow.
      // The fix invalidates the cached scale on a text-scale change and
      // re-measures to the largest scale that still fits, so the rendered
      // title stays about the same height.
      setScale(() => systemScale = 2.0);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final after = titleSize();
      // The re-measured fit keeps the title about the same height. Without the
      // fix the stale converged scale would leave it ~2x larger (and overflow),
      // so a generous 25% tolerance still catches the regression.
      expect(after.height, closeTo(before.height, before.height * 0.25));
    },
  );

  // A dance tall enough that, at the manual large-print floor (scale 1.0), its
  // card far exceeds a smaller-than-fullscreen window — the issue #527 repro.
  Dance tallDance() => Dance(
    id: 'tall',
    title: 'A Dance With Many Figures',
    figures: [
      for (var i = 0; i < 8; i++)
        Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
    ],
    callingNotes:
        'Balance and swing your neighbour, then long lines forward '
        'and back before the ladies chain across the set.',
    status: DanceStatus.active,
    createdAt: _now,
    updatedAt: _now,
  );

  Future<void> pumpAutoSized(
    WidgetTester tester,
    Dance dance,
    Size window,
    FormationColorsController controller,
  ) async {
    await tester.binding.setSurfaceSize(window);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: SafeArea(
            child: FormationColorsScope(
              controller: controller,
              child: PerformCard(
                dance: dance,
                renderer: _renderer,
                dialect: Dialect.larksRobins,
                textScale: 1.0,
                autoSize: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Like [pumpAutoSized] but wraps a [ReduceMotionScope] override and does
  /// *not* settle, so the test can step frame-by-frame through the auto-fit
  /// search (issue #628, F-L3).
  Future<void> pumpAutoSizedWithMotionSetting(
    WidgetTester tester,
    Dance dance,
    Size window,
    FormationColorsController controller, {
    required bool reduceMotion,
  }) async {
    await tester.binding.setSurfaceSize(window);
    final notifier = ValueNotifier<bool>(reduceMotion);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: ReduceMotionScope(
          notifier: notifier,
          child: Scaffold(
            body: SafeArea(
              child: FormationColorsScope(
                controller: controller,
                child: PerformCard(
                  dance: dance,
                  renderer: _renderer,
                  dialect: Dialect.larksRobins,
                  textScale: 1.0,
                  autoSize: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The [Opacity] that gates the auto-fit search's visibility while it has
  /// not yet converged (see `_FitToHeightState.build`).
  Opacity fitOpacity(WidgetTester tester) => tester.widget<Opacity>(
    find.ancestor(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Opacity),
    ),
  );

  ScrollPosition scrollPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  /// The size a figure row's text is actually drawn at: its style's font size
  /// through the paragraph's own text scaler (system scale × in-view scale).
  double figureFontSize(WidgetTester tester) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.textContaining('robins chain').first,
    );
    return paragraph.textScaler.scale(paragraph.text.style!.fontSize!);
  }

  /// The app's body text size under [systemScale] — the floor auto-size may
  /// not shrink the figures below.
  double osBodySize(WidgetTester tester, double systemScale) {
    final context = tester.element(find.byType(PerformCard));
    return Theme.of(context).textTheme.bodyLarge!.fontSize! * systemScale;
  }

  for (final systemScale in const [1.0, 3.0]) {
    testWidgets(
      'auto-size never draws the figures below the OS-scaled body size; a '
      'card too tall for that scrolls instead (${systemScale}x text)',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final c = await _controllerWith(null);

        // The issue #527 window: smaller than full screen, too short for the
        // whole tall card at a readable size. The fit used to shrink the card
        // to a fifth of the user's size to avoid scrolling; at accessibility
        // text sizes that drew the figures *smaller* than at the default size.
        await tester.binding.setSurfaceSize(const Size(720, 620));
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(systemScale)),
                child: Scaffold(
                  body: SafeArea(
                    child: FormationColorsScope(
                      controller: c,
                      child: PerformCard(
                        dance: tallDance(),
                        renderer: _renderer,
                        dialect: Dialect.larksRobins,
                        textScale: 1.0,
                        autoSize: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          figureFontSize(tester),
          greaterThanOrEqualTo(osBodySize(tester, systemScale) - 0.01),
        );
        // Below the floor the card scrolls rather than clipping…
        final pos = scrollPosition(tester);
        expect(pos.maxScrollExtent, greaterThan(0.0));
        // …and its last section stays reachable.
        pos.jumpTo(pos.maxScrollExtent);
        await tester.pump();
        expect(
          find.textContaining('robins chain across the set.'),
          findsOneWidget,
        );
      },
    );
  }

  for (final systemScale in const [1.0, 3.0]) {
    testWidgets(
      'at the auto-size floor, figure notes, the beats label and the status '
      'banner are not drawn below the OS-scaled body size '
      '(${systemScale}x text)',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final c = await _controllerWith(null);
        // Figure notes, the beats label and the status banner are drawn
        // smaller than the figure lines the fit's floor is computed from.
        final dance = Dance(
          id: 'tall-notes',
          title: 'Notes',
          figures: [
            for (var i = 0; i < 8; i++)
              Figure(
                move: 'chain',
                params: {'who': 'role2s', 'beats': 16},
                note: 'Note $i',
              ),
          ],
          status: DanceStatus.deprecated,
          createdAt: _now,
          updatedAt: _now,
        );
        await tester.binding.setSurfaceSize(const Size(720, 620));
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(systemScale)),
                child: Scaffold(
                  body: SafeArea(
                    child: FormationColorsScope(
                      controller: c,
                      child: PerformCard(
                        dance: dance,
                        renderer: _renderer,
                        dialect: Dialect.larksRobins,
                        textScale: 1.0,
                        autoSize: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        double drawn(Finder finder) {
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          return paragraph.textScaler.scale(paragraph.text.style!.fontSize!);
        }

        final body = osBodySize(tester, systemScale);
        // The card is at the floor: its figure lines are at the OS body size
        // and it scrolls. Without that, the checks below prove nothing.
        expect(scrollPosition(tester).maxScrollExtent, greaterThan(0.0));
        expect(figureFontSize(tester), closeTo(body, 0.5));

        expect(
          drawn(find.text('Note 0')),
          greaterThanOrEqualTo(body - 0.01),
          reason: 'figure note',
        );
        expect(
          drawn(find.text('Deprecated')),
          greaterThanOrEqualTo(body - 0.01),
          reason: 'status banner',
        );
        // The beats label keeps its cap, which wins where it is lower.
        final beatsFloor =
            body / systemScale * math.min(systemScale, kBeatsLabelMaxTextScale);
        expect(
          drawn(find.text('16 beats').first),
          greaterThanOrEqualTo(beatsFloor - 0.01),
          reason: 'beats label',
        );
      },
    );
  }

  testWidgets(
    'auto-size never draws a free-text card below the OS-scaled body size',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(420, 220));
      const systemScale = 3.0;
      final long = List.filled(12, 'Waltz break, then announcements').join(' ');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(systemScale)),
              child: Scaffold(
                body: PerformTextCard(
                  text: long,
                  textScale: 1.0,
                  renderer: _renderer,
                  dialect: Dialect.larksRobins,
                  autoSize: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byKey(const ValueKey('perform-text')),
      );
      final drawn = paragraph.textScaler.scale(paragraph.text.style!.fontSize!);
      final body =
          Theme.of(
            tester.element(find.byType(PerformTextCard)),
          ).textTheme.bodyLarge!.fontSize! *
          systemScale;
      expect(drawn, greaterThanOrEqualTo(body - 0.01));
      // The card's own body is larger than ordinary body text, so its floor
      // sits below it: the card does shrink, just not past the body size.
      expect(drawn, lessThan(body * 1.5));
    },
  );

  testWidgets(
    'auto-size keeps the whole card reachable by scrolling when even the '
    'smallest fit overflows a very short window (never clipped, issue #527)',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = await _controllerWith(null);

      // A window too short for even the minimum auto scale. The card must not
      // clip: the SingleChildScrollView fallback keeps every section reachable.
      await pumpAutoSized(tester, tallDance(), const Size(420, 220), c);

      expect(tester.takeException(), isNull);
      final pos = scrollPosition(tester);
      // Content is taller than the viewport, so it is scrollable rather than cut
      // off — "content is never hidden".
      expect(pos.maxScrollExtent, greaterThan(0.0));

      // Scroll to the end and confirm the last section can be revealed.
      pos.jumpTo(pos.maxScrollExtent);
      await tester.pump();
      expect(
        find.textContaining('robins chain across the set.'),
        findsOneWidget,
      );
    },
  );

  // Regression for issue #628 (F-L3): the auto-fit search's multi-frame
  // grow-in (see `_FitToHeightState._measureAndStep`) must honour Reduce
  // motion — hidden while searching, the final size then appearing in one
  // step — matching the pattern #447 established elsewhere (e.g. `Shimmer`).
  testWidgets(
    'auto-size hides the multi-frame grow-in search when Reduce motion is '
    'on, then reveals the final size in one step (issue #628)',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = await _controllerWith(null);

      // A window the tall card fits at a scale above the auto-size floor but
      // well below the ceiling, so the search needs several frames to grow
      // and bisect to converge, and a stray visible frame would be caught.
      await pumpAutoSizedWithMotionSetting(
        tester,
        tallDance(),
        const Size(720, 1400),
        c,
        reduceMotion: true,
      );

      var revealed = false;
      var hiddenFrames = 0;
      for (var i = 0; i < 40 && !revealed; i++) {
        await tester.pump();
        final opacity = fitOpacity(tester).opacity;
        if (opacity == 1.0) {
          revealed = true;
        } else {
          expect(opacity, 0.0);
          hiddenFrames++;
        }
      }

      // The search must actually have taken multiple (hidden) frames to
      // converge — otherwise this test would pass vacuously even without the
      // opacity gate (e.g. if the fit converged in a single frame).
      expect(hiddenFrames, greaterThan(1));
      // …and it must actually have converged (not just hit the frame cap) and
      // reveal a correctly-sized, non-overflowing card.
      expect(revealed, isTrue);
      expect(tester.takeException(), isNull);
      expect(scrollPosition(tester).maxScrollExtent, lessThan(1.0));
      expect(
        find.textContaining('robins chain across the set.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'auto-size grow-in stays visible throughout when Reduce motion is off '
    '(issue #628, unchanged behaviour)',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = await _controllerWith(null);

      await pumpAutoSizedWithMotionSetting(
        tester,
        tallDance(),
        const Size(720, 1400),
        c,
        reduceMotion: false,
      );

      // With motion allowed the fit is visible from the very first frame,
      // throughout the search and after it settles.
      expect(fitOpacity(tester).opacity, 1.0);
      for (var i = 0; i < 10; i++) {
        await tester.pump();
        expect(fitOpacity(tester).opacity, 1.0);
      }

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(fitOpacity(tester).opacity, 1.0);
      expect(scrollPosition(tester).maxScrollExtent, lessThan(1.0));
    },
  );

  testWidgets(
    'auto-size becomes visible under Reduce motion even when the search '
    'settles without ever changing the scale (issue #628 follow-up)',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = await _controllerWith(null);

      // A window too short for even the minimum auto scale (the #527 "never
      // clipped" repro): the very first measurement overflows at `minScale`
      // (the scale `_scale` already starts at), so `_settle` converges without
      // ever changing `_scale`. Before the fix that meant `setState` was never
      // called on this transition, leaving the content stuck at `Opacity: 0`
      // under Reduce motion forever.
      await pumpAutoSizedWithMotionSetting(
        tester,
        tallDance(),
        const Size(420, 220),
        c,
        reduceMotion: true,
      );

      var revealed = false;
      for (var i = 0; i < 10 && !revealed; i++) {
        await tester.pump();
        if (fitOpacity(tester).opacity == 1.0) revealed = true;
      }

      expect(revealed, isTrue);
      expect(tester.takeException(), isNull);
      // The scrollable fallback still keeps the (unshrinkable) content
      // reachable, exactly as the motion-off #527 test asserts.
      expect(scrollPosition(tester).maxScrollExtent, greaterThan(0.0));
    },
  );

  // Regression for issue #619: a figure note is the only free-text field not
  // routed through renderFreeText, so a canonical role token leaked verbatim
  // into the performed figure row instead of following the active dialect.
  testWidgets(
    'figure note with a role token renders in the active dialect (issue #619)',
    (tester) async {
      final c = await _controllerWith(null);
      final dance = _dance().copyWith(
        figures: [
          Figure(
            move: 'allemande',
            params: {'who': 'role2s', 'travel': 1.0},
            note: 'role2s scoop them up',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: FormationColorsScope(
              controller: c,
              child: PerformCard(
                dance: dance,
                renderer: _renderer,
                dialect: Dialect.larksRobins,
                textScale: 1.0,
              ),
            ),
          ),
        ),
      );

      expect(find.text('robins scoop them up'), findsOneWidget);
      expect(find.text('role2s scoop them up'), findsNothing);
    },
  );

  // Regression for the review comment on #619: `Substitutor` treats `_` as a
  // word character, so a role token immediately touching an emphasis
  // delimiter (`_role2s_`) would not match a naive whole-string substitution.
  // The note must be emphasis-parsed (delimiters stripped) BEFORE dialect
  // substitution, exactly like the custom-figure `mainSpans` path, so
  // substitution never depends on adjacent markup.
  testWidgets(
    'figure note substitutes a role token immediately touching emphasis '
    'markup (issue #619 follow-up)',
    (tester) async {
      final c = await _controllerWith(null);
      final dance = _dance().copyWith(
        figures: [
          Figure(
            move: 'allemande',
            params: {'who': 'role2s', 'travel': 1.0},
            note: '_role2s_ scoop them up',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: FormationColorsScope(
              controller: c,
              child: PerformCard(
                dance: dance,
                renderer: _renderer,
                dialect: Dialect.larksRobins,
                textScale: 1.0,
              ),
            ),
          ),
        ),
      );

      // The rendered (delimiter-stripped) text run must read "robins", never
      // the raw canonical token nor the markup-wrapped original.
      expect(find.textContaining('robins scoop them up'), findsOneWidget);
      expect(find.textContaining('role2s'), findsNothing);
      expect(find.textContaining('_role2s_'), findsNothing);
    },
  );

  for (final status in [
    DanceStatus.deprecated,
    DanceStatus.broken,
    DanceStatus.draft,
    DanceStatus.variation,
  ]) {
    testWidgets('the ${status.name} banner uses the Collection chip glyph and '
        'wraps rather than overflowing at a large Perform size', (
      tester,
    ) async {
      final c = await _controllerWith(null);
      await tester.binding.setSurfaceSize(const Size(360, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormationColorsScope(
                controller: c,
                child: PerformCard(
                  dance: Dance(
                    id: 'd1',
                    title: 'Status Dance',
                    status: status,
                    createdAt: _now,
                    updatedAt: _now,
                  ),
                  renderer: _renderer,
                  dialect: Dialect.larksRobins,
                  textScale: 3.0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final expected = danceStatusPresentation(status, l10n);
      final banner = find.ancestor(
        of: find.text(expected.label),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: banner.first, matching: find.byIcon(expected.icon)),
        findsOneWidget,
      );
    });
  }

  group('tune details (meter and key)', () {
    Future<void> pumpCard(
      WidgetTester tester,
      Dance dance, {
      bool canonicalDiscouragedTerms = false,
    }) async {
      final c = await _controllerWith(null);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: CanonicalDiscouragedTermsScope(
              notifier: ValueNotifier<bool>(canonicalDiscouragedTerms),
              child: FormationColorsScope(
                controller: c,
                child: PerformCard(
                  dance: dance,
                  renderer: _renderer,
                  dialect: Dialect.larksRobins,
                  textScale: 1.0,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows the meter and key on one labelled row', (tester) async {
      await pumpCard(
        tester,
        _dance().copyWith(meter: '3/2', musicalKey: 'A minor'),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('perform-tune-details')),
          matching: find.text('Meter: 3/2 · Key: A minor'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows only the meter when no key is set', (tester) async {
      await pumpCard(tester, _dance().copyWith(meter: '6/8'));
      expect(find.text('Meter: 6/8'), findsOneWidget);
      expect(find.textContaining('Key:'), findsNothing);
    });

    testWidgets('has no row when neither is set', (tester) async {
      await pumpCard(tester, _dance());
      expect(find.byKey(const ValueKey('perform-tune-details')), findsNothing);
    });

    testWidgets('renders a discouraged term in the typed value canonically', (
      tester,
    ) async {
      await pumpCard(
        tester,
        _dance().copyWith(musicalKey: 'Gypsy'),
        canonicalDiscouragedTerms: true,
      );
      expect(find.text('Key: Shoulder round'), findsOneWidget);
      expect(find.textContaining('Gypsy'), findsNothing);
    });
  });

  group('credits with years', () {
    Future<void> pumpCard(
      WidgetTester tester,
      Dance dance, {
      List<String> authorNames = const [],
      List<String> interpreterNames = const [],
    }) async {
      final c = await _controllerWith(null);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: FormationColorsScope(
              controller: c,
              child: PerformCard(
                dance: dance,
                renderer: _renderer,
                dialect: Dialect.larksRobins,
                textScale: 1.0,
                authorNames: authorNames,
                interpreterNames: interpreterNames,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows the authors with the composed year and the '
        'interpreters with the interpreted year', (tester) async {
      await pumpCard(
        tester,
        _dance().copyWith(
          composedOn: PartialDate(1651),
          interpretedOn: PartialDate(1916, 5),
        ),
        authorNames: const ['John Playford'],
        interpreterNames: const ['Cecil Sharp', 'George Butterworth'],
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('perform-authors'))).data,
        'John Playford (1651)',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('perform-interpreters')))
            .data,
        'Interpreted by Cecil Sharp, George Butterworth (1916)',
      );
    });

    testWidgets('has no interpreter line without interpreters or a year', (
      tester,
    ) async {
      await pumpCard(tester, _dance(), authorNames: const ['Pat Shaw']);
      expect(find.text('Pat Shaw'), findsOneWidget);
      expect(find.byKey(const ValueKey('perform-interpreters')), findsNothing);
    });
  });

  group('Barnes reference', () {
    Future<void> pumpCard(
      WidgetTester tester,
      Dance dance, {
      bool canonicalDiscouragedTerms = false,
    }) async {
      final c = await _controllerWith(null);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: CanonicalDiscouragedTermsScope(
              notifier: ValueNotifier<bool>(canonicalDiscouragedTerms),
              child: FormationColorsScope(
                controller: c,
                child: PerformCard(
                  dance: dance,
                  renderer: _renderer,
                  dialect: Dialect.larksRobins,
                  textScale: 1.0,
                ),
              ),
            ),
          ),
        ),
      );
    }

    String? barnesRow(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('perform-barnes-reference')),
            matching: find.byType(Text),
          ),
        )
        .data;

    testWidgets('shows the reference on its own labelled row', (tester) async {
      await pumpCard(
        tester,
        _dance().copyWith(form: DanceForm.ecd, barnesReference: 'BIII p. 92'),
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('perform-barnes-reference')),
                matching: find.byType(Text),
              ),
            )
            .data,
        'Barnes: BIII p. 92',
      );
    });

    testWidgets('trims the typed value', (tester) async {
      await pumpCard(
        tester,
        _dance().copyWith(form: DanceForm.ecd, barnesReference: ' BIII p. 92 '),
      );
      expect(barnesRow(tester), 'Barnes: BIII p. 92');
    });

    testWidgets('renders a discouraged term in the value canonically', (
      tester,
    ) async {
      await pumpCard(
        tester,
        _dance().copyWith(form: DanceForm.ecd, barnesReference: 'Gypsy p. 4'),
        canonicalDiscouragedTerms: true,
      );
      expect(barnesRow(tester), 'Barnes: Shoulder round p. 4');
      expect(find.textContaining('Gypsy'), findsNothing);
    });

    testWidgets('has no row when the reference is blank', (tester) async {
      await pumpCard(
        tester,
        _dance().copyWith(form: DanceForm.ecd, barnesReference: '  '),
      );
      expect(
        find.byKey(const ValueKey('perform-barnes-reference')),
        findsNothing,
      );
    });
  });
}
