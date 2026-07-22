import 'dart:async';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app_metadata.dart';
import 'crash_fallback.dart';
import 'crash_log_store.dart';

/// A sink that captured errors are forwarded to. Kept as an interface so
/// `main.dart` and tests can inject a real [CrashReporter] or a fake without
/// pulling in file I/O.
abstract class CrashLogSink {
  /// Records [error] (with optional [stack]) as having been caught by [source]
  /// (e.g. `FlutterError.onError`, `PlatformDispatcher.onError`,
  /// `runZonedGuarded`, `integrity-probe`).
  void record(Object error, StackTrace? stack, {required String source});
}

/// Produces the coarse platform descriptor stored on each record. Injectable so
/// tests are deterministic regardless of the host OS.
typedef PlatformDescriber = String Function();

/// Builds [CrashLogRecord]s from caught errors and appends them to a
/// [CrashLogStore]. Appends are fire-and-forget and fully guarded: a logging
/// failure must never escape a global error handler (that would risk an
/// error-while-logging feedback loop).
class CrashReporter implements CrashLogSink {
  CrashReporter({
    required this.store,
    this.appVersion = kAppVersion,
    PlatformDescriber? platformDescriber,
    DateTime Function()? clock,
    this.onAppendError,
  }) : _platformDescriber = platformDescriber ?? _defaultPlatform,
       _clock = clock ?? DateTime.now;

  final CrashLogStore store;
  final String appVersion;
  final PlatformDescriber _platformDescriber;
  final DateTime Function() _clock;

  /// Optional hook invoked when a persist attempt fails; used by tests to
  /// observe the (otherwise swallowed) failure.
  final void Function(Object error, StackTrace stack)? onAppendError;

  static String _defaultPlatform() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Builds (but does not persist) the record for [error]. Exposed for tests.
  @visibleForTesting
  CrashLogRecord buildRecord(
    Object error,
    StackTrace? stack, {
    required String source,
  }) => CrashLogRecord(
    timestampUtc: _clock().toUtc(),
    appVersion: appVersion,
    platform: _platformDescriber(),
    source: source,
    errorType: error.runtimeType.toString(),
    errorMessage: error.toString(),
    stack: (stack ?? StackTrace.current).toString(),
  );

  @override
  void record(Object error, StackTrace? stack, {required String source}) {
    final record = buildRecord(error, stack, source: source);
    unawaited(_appendGuarded(record));
  }

  Future<void> _appendGuarded(CrashLogRecord record) async {
    try {
      await store.append(record);
    } catch (error, stack) {
      onAppendError?.call(error, stack);
      if (kDebugMode) debugPrint('Crash log append failed: $error');
    }
  }
}

/// Installs the global framework/engine error hooks so every uncaught error is
/// routed to [sink] and the raw red error box is replaced by [CrashFallback].
///
/// - [FlutterError.onError] forwards framework (build/layout/paint) errors and,
///   in debug, still calls [FlutterError.presentError] so the console output a
///   developer expects is preserved.
/// - [PlatformDispatcher.instance.onError] forwards engine/isolate errors that
///   escape the framework, returning `true` to mark them handled.
/// - [ErrorWidget.builder] renders the friendly, recoverable fallback.
///
/// Pair this with [runGuarded], which additionally wraps the app in a
/// [runZonedGuarded] zone to catch uncaught *async* errors.
void installGlobalErrorHandlers(
  CrashLogSink sink, {
  bool presentErrorInDebug = true,
}) {
  FlutterError.onError = (details) {
    sink.record(
      details.exception,
      details.stack,
      source: 'FlutterError.onError',
    );
    if (kDebugMode && presentErrorInDebug) {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    sink.record(error, stack, source: 'PlatformDispatcher.onError');
    return true;
  };
  ErrorWidget.builder = (details) => CrashFallback(details: details);
}

/// Runs [body] (which should call `runApp`) inside a [runZonedGuarded] zone so
/// uncaught asynchronous errors are captured to [sink] instead of crashing the
/// app silently.
void runGuarded(void Function() body, CrashLogSink sink) {
  runZonedGuarded(body, (error, stack) {
    sink.record(error, stack, source: 'runZonedGuarded');
  });
}
