import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart' show AppData;
import 'package:compendium_app/src/data/backup_document.dart'
    show
        defaultBackupCodecRunner,
        runBackupCodecInline,
        runBackupCodecOnIsolate;
import 'package:compendium_app/src/screens/settings/settings_keys.dart';
import 'package:compendium_app/src/sync/restored_copy_check.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/full_app_harness.dart';
import '../support/noop_sync_transport.dart';
import '../support/sync_test_network.dart';

class _FakeMarker implements NoBackupMarker {
  _FakeMarker({this.present = false});

  bool present;
  bool failRead = false;

  @override
  Future<bool> exists() async {
    if (failRead) throw PlatformException(code: 'io');
    return present;
  }

  @override
  Future<void> write() async => present = true;
}

const _noticeKey = ValueKey('restored-copy-sync-notice');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(rootBundle.clear);
  setUp(() => defaultBackupCodecRunner = runBackupCodecInline);
  tearDown(() => defaultBackupCodecRunner = runBackupCodecOnIsolate);

  /// Boots the app over [appData] with [marker], counting the coordinators
  /// built for an installation whose Device Sync is on, as the production
  /// factory does (it builds none while `sync_enabled` is not `true`).
  Future<int Function()> boot(
    WidgetTester tester,
    AppData appData,
    NoBackupMarker marker,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var built = 0;
    Future<SyncCoordinator?> factory(CompendiumRepositories repos) async {
      if (await repos.settings.get(kSyncEnabledKey) != true) return null;
      built++;
      return SyncCoordinator(
        syncId: 'store-one',
        deviceId: 'device',
        store: CompendiumSyncCoordinatorStore(repos),
        transport: NoopSyncCoordinatorTransport(),
        passOperation: ({initialStore}) async =>
            const SyncPassResult(SyncPassStatus.completed),
      );
    }

    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
        integrityCheck: () async => true,
        syncCoordinatorFactory: factory,
        syncNetworkClassifier: const UnmeteredSyncNetwork(),
        noBackupMarker: marker,
      ),
    );
    await tester.pumpAndSettle();
    return () => built;
  }

  /// A library that was syncing on the phone it came from.
  Future<AppData> syncingLibrary({required bool flag}) async {
    final appData = openTestAppData();
    final settings = appData.repositories.settings;
    if (flag) await settings.set(kNoBackupMarkerWrittenKey, true);
    await settings.set(kSyncIdKey, 'store-one');
    await settings.set(kSyncEnabledKey, true);
    await settings.set(kSyncDeviceIdKey, 'old_phone');
    return appData;
  }

  testWidgets('a library restored from a device backup starts with Device '
      'Sync off and its old identity gone, and says why', (tester) async {
    final appData = await syncingLibrary(flag: true);
    final marker = _FakeMarker();

    final built = await boot(tester, appData, marker);

    expect(built(), 0, reason: 'no coordinator under the copied identity');
    final settings = appData.repositories.settings;
    expect(await settings.get(kSyncEnabledKey), isFalse);
    expect(await settings.get(kSyncDeviceIdKey), isNull);
    expect(marker.present, isTrue);
    expect(find.byKey(_noticeKey), findsOneWidget);
  });

  testWidgets('the first start after an update keeps Device Sync on, as it '
      'was, and says nothing', (tester) async {
    final appData = await syncingLibrary(flag: false);
    final marker = _FakeMarker();

    final built = await boot(tester, appData, marker);

    expect(built(), 1);
    final settings = appData.repositories.settings;
    expect(await settings.get(kSyncDeviceIdKey), 'old_phone');
    expect(await settings.get(kNoBackupMarkerWrittenKey), isTrue);
    expect(marker.present, isTrue);
    expect(find.byKey(_noticeKey), findsNothing);
  });

  testWidgets('an ordinary start syncs and says nothing', (tester) async {
    final appData = await syncingLibrary(flag: true);

    final built = await boot(tester, appData, _FakeMarker(present: true));

    expect(built(), 1);
    expect(find.byKey(_noticeKey), findsNothing);
  });

  testWidgets('a marker that cannot be read leaves Device Sync as it was',
      (tester) async {
    final appData = await syncingLibrary(flag: true);

    final built = await boot(tester, appData, _FakeMarker()..failRead = true);

    expect(built(), 1);
    expect(
      await appData.repositories.settings.get(kSyncDeviceIdKey),
      'old_phone',
    );
    expect(find.byKey(_noticeKey), findsNothing);
  });
}
