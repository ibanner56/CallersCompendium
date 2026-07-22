import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Delivers the exported diagnostics [contents] to the user as a file named
/// [suggestedFileName]. Returns `true` if it was saved/shared, or `false` if
/// the user cancelled the dialog. Genuine I/O/plugin failures should throw.
/// Mirrors [BackupSaver] in `backup_io.dart`; widget tests override this seam
/// so no real file/share plugin is invoked.
typedef LogSaver =
    Future<bool> Function(String contents, String suggestedFileName);

/// Test seam for platform detection; defaults to the real `dart:io` getters.
bool Function() isDesktopPlatformForLog = () =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

const _logTypeGroup = XTypeGroup(
  label: 'Diagnostics log',
  extensions: ['log', 'txt'],
  uniformTypeIdentifiers: ['public.plain-text'],
  mimeTypes: ['text/plain'],
);

/// A timestamped suggested file name for an exported diagnostics log, e.g.
/// `caller-compendium-diagnostics-20260722-075345.log`.
String diagnosticsLogFileName([DateTime? now]) {
  final ts = (now ?? DateTime.now()).toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${ts.year}${two(ts.month)}${two(ts.day)}-'
      '${two(ts.hour)}${two(ts.minute)}${two(ts.second)}';
  return 'caller-compendium-diagnostics-$stamp.log';
}

/// Default [LogSaver].
///
/// On desktop this is a "save a file" action (native Save As via
/// `file_selector`); on mobile it is a "share to another app" action (temp file
/// + OS share sheet via `share_plus`). Mirrors `saveBackupToFile`, including the
/// defensive `create(recursive: true)` before the mobile temp-file write.
Future<bool> saveDiagnosticsLog(
  String contents,
  String suggestedFileName,
) async {
  if (isDesktopPlatformForLog()) {
    final location = await getSaveLocation(
      suggestedName: suggestedFileName,
      acceptedTypeGroups: const [_logTypeGroup],
    );
    if (location == null) return false;
    await File(location.path).writeAsString(contents);
    return true;
  }

  final dir = await getTemporaryDirectory();
  await dir.create(recursive: true);
  final file = File('${dir.path}/$suggestedFileName');
  await file.writeAsString(contents);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/plain')],
      fileNameOverrides: [suggestedFileName],
      subject: suggestedFileName,
    ),
  );
  return true;
}
