import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the directory the crash log lives in. Injectable so tests can point
/// the store at a temp directory instead of the real app-support location
/// (which needs the `path_provider` platform channel, unavailable under
/// `flutter test`).
typedef CrashLogDirProvider = Future<Directory> Function();

/// The on-device, offline crash log (issue #458): a size-capped, rotating set
/// of JSONL files in the app-support directory. **No network, no telemetry** —
/// nothing here leaves the device unless the user explicitly exports it from
/// Settings → Diagnostics.
///
/// Despite the name, it captures more than uncaught crashes: every caught
/// error surfaced to the user (a snackbar, an inline error banner) is written
/// here too, via `error_log.dart`'s `logCaughtError` (issue #963) — the file
/// name and the on-disk `diagnostics/crash.log` path predate that change and
/// were kept rather than migrated, since nothing depends on the name itself.
///
/// Records are appended one-JSON-per-line to `diagnostics/crash.log`. When that
/// file would exceed [maxFileBytes] it is rolled to `crash.log.1` (existing
/// rolled files shift up, the oldest beyond [maxRolledFiles] is pruned), so the
/// log can never grow without bound. Reads tolerate partial/rolled lines by
/// skipping anything that doesn't parse (see [CrashLogRecord.tryParseLine]).
///
/// All operations are serialized through an internal queue so a burst of errors
/// (or a concurrent read/clear) can't interleave writes and corrupt a line.
class CrashLogStore {
  CrashLogStore({
    required this.directoryProvider,
    this.maxFileBytes = defaultMaxFileBytes,
    this.maxRolledFiles = defaultMaxRolledFiles,
    this.maxRecordBytes = defaultMaxRecordBytes,
  });

  /// Process-wide store for the real app-support crash log.
  ///
  /// Returns a single shared instance: the global error handlers (installed in
  /// `main`) and the Settings ▸ Diagnostics UI must write/read/clear through the
  /// **same** object, because each store serializes its own operations through a
  /// private queue ([_enqueue]). Two stores over the same files would each have
  /// their own queue, so an append/rotation on one could interleave with a
  /// read/export/clear on the other and tear a line. Tests never take this path
  /// — they inject their own store via [directoryProvider], so there is no
  /// shared global state to leak between tests.
  factory CrashLogStore.appSupport({
    int maxFileBytes = defaultMaxFileBytes,
    int maxRolledFiles = defaultMaxRolledFiles,
    int maxRecordBytes = defaultMaxRecordBytes,
  }) => _sharedAppSupport ??= CrashLogStore(
    directoryProvider: () async {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'diagnostics'));
    },
    maxFileBytes: maxFileBytes,
    maxRolledFiles: maxRolledFiles,
    maxRecordBytes: maxRecordBytes,
  );

  static CrashLogStore? _sharedAppSupport;

  /// Base file name of the active log; rolled files are `crash.log.1`, `.2`, …
  static const String baseName = 'crash.log';

  /// Default per-file size cap (~1 MB) before rotation.
  static const int defaultMaxFileBytes = 1024 * 1024;

  /// Default number of rolled files retained in addition to the active log.
  static const int defaultMaxRolledFiles = 3;

  /// Default per-record size cap (64 KiB). A single record is truncated to fit
  /// this (or [maxFileBytes] when smaller) so one pathological error can't grow
  /// the log without bound (see [append]).
  static const int defaultMaxRecordBytes = 64 * 1024;

  /// Resolves the directory the log lives in (see [CrashLogDirProvider]).
  final CrashLogDirProvider directoryProvider;

  /// Rotate the active log once it would exceed this many bytes.
  final int maxFileBytes;

  /// How many rolled files (`crash.log.1` … `crash.log.N`) to keep.
  final int maxRolledFiles;

  /// Upper bound on a single serialized record; larger records are truncated.
  final int maxRecordBytes;

  Directory? _dir;
  Future<void> _tail = Future<void>.value();

  /// Serializes [action] behind any in-flight store operation so writes,
  /// reads, and clears never interleave.
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    // Keep the tail alive even if this action fails, so a single failure
    // doesn't wedge the queue.
    // diagnostics: silent — this IS the crash-log store's own internal queue
    // guard; the caller (`result`, returned below) still surfaces the real
    // failure to whoever awaits it (e.g. `CrashReporter._recordGuarded`,
    // which already logs it via `onAppendError`/debug print). Logging here
    // too would double-count the same failure through the very store being
    // guarded.
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Directory> _resolveDir() async {
    final dir = _dir ??= await directoryProvider();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Appends [record] to the active log, rotating first if it would overflow
  /// [maxFileBytes]. A single oversized record is truncated to [maxRecordBytes]
  /// (or [maxFileBytes] when that is smaller) first, so no one record can make a
  /// log file grow without bound.
  Future<void> append(CrashLogRecord record) => _enqueue(() async {
    final dir = await _resolveDir();
    final cap = maxRecordBytes < maxFileBytes ? maxRecordBytes : maxFileBytes;
    // Reserve one byte for the trailing newline so the record plus its newline
    // still fits the per-record budget.
    final bounded = record.truncatedToFit(cap - 1);
    final bytes = utf8.encode('${bounded.toJsonLine()}\n');
    final current = File(p.join(dir.path, baseName));
    if (await current.exists()) {
      final length = await current.length();
      if (length > 0 && length + bytes.length > maxFileBytes) {
        await _rotate(dir);
      }
    }
    await current.writeAsBytes(bytes, mode: FileMode.append, flush: true);
  });

  Future<void> _rotate(Directory dir) async {
    File rolled(int i) => File(p.join(dir.path, '$baseName.$i'));
    final oldest = rolled(maxRolledFiles);
    if (await oldest.exists()) await oldest.delete();
    for (var i = maxRolledFiles - 1; i >= 1; i--) {
      final src = rolled(i);
      if (await src.exists()) {
        await src.rename(p.join(dir.path, '$baseName.${i + 1}'));
      }
    }
    final current = File(p.join(dir.path, baseName));
    if (await current.exists()) {
      await current.rename(p.join(dir.path, '$baseName.1'));
    }
  }

  /// Reads the retained records. Defaults to newest-first (the order the UI
  /// shows), optionally capped at [limit]. Chronological order across files is
  /// oldest rolled file → … → `crash.log.1` → active log.
  Future<List<CrashLogRecord>> readRecords({
    int? limit,
    bool newestFirst = true,
  }) => _enqueue(() async {
    final dir = await _resolveDir();
    final records = <CrashLogRecord>[];
    for (var i = maxRolledFiles; i >= 1; i--) {
      await _collect(File(p.join(dir.path, '$baseName.$i')), records);
    }
    await _collect(File(p.join(dir.path, baseName)), records);
    var result = newestFirst ? records.reversed.toList() : records;
    if (limit != null && result.length > limit) {
      result = result.sublist(0, limit);
    }
    return result;
  });

  Future<void> _collect(File file, List<CrashLogRecord> into) async {
    if (!await file.exists()) return;
    for (final line in const LineSplitter().convert(
      await file.readAsString(),
    )) {
      final record = CrashLogRecord.tryParseLine(line);
      if (record != null) into.add(record);
    }
  }

  /// Deletes the active log and every rolled file.
  Future<void> clear() => _enqueue(() async {
    final dir = await _resolveDir();
    final active = File(p.join(dir.path, baseName));
    if (await active.exists()) await active.delete();
    for (var i = 1; i <= maxRolledFiles; i++) {
      final rolled = File(p.join(dir.path, '$baseName.$i'));
      if (await rolled.exists()) await rolled.delete();
    }
  });
}
