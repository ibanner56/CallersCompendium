/// The structured crash-log record persisted by the app's local, offline crash
/// log (issue #458). Pure Dart (ADR-001): the model, its JSON-line
/// serialization, and the scrubbing hook live in core so they can be unit-tested
/// with `dart test`. File rotation and I/O live in the app (`crash_log_store`).
///
/// Records are stored one-per-line as JSON (JSONL): appending is a single write
/// and parsing is line-oriented, which keeps rotation-by-size trivial and makes
/// a truncated/rolled file safe to read (a partial trailing line is simply
/// skipped).
library;

import 'dart:convert';

import 'crash_redactor.dart';

/// One captured error: when it happened, the app/platform context, where the
/// handler caught it, and the (raw) error + stack text.
class CrashLogRecord {
  const CrashLogRecord({
    required this.timestampUtc,
    required this.appVersion,
    required this.platform,
    required this.source,
    required this.errorType,
    required this.errorMessage,
    required this.stack,
  });

  /// Current on-disk schema version, written as `v` and checked on read so a
  /// future format change can be migrated or skipped rather than mis-parsed.
  static const int schemaVersion = 1;

  /// When the error was captured, always in UTC.
  final DateTime timestampUtc;

  /// The app's marketing version (e.g. `0.1.0`).
  final String appVersion;

  /// Coarse platform/OS descriptor (e.g. `macos 14.5`).
  final String platform;

  /// Which handler captured this (e.g. `FlutterError.onError`,
  /// `PlatformDispatcher.onError`, `runZonedGuarded`, `integrity-probe`).
  final String source;

  /// The error's runtime type name (e.g. `StateError`).
  final String errorType;

  /// The error's message (`error.toString()`); may contain user content, so it
  /// is scrubbed for the default export (see [scrubbed]).
  final String errorMessage;

  /// The captured stack trace text; may contain absolute paths, so it is
  /// scrubbed for the default export (see [scrubbed]).
  final String stack;

  /// Serializes this record to a single JSON line (no embedded newlines), for
  /// appending to the rotating JSONL log.
  String toJsonLine() => jsonEncode({
    'v': schemaVersion,
    'ts': timestampUtc.toUtc().toIso8601String(),
    'app': appVersion,
    'platform': platform,
    'source': source,
    'type': errorType,
    'msg': errorMessage,
    'stack': stack,
  });

  /// Parses a single JSONL [line] back into a record, or returns `null` when
  /// the line is blank, malformed, or an unrecognized schema version. Readers
  /// use this to skip partial/rolled lines without failing the whole read.
  static CrashLogRecord? tryParseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['v'] != schemaVersion) return null;
      final ts = DateTime.tryParse(decoded['ts'] as String? ?? '');
      if (ts == null) return null;
      return CrashLogRecord(
        timestampUtc: ts.toUtc(),
        appVersion: decoded['app'] as String? ?? '',
        platform: decoded['platform'] as String? ?? '',
        source: decoded['source'] as String? ?? '',
        errorType: decoded['type'] as String? ?? '',
        errorMessage: decoded['msg'] as String? ?? '',
        stack: decoded['stack'] as String? ?? '',
      );
    } on FormatException {
      return null;
    }
  }

  /// A human-readable multi-line rendering of this record, used both for the
  /// in-app "recent entries" view and the exported log file.
  String toReadable() {
    final buffer = StringBuffer()
      ..writeln(
        '[${timestampUtc.toUtc().toIso8601String()}] '
        'v$appVersion $platform — $source',
      )
      ..writeln(errorType.isEmpty ? errorMessage : '$errorType: $errorMessage');
    if (stack.trim().isNotEmpty) buffer.writeln(stack.trimRight());
    return buffer.toString().trimRight();
  }

  /// A short one-line summary (type + first line of the message), for compact
  /// list rows in the Diagnostics UI.
  String get summary {
    final firstLine = errorMessage.split('\n').first.trim();
    if (errorType.isEmpty) return firstLine;
    return firstLine.isEmpty ? errorType : '$errorType: $firstLine';
  }

  /// Returns a copy with the free-text fields ([errorMessage], [stack]) scrubbed
  /// by [redactor]. The timestamp, version, platform, source, and error *type*
  /// are structural diagnostics with no user content, so they are preserved.
  CrashLogRecord scrubbed(CrashRedactor redactor) => CrashLogRecord(
    timestampUtc: timestampUtc,
    appVersion: appVersion,
    platform: platform,
    source: source,
    errorType: errorType,
    errorMessage: redactor.scrub(errorMessage),
    stack: redactor.scrub(stack),
  );
}
