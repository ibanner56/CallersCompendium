import 'dart:async';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings/sync_pairing_screen.dart';
import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_app/src/sync/sync_network.dart';
import 'package:compendium_app/src/sync/sync_scope.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

final class _Network implements SyncNetworkClassifier {
  @override
  Future<SyncNetworkKind> current() async => SyncNetworkKind.unmetered;
}

/// Back, the app bar arrow and Esc all reach the pairing screen through
/// `Navigator.maybePop`; typed input must ask before it is thrown away.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final screen = find.byType(SyncPairingScreen);
  const keepEditing = ValueKey('discard-cancel');
  const discard = ValueKey('discard-confirm');

  /// Opens the screen on top of a host route, so Back has somewhere to go.
  Future<void> open(
    WidgetTester tester,
    String path, {
    SyncPairingProbeFactory? probeFactory,
  }) async {
    final repos = openTestRepositories();
    final controller = SyncController(
      settings: repos.settings,
      syncLocal: repos.syncLocal,
      coordinator: () => null,
      reconfigure: ({bool startPass = true}) async {},
      classifier: _Network(),
      pairingProbeFactory: probeFactory,
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);
    await tester.pumpWidget(
      RepositoriesScope(
        repositories: repos,
        child: SyncScope(
          controller: controller,
          child: MaterialApp(
            localizationsDelegates: testLocalizationsDelegates,
            supportedLocales: testSupportedLocales,
            home: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('host-open'),
                onPressed: () => showSyncPairingScreen(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('host-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('sync-pairing-$path')));
    await tester.pumpAndSettle();
    expect(screen, findsOneWidget);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('a connect phrase asks before Back discards it', (tester) async {
    await open(tester, 'connect');
    await tester.enterText(
      find.byKey(const ValueKey('sync-pairing-phrase-field')),
      'alpha-bravo',
    );
    await tester.pump();

    await back(tester);
    expect(find.byKey(discard), findsOneWidget);
    await tester.tap(find.byKey(keepEditing));
    await tester.pumpAndSettle();
    expect(screen, findsOneWidget);
    expect(find.text('alpha-bravo'), findsOneWidget);

    await back(tester);
    await tester.tap(find.byKey(discard));
    await tester.pumpAndSettle();
    expect(screen, findsNothing);
  });

  testWidgets('an untouched connect screen leaves without asking', (
    tester,
  ) async {
    await open(tester, 'connect');
    await back(tester);
    expect(find.byKey(discard), findsNothing);
    expect(screen, findsNothing);
  });

  testWidgets('an edited create phrase asks before Back discards it', (
    tester,
  ) async {
    await open(tester, 'create');
    await tester.enterText(
      find.byKey(const ValueKey('sync-pairing-phrase')),
      'my own phrase',
    );
    await tester.pump();
    await back(tester);
    expect(find.byKey(discard), findsOneWidget);
    expect(screen, findsOneWidget);
  });

  testWidgets('the generated phrase, even regenerated, leaves without asking', (
    tester,
  ) async {
    await open(tester, 'create');
    await tester.tap(find.byKey(const ValueKey('sync-pairing-regenerate')));
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.byKey(discard), findsNothing);
    expect(screen, findsNothing);
  });

  testWidgets('an edited server address asks before Back discards it', (
    tester,
  ) async {
    await open(tester, 'connect');
    await tester.enterText(
      find.byKey(const ValueKey('sync-pairing-endpoint-field')),
      'https://sync.example.org/',
    );
    await tester.pump();
    await back(tester);
    expect(find.byKey(discard), findsOneWidget);
  });

  testWidgets('Back while pairing is in flight leaves without asking', (
    tester,
  ) async {
    // Tall enough that the lazy list builds Continue without scrolling.
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gate = Completer<void>();
    await open(
      tester,
      'connect',
      probeFactory: (syncId, endpoint) => SyncPairingProbe(
        getStore: ({required previouslyUsed}) async {
          await gate.future;
          throw StateError('closed');
        },
        createStore: () async => throw StateError('connect must not POST'),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('sync-pairing-phrase-field')),
      'alpha-bravo-charlie-delta',
    );
    final skip = find.byKey(const ValueKey('sync-pairing-backup-skip'));
    await tester.tap(skip);
    await tester.pumpAndSettle();
    final go = find.byKey(const ValueKey('sync-pairing-continue'));
    await tester.tap(go);
    await tester.pump();

    await back(tester);
    expect(find.byKey(discard), findsNothing);
    expect(screen, findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
  });
}
