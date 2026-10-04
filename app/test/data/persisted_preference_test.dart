import 'package:compendium_app/src/data/persisted_preference.dart';
import 'package:compendium_app/src/diagnostics/crash_reporter.dart';
import 'package:compendium_app/src/diagnostics/error_log.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

class _RecordingCrashLogSink implements CrashLogSink {
  final List<String> sources = [];

  @override
  void record(Object error, StackTrace? stack, {required String source}) {
    sources.add(source);
  }
}

PreferenceNotifier<bool> _boolPref({bool? initialValue}) =>
    PreferenceNotifier<bool>(
      key: 'test_pref',
      defaultValue: true,
      initialValue: initialValue,
      decode: (Object? v) => v is bool ? v : true,
      encode: (v) => v,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  tearDown(resetCaughtErrorLogForTesting);

  test('applyStored assigns the default for null and wrong types', () {
    final pref = _boolPref();
    pref.applyStored(false);
    expect(pref.value, isFalse);
    pref.applyStored(null);
    expect(pref.value, isTrue);
    pref.applyStored(false);
    pref.applyStored('false');
    expect(pref.value, isTrue);
    pref.applyStored(false);
    pref.applyStored(0);
    expect(pref.value, isTrue);
  });

  test('reset returns to the default, not the initial value', () {
    final pref = _boolPref(initialValue: false);
    expect(pref.value, isFalse);
    pref.applyStored(false);
    pref.reset();
    expect(pref.value, isTrue);
  });

  test('a tri-state preference decodes a wrong type to null', () {
    final pref = PreferenceNotifier<bool?>(
      key: 'test_tristate',
      defaultValue: null,
      decode: (Object? v) => v is bool ? v : null,
      encode: (v) => v,
    );
    pref.applyStored(true);
    expect(pref.value, isTrue);
    pref.applyStored('yes');
    expect(pref.value, isNull);
  });

  test('read returns the stored value, null when absent', () async {
    final repos = openTestRepositories();
    final pref = _boolPref();
    expect(await pref.read(repos.settings), isNull);
    await repos.settings.set('test_pref', false);
    expect(await pref.read(repos.settings), isFalse);
  });

  test('persist writes the encoded value', () async {
    final repos = openTestRepositories();
    final pref = _boolPref()..value = false;
    await pref.persist(repos.settings);
    expect(await repos.settings.get('test_pref'), isFalse);
  });

  test('persist logs and does not throw when set fails', () async {
    final failing = openTestRepositoriesWithFailingSettings();
    final sink = _RecordingCrashLogSink();
    installCaughtErrorLog(sink);
    final pref = _boolPref()..value = false;

    await pref.persist(failing.settings);

    expect(sink.sources, ['preference.persist.test_pref']);
  });
}
