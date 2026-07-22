import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final record = CrashLogRecord(
    timestampUtc: DateTime.utc(2026, 7, 22, 7, 53, 45),
    appVersion: '0.1.0',
    platform: 'macos 14.5',
    source: 'FlutterError.onError',
    errorType: 'StateError',
    errorMessage: 'Bad state: no active dance',
    stack: '#0 main (package:compendium_app/main.dart:10:2)',
  );

  test('round-trips through a JSON line', () {
    final parsed = CrashLogRecord.tryParseLine(record.toJsonLine());
    expect(parsed, isNotNull);
    expect(parsed!.timestampUtc, record.timestampUtc);
    expect(parsed.appVersion, '0.1.0');
    expect(parsed.platform, 'macos 14.5');
    expect(parsed.source, 'FlutterError.onError');
    expect(parsed.errorType, 'StateError');
    expect(parsed.errorMessage, 'Bad state: no active dance');
    expect(parsed.stack, contains('package:compendium_app/main.dart:10:2'));
  });

  test('toJsonLine is single-line even with a multi-line stack', () {
    final multi = CrashLogRecord(
      timestampUtc: DateTime.utc(2026),
      appVersion: '0.1.0',
      platform: 'linux',
      source: 'zone',
      errorType: 'Exception',
      errorMessage: 'boom',
      stack: '#0 a\n#1 b\n#2 c',
    );
    expect(multi.toJsonLine(), isNot(contains('\n')));
    final parsed = CrashLogRecord.tryParseLine(multi.toJsonLine());
    expect(parsed!.stack, '#0 a\n#1 b\n#2 c');
  });

  test('tryParseLine skips blank, malformed, and wrong-version lines', () {
    expect(CrashLogRecord.tryParseLine(''), isNull);
    expect(CrashLogRecord.tryParseLine('   '), isNull);
    expect(CrashLogRecord.tryParseLine('not json'), isNull);
    expect(CrashLogRecord.tryParseLine('[1,2,3]'), isNull);
    expect(CrashLogRecord.tryParseLine('{"v":999,"ts":"x"}'), isNull);
  });

  test('scrubbed() redacts message and stack but keeps structural fields', () {
    final raw = CrashLogRecord(
      timestampUtc: DateTime.utc(2026),
      appVersion: '0.1.0',
      platform: 'macos',
      source: 'zone',
      errorType: 'FormatException',
      errorMessage: 'could not parse "Chinquapin Reel" for jane@example.com',
      stack: 'at /Users/jane/app/lib/main.dart:10:2',
    );
    final scrubbed = raw.scrubbed(
      const CrashRedactor(userContentTerms: {'Chinquapin Reel'}),
    );
    expect(scrubbed.errorMessage, isNot(contains('Chinquapin Reel')));
    expect(scrubbed.errorMessage, isNot(contains('jane@example.com')));
    expect(scrubbed.stack, isNot(contains('/Users/jane')));
    expect(scrubbed.stack, contains('main.dart:10:2'));
    // Structural fields are preserved.
    expect(scrubbed.timestampUtc, raw.timestampUtc);
    expect(scrubbed.appVersion, '0.1.0');
    expect(scrubbed.platform, 'macos');
    expect(scrubbed.errorType, 'FormatException');
  });

  test('summary and toReadable are concise and complete', () {
    expect(record.summary, 'StateError: Bad state: no active dance');
    final readable = record.toReadable();
    expect(readable, contains('2026-07-22T07:53:45.000Z'));
    expect(readable, contains('v0.1.0 macos 14.5 — FlutterError.onError'));
    expect(readable, contains('StateError: Bad state: no active dance'));
    expect(readable, contains('package:compendium_app/main.dart:10:2'));
  });
}
