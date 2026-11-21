import 'package:flutter/services.dart';

/// The mockable seam to the macOS check for an app that is running from a
/// read-only volume, which usually means it was never installed — issue #1725:
/// double-clicked inside the mounted `.dmg`, or run from Gatekeeper's
/// translocated copy. Native side:
/// `app/macos/Runner/InstallLocationBridge.swift`.
class InstallLocationChannel {
  InstallLocationChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Platform-channel name shared with the native handler.
  static const String channelName =
      'is.banner.callerscompendium/install_location';

  final MethodChannel _channel;

  /// Whether the running app bundle is on a read-only volume (the disk image,
  /// or a translocated copy). This is a proxy for "not installed", not proof
  /// of it: a translocated copy of an app that is already in Applications
  /// reads `true` too. Any channel error, or a platform with no native
  /// implementation, reads as `false`: a missed notice is harmless, a false
  /// one is not.
  Future<bool> isRunningUninstalled() async {
    try {
      return await _channel.invokeMethod<bool>('isRunningUninstalled') ?? false;
    } on MissingPluginException {
      // diagnostics: silent — no native implementation on this platform; treat as installed
      return false;
    } on PlatformException {
      // diagnostics: silent — native check failed; treat as installed so no false notice shows
      return false;
    }
  }
}
