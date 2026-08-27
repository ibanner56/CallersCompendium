import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Materializes a share-bundle payload as an [XFile] for the OS share sheet.
typedef BundleFileWriter = Future<XFile> Function(String json, String fileName);

/// Resolves the temporary directory used to stage a share file.
typedef ShareTempDirProvider = Future<Directory> Function();

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
