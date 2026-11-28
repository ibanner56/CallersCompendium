import 'dart:io';
import 'dart:ui' show Rect;

import 'package:compendium_core/compendium_core.dart'
    show csvExtension, csvMimeType;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, visibleForTesting;
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/picker_extensions.dart';

/// Materializes a share-bundle payload as an [XFile] for the OS share sheet.
typedef BundleFileWriter = Future<XFile> Function(String json, String fileName);

/// Resolves the temporary directory used to stage a share file.
typedef ShareTempDirProvider = Future<Directory> Function();

/// Result of a user-confirmed JSON save.
class JsonSaveResult {
  const JsonSaveResult({required this.path, required this.fileName});

  /// The path or platform document identifier returned by the save API.
  final String path;

  /// The name presented to the user for the saved document, when provided by
  /// the platform.
  final String? fileName;
}

/// Opens a native desktop Save As dialog.
typedef JsonSaveLocationPicker =
    Future<FileSaveLocation?> Function({
      String? suggestedName,
      List<XTypeGroup>? acceptedTypeGroups,
      String? initialDirectory,
      bool? canCreateDirectories,
    });

/// Opens a native mobile document save dialog for a staged source file.
typedef JsonMobileSaveFile = Future<String?> Function(String sourceFilePath);

bool Function() isJsonExportDesktopPlatform = () =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Whether the OS share sheet cannot carry files on this platform.
///
/// `share_plus` throws `UnimplementedError` for any [ShareParams.files] on
/// Linux (only text and `mailto:` work), so file shares fall back to the native
/// Save As dialog there. A top-level seam, like [isJsonExportDesktopPlatform],
/// so tests can force either branch regardless of the host.
bool Function() isBundleShareUnsupported = () => Platform.isLinux;

/// The default file-type filter for [saveJsonBundle]. Its label is the format
/// name, not prose, so it is the same in every language and stays a literal
/// (as does [bundleSaveTypeGroup]'s upper-cased extension).
@visibleForTesting
XTypeGroup jsonBundleTypeGroup({bool? isLinux}) => XTypeGroup(
  label: 'JSON',
  extensions: pickerExtensions(['json'], isLinux),
  uniformTypeIdentifiers: ['public.json'],
  mimeTypes: ['application/json'],
);

/// The file-type filter for the Save As fallback in [_saveBundleAs].
@visibleForTesting
XTypeGroup bundleSaveTypeGroup(String extension, {bool? isLinux}) => XTypeGroup(
  label: extension.toUpperCase(),
  extensions: pickerExtensions([extension], isLinux),
  mimeTypes: const ['application/json'],
);

/// The file-type filter for a CSV spreadsheet export (#2332). Like
/// [jsonBundleTypeGroup], its label is the format name and stays a literal.
XTypeGroup csvTypeGroup({bool? isLinux}) => XTypeGroup(
  label: 'CSV',
  extensions: pickerExtensions([csvExtension], isLinux),
  uniformTypeIdentifiers: const ['public.comma-separated-values-text'],
  mimeTypes: const [csvMimeType],
);

/// The folder, in the app's temporary folder, that the export menus and the
/// phone backup stage a file in for the share sheet or a phone's save dialog
/// ([writeBundleFile], `saveBackupToFile`). Named for this app: on Windows the
/// temporary folder is shared by all of one user's programs. Not `share_plus`:
/// on Android that plugin copies a shared file into a folder of that name in
/// the cache, and refuses a file already in it ([clearSharePlusCopies]).
const String kShareStagingFolderName = 'callers-compendium-share-staging';

/// The staging folder: [kShareStagingFolderName] in [temporaryDirectory]
/// (the app's temporary folder by default). It may not exist yet.
Future<Directory> shareStagingDirectory({
  ShareTempDirProvider temporaryDirectory = getTemporaryDirectory,
}) async => Directory(
  p.join((await temporaryDirectory()).path, kShareStagingFolderName),
);

/// Deletes everything in the staging folder [stagingDirectory] gives
/// ([shareStagingDirectory] by default), leaving the folder itself.
///
/// A file handed to the share sheet is not deleted when the sheet returns:
/// on some platforms the receiving app has not read it by then. It is
/// deleted here instead, before the next file is staged and once at start,
/// so a spreadsheet with a caller's pay or a calendar file with a hall's
/// address does not stay in the app's temporary folder. Anything that cannot
/// be deleted is left for the next time; this never throws.
Future<void> clearShareStaging({ShareTempDirProvider? stagingDirectory}) async {
  final Directory dir;
  try {
    dir = await (stagingDirectory ?? shareStagingDirectory)();
  } on Exception {
    // diagnostics: silent — no temporary folder, so nothing staged in it
    return;
  }
  try {
    // A link here is not a folder this app made: listing it would list, and
    // empty, whatever it points to.
    if (await FileSystemEntity.isLink(dir.path)) return;
    if (!await dir.exists()) return;
    await for (final entry in dir.list(followLinks: false)) {
      try {
        await entry.delete(recursive: true);
      } on FileSystemException {
        // diagnostics: silent — left for the next clear
      }
    }
  } on FileSystemException {
    // diagnostics: silent — the folder could not be listed; the next clear tries again
  }
}

