import 'dart:convert';
import 'dart:math';

import 'package:compendium_core/compendium_core.dart';

import '../data/app_database.dart' show resolveDatabaseFile;
import '../screens/settings/settings_keys.dart'
    show kSyncDeviceIdKey, kSyncIdKey;
import 'sync_coordinator.dart';
import 'sync_http_client.dart';
import 'sync_isolate.dart';

/// Builds the production coordinator after the database-backed settings are
/// available.
///
/// A missing sync ID is the disabled state. The device identifier is generated
/// once when a user enables sync and is never taken from a peer or a backup.
final class ConfiguredSyncCoordinatorFactory {
  const ConfiguredSyncCoordinatorFactory({required this.endpoint});

  /// Uses the release-configured endpoint, or keeps sync disabled when a
  /// build has not opted into a service endpoint.
  ConfiguredSyncCoordinatorFactory.fromEnvironment()
    : endpoint = _syncEndpointEnvironment.isEmpty
          ? null
          : Uri.tryParse(_syncEndpointEnvironment);

  final Uri? endpoint;

  Future<SyncCoordinator?> call(CompendiumRepositories repositories) async {
    final rawSyncId = await repositories.settings.get(kSyncIdKey);
    if (rawSyncId == null) return null;
    if (rawSyncId is! String) {
      throw const FormatException('stored sync ID must be a string');
    }
    final syncId = normalizeSyncId(rawSyncId);
    if (syncId.isEmpty) return null;
    final endpoint = this.endpoint;
    if (endpoint == null) return null;
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
      store: CompendiumSyncCoordinatorStore(repositories),
      transport: SyncHttpCoordinatorTransport(client),
      passOperation: IsolatedSyncPassOperation(
        databasePath: databasePath,
        endpoint: endpoint,
        syncId: syncId,
        deviceId: deviceId,
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

const _syncEndpointEnvironment = String.fromEnvironment(
  'CALLERS_COMPENDIUM_SYNC_ENDPOINT',
);

final _validDeviceId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
