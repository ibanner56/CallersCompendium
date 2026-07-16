import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Delivers a finished backup [json] to the user as a file named
/// [suggestedFileName]. See [saveBackupToFile] for the default implementation;
/// widget tests override this seam so no real file/share plugin is invoked.
typedef BackupSaver =
    Future<void> Function(String json, String suggestedFileName);

/// Prompts the user to choose a backup file and returns its contents, or `null`
/// if they cancelled. See [pickBackupFile] for the default implementation;
/// widget tests override this seam to return canned JSON.
typedef BackupPicker = Future<String?> Function();

/// Default [BackupSaver]: writes [json] to a temp file (via `path_provider`) and
/// hands it to the OS share/save sheet (via `share_plus`), mirroring the
/// share-a-file pattern used elsewhere in the app.
Future<void> saveBackupToFile(String json, String suggestedFileName) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$suggestedFileName');
  await file.writeAsString(json);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      fileNameOverrides: [suggestedFileName],
      subject: suggestedFileName,
    ),
  );
}

/// Default [BackupPicker]: opens the native open-file dialog (via
/// `file_selector`), restricted to `.json`, and reads the chosen file's text.
/// Returns `null` when the user cancels.
Future<String?> pickBackupFile() async {
  const jsonGroup = XTypeGroup(
    label: 'Backup (JSON)',
    extensions: ['json'],
    uniformTypeIdentifiers: ['public.json'],
    mimeTypes: ['application/json'],
  );
  final file = await openFile(acceptedTypeGroups: const [jsonGroup]);
  if (file == null) return null;
  return file.readAsString();
}
