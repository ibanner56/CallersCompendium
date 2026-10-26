import 'dart:async';

import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_network.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/noop_sync_transport.dart';
import '../support/test_repositories.dart';

/// Device-scoped settings writes (#1933): a window move must not schedule a
/// sync pass, and nothing here may strand a counter that swallows a later edit.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late CompendiumRepositories repos;
  late int passes;
  late SyncController controller;
  late StreamSubscription<Object?> subscription;

  Future<void> settle() async {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }

  setUp(() async {
    repos = openTestRepositories();
    passes = 0;
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device',
      store: CompendiumSyncCoordinatorStore(repos),
      transport: NoopSyncCoordinatorTransport(),
      passOperation: ({initialStore}) async {
        passes++;
        return SyncPassResult(SyncPassStatus.completed);
      },
    );
    controller = SyncController(
      settings: repos.settings,
      syncLocal: repos.syncLocal,
      coordinator: () => coordinator,
      reconfigure: ({bool startPass = true}) async {},
      classifier: _Unmetered(),
      debounce: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);
    // Production wiring (`main.dart`): table names to `notifyTableUpdates`.
    subscription = repos.db.tableUpdates().listen((updates) {
      controller.notifyTableUpdates({for (final u in updates) u.table});
    });
    addTearDown(subscription.cancel);
    await controller.load();
    await controller.setEnabled(true);
    await settle();
    passes = 0;
  });

  test('a device-scoped write schedules no pass', () async {
    await repos.settings.set('window_frame', {'x': 1});
    await settle();
    expect(passes, 0);
  });

  test('a device-local write schedules no pass', () async {
    expect(
      classifySettingsKey('perform_text_scale')!.egress,
      EgressClass.deviceLocal,
    );
    await repos.settings.set('perform_text_scale', 1.5);
    await settle();
    expect(passes, 0);
  });

  test('a shareable write schedules exactly one pass', () async {
    await repos.settings.set('reduce_motion', true);
    await settle();
    expect(passes, 1);
  });

  test('an unclassified key schedules a pass', () async {
    expect(classifySettingsKey('no_such_setting_1933'), isNull);
    await repos.settings.set('no_such_setting_1933', 1);
    await settle();
    expect(passes, 1);
  });

  test('removing a shareable key permanently schedules a pass', () async {
    await repos.settings.set('reduce_motion', true);
    await settle();
    passes = 0;
    await repos.settings.remove('reduce_motion', permanent: true);
    await settle();
    expect(passes, 1);
  });

  test('a shareable write batched with a device-scoped one schedules a '
      'pass', () async {
    await repos.db.transaction(() async {
      await repos.settings.set('window_frame', {'x': 2});
      await repos.settings.set('reduce_motion', false);
    });
    await settle();
    expect(passes, 1);
  });

  test('a device-scoped write batched with a synced table schedules a '
      'pass', () async {
    // One commit: the tally is device-scoped only, but `dances` is in the
    // batch, so it is a real edit.
    await repos.db.transaction(() async {
      await repos.settings.set('window_frame', {'x': 2});
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'My Dance',
          figures: const [],
          createdAt: DateTime.utc(2026, 10, 26),
          updatedAt: DateTime.utc(2026, 10, 26),
        ),
      );
    });
    await settle();
    expect(passes, 1);
  });

  test('a no-op device-scoped write strands nothing: the next genuine '
      'edit still schedules a pass', () async {
    // Removing an absent key writes no row, so no table update follows it.
    await repos.settings.remove('window_frame', permanent: true);
    await settle();
    expect(passes, 0);

    await repos.settings.set('reduce_motion', true);
    await settle();
    expect(passes, 1);
  });

  test('a device-scoped write does not swallow the controller\'s own '
      'expectation or a later edit', () async {
    await repos.settings.set('window_frame', {'x': 3});
    await settle();
    await controller.setWifiOnly(false);
    await settle();
    expect(passes, 0, reason: 'the controller\'s own write is bookkeeping');
    await repos.settings.set('reduce_motion', true);
    await settle();
    expect(passes, 1);
  });
}

class _Unmetered implements SyncNetworkClassifier {
  @override
  Future<SyncNetworkKind> current() async => SyncNetworkKind.unmetered;
}