/// Deletes the copies `share_plus` keeps on Android of the files last shared:
/// it copies each shared file into a `share_plus` folder in the app's cache
/// ([cacheDirectory]), and empties that folder only when the next share
/// starts. Run only at start ([clearLeftoverSharedFiles]), before any share
/// of this process. Never throws.
Future<void> clearSharePlusCopies({
  ShareTempDirProvider cacheDirectory = getTemporaryDirectory,
}) => clearShareStaging(
  stagingDirectory: () async =>
      Directory(p.join((await cacheDirectory()).path, 'share_plus')),
);

/// Whether [clearLeftoverSharedFiles] has run in this process.
bool _leftoverSharedFilesCleared = false;

/// Lets a test call [clearLeftoverSharedFiles] again as a fresh process would.
@visibleForTesting
void resetLeftoverSharedFilesClearedForTesting() =>
    _leftoverSharedFilesCleared = false;

/// Whether [clearLeftoverSharedFiles] has been called in this process.
@visibleForTesting
bool get leftoverSharedFilesClearedForTesting => _leftoverSharedFilesCleared;

/// Clears what earlier runs left staged for sharing: the staging folder
/// ([clearShareStaging]) and, on Android, `share_plus`'s copies
/// ([clearSharePlusCopies]). Not on Linux, where a file is never staged (it
/// is saved instead, [isBundleShareUnsupported]) and the temporary folder is
/// the system's shared one. Never throws.
///
/// Only the first call in a process does anything. The app calls it as each
/// bootstrap starts, and a Retry or a reset bootstraps again in the same
/// process, possibly while a file shared moments before (a recovery copy
/// shared from the recovery screen before a reset) is still being read by
/// the app it went to.
Future<void> clearLeftoverSharedFiles({
  required TargetPlatform platform,
  ShareTempDirProvider temporaryDirectory = getTemporaryDirectory,
}) async {
  if (_leftoverSharedFilesCleared) return;
  _leftoverSharedFilesCleared = true;
  if (platform == TargetPlatform.linux) return;
  await clearShareStaging(
    stagingDirectory: () =>
        shareStagingDirectory(temporaryDirectory: temporaryDirectory),
  );
  if (platform == TargetPlatform.android) {
    await clearSharePlusCopies(cacheDirectory: temporaryDirectory);
  }
}

/// Writes [json] to a path-safe [fileName] in the staging folder [getDir]
/// gives ([shareStagingDirectory] by default), typed as [mimeType] for the
/// share sheet. The folder is emptied first ([clearShareStaging]): a file
/// staged before has had its share sheet closed by now. So [getDir] must give
/// a folder kept for staging, never the temporary folder itself.
Future<XFile> writeBundleFile(
  String json,
  String fileName, {
  ShareTempDirProvider getDir = shareStagingDirectory,
  String mimeType = 'application/json',
}) async {
  final dir = await getDir();
  await clearShareStaging(stagingDirectory: () async => dir);
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, fileName));
  await file.writeAsString(json);
  return XFile(file.path, mimeType: mimeType);
}

/// Default [BundleFileWriter] used by export menus.
Future<XFile> writeBundleTempFile(String json, String fileName) =>
    writeBundleFile(json, fileName);

/// [BundleFileWriter] for a CSV export: the same staging as
/// [writeBundleTempFile], typed as CSV so the share sheet offers spreadsheet
/// apps.
Future<XFile> writeCsvTempFile(String csv, String fileName) =>
    writeBundleFile(csv, fileName, mimeType: csvMimeType);

