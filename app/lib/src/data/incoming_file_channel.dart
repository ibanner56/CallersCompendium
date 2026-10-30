import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../diagnostics/error_log.dart';
import 'desktop_open_path.dart';

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
///
/// Windows and Linux have no native side (PLAT-3). There the path comes from
/// the command line ([initialDesktopPath]) or from a second launch over the
/// single-instance channel ([openDesktopPath]). Both are checked with
/// [checkDesktopOpenPath] and delivered as files the app does not own, so
/// intake never deletes the user's copy.
class IncomingFileChannel {
  IncomingFileChannel({MethodChannel? channel, String? initialDesktopPath})
    : _channel = channel ?? const MethodChannel(channelName) {
    if (initialDesktopPath != null) openDesktopPath(initialDesktopPath);
  }

  /// Platform-channel name shared with the native handlers. Namespaced to the
  /// app so it never collides with a plugin channel.
  static const String channelName =
      'is.banner.callerscompendium/incoming_files';

  final MethodChannel _channel;
  final StreamController<IncomingFile> _controller =
      StreamController<IncomingFile>.broadcast();
  final StreamController<String> _urlController =
      StreamController<String>.broadcast();

  /// Desktop opens are checked in arrival order, one at a time.
  Future<void> _desktopOpens = Future<void>.value();

  /// Set once [initialFile] has been asked: the app is ready, so a desktop
  /// open goes to [files] rather than waiting in [_pendingDesktopFile].
  bool _initialFileTaken = false;

  /// The latest desktop open that arrived before [initialFile] was asked.
  IncomingFile? _pendingDesktopFile;

  /// The desktop file intake is handling now, until [fileHandled]. Any local
  /// process can send desktop opens, so they are coalesced: one import
  /// review at a time, and only the latest open waits behind it.
  IncomingFile? _desktopFileInIntake;

  /// The latest desktop open that arrived while [_desktopFileInIntake] was set.
  IncomingFile? _queuedDesktopFile;

  /// Time since the last desktop rejection was delivered; another within
  /// [kDesktopRejectionCooldown] is dropped, so a peer cannot queue snackbars.
  Stopwatch? _sinceDesktopRejection;

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
  ///
  /// On Windows and Linux, where no native side answers, this is the desktop
  /// open that arrived before the app was ready, if any (the latest one).
  Future<IncomingFile?> initialFile() async {
    final native = await _nativeInitialFile();
    await _desktopOpens;
    _initialFileTaken = true;
    final desktop = _pendingDesktopFile;
    _pendingDesktopFile = null;
    if (native != null) return native;
    _desktopFileInIntake = desktop;
    return desktop;
  }

  /// Tells the channel intake has finished with [file] (from [files] or
  /// [initialFile]), so the next desktop open, if one is waiting, can go to
  /// [files]. A file that did not come from a desktop open is ignored.
  void fileHandled(IncomingFile file) {
    if (!identical(file, _desktopFileInIntake)) return;
    _desktopFileInIntake = null;
    final next = _queuedDesktopFile;
    _queuedDesktopFile = null;
    if (next != null) _emitDesktopFile(next);
  }

  void _emitDesktopFile(IncomingFile file) {
    if (_desktopFileInIntake != null) {
      _queuedDesktopFile = file;
    } else if (!_controller.isClosed) {
      _desktopFileInIntake = file;
      _controller.add(file);
    }
  }

