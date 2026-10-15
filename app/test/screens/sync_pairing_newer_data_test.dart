import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/settings/sync_pairing_screen.dart';
import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_app/src/sync/sync_network.dart';
import 'package:compendium_app/src/sync/sync_scope.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

final class _Network implements SyncNetworkClassifier {
  @override
  Future<SyncNetworkKind> current() async => SyncNetworkKind.unmetered;
}

/// The pairing warning about devices on earlier app versions (#709
/// consolidated spec, decision 13): shown on both paths once this build syncs
/// something they cannot read, and not before.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const finder = ValueKey('sync-pairing-newer-data-disclosure');

  Future<void> pump(WidgetTester tester, SyncCapabilityPolicy policy) async {
    final repos = openTestRepositories();
    final controller = SyncController(
      settings: repos.settings,
      syncLocal: repos.syncLocal,
      coordinator: () => null,
      reconfigure: ({bool startPass = true}) async {},
      classifier: _Network(),
    );
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: RepositoriesScope(
          repositories: repos,
          child: SyncScope(
            controller: controller,
            child: SyncPairingScreen(
              key: UniqueKey(),
              capabilityPolicy: policy,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> choose(WidgetTester tester, String path) async {
    await tester.tap(find.byKey(ValueKey('sync-pairing-$path')));
    await tester.pumpAndSettle();
  }

  testWidgets('shown on both paths while this build advertises a capability', (
    tester,
  ) async {
    for (final path in const ['create', 'connect']) {
      await pump(tester, const SyncCapabilityPolicy(advertised: {'test.v1'}));
      await choose(tester, path);
      expect(find.byKey(finder), findsOneWidget, reason: path);
      expect(
        find.text('Every device needs an up-to-date app'),
        findsOneWidget,
        reason: path,
      );
    }
  });

  testWidgets('silent while this build advertises nothing, as it does today', (
    tester,
  ) async {
    expect(SyncCapabilityPolicy.build.advertised, isEmpty);
    for (final path in const ['create', 'connect']) {
      await pump(tester, SyncCapabilityPolicy.build);
      await choose(tester, path);
      expect(find.byKey(finder), findsNothing, reason: path);
    }
  });
}
