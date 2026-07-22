import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Delivers a finished backup [json] to the user as a file named
/// [suggestedFileName]. Returns `true` if the backup was delivered/saved, or
/// `false` if the user cancelled the save/share dialog without picking a
/// destination. Genuine I/O or plugin failures should still throw. See
/// [saveBackupToFile] for the default implementation; widget tests override
/// this seam so no real file/share plugin is invoked.
typedef BackupSaver =
    Future<bool> Function(String json, String suggestedFileName);

/// Prompts the user to choose a backup file and returns its contents, or `null`
/// if they cancelled. See [pickBackupFile] for the default implementation;
/// widget tests override this seam to return canned JSON.
typedef BackupPicker = Future<String?> Function();

/// Test seam for platform detection; defaults to the real `dart:io`
/// `Platform` getters. Overridable so tests can force either branch without
/// depending on the host OS running the test suite.
bool Function() isDesktopPlatform = () =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

const _jsonTypeGroup = XTypeGroup(
  label: 'Backup (JSON)',
  extensions: ['json'],
  uniformTypeIdentifiers: ['public.json'],
  mimeTypes: ['application/json'],
);

/// Maximum size, in bytes, of a backup file the restore path will read into
/// memory (~50 MiB).
///
/// Backups are JSON text and even a very large collection serializes to a few
/// megabytes, so this is generous headroom for legitimate files while refusing
/// one large enough to exhaust memory. The restore reads the whole file into a
/// `String`, so an unbounded read of an untrusted/corrupt file is an
/// uncontrolled resource-consumption risk (OWASP A04/A05); this ceiling caps it.
const int kMaxBackupFileBytes = 50 * 1024 * 1024;

/// Thrown by [pickBackupFile] when the chosen file exceeds
/// [kMaxBackupFileBytes]. Carries a friendly, user-facing [message] so the UI
/// can explain the refusal without surfacing internals or a stack trace.
class BackupFileTooLargeException implements Exception {
  const BackupFileTooLargeException({
    required this.sizeBytes,
    required this.maxBytes,
  });

  /// The rejected file's size in bytes.
  final int sizeBytes;

  /// The enforced ceiling ([kMaxBackupFileBytes]) in bytes.
  final int maxBytes;

  /// User-facing explanation (no stack traces / internals).
  String get message =>
      'That file is too large to be a Caller\u2019s Compendium backup '
      '(${_mib(sizeBytes)} MB; limit ${_mib(maxBytes)} MB). '
      'Your data is unchanged.';

  @override
  String toString() => 'BackupFileTooLargeException: $message';

  static String _mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}

/// Default [BackupSaver].
///
/// On desktop (macOS/Windows/Linux) a backup is a "save a file" action: this
/// shows a native Save As dialog (via `file_selector`'s [getSaveLocation]) and
/// writes [json] straight to the chosen path. Returns `false` without writing
/// anything if the user cancels the dialog.
///
/// On mobile (iOS/Android) a backup is a "share to another app" action: this
/// writes [json] to a temp file (via `path_provider`) and hands it to the OS
/// share sheet (via `share_plus`), returning `true` once the sheet has been
/// invoked (share-sheet completion isn't reliably observable on those
/// platforms).
Future<bool> saveBackupToFile(String json, String suggestedFileName) async {
  if (isDesktopPlatform()) {
    final location = await getSaveLocation(
      suggestedName: suggestedFileName,
      acceptedTypeGroups: const [_jsonTypeGroup],
    );
    if (location == null) return false;
    await File(location.path).writeAsString(json);
    return true;
  }

  final dir = await getTemporaryDirectory();
  // Create the directory first: this branch runs on mobile (iOS/Android), and
  // on sandboxed platforms `getTemporaryDirectory()` can hand back a per-app
  // subdirectory that doesn't exist yet — writing into a missing directory
  // throws `PathNotFoundException`. Defensive I/O for the share-staging path.
  await dir.create(recursive: true);
  final file = File('${dir.path}/$suggestedFileName');
  await file.writeAsString(json);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      fileNameOverrides: [suggestedFileName],
      subject: suggestedFileName,
    ),
  );
  return true;
}

/// Default [BackupPicker]: opens the native open-file dialog (via
/// `file_selector`), restricted to `.json`, and reads the chosen file's text
/// (subject to the [kMaxBackupFileBytes] size cap). Returns `null` when the
/// user cancels.
Future<String?> pickBackupFile() async {
  final file = await openFile(acceptedTypeGroups: const [_jsonTypeGroup]);
  if (file == null) return null;
  return readBackupFile(file);
}

/// Reads [file]'s text for restore, refusing a file larger than [maxBytes]
/// ([kMaxBackupFileBytes] by default) with a [BackupFileTooLargeException].
///
/// Enforcement is two-layered so the cap holds even against a hostile or
/// racing path (OWASP A04/A05: uncontrolled resource consumption):
/// 1. A fast pre-rejection using `XFile.length()` (a cheap stat) rejects an
///    obviously-oversized file before any bytes are read. This is advisory
///    only — the file could grow or be swapped between the stat and the read
///    (a TOCTOU gap), so it is NOT the real guarantee.
/// 2. The **actual** read streams the file via `openRead()` and aborts the
///    moment the accumulated size exceeds [maxBytes] (reading at most
///    `maxBytes + 1` worth before rejecting). This bounds the real allocation
///    regardless of what `length()` claimed, so a file that reports a small or
///    stale size but streams more than the cap is still rejected.
///
/// Only the collected bytes (guaranteed within the cap) are decoded as UTF-8.
/// Exposed for testing; production code reaches it through [pickBackupFile].
@visibleForTesting
Future<String> readBackupFile(
  XFile file, {
  int maxBytes = kMaxBackupFileBytes,
}) async {
  // Layer 1: fast pre-rejection on the reported size (advisory; see above).
  final reported = await file.length();
  if (reported > maxBytes) {
    throw BackupFileTooLargeException(sizeBytes: reported, maxBytes: maxBytes);
  }

  // Layer 2: bound the real read. Accumulate stream chunks and stop as soon as
  // we cross the cap, so the actual bytes held never exceed maxBytes.
  final builder = BytesBuilder(copy: false);
  var total = 0;
  await for (final chunk in file.openRead()) {
    total += chunk.length;
    if (total > maxBytes) {
      throw BackupFileTooLargeException(sizeBytes: total, maxBytes: maxBytes);
    }
    builder.add(chunk);
  }
  return utf8.decode(builder.takeBytes());
}
