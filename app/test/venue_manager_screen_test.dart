import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/confirm_before_delete_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/venue_manager_screen.dart';

import 'support/fab_clearance.dart';
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

    // Friendly, non-crashing message; the venue is still present, and no
    // Undo is offered for a delete that did not happen.
    expect(find.byKey(const ValueKey('venue-delete-blocked')), findsOneWidget);
    expect(find.byKey(const ValueKey('venue-delete-undo')), findsNothing);
    expect(await repos.venues.getById('v1'), isNotNull);
  });

  testWidgets('deletes an unlinked venue at once, with Undo', (tester) async {
    final repos = openTestRepositories();
    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('venue-manager-delete-v1')));
    await tester.pumpAndSettle();

    // No dialog: "Confirm before delete" is off by default, and Undo covers it.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('"Grange Hall" deleted.'), findsOneWidget);
    expect(find.byKey(const ValueKey('venue-delete-undo')), findsOneWidget);

    expect(await repos.venues.getById('v1'), isNull);
    expect(find.byKey(const ValueKey('venue-manager-empty')), findsOneWidget);
    // The title says it once; the body must not open by repeating it.
    expect(find.textContaining('No venues yet'), findsOneWidget);
    expect(find.text('No venues yet'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('venue-manager-empty-add')),
      findsOneWidget,
    );
  });

  testWidgets('creating a venue offers to link typed programs of that name', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      Program(
        id: 'typed',
        title: 'Old night',
        venue: 'Grange Hall',
        slots: const [],
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('venue-manager-empty-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('venue-name-field')),
      'Grange Hall',
    );
    await tester.tap(find.byKey(const ValueKey('venue-editor-save')));
    await tester.pumpAndSettle();

    expect(find.text('Link earlier programs?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('venue-link-offer-confirm')));
    await tester.pumpAndSettle();

    final venue = (await repos.venues.listAll()).single;
    expect((await repos.programs.getById('typed'))!.venueId, venue.id);
  });

  testWidgets('creating a venue nothing is typed for shows no offer', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('venue-manager-empty-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('venue-name-field')),
      'Grange Hall',
    );
    await tester.tap(find.byKey(const ValueKey('venue-editor-save')));
    await tester.pumpAndSettle();

    expect(find.text('Link earlier programs?'), findsNothing);
    expect(await repos.venues.listAll(), hasLength(1));
  });

  group('the floating New venue', () {
    testWidgets('waits for a list: the empty state carries New venue', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(tester, repos);

      expect(
        find.byKey(const ValueKey('venue-manager-empty-add')),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('shows once there is a venue', (tester) async {
      final repos = openTestRepositories();
      await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
      await _pump(tester, repos);

      expect(find.byKey(const ValueKey('venue-manager-add')), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    for (final c in fabClearanceCases) {
      testWidgets('never covers the last venue (${c.name})', (tester) async {
        final repos = openTestRepositories();
        for (var i = 0; i < 30; i++) {
          final n = '$i'.padLeft(2, '0');
          await repos.venues.upsert(Venue(id: 'v$n', name: 'Hall $n'));
        }
        await _pump(tester, repos);
        await atPhoneSize(
          tester,
          width: c.width,
          scale: c.scale,
          keyboard: c.keyboard,
        );
        await tester.pumpAndSettle();

        await expectFabClearsLastRow(
          tester,
          list: find.byType(ListView),
          lastRow: find.byKey(const ValueKey('venue-manager-tile-v29')),
        );
      });
    }
  });

  testWidgets('Undo brings a deleted venue back', (tester) async {
    final repos = openTestRepositories();
    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
    await _pump(tester, repos);

    await tester.tap(find.byKey(const ValueKey('venue-manager-delete-v1')));
    await tester.pumpAndSettle();
    expect(await repos.venues.getById('v1'), isNull);

    await tester.tap(find.byKey(const ValueKey('venue-delete-undo')));
    await tester.pumpAndSettle();

    expect((await repos.venues.getById('v1'))?.name, 'Grange Hall');
    expect(find.byKey(const ValueKey('venue-manager-tile-v1')), findsOneWidget);
  });

  testWidgets('asks first when "Confirm before delete" is on', (tester) async {
    final repos = openTestRepositories();
    await repos.venues.upsert(Venue(id: 'v1', name: 'Grange Hall'));
    final confirm = ValueNotifier<bool>(true);
    addTearDown(confirm.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => ConfirmBeforeDeleteScope(
          notifier: confirm,
          child: RepositoriesScope(repositories: repos, child: child!),
        ),
        home: const VenueManagerScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('venue-manager-delete-v1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('confirm-delete-dialog')), findsOneWidget);
    expect(await repos.venues.getById('v1'), isNotNull);

    await tester.tap(find.byKey(const ValueKey('confirm-delete-confirm')));
    await tester.pumpAndSettle();
    expect(await repos.venues.getById('v1'), isNull);
    expect(find.byKey(const ValueKey('venue-delete-undo')), findsOneWidget);
  });
}
