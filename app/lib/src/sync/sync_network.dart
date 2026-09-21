import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// What the current connection means for a *Sync only on WiFi* decision
/// (spec §6.12).
enum SyncNetworkKind {
  /// WiFi, ethernet or another connection not billed per byte.
  unmetered,

  /// A cellular connection, or one the OS reports as metered.
  metered,

  /// No connection at all.
  offline,

  /// The platform could not say. Treated as not metered, so a platform that
  /// cannot classify its connection never silently stops syncing.
  unknown,
}

/// Reports the current connection kind. A seam so tests do not touch the
/// platform channel.
abstract interface class SyncNetworkClassifier {
  Future<SyncNetworkKind> current();
}

/// Classifies through `connectivity_plus`.
final class ConnectivityPlusNetworkClassifier implements SyncNetworkClassifier {
  const ConnectivityPlusNetworkClassifier();

  @override
  Future<SyncNetworkKind> current() async {
    try {
      return classifyConnectivity(await Connectivity().checkConnectivity());
    } on Object {
      // diagnostics: silent — a classifier failure degrades to "unknown",
      // which does not suppress sync.
      return SyncNetworkKind.unknown;
    }
  }
}

/// Maps the platform's connectivity results onto [SyncNetworkKind]. Any
/// unmetered transport wins over a metered one, because the OS routes over the
/// unmetered link when both are up.
SyncNetworkKind classifyConnectivity(List<ConnectivityResult> results) {
  if (results.isEmpty) return SyncNetworkKind.unknown;
  if (results.every((r) => r == ConnectivityResult.none)) {
    return SyncNetworkKind.offline;
  }
  const unmetered = {
    ConnectivityResult.wifi,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,
  };
  if (results.any(unmetered.contains)) return SyncNetworkKind.unmetered;
  if (results.contains(ConnectivityResult.mobile)) {
    return SyncNetworkKind.metered;
  }
  return SyncNetworkKind.unknown;
}
