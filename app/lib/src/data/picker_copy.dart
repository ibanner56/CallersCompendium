/// The copies a system file picker makes of a chosen file, and deleting them
/// once the file has been read.
///
/// On iPhone and iPad the document picker copies the chosen file into a
/// `<bundle id>-Inbox` folder in the app's tmp folder; on Android the file
/// selector copies it into a UUID-named folder in the app's cache. Either copy
/// would otherwise stay until the system clears the folder, and for a picked
/// backup that is the whole library. Elsewhere the picker hands back the
/// user's own file, which is never deleted.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dance_code_scanner.dart' show deleteAndroidPickerCopy;

/// Reads [file], a file a system picker handed over, with [read], then
/// deletes the picker's copy of it ([deletePickerCopy]), whether the read
/// succeeded or not. [platform] and [temporaryDirectory] are for tests.
Future<T> readPickedFile<T>(
  XFile file,
  Future<T> Function(XFile file) read, {
  TargetPlatform? platform,
  Future<Directory> Function()? temporaryDirectory,
}) async {
  try {
    return await read(file);
  } finally {
    await deletePickerCopy(
      file.path,
      platform: platform,
      temporaryDirectory: temporaryDirectory,
    );
  }
}

/// Deletes [path] when it is the system picker's copy of a chosen file on
/// [platform] (the current one by default): on iOS
/// [deleteIosDocumentPickerCopy], looking in [temporaryDirectory] (the app's
/// tmp folder by default); on Android [deleteAndroidPickerCopy], looking in
/// [temporaryDirectory] (the app's cache folder by default). On any other
/// platform, and for any other path, nothing is deleted. Never throws.
Future<void> deletePickerCopy(
  String path, {
  TargetPlatform? platform,
  Future<Directory> Function()? temporaryDirectory,
}) async {
  try {
    switch (platform ?? defaultTargetPlatform) {
      case TargetPlatform.iOS:
        await deleteIosDocumentPickerCopy(
          path,
          // NSTemporaryDirectory, not the caches folder path_provider calls
          // temporary on iOS: the document picker's copies are in tmp.
          temporaryDirectory: temporaryDirectory == null
              ? Directory.systemTemp
              : await temporaryDirectory(),
        );
      case TargetPlatform.android:
        await deleteAndroidPickerCopy(
          path,
          cacheDirectory: await (temporaryDirectory ?? getTemporaryDirectory)(),
        );
      case TargetPlatform.macOS ||
          TargetPlatform.windows ||
          TargetPlatform.linux ||
          TargetPlatform.fuchsia:
        break;
    }
  } on Exception {
    // diagnostics: silent — no temporary folder to look in, so no copy to delete
  }
}

/// Deletes [path] when it is the iOS document picker's copy of a chosen file:
/// a file in a folder whose name ends in `-Inbox`, directly in
/// [temporaryDirectory] (the app's tmp folder), links resolved on both
/// sides. The folder is left; any other path is left alone.
Future<void> deleteIosDocumentPickerCopy(
  String path, {
  required Directory temporaryDirectory,
}) async {
  if (path.isEmpty) return;
  final String temp;
  final String canonical;
  try {
    temp = await temporaryDirectory.resolveSymbolicLinks();
    canonical = await File(path).resolveSymbolicLinks();
  } on FileSystemException {
    // diagnostics: silent — the copy or the tmp folder is gone, so there is nothing to delete
    return;
  }
  final folder = p.dirname(canonical);
  if (p.dirname(folder) != temp || !p.basename(folder).endsWith('-Inbox')) {
    return;
  }
  try {
    await File(canonical).delete();
  } on FileSystemException {
    // diagnostics: silent — the copy is already gone
  }
}
