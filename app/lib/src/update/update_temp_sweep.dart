/// Startup cleanup of update-download directories that earlier runs left in the
/// system temp directory.
///
/// `UpdateController.startAssistedDownload` writes a Windows/Linux installer
/// into a fresh `cc_update_<random>` directory under the temp directory. A
/// failed or cancelled attempt removes its own directory, but two cases leave
/// one behind:
///
/// * **A successful download, on purpose.** The verified installer stays in
///   place after `AssistedDownloadStatus.completed` so the user can still reach
///   it (Linux reveals it for the user to run; Windows runs it from there).
///   Nothing removes it afterwards.
/// * **A discard that could not finish.** If the app exits (or the OS never
///   releases the partial file's handle) before the deferred removal runs, the
///   directory survives; on Windows an open handle blocks deleting it.
///
/// [sweepStaleUpdateTempDirs] removes those once they are old enough that no
/// download or install can still be using them.
library;

import 'dart:io';

import 'update_config.dart';

/// Deletes `cc_update_*` directories directly under [tempDir] whose most recent
/// activity is older than [minAge], and returns how many it removed.
///
/// Best-effort and exception-safe: an unreadable temp directory, an entry that
/// vanishes mid-scan, or a delete that fails (a file still in use on Windows)
/// is skipped, never thrown; whatever could not be removed is retried by the
/// next launch's sweep.
///
/// A directory is removed only when **all** of these hold:
///
/// * it is a real directory (not a symlink, so a link planted in the shared
///   temp directory can never redirect the delete) whose name starts with
///   [kUpdateTempDirPrefix];
/// * its "last activity" is at least [minAge] before [now]. That is the newest
///   modification time of the directory and of its direct entries, because an
///   in-flight download keeps writing to its file while the directory's own
///   time stays at the moment the file was created. A time in the future (clock
///   skew) counts as recent.
///
/// The age guard is what protects a download another running instance of the
/// app is still writing and an installer the user has only just been handed.
/// [now] is injectable for tests.
Future<int> sweepStaleUpdateTempDirs(
  Directory tempDir, {
  DateTime Function()? now,
  Duration minAge = kUpdateTempDirMinAge,
}) async {
  var removed = 0;
  try {
    final cutoff = (now ?? DateTime.now)().subtract(minAge);
    await for (final entry in tempDir.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final name = entry.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
        orElse: () => '',
      );
      if (!name.startsWith(kUpdateTempDirPrefix)) continue;
      try {
        if (await _lastActivity(entry).then((t) => t.isAfter(cutoff))) continue;
        await entry.delete(recursive: true);
        removed++;
      } on Object {
        // diagnostics: silent — best-effort housekeeping; a directory that is
        // in use or already gone is left for the next launch.
      }
    }
  } on Object {
    // diagnostics: silent — the temp directory itself was unreadable.
  }
  return removed;
}

/// The newest modification time of [dir] and its direct entries.
Future<DateTime> _lastActivity(Directory dir) async {
  var newest = (await dir.stat()).modified;
  await for (final child in dir.list(followLinks: false)) {
    final modified = (await child.stat()).modified;
    if (modified.isAfter(newest)) newest = modified;
  }
  return newest;
}
