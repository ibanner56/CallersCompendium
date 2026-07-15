import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_app/src/screens/perform_dance_screen.dart';
import 'package:compendium_app/src/theme/color_schemes.dart';

import 'support/test_repositories.dart';
import 'support/fake_wakelock.dart';

final _now = DateTime.utc(2026, 1, 1);

final _renderer = FigureRenderer(contraTaxonomy);

Dance _dance({
  String id = 'd1',
  String title = 'Test Dance',
  List<Figure> figures = const [],
  DanceStatus status = DanceStatus.active,
  DanceLevel? level,
}) => Dance(
  id: id,
  title: title,
  figures: figures,
  status: status,
  level: level,
  createdAt: _now,
  updatedAt: _now,
);

Figure _chain() =>
    Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16});

Future<void> _pumpPerform(
  WidgetTester tester, {
  required Dance dance,
  List<String> authorNames = const [],
  Dialect? activeDialect,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(activeDialect ?? Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          ActiveDialectScope(notifier: notifier, child: child!),
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
    // Larks/Robins preset: role2s -> Robins.
    expect(find.text('Robins chain across'), findsOneWidget);
  });

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
    expect(find.text('neighbors allemande left 1½'), findsOneWidget);

    // Assistive tech hears the spoken-friendly expansion, glyph-free, as the
    // figure line's single merged semantics label.
    final semantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('one and a half times')),
    );
    expect(
      semantics.label,
      contains('neighbors allemande left one and a half times, 8 beats'),
    );
    expect(semantics.label, isNot(contains('1½')));
    handle.dispose();
  });

  testWidgets('canonical toggle flips the rendered figure text', (
    tester,
  ) async {
    await _pumpPerform(tester, dance: _dance(figures: [_chain()]));

    expect(find.text('Robins chain across'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('perform-dialect-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('role2s chain across'), findsOneWidget);
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
    expect(find.text('role2s chain across'), findsOneWidget);
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

      // The Switch carries the accessible name and toggle role; the decorative
      // "Canonical" text is excluded so it isn't announced separately.
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('perform-dialect-toggle')),
        ),
        isSemantics(label: 'Show canonical terms', hasTapAction: true),
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
}
