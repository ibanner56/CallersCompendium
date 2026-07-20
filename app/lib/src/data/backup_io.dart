import 'dart:io';

import 'package:file_selector/file_selector.dart';
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
  // Create the directory first: on sandboxed macOS `getTemporaryDirectory()`
  // can return a per-bundle `Caches/` subdirectory that doesn't exist yet, and
  // writing into a missing directory throws `PathNotFoundException`.
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
/// `file_selector`), restricted to `.json`, and reads the chosen file's text.
/// Returns `null` when the user cancels.
Future<String?> pickBackupFile() async {
  final file = await openFile(acceptedTypeGroups: const [_jsonTypeGroup]);
  if (file == null) return null;
  return file.readAsString();
}