/// Saves a JSON export through a user-reachable native file destination.
///
/// Desktop uses [file_selector]'s Save As panel. Android and iOS stage the
/// exact JSON in the staging folder ([writeBundleFile]), hand that file to the
/// platform document-save dialog, filtered to [mobileMimeTypes], and delete
/// it once the dialog returns. A `null` result means the user cancelled.
Future<JsonSaveResult?> saveJsonBundle(
  String json,
  String fileName, {
  bool Function()? isDesktop,
  bool Function()? isMacOS,
  bool Function()? isAndroid,
  JsonSaveLocationPicker? saveLocationPicker,
  JsonMobileSaveFile? mobileSaveFile,
  BundleFileWriter? stageFile,
  List<XTypeGroup>? acceptedTypeGroups,
  List<String> mobileMimeTypes = const ['application/json'],
}) async {
  if ((isDesktop ?? isJsonExportDesktopPlatform)()) {
    final location = await (saveLocationPicker ?? _showSaveLocation)(
      suggestedName: fileName,
      acceptedTypeGroups: acceptedTypeGroups ?? [jsonBundleTypeGroup()],
    );
    if (location == null) return null;
    final destination = (isMacOS ?? (() => Platform.isMacOS))()
        ? location.path
        : await _collisionSafePath(location.path);
    await File(destination).writeAsString(json, flush: true);
    return JsonSaveResult(path: destination, fileName: p.basename(destination));
  }

  final staged = await (stageFile ?? writeBundleTempFile)(json, fileName);
  try {
    final savedPath =
        await (mobileSaveFile ??
            (path) => _saveMobileFile(path, mobileMimeTypes))(staged.path);
    if (savedPath == null) return null;
    return JsonSaveResult(
      path: savedPath,
      fileName: (isAndroid ?? (() => Platform.isAndroid))()
          ? null
          : _fileNameFromSavePath(savedPath, fileName),
    );
  } finally {
    final stagedFile = File(staged.path);
    if (await stagedFile.exists()) {
      await stagedFile.delete();
    }
  }
}

/// How [shareOrSaveBundleFile] delivered a bundle.
class BundleDeliveryResult {
  const BundleDeliveryResult.shared() : saved = null;
  const BundleDeliveryResult.saved(JsonSaveResult this.saved);

  /// The save result, or `null` when the bundle went to the share sheet.
  final JsonSaveResult? saved;

  bool get wasSaved => saved != null;
}

/// Delivers a bundle file: the OS share sheet where it can carry files, the
/// native Save As dialog where it cannot ([isBundleShareUnsupported]).
///
/// Returns `null` when the user cancelled the Save As dialog. Failures are
/// not caught here; callers wrap this in `guardExport` so they are logged.
/// Every seam defaults to the production behaviour.
Future<BundleDeliveryResult?> shareOrSaveBundleFile({
  required String json,
  required String fileName,
  required String subject,
  required Rect? origin,
  Future<void> Function(ShareParams params)? shareInvoker,
  BundleFileWriter? bundleFileWriter,
  Future<JsonSaveResult?> Function(String json, String fileName)? saveInvoker,
}) async {
  if (isBundleShareUnsupported()) {
    final result = await (saveInvoker ?? _saveBundleAs)(json, fileName);
    if (result == null) return null;
    return BundleDeliveryResult.saved(result);
  }
  final xfile = await (bundleFileWriter ?? writeBundleTempFile)(json, fileName);
  await (shareInvoker ?? SharePlus.instance.share)(
    ShareParams(
      files: [xfile],
      fileNameOverrides: [fileName],
      subject: subject,
      sharePositionOrigin: origin,
    ),
  );
  return const BundleDeliveryResult.shared();
}

Future<JsonSaveResult?> _saveBundleAs(String json, String fileName) {
  final extension = p.extension(fileName).replaceFirst('.', '');
  return saveJsonBundle(
    json,
    fileName,
    acceptedTypeGroups: [bundleSaveTypeGroup(extension)],
  );
}

Future<FileSaveLocation?> _showSaveLocation({
  String? suggestedName,
  List<XTypeGroup>? acceptedTypeGroups,
  String? initialDirectory,
  bool? canCreateDirectories,
}) => getSaveLocation(
  suggestedName: suggestedName,
  acceptedTypeGroups: acceptedTypeGroups ?? const [],
  initialDirectory: initialDirectory,
  canCreateDirectories: canCreateDirectories,
);

Future<String?> _saveMobileFile(
  String sourceFilePath,
  List<String> mimeTypes,
) => FlutterFileDialog.saveFile(
  params: SaveFileDialogParams(
    sourceFilePath: sourceFilePath,
    mimeTypesFilter: mimeTypes,
  ),
);

String _fileNameFromSavePath(String savedPath, String fallback) {
  final uriPath = Uri.tryParse(savedPath)?.path;
  final fileName = p.basename(
    uriPath == null || uriPath.isEmpty ? savedPath : uriPath,
  );
  return fileName.isEmpty ? fallback : fileName;
}

Future<String> _collisionSafePath(String path) async {
  if (!await File(path).exists()) return path;

  final directory = p.dirname(path);
  final extension = p.extension(path);
  final stem = p.basenameWithoutExtension(path);
  for (var suffix = 1; ; suffix++) {
    final candidate = p.join(directory, '$stem ($suffix)$extension');
    if (!await File(candidate).exists()) return candidate;
  }
}
