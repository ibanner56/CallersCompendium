import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/dialect_library_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_app/src/screens/perform_dance_screen.dart';
import 'package:compendium_app/src/screens/perform_walkthrough_overlay.dart';
import 'package:compendium_app/src/screens/settings_screen.dart'
    show
        kAutoSizePerformKey,
        kPerformCanonicalViewKey,
        kPerformStageModeKey,
        kPerformTextScaleKey;
import 'package:compendium_app/src/theme/app_typography.dart';
import 'package:compendium_app/src/theme/color_schemes.dart';

import 'support/test_repositories.dart';
import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

final _renderer = FigureRenderer(contraTaxonomy);

Dance _dance({
  String id = 'd1',
  String title = 'Test Dance',
  List<Figure> figures = const [],
  DanceStatus status = DanceStatus.active,
  DanceLevel? level,
  String walkthrough = '',
}) => Dance(
  id: id,
  title: title,
  figures: figures,
  status: status,
  level: level,
  walkthrough: walkthrough,
  createdAt: _now,
  updatedAt: _now,
);

Figure _chain() =>
    Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16});

/// A [SettingsRepository] whose auto-size read blocks until [gate] completes,
/// so a test can deterministically drive the "settings load resolves *after*
/// the user has already acted" race (ROADMAP G.1).
class _GatedSettings extends SettingsRepository {
  _GatedSettings(super.db, {required this.gate, required this.persistedValue});

  final Completer<void> gate;
  final bool persistedValue;

  @override
  Future<Object?> get(String key) async {
    if (key == kAutoSizePerformKey) {
      await gate.future;
      return persistedValue;
    }
    return super.get(key);
  }
}

