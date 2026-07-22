import 'dart:async';
import 'dart:io';

import 'package:compendium_app/src/diagnostics/crash_fallback.dart';
import 'package:compendium_app/src/diagnostics/crash_log_store.dart';
import 'package:compendium_app/src/diagnostics/crash_reporter.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [CrashLogSink] that records the sources it was called with and completes
/// [first] on the initial call, so async routing can be awaited deterministically.
class _RecordingSink implements CrashLogSink {
  final List<String> sources = [];
  final Completer<void> first = Completer<void>();

  @override
  void record(Object error, StackTrace? stack, {required String source}) {
    sources.add(source);
    if (!first.isCompleted) first.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late CrashLogStore store;
  late CrashReporter reporter;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('crash_reporter_test');
    store = CrashLogStore(directoryProvider: () async => dir);
    reporter = CrashReporter(
      store: store,
      appVersion: '9.9.9',
      platformDescriber: () => 'testos 1.0',
      clock: () => DateTime.utc(2026, 5, 4, 3, 2, 1),
    );
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('CrashReporter', () {
    test('buildRecord captures type/message/context deterministically', () {
      final record = reporter.buildRecord(
        StateError('nope'),
        StackTrace.fromString('#0 frame'),
        source: 'unit',
      );
      expect(record.errorType, 'StateError');
      expect(record.errorMessage, contains('nope'));
      expect(record.appVersion, '9.9.9');
      expect(record.platform, 'testos 1.0');
      expect(record.source, 'unit');
      expect(record.timestampUtc, DateTime.utc(2026, 5, 4, 3, 2, 1));
      expect(record.stack, contains('#0 frame'));
    });

    test('record appends the built record to the store', () async {
      reporter.record(
        StateError('persisted'),
        StackTrace.current,
        source: 'unit',
      );
      final records = await store.readRecords();
      expect(records, hasLength(1));
      expect(records.single.errorMessage, contains('persisted'));
      expect(records.single.source, 'unit');
    });

    test(
      'a persist failure is swallowed and surfaced via onAppendError',
      () async {
        Object? seen;
        final failing = CrashReporter(
          store: _ThrowingStore(),
          onAppendError: (error, _) => seen = error,
        );
        // Must not throw out of the (fire-and-forget) handler path.
        failing.record(StateError('boom'), StackTrace.current, source: 'unit');
        await Future<void>.delayed(Duration.zero);
        expect(seen, isNotNull);
      },
    );

    test(
      'an error whose toString() throws is guarded, not propagated',
      () async {
        Object? seen;
        final r = CrashReporter(
          store: store,
          onAppendError: (error, _) => seen = error,
        );
        // buildRecord reads error.toString(); a hostile toString must be caught
        // inside the no-throw guard rather than escaping the global handler.
        r.record(_HostileError(), StackTrace.current, source: 'unit');
        await Future<void>.delayed(Duration.zero);
        expect(seen, isNotNull);
        expect(await store.readRecords(), isEmpty);
      },
    );
  });

  group('installGlobalErrorHandlers', () {
    late FlutterExceptionHandler? origFlutterOnError;
    late ErrorWidgetBuilder origErrorBuilder;
    late Object? origPlatformOnError;

    setUp(() {
      origFlutterOnError = FlutterError.onError;
      origErrorBuilder = ErrorWidget.builder;
      origPlatformOnError = PlatformDispatcher.instance.onError;
    });

    tearDown(() {
      FlutterError.onError = origFlutterOnError;
      ErrorWidget.builder = origErrorBuilder;
      PlatformDispatcher.instance.onError =
          origPlatformOnError as bool Function(Object, StackTrace)?;
    });

    test('routes FlutterError.onError to the sink', () async {
      installGlobalErrorHandlers(reporter, presentErrorInDebug: false);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('framework boom'),
          stack: StackTrace.current,
        ),
      );
      final records = await store.readRecords();
      expect(records.map((r) => r.source), contains('FlutterError.onError'));
      expect(
        records.any((r) => r.errorMessage.contains('framework boom')),
        isTrue,
      );
    });

    test(
      'routes PlatformDispatcher.onError to the sink and marks it handled',
      () async {
        installGlobalErrorHandlers(reporter, presentErrorInDebug: false);
        final handled = PlatformDispatcher.instance.onError!(
          StateError('engine boom'),
          StackTrace.current,
        );
        expect(handled, isTrue);
        final records = await store.readRecords();
        expect(
          records.map((r) => r.source),
          contains('PlatformDispatcher.onError'),
        );
      },
    );

    test('installs the friendly recoverable fallback widget', () {
      installGlobalErrorHandlers(reporter, presentErrorInDebug: false);
      final widget = ErrorWidget.builder(
        FlutterErrorDetails(exception: StateError('x')),
      );
      expect(widget, isA<CrashFallback>());
    });
  });

  group('runGuarded', () {
    test('routes uncaught asynchronous errors to the sink', () async {
      final sink = _RecordingSink();
      runGuarded(() {
        // An error thrown from a later microtask/timer escapes the caller and
        // is only catchable by the guarding zone.
        Timer.run(() => throw StateError('async boom'));
      }, sink);
      await sink.first.future.timeout(const Duration(seconds: 5));
      expect(sink.sources, contains('runZonedGuarded'));
    });
  });
}

/// A store whose append always fails, to exercise [CrashReporter]'s guard.
class _ThrowingStore extends CrashLogStore {
  _ThrowingStore() : super(directoryProvider: _unused);

  static Future<Directory> _unused() async =>
      throw StateError('should not resolve dir');

  @override
  Future<void> append(CrashLogRecord record) async =>
      throw StateError('disk full');
}

/// An error whose `toString()` throws, to exercise the no-throw guard around
/// record building.
class _HostileError implements Exception {
  @override
  String toString() => throw StateError('toString blew up');
}
