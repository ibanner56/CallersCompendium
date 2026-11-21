import 'package:compendium_app/src/sync/sync_network.dart';

/// A connection that is never metered. Widget tests inject it into
/// `CompendiumApp` because the connectivity platform channel does not answer
/// under fake async, which would stall `pumpAndSettle`.
final class UnmeteredSyncNetwork implements SyncNetworkClassifier {
  const UnmeteredSyncNetwork();

  @override
  Future<SyncNetworkKind> current() async => SyncNetworkKind.unmetered;
}