  Future<IncomingFile?> _nativeInitialFile() async {
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

  /// Completes once every [openDesktopPath] call so far has been checked and
  /// delivered or dropped.
  @visibleForTesting
  Future<void> get desktopOpensSettled => _desktopOpens;

  /// Hands intake a file a desktop launch asked to open (PLAT-3). [raw] is
  /// untrusted: it may come from any local process over the single-instance
  /// channel. It is checked with [checkDesktopOpenPath]. A refusal the user
  /// could have caused by opening a real file arrives as an
  /// [IncomingFileRejection], so they are told, at most once per
  /// [kDesktopRejectionCooldown]; a path the file associations never produce
  /// (malformed, relative, another extension) is dropped. An accepted file is
  /// never app-owned, so intake reads it and leaves it in place. Before
  /// [initialFile] has been asked the latest one waits for it; after, it goes
  /// to [files], one at a time: while intake has one, only the latest later
  /// open waits, until [fileHandled].
  void openDesktopPath(String raw) {
    _desktopOpens = _desktopOpens.then((_) async {
      final DesktopOpenCheck check;
      try {
        check = await checkDesktopOpenPath(raw);
      } catch (error, stackTrace) {
        // A fault here must not fail [initialFile], which awaits this chain.
        logCaughtErrorTypeOnly(
          error,
          stackTrace,
          source: 'incoming_file_channel.openDesktopPath',
        );
        return;
      }
      final path = check.path;
      final IncomingFile file;
      if (path != null) {
        file = IncomingFile(path: path, appOwned: false);
      } else {
        final rejection = switch (check.rejection!) {
          DesktopOpenRejection.tooLarge => IncomingFileRejection.tooLarge,
          DesktopOpenRejection.remote ||
          DesktopOpenRejection.notRegularFile ||
          DesktopOpenRejection.deviceName => IncomingFileRejection.unreadable,
          DesktopOpenRejection.malformed ||
          DesktopOpenRejection.notAbsolute ||
          DesktopOpenRejection.wrongExtension => null,
        };
        if (rejection == null) return;
        final since = _sinceDesktopRejection;
        if (since != null && since.elapsed < kDesktopRejectionCooldown) return;
        _sinceDesktopRejection = Stopwatch()..start();
        file = IncomingFile.rejected(rejection);
      }
      if (!_initialFileTaken) {
        _pendingDesktopFile = file;
      } else {
        _emitDesktopFile(file);
      }
    });
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
      // Native refused to stage the file (over the size cap). No path exists;
      // an unrecognised reason is dropped like any other junk payload.
      final rejected = raw['rejected'];
      if (rejected == IncomingFileRejection.tooLarge.wireName) {
        return const IncomingFile.rejected(IncomingFileRejection.tooLarge);
      }
      final path = raw['path'];
      final appOwned = raw['appOwned'];
      if (path is String && path.isNotEmpty && appOwned is bool) {
        return IncomingFile(path: path, appOwned: appOwned);
      }
    }
    return null;
  }
}

/// Shortest gap between two desktop-open rejections shown to the user; about
/// as long as the snackbar that shows one.
const Duration kDesktopRejectionCooldown = Duration(seconds: 4);

/// Why an incoming file was refused before intake read it, so no path exists.
enum IncomingFileRejection {
  /// The file exceeded the incoming-archive size cap while being staged.
  tooLarge('tooLarge'),

  /// A desktop open named a file the app will not read: a network-share or
  /// device path, a symlink, or something that is not a regular file
  /// ([DesktopOpenRejection.remote], [DesktopOpenRejection.notRegularFile],
  /// [DesktopOpenRejection.deviceName]).
  /// Never sent by native code.
  unreadable('unreadable');

  const IncomingFileRejection(this.wireName);

  /// Value of the `rejected` key in the channel payload.
  final String wireName;
}

/// A file handed to the app by the operating system.
///
/// [appOwned] is supplied by the native producer when it created a private
/// staging copy. It is never inferred from [path], because path layouts differ
/// by platform and a path alone cannot prove ownership.
///
/// When native refused to stage the file, [rejection] is set and [path] is
/// empty: there is no staged copy to read or delete.
class IncomingFile {
  const IncomingFile({required this.path, required this.appOwned})
    : rejection = null;

  const IncomingFile.rejected(IncomingFileRejection this.rejection)
    : path = '',
      appOwned = false;

  final String path;
  final bool appOwned;
  final IncomingFileRejection? rejection;

  @override
  bool operator ==(Object other) =>
      other is IncomingFile &&
      other.path == path &&
      other.appOwned == appOwned &&
      other.rejection == rejection;

  @override
  int get hashCode => Object.hash(path, appOwned, rejection);
}