Future<void> _pumpPerform(
  WidgetTester tester, {
  required Dance dance,
  List<String> authorNames = const [],
  Dialect? activeDialect,
  bool autoSize = false,
  Size surfaceSize = const Size(1400, 2400),
  DialectLibraryController? dialectLibrary,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(activeDialect ?? Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final repos = openTestRepositories();
  await repos.settings.set(kAutoSizePerformKey, autoSize);
  Widget withLibrary(Widget child) => dialectLibrary == null
      ? child
      : DialectLibraryScope(controller: dialectLibrary, child: child);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: withLibrary(
          ActiveDialectScope(notifier: notifier, child: child!),
        ),
      ),
      home: PerformDanceScreen(
        dance: dance,
        renderer: _renderer,
        authorNames: authorNames,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetail(
  WidgetTester tester,
  CompendiumRepositories repos,
  String danceId, {
  Dialect? activeDialect,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(activeDialect ?? Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: DanceDetailScreen(danceId: danceId),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installFakeWakelock);

  group('AppBar responsive overflow (issue #433)', () {
    // The single-dance Perform toolbar shares the responsive overflow with the
    // program view: on narrow phones secondary actions collapse into a "More
    // actions" overflow while the stage-mode toggle and dialect quick-switch
    // stay inline; the full set shows inline on wide layouts. Mount
    // DialectLibraryScope so the quick-switch renders and keep a non-canonical
    // dialect so the canonical toggle is part of the set.

    Future<DialectLibraryController> loadedLibrary() async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      final controller = DialectLibraryController(repos.settings);
      await controller.load();
      addTearDown(controller.dispose);
      return controller;
    }

    Future<void> pumpFullSet(WidgetTester tester, Size size) async {
      await _pumpPerform(
        tester,
        dance: _dance(figures: [_chain()]),
        surfaceSize: size,
        dialectLibrary: await loadedLibrary(),
      );
    }

    const inlineSecondaryKeys = [
      'perform-metronome',
      'decrease-text-size',
      'increase-text-size',
      'perform-autosize-toggle',
      'perform-dialect-toggle',
    ];
    const overflowItemKeys = [
      'perform-metronome-menu',
      'decrease-text-size-menu',
      'increase-text-size-menu',
      'perform-autosize-toggle-menu',
      'perform-dialect-toggle-menu',
    ];

    for (final width in const [360.0, 430.0]) {
      testWidgets(
        'collapses secondary actions with no overflow at ${width.toInt()}px',
        (tester) async {
          await pumpFullSet(tester, Size(width, 900));

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('perform-stage-toggle')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('dialect-quick-switch')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('perform-overflow-menu')),
            findsOneWidget,
          );
          for (final key in inlineSecondaryKeys) {
            expect(
              find.byKey(ValueKey(key)),
              findsNothing,
              reason: '$key should be collapsed into the overflow menu',
            );
          }

          await tester.tap(find.byKey(const ValueKey('perform-overflow-menu')));
          await tester.pumpAndSettle();
          for (final key in overflowItemKeys) {
            expect(
              find.byKey(ValueKey(key)),
              findsOneWidget,
              reason: '$key should be reachable via the overflow menu',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('shows the full action set inline on a wide tablet', (
      tester,
    ) async {
      await pumpFullSet(tester, const Size(1024, 1366));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('perform-overflow-menu')), findsNothing);
      expect(
        find.byKey(const ValueKey('dialect-quick-switch')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('perform-stage-toggle')),
        findsOneWidget,
      );
      for (final key in inlineSecondaryKeys) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
    });
  });

  testWidgets('renders title, author, and a figure with the active dialect', (
    tester,
  ) async {
    await _pumpPerform(
      tester,
      dance: _dance(title: 'Midwest Folklore', figures: [_chain()]),
      authorNames: const ['Gene Hubert'],
    );

    expect(find.text('Midwest Folklore'), findsOneWidget);
    expect(find.text('Gene Hubert'), findsOneWidget);
    // Section header derived from the phrase structure.
    expect(find.text('A1'), findsOneWidget);
    // Larks/Robins preset: role2s -> robins.
    expect(find.text('robins chain'), findsOneWidget);
  });

  testWidgets(
    'renders figure rows and section headers in Atkinson, title in Fraunces',
    (tester) async {
      await _pumpPerform(
        tester,
        dance: _dance(title: 'Midwest Folklore', figures: [_chain()]),
        authorNames: const ['Gene Hubert'],
      );

      // Perform is the accessibility-critical surface: the distance-read body
      // (figure rows + phrase section headers) must render in the Atkinson
      // Hyperlegible face, not the Fraunces serif (§1c).
      final figureStyle = tester.widget<Text>(find.text('robins chain')).style;
      expect(figureStyle?.fontFamily, AppTypography.bodyFamily);

      final sectionStyle = tester.widget<Text>(find.text('A1')).style;
      expect(sectionStyle?.fontFamily, AppTypography.bodyFamily);

      final authorStyle = tester.widget<Text>(find.text('Gene Hubert')).style;
      expect(authorStyle?.fontFamily, AppTypography.bodyFamily);

      // The dance title keeps Fraunces for brand identity.
      final titleStyle = tester
          .widget<Text>(find.byKey(const ValueKey('perform-title')))
          .style;
      expect(titleStyle?.fontFamily, AppTypography.displayFamily);
    },
  );

  testWidgets('figure line announces the verbose form to assistive tech', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpPerform(
      tester,
      dance: _dance(
        figures: [
          Figure(
            move: 'allemande',
            params: {'hand': 'left', 'turn': 1.5, 'beats': 8},
          ),
        ],
      ),
    );

    // The large-print card keeps the terse, glyph-bearing text on screen.
    expect(find.text('neighbor allemande left 1½'), findsOneWidget);

    // Assistive tech hears the spoken-friendly expansion, glyph-free, as the
    // figure line's single merged semantics label.
    final semantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('one and a half times')),
    );
    expect(
      semantics.label,
      contains('neighbor allemande left one and a half times, 8 beats'),
    );
    expect(semantics.label, isNot(contains('1½')));
    handle.dispose();
  });

  testWidgets('canonical toggle flips the rendered figure text', (
    tester,
  ) async {
    await _pumpPerform(tester, dance: _dance(figures: [_chain()]));

    expect(find.text('robins chain'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('perform-dialect-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('role2s chain'), findsOneWidget);
  });

  testWidgets('dialect toggle is hidden when active dialect is canonical', (
    tester,
  ) async {
    await _pumpPerform(
      tester,
      dance: _dance(figures: [_chain()]),
      activeDialect: Dialect.canonical,
    );

    expect(find.byKey(const ValueKey('perform-dialect-toggle')), findsNothing);
    // Canonical tokens render verbatim.
    expect(find.text('role2s chain'), findsOneWidget);
  });

  testWidgets('size control increases and decreases the applied text scale', (
    tester,
  ) async {
    await _pumpPerform(
      tester,
      dance: _dance(title: 'Fizz', figures: [_chain()]),
    );

    final titleFinder = find.byKey(const ValueKey('perform-title'));
    final baseWidth = tester.getSize(titleFinder).width;

    await tester.tap(find.byKey(const ValueKey('increase-text-size')));
    await tester.pumpAndSettle();
    final largerWidth = tester.getSize(titleFinder).width;
    expect(largerWidth, greaterThan(baseWidth));

    await tester.tap(find.byKey(const ValueKey('decrease-text-size')));
    await tester.tap(find.byKey(const ValueKey('decrease-text-size')));
    await tester.pumpAndSettle();
    final smallerWidth = tester.getSize(titleFinder).width;
    expect(smallerWidth, lessThan(baseWidth));
  });

  testWidgets('shows status banner for a non-active dance', (tester) async {
    await _pumpPerform(tester, dance: _dance(status: DanceStatus.broken));
    expect(find.text('Broken'), findsOneWidget);
  });

  testWidgets('opens in the dark-stage high-contrast theme by default', (
    tester,
  ) async {
    await _pumpPerform(tester, dance: _dance(figures: [_chain()]));

    final scheme = Theme.of(
      tester.element(find.byType(PerformCard)),
    ).colorScheme;
    expect(scheme, AppColorSchemes.highContrast);
    expect(scheme.brightness, Brightness.dark);
    expect(scheme.surface, AppColorSchemes.highContrast.surface);
  });

  testWidgets('stage toggle falls back to the ambient theme and back', (
    tester,
  ) async {
    await _pumpPerform(tester, dance: _dance(figures: [_chain()]));

    // Default on: stage theme.
    expect(
      Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
      AppColorSchemes.highContrast,
    );

    // Toggle off -> the ambient MaterialApp (light) theme applies.
    await tester.tap(find.byKey(const ValueKey('perform-stage-toggle')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
      isNot(AppColorSchemes.highContrast),
    );

    // Toggle back on -> stage restored.
    await tester.tap(find.byKey(const ValueKey('perform-stage-toggle')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
      AppColorSchemes.highContrast,
    );
  });

  testWidgets('stage toggle is keyboard/AT-reachable with on/off state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await _pumpPerform(tester, dance: _dance(figures: [_chain()]));

    final toggle = find.byKey(const ValueKey('perform-stage-toggle'));
    // Default on: focusable, tappable button announcing its toggled state.
    expect(
      tester.getSemantics(toggle),
      isSemantics(
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasToggledState: true,
        isToggled: true,
      ),
      reason: 'stage toggle must announce its on state',
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(toggle),
      isSemantics(
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasToggledState: true,
        isToggled: false,
      ),
      reason: 'stage toggle must announce its off state after tapping',
    );

    handle.dispose();
  });

  testWidgets('exit and size controls are keyboard- and AT-reachable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await _pumpPerform(tester, dance: _dance(figures: [_chain()]));

    // Each control must expose a tap action, an accessible name (via its
    // tooltip — the standard icon-button pattern; a redundant Semantics label
    // would double-announce), and be focusable — not merely have a non-null
    // onPressed.
    for (final (key, label) in const [
      ('exit-perform', 'Exit performance view'),
      ('decrease-text-size', 'Decrease text size'),
      ('increase-text-size', 'Increase text size'),
    ]) {
      expect(
        tester.getSemantics(find.byKey(ValueKey(key))),
        isSemantics(
          tooltip: label,
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
        ),
        reason: '$key must be labelled, focusable, and tappable',
      );
    }

    handle.dispose();
  });

  testWidgets(
    'dialect toggle exposes a single named toggle (no double-announce)',
    (tester) async {
      final handle = tester.ensureSemantics();

      await _pumpPerform(tester, dance: _dance(figures: [_chain()]));

      // The icon button carries the accessible name (via its tooltip — the
      // standard icon-button pattern) plus the toggle role/state. A redundant
      // Semantics label would double-announce, so none is set. The decorative
      // "Canonical" text no longer exists, so nothing is announced separately.
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('perform-dialect-toggle')),
        ),
        isSemantics(
          tooltip: 'Show canonical terms',
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasToggledState: true,
        ),
      );
      expect(find.bySemanticsLabel('Canonical'), findsNothing);

      handle.dispose();
    },
  );

  testWidgets('detail "Perform this dance" action navigates to the view', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Perform Me'));

    await _pumpDetail(tester, repos, 'd1');

    await tester.tap(find.byKey(const ValueKey('perform-dance')));
    await tester.pumpAndSettle();

    expect(find.byType(PerformDanceScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('perform-title')), findsOneWidget);
  });

  testWidgets('exit control returns to the detail screen', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Perform Me'));

    await _pumpDetail(tester, repos, 'd1');

    await tester.tap(find.byKey(const ValueKey('perform-dance')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformDanceScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('exit-perform')));
    await tester.pumpAndSettle();

    expect(find.byType(PerformDanceScreen), findsNothing);
    expect(find.byType(DanceDetailScreen), findsOneWidget);
  });

  group('auto-size (ROADMAP G.1)', () {
    testWidgets(
      'grows the text beyond the manual default to fill the viewport',
      (tester) async {
        await _pumpPerform(
          tester,
          dance: _dance(title: 'Fizz', figures: [_chain()]),
          autoSize: true,
        );

        // A short dance on a large surface auto-scales beyond the manual
        // large-print default (the effective text scaler at the title, over
        // the unit system scale used in tests, exceeds kPerformDefaultScale).
        final titleElement = tester.element(
          find.byKey(const ValueKey('perform-title')),
        );
        final effectiveScale = MediaQuery.of(titleElement).textScaler.scale(1);
        expect(effectiveScale, greaterThan(kPerformDefaultScale));
      },
    );

    testWidgets('chooses a larger scale on a taller viewport', (tester) async {
      final titleFinder = find.byKey(const ValueKey('perform-title'));
      final dance = _dance(
        title: 'Fizz',
        figures: [_chain(), _chain(), _chain(), _chain()],
      );

      await _pumpPerform(
        tester,
        dance: dance,
        autoSize: true,
        surfaceSize: const Size(1400, 900),
      );
      final shortWidth = tester.getSize(titleFinder).width;

      await _pumpPerform(
        tester,
        dance: dance,
        autoSize: true,
        surfaceSize: const Size(1400, 2400),
      );
      final tallWidth = tester.getSize(titleFinder).width;

      expect(tallWidth, greaterThan(shortWidth));
    });

    testWidgets('a long dance on a small screen scrolls without overflowing', (
      tester,
    ) async {
      await _pumpPerform(
        tester,
        dance: _dance(
          title: 'A very long dance indeed',
          figures: List.filled(12, _chain()),
        ),
        autoSize: true,
        surfaceSize: const Size(400, 300),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('tapping A+ hands control back to the manual size', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPerform(
        tester,
        dance: _dance(title: 'Fizz', figures: [_chain()]),
        autoSize: true,
      );

      final toggle = find.byKey(const ValueKey('perform-autosize-toggle'));
      expect(tester.getSemantics(toggle), isSemantics(isToggled: true));

      await tester.tap(find.byKey(const ValueKey('increase-text-size')));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(toggle),
        isSemantics(isToggled: false),
        reason: 'using A+ switches the session to manual sizing',
      );
      handle.dispose();
    });

    testWidgets('auto-size toggle is AT-reachable and reflects its state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPerform(
        tester,
        dance: _dance(figures: [_chain()]),
        autoSize: true,
      );

      final toggle = find.byKey(const ValueKey('perform-autosize-toggle'));
      expect(
        tester.getSemantics(toggle),
        isSemantics(
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasToggledState: true,
          isToggled: true,
        ),
        reason: 'auto-size toggle must announce its on state',
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(toggle),
        isSemantics(
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasToggledState: true,
          isToggled: false,
        ),
        reason: 'auto-size toggle must announce its off state after tapping',
      );
      handle.dispose();
    });

    testWidgets(
      'a toggle before the persisted load resolves wins (no clobber)',
      (tester) async {
        final handle = tester.ensureSemantics();
        // Dispose inside the body (not addTearDown): flutter_test's
        // end-of-test semantics-handle check runs *before* tearDown callbacks,
        // so a deferred dispose would trip "SemanticsHandle was active". The
        // try/finally still releases it if an expect() throws early.
        try {
          await tester.binding.setSurfaceSize(const Size(1400, 2400));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          // Persisted value is ON, but the read is gated so it stays in-flight
          // while the user acts.
          final gate = Completer<void>();
          final db = CompendiumDatabase(NativeDatabase.memory());
          addTearDown(db.close);
          final repos = CompendiumRepositories(
            db,
            contraTaxonomy,
            settings: _GatedSettings(db, gate: gate, persistedValue: true),
          );
          final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
          addTearDown(notifier.dispose);

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: testLocalizationsDelegates,
              supportedLocales: testSupportedLocales,
              builder: (context, child) => RepositoriesScope(
                repositories: repos,
                child: ActiveDialectScope(notifier: notifier, child: child!),
              ),
              home: PerformDanceScreen(
                dance: _dance(figures: [_chain()]),
                renderer: _renderer,
              ),
            ),
          );
          // One frame: the screen is up and its settings read is pending on the
          // gate; auto-size shows its on-by-default state.
          await tester.pump();

          final toggle = find.byKey(const ValueKey('perform-autosize-toggle'));
          await tester.tap(toggle);
          await tester.pump();
          expect(
            tester.getSemantics(toggle),
            isSemantics(isToggled: false),
            reason: 'user turned auto-size off before the load resolved',
          );

          // Now let the persisted (on) value arrive late. The guard must keep
          // the user's off choice rather than clobbering it back on.
          gate.complete();
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(toggle),
            isSemantics(isToggled: false),
            reason: 'a late persisted load must not override an in-view action',
          );
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets('the tap-tempo button opens the metronome sheet', (
      tester,
    ) async {
      await _pumpPerform(tester, dance: _dance());

      await tester.tap(find.byKey(const ValueKey('perform-metronome')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tap-tempo-target')), findsOneWidget);
      expect(find.text('Tap to set tempo'), findsOneWidget);
    });
  });

  group('a11y prefs persistence (issue #449)', () {
    // Builds the Perform view against a caller-supplied repositories instance so
    // a test can seed the settings store first (restore) or read it back after
    // interacting (write-through). Mirrors [_pumpPerform] but shares one store.
    Future<void> pumpWith(
      WidgetTester tester,
      CompendiumRepositories repos, {
      required Dance dance,
      Dialect? activeDialect,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = ValueNotifier<Dialect>(
        activeDialect ?? Dialect.larksRobins,
      );
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: ActiveDialectScope(notifier: notifier, child: child!),
          ),
          home: PerformDanceScreen(dance: dance, renderer: _renderer),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('restores persisted stage mode and canonical view on entry', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(kAutoSizePerformKey, false);
      await repos.settings.set(kPerformStageModeKey, false);
      await repos.settings.set(kPerformCanonicalViewKey, true);

      await pumpWith(tester, repos, dance: _dance(figures: [_chain()]));

      // Stage mode restored OFF -> the ambient (non-stage) theme applies.
      expect(
        Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
        isNot(AppColorSchemes.highContrast),
      );
      // Canonical view restored ON -> figures show canonical tokens.
      expect(find.text('role2s chain'), findsOneWidget);
      expect(find.text('robins chain'), findsNothing);
    });

    testWidgets('restores a persisted manual text scale on entry', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(kAutoSizePerformKey, false);
      await repos.settings.set(
        kPerformTextScaleKey,
        kPerformDefaultScale + 2 * kPerformScaleStep,
      );

      await pumpWith(
        tester,
        repos,
        dance: _dance(title: 'Fizz', figures: [_chain()]),
      );

      // Manual mode with an empty store renders at exactly the default scale,
      // so a restored larger scale must read above the default.
      final restoredScale = MediaQuery.of(
        tester.element(find.byKey(const ValueKey('perform-title'))),
      ).textScaler.scale(1);
      expect(restoredScale, greaterThan(kPerformDefaultScale));
    });

    testWidgets('applies defaults and does not crash when the store is empty', (
      tester,
    ) async {
      final repos = openTestRepositories();

      await pumpWith(tester, repos, dance: _dance(figures: [_chain()]));

      expect(tester.takeException(), isNull);
      // Stage on by default.
      expect(
        Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
        AppColorSchemes.highContrast,
      );
      // Canonical off by default -> active-dialect tokens.
      expect(find.text('robins chain'), findsOneWidget);
      expect(find.text('role2s chain'), findsNothing);
    });

    testWidgets('writes each pref through to the settings store on change', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(kAutoSizePerformKey, false);

      await pumpWith(tester, repos, dance: _dance(figures: [_chain()]));

      await tester.tap(find.byKey(const ValueKey('perform-stage-toggle')));
      await tester.pumpAndSettle();
      expect(await repos.settings.get(kPerformStageModeKey), isFalse);

      await tester.tap(find.byKey(const ValueKey('perform-dialect-toggle')));
      await tester.pumpAndSettle();
      expect(await repos.settings.get(kPerformCanonicalViewKey), isTrue);

      await tester.tap(find.byKey(const ValueKey('increase-text-size')));
      await tester.pumpAndSettle();
      final storedScale = await repos.settings.get(kPerformTextScaleKey);
      expect(storedScale, isA<num>());
      expect(
        (storedScale as num).toDouble(),
        greaterThan(kPerformDefaultScale),
      );
    });
  });

  group('walkthrough overlay (issue #370)', () {
    testWidgets('no toggle is shown when the dance has no walkthrough', (
      tester,
    ) async {
      await _pumpPerform(tester, dance: _dance(figures: [_chain()]));
      expect(
        find.byKey(const ValueKey('perform-walkthrough-toggle')),
        findsNothing,
      );
    });

    testWidgets('toggling shows then hides the walkthrough overlay', (
      tester,
    ) async {
      await _pumpPerform(
        tester,
        dance: _dance(
          figures: [_chain()],
          walkthrough: 'A1: neighbours balance and swing.',
        ),
      );

      final toggle = find.byKey(const ValueKey('perform-walkthrough-toggle'));
      expect(toggle, findsOneWidget);
      // Off by default: the overlay is absent until requested.
      expect(find.byType(PerformWalkthroughOverlay), findsNothing);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byType(PerformWalkthroughOverlay), findsOneWidget);
      expect(find.text('A1: neighbours balance and swing.'), findsOneWidget);

      // Closing from within the overlay hides it again.
      await tester.tap(find.byKey(const ValueKey('perform-walkthrough-close')));
      await tester.pumpAndSettle();
      expect(find.byType(PerformWalkthroughOverlay), findsNothing);
    });

    testWidgets(
      'overlay is a sibling of the card, never inside its auto-size subtree',
      (tester) async {
        // The overlay must not participate in PerformCard's _FitToHeight
        // measurement (#370/#527): assert it is NOT a descendant of the card
        // even with auto-size on, so surfacing it can never shrink the notation.
        await _pumpPerform(
          tester,
          autoSize: true,
          dance: _dance(
            figures: [_chain()],
            walkthrough: 'A1: neighbours balance and swing.',
          ),
        );

        await tester.tap(
          find.byKey(const ValueKey('perform-walkthrough-toggle')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PerformWalkthroughOverlay), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(PerformCard),
            matching: find.byType(PerformWalkthroughOverlay),
          ),
          findsNothing,
        );
      },
    );
  });
}
