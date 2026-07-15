import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/perform_dance_screen.dart';

import 'support/test_repositories.dart';

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
