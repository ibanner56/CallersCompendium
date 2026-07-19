import 'dart:async';

import 'package:flutter/services.dart';

/// The single, mockable seam between the OS "open this file with the app"
/// plumbing (iOS `SceneDelegate`, macOS `AppDelegate`, Android `MainActivity`)
/// and the Dart intake handler.
///
/// The native side does one thing: forward the **path** of a file the OS handed
/// the app (via AirDrop, "Open with…", or a share/intent) over a
/// [MethodChannel]. Dart owns all validation and import — the native code trusts
/// nothing and interprets nothing. This keeps the platform code tiny and lets
/// tests exercise intake by pushing paths through a fake channel with **no real
/// platform channel** involved.
///
/// Two delivery moments are covered:
/// - **Cold start:** the app was launched to open a file. Dart pulls it once
///   via [initialFile] after startup.
/// - **Warm/running:** a file arrives while the app is already open. Native
///   invokes `fileOpened`, surfaced on the [files] stream.
class IncomingFileChannel {
  IncomingFileChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Platform-channel name shared with the native handlers. Namespaced to the
  /// app so it never collides with a plugin channel.
  static const String channelName =
      'is.banner.callerscompendium/incoming_files';

  final MethodChannel _channel;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  /// Paths of files opened while the app is running. Broadcast so multiple
  /// listeners (or none, before wiring) never drop the app.
  Stream<String> get files => _controller.stream;

  /// Registers the handler for files delivered while the app is running.
  /// Idempotent-ish: calling again replaces the handler.
  void start() {
    _channel.setMethodCallHandler(_handle);
  }

  Future<Object?> _handle(MethodCall call) async {
    if (call.method == 'fileOpened') {
      final path = call.arguments;
      if (path is String && path.isNotEmpty) {
        _controller.add(path);
      }
    }
    return null;
  }

  /// The path of the file the app was **launched** to open (cold start), or
  /// `null` when the app started normally. A channel error (e.g. no native
  /// implementation on an unsupported platform) is treated as "no file" so the
  /// app never fails to start over intake.
  Future<String?> initialFile() async {
    try {
      final path = await _channel.invokeMethod<String>('getInitialFile');
      return (path != null && path.isNotEmpty) ? path : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_controller.close());
  }
}
