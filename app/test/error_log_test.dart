import 'dart:io';

import 'package:compendium_app/src/diagnostics/crash_log_store.dart';
import 'package:compendium_app/src/diagnostics/crash_reporter.dart';
import 'package:compendium_app/src/diagnostics/error_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [CrashLogSink] that records every call, and can optionally be made to
/// throw, to exercise [logCaughtError]'s no-throw guard.
class _RecordingSink implements CrashLogSink {
  final List<String> sources = [];
  bool throwOnRecord = false;

  @override
  void record(Object error, StackTrace? stack, {required String source}) {
    if (throwOnRecord) throw StateError('sink exploded');
    sources.add(source);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(resetCaughtErrorLogForTesting);

  group('logCaughtError', () {
    test('is a no-op before installCaughtErrorLog has run', () {
      // Guards issue #963's zero-test-churn design: a widget test that never
      // installs a sink (the overwhelming majority of this app's tests) must
      // be able to hit an instrumented catch site without crashing or needing
      // any setup.
      expect(
        () => logCaughtError(
          StateError('uninstalled'),
          StackTrace.current,
          source: 'unit.test',
        ),
        returnsNormally,
      );
    });

    test('forwards to the installed sink with the given source', () {
      final sink = _RecordingSink();
      installCaughtErrorLog(sink);

      logCaughtError(
        StateError('boom'),
        StackTrace.current,
        source: 'dance_list_screen._importOnline',
      );

      expect(sink.sources, ['dance_list_screen._importOnline']);
    });

    test('never throws when the installed sink throws', () {
      final sink = _RecordingSink()..throwOnRecord = true;
      installCaughtErrorLog(sink);

      // This call sits ahead of a user-visible error surface (a snackbar) at
      // every real call site; a throw here must never propagate and block
      // that surface from showing.
      expect(
        () => logCaughtError(
          StateError('boom'),
          StackTrace.current,
          source: 'unit.test',
        ),
        returnsNormally,
      );
    });

    test('routes through to a real CrashReporter/CrashLogStore', () async {
      final dir = await Directory.systemTemp.createTemp('error_log_test');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final store = CrashLogStore(directoryProvider: () async => dir);
      final reporter = CrashReporter(store: store);
      installCaughtErrorLog(reporter);

      logCaughtError(
        StateError('end to end'),
        StackTrace.current,
        source: 'unit.test',
      );
      // CrashReporter.record is fire-and-forget (unawaited internally); give
      // its microtask a turn to complete before reading the store back.
      await Future<void>.delayed(Duration.zero);

      final records = await store.readRecords();
      expect(records, hasLength(1));
      expect(records.single.source, 'unit.test');
      expect(records.single.errorMessage, contains('end to end'));
    });
  });
}
