import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Materializes a share-bundle payload as an [XFile] for the OS share sheet.
typedef BundleFileWriter = Future<XFile> Function(String json, String fileName);

/// Resolves the temporary directory used to stage a share file.
typedef ShareTempDirProvider = Future<Directory> Function();

/// Result of a user-confirmed JSON save.
class JsonSaveResult {
  const JsonSaveResult({required this.path, required this.fileName});

  /// The path or platform document identifier returned by the save API.
  final String path;

  /// The name presented to the user for the saved document.
  final String fileName;
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
  JsonSaveLocationPicker? saveLocationPicker,
  JsonMobileSaveFile? mobileSaveFile,
  BundleFileWriter? stageFile,
}) async {
  if ((isDesktop ?? isJsonExportDesktopPlatform)()) {
    final location = await (saveLocationPicker ?? _showSaveLocation)(
      suggestedName: fileName,
      acceptedTypeGroups: const [_jsonTypeGroup],
    );
    if (location == null) return null;
    final destination = await _collisionSafePath(location.path);
    await File(destination).writeAsString(json, flush: true);
    return JsonSaveResult(path: destination, fileName: p.basename(destination));
  }

  final staged = await (stageFile ?? writeBundleTempFile)(json, fileName);
  try {
    final savedPath = await (mobileSaveFile ?? _saveMobileFile)(staged.path);
    if (savedPath == null) return null;
    return JsonSaveResult(path: savedPath, fileName: fileName);
  } finally {
    final stagedFile = File(staged.path);
    if (await stagedFile.exists()) {
      await stagedFile.delete();
    }
  }
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
