import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/venue_manager_screen.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

Future<void> _pump(WidgetTester tester, CompendiumRepositories repos) async {
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: const VenueManagerScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('browses and searches venues by name', (tester) async {
    final repos = openTestRepositories();
    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
    await repos.venues.upsert(Venue(id: 'v2', name: 'Town Hall'));
    await _pump(tester, repos);

    expect(find.byKey(const ValueKey('venue-manager-tile-v1')), findsOneWidget);
    expect(find.byKey(const ValueKey('venue-manager-tile-v2')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('venue-manager-search')),
      'grange',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('venue-manager-tile-v1')), findsOneWidget);
    expect(find.byKey(const ValueKey('venue-manager-tile-v2')), findsNothing);
  });

  testWidgets('delete surfaces the guard error when a program still links it', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Linked night',
        venueId: 'v1',
        status: ProgramStatus.draft,
        slots: const [],
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('venue-manager-delete-v1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('venue-delete-confirm')));
    await tester.pumpAndSettle();

    // Friendly, non-crashing message; the venue is still present.
    expect(find.byKey(const ValueKey('venue-delete-blocked')), findsOneWidget);
    expect(await repos.venues.getById('v1'), isNotNull);
  });

  testWidgets('deletes an unlinked venue', (tester) async {
    final repos = openTestRepositories();
    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('venue-manager-delete-v1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('venue-delete-confirm')));
    await tester.pumpAndSettle();

    expect(await repos.venues.getById('v1'), isNull);
    expect(find.byKey(const ValueKey('venue-manager-empty')), findsOneWidget);
  });
}
