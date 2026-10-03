import 'dart:io';
import 'dart:ui' show Rect;

import 'package:file_selector/file_selector.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

const _jsonTypeGroup = XTypeGroup(
  label: 'JSON',
  extensions: ['json'],
  uniformTypeIdentifiers: ['public.json'],
  mimeTypes: ['application/json'],
);

/// Writes [json] to a path-safe [fileName] in the temporary directory.
Future<XFile> writeBundleFile(
  String json,
  String fileName, {
  ShareTempDirProvider getDir = getTemporaryDirectory,
}) async {
  final dir = await getDir();
  await dir.create(recursive: true);
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(json);
  return XFile(file.path, mimeType: 'application/json');
}

/// Default [BundleFileWriter] used by export menus.
Future<XFile> writeBundleTempFile(String json, String fileName) =>
    writeBundleFile(json, fileName);

/// Saves a JSON export through a user-reachable native file destination.
///
/// Desktop uses [file_selector]'s Save As panel. Android and iOS stage the
/// exact JSON in a temporary file, then hand that file to the platform
/// document-save dialog. A `null` result means the user cancelled.
Future<JsonSaveResult?> saveJsonBundle(
  String json,
  String fileName, {
  bool Function()? isDesktop,
  bool Function()? isMacOS,
  bool Function()? isAndroid,
  JsonSaveLocationPicker? saveLocationPicker,
  JsonMobileSaveFile? mobileSaveFile,
  BundleFileWriter? stageFile,
  List<XTypeGroup> acceptedTypeGroups = const [_jsonTypeGroup],
}) async {
  if ((isDesktop ?? isJsonExportDesktopPlatform)()) {
    final location = await (saveLocationPicker ?? _showSaveLocation)(
      suggestedName: fileName,
      acceptedTypeGroups: acceptedTypeGroups,
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
    final savedPath = await (mobileSaveFile ?? _saveMobileFile)(staged.path);
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
    acceptedTypeGroups: [
      XTypeGroup(
        label: extension.toUpperCase(),
        extensions: [extension],
        mimeTypes: const ['application/json'],
      ),
    ],
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

Future<String?> _saveMobileFile(String sourceFilePath) =>
    FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        sourceFilePath: sourceFilePath,
        mimeTypesFilter: const ['application/json'],
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
