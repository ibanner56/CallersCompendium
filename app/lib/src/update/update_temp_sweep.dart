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
/// download or install can still be using them, and never removes a directory
/// that holds the executable that is running (on Linux the downloaded
/// AppImage is the app, and users keep running it from where it landed).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'update_config.dart';

/// What Dart's `Directory.createTemp` appends to a prefix: a run of ASCII
/// letters and digits, or on Windows, when its first pick is taken, a hyphenated
/// identifier. Hyphens are allowed so either way is swept; anything else after
/// [kUpdateTempDirPrefix] (a dot, a space, a path separator) is not ours to
/// delete.
final RegExp _updateDirName = RegExp('^$kUpdateTempDirPrefix[A-Za-z0-9-]+\$');

/// The files this process is running from, for [sweepStaleUpdateTempDirs]'s
/// `inUsePaths`: the AppImage that launched it (`APPIMAGE`, set by the
/// AppImage runtime, whose mount point is what [Platform.resolvedExecutable]
/// then names) and the executable itself. [environment] and
/// [resolvedExecutable] are injectable for tests.
List<String> runningExecutablePaths({
  Map<String, String>? environment,
  String? resolvedExecutable,
}) {
  final appImage = (environment ?? Platform.environment)['APPIMAGE'];
  final executable = resolvedExecutable ?? Platform.resolvedExecutable;
  return [
    if (appImage != null && appImage.isNotEmpty) appImage,
    if (executable.isNotEmpty) executable,
  ];
}

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
///   temp directory can never redirect the delete) whose name is
///   [kUpdateTempDirPrefix] followed by letters, digits and hyphens only, which is
///   what `Directory.createTemp` generates;
/// * it does not contain any of [inUsePaths] (the running executable: pass
///   [runningExecutablePaths]). Paths are compared after resolving symbolic
///   links, by whole path segments, so `cc_update_ab` never protects or
///   matches `cc_update_abc`, and a symlink to the file counts as the file;
/// * its "last activity" is at least [minAge] before [now]. That is the newest
///   modification time of the directory and of its direct entries, because an
///   in-flight download keeps writing to its file while the directory's own
///   time stays at the moment the file was created. A time in the future (clock
///   skew) counts as recent.
///
/// The age guard is what protects a download another running instance of the
/// app is still writing and an installer the user has only just been handed;
/// the [inUsePaths] guard is what protects an installer the user has been
/// running for longer than that. [now] is injectable for tests.
Future<int> sweepStaleUpdateTempDirs(
  Directory tempDir, {
  required Iterable<String> inUsePaths,
  DateTime Function()? now,
  Duration minAge = kUpdateTempDirMinAge,
}) async {
  var removed = 0;
  try {
    final cutoff = (now ?? DateTime.now)().subtract(minAge);
    final inUse = <String>[];
    for (final path in inUsePaths) {
      inUse.addAll(await _pathForms(path, () => File(path)));
    }
    await for (final entry in tempDir.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final name = entry.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
        orElse: () => '',
      );
      if (!_updateDirName.hasMatch(name)) continue;
      try {
        final dirForms = await _pathForms(entry.path, () => entry);
        if (inUse.any(
          (used) => dirForms.any(
            (dir) => p.equals(dir, used) || p.isWithin(dir, used),
          ),
        )) {
          continue;
        }
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

/// [path] as given (made absolute) and with symbolic links resolved. Both are
/// compared so a path is recognised however the caller and the filesystem
/// spell it (`/var` versus `/private/var`, an AppImage reached through a
/// link). A path that no longer exists is compared as given.
Future<List<String>> _pathForms(
  String path,
  FileSystemEntity Function() entity,
) async {
  final forms = <String>[p.normalize(p.absolute(path))];
  try {
    forms.add(p.normalize(await entity().resolveSymbolicLinks()));
  } on Object {
    // diagnostics: silent — the path is gone or unreadable; its given spelling
    // is all there is to compare.
  }
  return forms;
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
