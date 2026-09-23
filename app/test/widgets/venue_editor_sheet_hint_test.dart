// Guards the §6.13 partial-venue hint (ADR-004/W13 PR3).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/venue_editor_sheet.dart';
import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_app/src/sync/sync_network.dart';
import 'package:compendium_app/src/sync/sync_scope.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

final class _NoopNetwork implements SyncNetworkClassifier {
  @override
  Future<SyncNetworkKind> current() async => SyncNetworkKind.unmetered;
}

/// Pumps a host screen with an "Open" button that shows [VenueEditorSheet]
/// for [initial]. [syncEnabled] controls the [SyncController] wired above it;
/// [wireSyncScope] false omits the scope entirely, mirroring a caller that has
/// not wired Device Sync into its tree.
Future<void> _pumpAndOpen(
  WidgetTester tester, {
  required CompendiumRepositories repos,
  Venue? initial,
  bool syncEnabled = true,
  bool wireSyncScope = true,
}) async {
  final syncController = SyncController(
    settings: repos.settings,
    syncLocal: repos.syncLocal,
    coordinator: () => null,
    reconfigure: ({bool startPass = true}) async {},
    classifier: _NoopNetwork(),
  );
  addTearDown(syncController.dispose);
  await syncController.load();
  if (syncEnabled) await syncController.setEnabled(true);

  // Scopes must wrap via `builder`, not `home`: a modal route pushed by
  // showModalBottomSheet lands in the Navigator's overlay, a sibling of
  // `home`'s subtree rather than a descendant of it, so a scope placed only
  // around `home` would be invisible to the sheet.
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) {
        Widget wrapped = RepositoriesScope(repositories: repos, child: child!);
        if (wireSyncScope) {
          wrapped = SyncScope(controller: syncController, child: wrapped);
        }
        return wrapped;
      },
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-editor'),
              onPressed: () => VenueEditorSheet.show(context, initial: initial),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-editor')));
  await tester.pumpAndSettle();
}

const _hintKey = ValueKey('venue-partial-sync-hint');

void main() {
  testWidgets(
    'shows for a venue with no address/contact fields while sync is on',
    (tester) async {
      final repos = openTestRepositories();
      await _pumpAndOpen(
        tester,
        repos: repos,
        initial: Venue(id: 'v1', name: 'Grange Hall'),
      );

      expect(find.byKey(_hintKey), findsOneWidget);
      expect(find.textContaining('stay on this device'), findsOneWidget);
    },
  );

  testWidgets(
    'names the fields rather than claiming contact details never travel '
    '(spec §6.13 requirement 3)',
    (tester) async {
      final repos = openTestRepositories();
      await _pumpAndOpen(
        tester,
        repos: repos,
        initial: Venue(id: 'v1', name: 'Grange Hall'),
      );

      final text = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(_hintKey),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(text, contains('address and contact fields'));
      // Never a blanket "contact details stay on this device" claim: Notes is
      // shareable free text, so the hint must flag it as the exception.
      expect(text, isNot(contains('contact details stay on this device')));
      expect(text, contains('Notes field does sync'));
    },
  );

  testWidgets('is absent while Device Sync is off', (tester) async {
    final repos = openTestRepositories();
    await _pumpAndOpen(
      tester,
      repos: repos,
      initial: Venue(id: 'v1', name: 'Grange Hall'),
      syncEnabled: false,
    );

    expect(find.byKey(_hintKey), findsNothing);
  });

  testWidgets(
    'is absent when any address or contact field already has content',
    (tester) async {
      final repos = openTestRepositories();
      await _pumpAndOpen(
        tester,
        repos: repos,
        initial: Venue(id: 'v1', name: 'Grange Hall', address1: '1 Main St'),
      );

      expect(find.byKey(_hintKey), findsNothing);
    },
  );

  testWidgets(
    'reacts live: typing into an address field makes it disappear without '
    'reopening the sheet',
    (tester) async {
      final repos = openTestRepositories();
      await _pumpAndOpen(
        tester,
        repos: repos,
        initial: Venue(id: 'v1', name: 'Grange Hall'),
      );
      expect(find.byKey(_hintKey), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('venue-address1-field')),
        '1 Main St',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(_hintKey),
        findsNothing,
        reason: 'derived live, not from the venue as it was when opened',
      );

      await tester.enterText(
        find.byKey(const ValueKey('venue-address1-field')),
        '',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_hintKey), findsOneWidget);
    },
  );

  testWidgets('is absent with no SyncScope ancestor (no crash)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpAndOpen(
      tester,
      repos: repos,
      initial: Venue(id: 'v1', name: 'Grange Hall'),
      wireSyncScope: false,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(_hintKey), findsNothing);
  });

  testWidgets('applies the same way to a brand-new venue', (tester) async {
    final repos = openTestRepositories();
    await _pumpAndOpen(tester, repos: repos);

    expect(find.byKey(_hintKey), findsOneWidget);
  });
}
