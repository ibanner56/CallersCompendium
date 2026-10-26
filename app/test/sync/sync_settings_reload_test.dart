import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/screens/app_shell.dart';
import 'package:compendium_app/src/screens/settings/settings_keys.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_app/src/sync/sync_failure.dart';
import 'package:compendium_app/src/sync/sync_scope.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/full_app_harness.dart';
import '../support/noop_sync_transport.dart';
import '../support/sync_test_network.dart';

/// Issue #1828: a sync pass that changes `settings` must reach the live
/// settings-backed controllers, not only the database.
void main() {
  Figure swing() =>
      testFigure(move: 'swing', params: {'who': 'neighbors', 'beats': 16});

  // A second full-app test in this file meets the root bundle's cached
  // `SynchronousFuture`s, which stall the User Guide's FutureBuilder and keep
  // `pumpAndSettle` from settling; startup_sequence_test.dart clears it too.
  setUp(rootBundle.clear);

  // The worker isolate's pass can also throw after its apply committed (a
  // manifest PUT on a flaky link); the failure then carries the applied kinds
  // instead of a result, and must reload the controllers just the same
  // (#1913). Before that fix it reloaded nothing until a relaunch.
  for (final throwsAfterApply in [false, true])
    testWidgets(
      throwsAfterApply
          ? 'a sync pass that throws after applying a setting reloads the '
                'live controllers, and the reload schedules no further pass'
          : 'a sync pass that applies a setting reloads the live controllers, '
                'and the reload schedules no further pass',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final appData = openTestAppData();
        late SyncController syncController;
        var passes = 0;
        var applyInbound = false;

        Future<SyncCoordinator?> factory(
          CompendiumRepositories repositories,
        ) async => SyncCoordinator(
          syncId: 'configured',
          deviceId: 'device',
          store: CompendiumSyncCoordinatorStore(repositories),
          transport: NoopSyncCoordinatorTransport(),
          passOperation: ({initialStore}) async {
            passes++;
            if (!applyInbound) {
              return const SyncPassResult(SyncPassStatus.completed);
            }
            applyInbound = false;
            // What the production pass does from its worker isolate: arm the
            // controller for the invalidation, write the peer's value, report
            // the kind applied.
            syncController.expectSyncAppliedInvalidation();
            await repositories.settings.set(
              kShorthandMappingsKey,
              ShorthandMappings([
                ShorthandMapping(token: 'bs', figures: [swing()]),
              ]).toJson(),
            );
            if (throwsAfterApply) {
              throw SyncWorkerFailure(
                'ClientException: Connection closed',
                SyncFailureCause.unreachable,
                appliedKinds: const {SyncRecordKind.setting},
              );
            }
            return const SyncPassResult(
              SyncPassStatus.completed,
              appliedKinds: [SyncRecordKind.setting],
            );
          },
        );

        await appData.repositories.settings.set(kSyncEnabledKey, true);
        await tester.pumpWidget(
          CompendiumApp(
            appData: appData,
            windowService: NoopWindowService(appData.repositories.settings),
            integrityCheck: () async => true,
            syncCoordinatorFactory: factory,
            syncNetworkClassifier: const UnmeteredSyncNetwork(),
            syncDebounce: const Duration(milliseconds: 20),
          ),
        );
        await tester.pumpAndSettle();
        expect(passes, 1, reason: 'the app-start pass');

        final context = tester.element(find.byType(AppShell));
        syncController = SyncScope.of(context);
        final shorthands = ShorthandMappingsScope.controllerOf(context);
        expect(shorthands.mappings, isEmpty);

        applyInbound = true;
        final pass = syncController.syncNow();
        await tester.pumpAndSettle();
        await pass;
        await tester.pumpAndSettle();

        final stored = await tester.runAsync(
          () => appData.repositories.settings.get(kShorthandMappingsKey),
        );
        expect(stored, isNotNull, reason: 'the pass did write the database');
        expect(shorthands.mappings.map((m) => m.token), [
          'bs',
        ], reason: 'the live controller must see what the pass applied');

        // The reload only reads; it must not look like a local edit and start
        // another pass, or two devices would bounce passes between them.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();
        expect(passes, 2, reason: 'the reload schedules no follow-up pass');
      },
    );
}
