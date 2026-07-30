import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/screens/import_shorthand_seed_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// Builds the seedable/conflicting split from synthetic CC buttons (own generic
/// contra phrasing — never CC's proprietary set) against [existing] tokens.
ShorthandCandidatePartition _partition(
  List<CcInsertCall> buttons, {
  Set<String> existing = const {},
}) {
  final candidates = buildInsertCallShorthandCandidates(
    buttons,
    taxonomy: contraTaxonomy,
  );
  return partitionInsertCallCandidates(candidates, existing);
}

/// Pumps [ImportShorthandSeedScreen] behind a launcher button so the screen is
/// pushed onto a real navigator. Used by tests that only assert on what the
/// screen renders (not its popped result).
Future<void> _pumpSeed(
  WidgetTester tester,
  ShorthandCandidatePartition partition,
) async {
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          ActiveDialectScope(notifier: dialect, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('launch'),
              onPressed: () =>
                  Navigator.of(context).push<List<ShorthandMapping>>(
                    MaterialPageRoute(
                      builder: (_) => ImportShorthandSeedScreen(
                        seedable: partition.seedable,
                        conflicting: partition.conflicting,
                        dialect: dialect.value,
                      ),
                    ),
                  ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('launch')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders seedable candidates with a figure preview', (
    tester,
  ) async {
    final partition = _partition([
      CcInsertCall(
        label: 'B&S-N',
        text: 'neighbor balance and swing',
        beats: 16,
      ),
      CcInsertCall(label: 'Circle', text: 'circle left 3/4', beats: 8),
    ]);
    await _pumpSeed(tester, partition);

    expect(find.byKey(const ValueKey('seed-tile-b&s-n')), findsOneWidget);
    expect(find.byKey(const ValueKey('seed-tile-circle')), findsOneWidget);
    expect(find.text('B&S-N'), findsOneWidget);
    // Figure preview rendered via the active dialect.
    expect(find.textContaining('swing'), findsWidgets);
  });

  testWidgets('Skip pops an empty list — nothing is seeded', (tester) async {
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    final partition = _partition([
      CcInsertCall(label: 'Sw', text: 'neighbor swing', beats: 8),
    ]);
    List<ShorthandMapping>? result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) =>
            ActiveDialectScope(notifier: dialect, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const ValueKey('launch'),
              onPressed: () async {
                result = await Navigator.of(context)
                    .push<List<ShorthandMapping>>(
                      MaterialPageRoute(
                        builder: (_) => ImportShorthandSeedScreen(
                          seedable: partition.seedable,
                          conflicting: partition.conflicting,
                          dialect: dialect.value,
                        ),
                      ),
                    );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('launch')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('seed-skip')));
    await tester.pumpAndSettle();

    expect(result, isEmpty);
  });

  testWidgets('selecting a subset and confirming returns those mappings', (
    tester,
  ) async {
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    final partition = _partition([
      CcInsertCall(label: 'Sw', text: 'neighbor swing', beats: 8),
      CcInsertCall(label: 'Circle', text: 'circle left 3/4', beats: 8),
    ]);
    List<ShorthandMapping>? result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) =>
            ActiveDialectScope(notifier: dialect, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const ValueKey('launch'),
              onPressed: () async {
                result = await Navigator.of(context)
                    .push<List<ShorthandMapping>>(
                      MaterialPageRoute(
                        builder: (_) => ImportShorthandSeedScreen(
                          seedable: partition.seedable,
                          conflicting: partition.conflicting,
                          dialect: dialect.value,
                        ),
                      ),
                    );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('launch')));
    await tester.pumpAndSettle();

    // Deselect the "Circle" candidate; keep "Sw".
    await tester.tap(find.byKey(const ValueKey('seed-check-circle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('seed-confirm')));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    expect(result!.single.token, 'Sw');
    expect(result!.single.figures.single.move, 'swing');
  });

  testWidgets('the alternate toggle seeds the alt expansion for the token', (
    tester,
  ) async {
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    final partition = _partition([
      CcInsertCall(
        label: 'Chain',
        text: 'ladies chain',
        beats: 8,
        altText: 'gents chain',
        altBeats: 8,
      ),
    ]);
    expect(partition.seedable.single.hasAlt, isTrue);
    List<ShorthandMapping>? result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) =>
            ActiveDialectScope(notifier: dialect, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const ValueKey('launch'),
              onPressed: () async {
                result = await Navigator.of(context)
                    .push<List<ShorthandMapping>>(
                      MaterialPageRoute(
                        builder: (_) => ImportShorthandSeedScreen(
                          seedable: partition.seedable,
                          conflicting: partition.conflicting,
                          dialect: dialect.value,
                        ),
                      ),
                    );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('launch')));
    await tester.pumpAndSettle();

    // Switch to the alternate expansion, then confirm.
    await tester.tap(find.text('Alternate'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('seed-confirm')));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    expect(result!.single.token, 'Chain');
    // The alt "gents chain" was chosen — a different expansion than "ladies
    // chain" but under the SAME token.
    expect(
      result!.single.figures,
      equals(partition.seedable.single.altFigures),
    );
  });

  testWidgets(
    'a conflicting candidate is surfaced as skipped, not selectable',
    (tester) async {
      final partition = _partition(
        [
          CcInsertCall(label: 'Sw', text: 'neighbor swing', beats: 8),
          CcInsertCall(label: 'Circle', text: 'circle left 3/4', beats: 8),
        ],
        existing: {'sw'},
      );
      await _pumpSeed(tester, partition);

      // The conflicting "Sw" appears only in the skipped section (no checkbox).
      expect(find.byKey(const ValueKey('seed-conflict-sw')), findsOneWidget);
      expect(find.byKey(const ValueKey('seed-check-sw')), findsNothing);
      // The non-conflicting "Circle" is still offered.
      expect(find.byKey(const ValueKey('seed-check-circle')), findsOneWidget);
    },
  );

  testWidgets('re-import dedupe: seeded tokens become conflicts on re-run', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);

    final buttons = [
      CcInsertCall(label: 'Sw', text: 'neighbor swing', beats: 8),
    ];

    // First import: token is free → seedable → seed it.
    final first = _partition(
      buttons,
      existing: {for (final m in controller.mappings) m.normalizedToken},
    );
    expect(first.seedable, hasLength(1));
    await controller.upsert(first.seedable.single.toPrimaryMapping());

    // Second import of the same file: the token now exists → routed to
    // conflicting, nothing new to seed.
    final second = _partition(
      buttons,
      existing: {for (final m in controller.mappings) m.normalizedToken},
    );
    expect(second.seedable, isEmpty);
    expect(second.conflicting, hasLength(1));
    expect(controller.mappings, hasLength(1));
  });
}
