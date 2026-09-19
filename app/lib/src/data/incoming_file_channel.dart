import 'dart:async';

import 'package:flutter/services.dart';

/// The single, mockable seam between the OS "open this file with the app"
/// plumbing (iOS `SceneDelegate`, macOS `AppDelegate`, Android `MainActivity`)
/// and the Dart intake handler.
///
/// The native side does one thing: forward the **path** of a file the OS handed
/// the app (via AirDrop, "Open with…", or a share/intent) over a
/// [MethodChannel]. A native-created copy is marked as app-owned in the
/// payload, so Dart can clean it up after intake without inferring ownership
/// from a platform-specific path. Dart owns all validation and import — the
/// native code trusts nothing and interprets nothing. This keeps the platform
/// code tiny and lets tests exercise intake through a fake channel with **no
/// real platform channel** involved.
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
  final StreamController<IncomingFile> _controller =
      StreamController<IncomingFile>.broadcast();
  final StreamController<String> _urlController =
      StreamController<String>.broadcast();

  /// Files opened while the app is running. Broadcast so multiple listeners
  /// (or none, before wiring) never drop the app.
  Stream<IncomingFile> get files => _controller.stream;

  /// Raw URL strings shared into the app while it is running (issue #343: a
  /// browser "Share" of a program page sends a `text/plain` URL via an Android
  /// `ACTION_SEND` intent or an iOS Share Extension). Broadcast, mirroring
  /// [files]. The string is **untrusted OS input** — Dart validates it
  /// (`extractSharedContraDbProgramUrl` / `extractSharedDanceLink`) before it
  /// reaches an import pipeline; the native side forwards it verbatim and
  /// interprets nothing.
  Stream<String> get urls => _urlController.stream;

  /// Registers the handler for files delivered while the app is running.
  /// Idempotent-ish: calling again replaces the handler.
  void start() {
    _channel.setMethodCallHandler(_handle);
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'fileOpened':
        final file = _decodeFile(call.arguments);
        if (file != null) {
          _controller.add(file);
        }
      case 'urlShared':
        final url = call.arguments;
        if (url is String && url.isNotEmpty) {
          _urlController.add(url);
        }
    }
    return null;
  }

  /// The file the app was **launched** to open (cold start), or `null` when
  /// the app started normally. Native-created copies are marked app-owned;
  /// legacy string payloads are accepted as unowned. A channel error (e.g. no
  /// native implementation on an unsupported platform) is treated as "no
  /// file" so the app never fails to start over intake.
  Future<IncomingFile?> initialFile() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('getInitialFile');
      return _decodeFile(raw);
    } on MissingPluginException {
      // diagnostics: silent — no native implementation on this platform; treat as no file
      return null;
    } on PlatformException {
      // diagnostics: silent — channel error on start; treat as no file so the app always starts
      return null;
    }
  }

  /// The URL the app was **launched** to import (cold start), or `null` when
  /// the app started normally / on a platform with no native implementation.
  /// A channel error is treated as "no URL" so the app never fails to start
  /// over intake — mirroring [initialFile].
  Future<String?> initialUrl() async {
    try {
      final url = await _channel.invokeMethod<String>('getInitialUrl');
      return (url != null && url.isNotEmpty) ? url : null;
    } on MissingPluginException {
      // diagnostics: silent — no native implementation on this platform; treat as no URL
      return null;
    } on PlatformException {
      // diagnostics: silent — channel error on start; treat as no URL so the app always starts
      return null;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_controller.close());
    unawaited(_urlController.close());
  }

  static IncomingFile? _decodeFile(Object? raw) {
    if (raw is String) {
      return raw.isNotEmpty ? IncomingFile(path: raw, appOwned: false) : null;
    }
    if (raw is Map) {
      final path = raw['path'];
      final appOwned = raw['appOwned'];
      if (path is String && path.isNotEmpty && appOwned is bool) {
        return IncomingFile(path: path, appOwned: appOwned);
      }
    }
    return null;
  }
}

/// A file handed to the app by the operating system.
///
/// [appOwned] is supplied by the native producer when it created a private
/// staging copy. It is never inferred from [path], because path layouts differ
/// by platform and a path alone cannot prove ownership.
class IncomingFile {
  const IncomingFile({required this.path, required this.appOwned});

  final String path;
  final bool appOwned;

  @override
  bool operator ==(Object other) =>
      other is IncomingFile && other.path == path && other.appOwned == appOwned;

  @override
  int get hashCode => Object.hash(path, appOwned);
}
