import 'dart:convert';
import 'dart:math';

import 'package:compendium_core/compendium_core.dart';

import '../data/app_database.dart' show resolveDatabaseFile;
import '../screens/settings/settings_keys.dart'
    show kSyncDeviceIdKey, kSyncEnabledKey, kSyncEndpointKey, kSyncIdKey;
import 'sync_coordinator.dart';
import 'sync_http_client.dart';
import 'sync_isolate.dart';
import 'sync_invalidation.dart';

/// Builds the production coordinator after the database-backed settings are
/// available.
///
/// Sync is off until the user turns it on (spec §6.1): the coordinator is built
/// only when `sync_enabled` is exactly `true`, so an unconfigured or disabled
/// installation constructs no client and makes no sync-related network call.
/// A missing sync ID is also the disabled state. The device identifier is generated
/// once when a user enables sync and is never taken from a peer or a backup.
///
/// The endpoint is the one recorded at pairing, which always writes it before
/// the sync ID; a missing endpoint is therefore also the disabled state.
final class ConfiguredSyncCoordinatorFactory {
  /// Notified immediately before a completed pass's applied-kinds
  /// invalidation reaches the main connection (see [markSyncAppliedTablesUpdated]).
  ///
  /// Mutable, not a constructor parameter: `main()` constructs this factory
  /// before `SyncController` exists, so `_CompendiumAppState` assigns this
  /// once the controller is built, routing the notification to
  /// `SyncController.expectSyncAppliedInvalidation` so the resulting
  /// `tableUpdates()` event is not mistaken for a local edit that should
  /// schedule a follow-up pass. Left `null` in tests, which build their own
  /// [SyncCoordinator] and never call through this factory.
  void Function()? onBeforeAppliedInvalidation;

  Future<SyncCoordinator?> call(CompendiumRepositories repositories) async {
    if (await repositories.settings.get(kSyncEnabledKey) != true) return null;
    final rawSyncId = await repositories.settings.get(kSyncIdKey);
    if (rawSyncId == null) return null;
    if (rawSyncId is! String) {
      throw const FormatException('stored sync ID must be a string');
    }
    final syncId = normalizeSyncId(rawSyncId);
    if (syncId.isEmpty) return null;
    final rawEndpoint = await repositories.settings.get(kSyncEndpointKey);
    if (rawEndpoint == null) return null;
    final endpoint = rawEndpoint is String
        ? tryParseSyncEndpoint(rawEndpoint)
        : null;
    if (endpoint == null) {
      throw const FormatException('stored sync endpoint is invalid');
    }
    final databasePath = (await resolveDatabaseFile()).path;

    final rawDeviceId = await repositories.settings.get(kSyncDeviceIdKey);
    final deviceId = switch (rawDeviceId) {
      null => await _createDeviceId(repositories),
      String value when _validDeviceId.hasMatch(value) => value,
      _ => throw const FormatException('stored sync device ID is invalid'),
    };

    final client = SyncHttpClient(endpoint: endpoint, syncId: syncId);
    return SyncCoordinator(
      syncId: syncId,
      deviceId: deviceId,
      store: CompendiumSyncCoordinatorStore(repositories, syncId: syncId),
      transport: SyncHttpCoordinatorTransport(client),
      passOperation: IsolatedSyncPassOperation(
        databasePath: databasePath,
        endpoint: endpoint,
        syncId: syncId,
        deviceId: deviceId,
        onAppliedKinds: (kinds) {
          onBeforeAppliedInvalidation?.call();
          markSyncAppliedTablesUpdated(repositories.db, kinds);
        },
      ).call,
    );
  }

  Future<String> _createDeviceId(CompendiumRepositories repositories) async {
    final bytes = List<int>.generate(18, (_) => Random.secure().nextInt(256));
    final deviceId = base64Url.encode(bytes).replaceAll('=', '');
    await repositories.settings.set(kSyncDeviceIdKey, deviceId);
    return deviceId;
  }
}

final _validDeviceId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
