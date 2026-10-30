import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'archive_intake_service.dart' show kMaxIncomingArchiveBytes;

/// The extension Windows and Linux register for the app (PLAT-3). The only
/// files a desktop "open with" request may name.
const String kDesktopShareFileExtension = '.ccshare';

/// Why a desktop open request was refused before anything read the file.
enum DesktopOpenRejection {
  /// Empty, or holds a control character (no real share file is named so,
  /// and a newline would split the loopback request line), or, on Windows, a
  /// `:` after the drive letter, which names an alternate data stream.
  malformed,

  /// Not an absolute path. The two launches have different working
  /// directories, so a relative path could name the wrong file. On Windows
  /// only a drive-absolute path (`C:\...`) counts: a root-relative `\x`
  /// resolves against whichever drive is current.
  notAbsolute,

  /// A path that starts with two separators in any mix (`\\server\share`,
  /// `/\server`, `\\?\`, `\\.\`) or with the NT prefix `\??\`. On Windows
  /// these reach a named host or a device, and a loopback peer must not be
  /// able to make the app contact a host: the stat alone would send the
  /// user's credentials to it.
  remote,

  /// The name does not end in [kDesktopShareFileExtension].
  wrongExtension,

  /// Missing, or not a regular file: a symlink (not followed), a directory, a
  /// named pipe, a socket or a device.
  notRegularFile,

  /// A reserved Windows device name such as `COM1.ccshare` or `nul.ccshare`,
  /// which Windows 10 and earlier open as the device.
  deviceName,

  /// Larger than [kMaxIncomingArchiveBytes].
  tooLarge,
}

/// The outcome of [checkDesktopOpenPath]: either the [path] to hand to intake,
/// or the [rejection].
class DesktopOpenCheck {
  const DesktopOpenCheck.accepted(String this.path) : rejection = null;
  const DesktopOpenCheck.rejected(DesktopOpenRejection this.rejection)
    : path = null;

  final String? path;
  final DesktopOpenRejection? rejection;
}

/// Checks a path that reached the app from a desktop launch: the command line
/// of this launch, or an `open` request on the single-instance loopback
/// channel.
///
/// The loopback channel is unauthenticated, so any local process can send a
/// path. A path that passes here only ever reaches import review, which reads
/// and validates the content itself and commits nothing until the user
/// confirms. The checks keep the request from naming anything but a local,
/// regular, size-capped `.ccshare` file:
///
/// - no control characters, and an absolute path (on Windows, drive-absolute
///   with no alternate data stream);
/// - no UNC, device or NT-namespace path (two leading separators, or `\??\`);
/// - on Windows, no reserved device name (`CON`, `NUL`, `COM1`, ...);
/// - the [kDesktopShareFileExtension] extension, compared case-insensitively;
/// - the last path component is a regular file, checked without following a
///   symlink or junction there (on Windows, another reparse point, such as a
///   OneDrive file, is followed);
/// - at most [maxBytes].
///
/// [context] decides the path rules (the platform's by default), so the
/// Windows rules can be tested on any host. The file-system checks go through
/// [probe], which is the real file system unless a test substitutes it.
///
/// The read happens later, by path, so a file swapped between this check and
/// that read is not caught here. Intake's read stops at the cap whatever the
/// file reports as its length (`ArchiveIntakeService`), it validates the bytes,
/// and review still needs the user's confirmation. Only the last component is
/// checked for a symlink: a symlinked parent directory is followed.
Future<DesktopOpenCheck> checkDesktopOpenPath(
  String raw, {
  int maxBytes = kMaxIncomingArchiveBytes,
  p.Context? context,
  @visibleForTesting DesktopFileProbe? probe,
}) async {
  final path = context ?? p.context;
  final windows = path.style == p.Style.windows;
  if (raw.isEmpty || raw.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
    return const DesktopOpenCheck.rejected(DesktopOpenRejection.malformed);
  }
  if (_twoLeadingSeparators.hasMatch(raw) || raw.startsWith(r'\??\')) {
    return const DesktopOpenCheck.rejected(DesktopOpenRejection.remote);
  }
  if (windows) {
    if (!_windowsDriveAbsolute.hasMatch(raw)) {
      return const DesktopOpenCheck.rejected(DesktopOpenRejection.notAbsolute);
    }
    if (raw.indexOf(':', 2) >= 0) {
      return const DesktopOpenCheck.rejected(DesktopOpenRejection.malformed);
    }
  } else if (!path.isAbsolute(raw)) {
    return const DesktopOpenCheck.rejected(DesktopOpenRejection.notAbsolute);
  }
  if (path.extension(raw).toLowerCase() != kDesktopShareFileExtension) {
    return const DesktopOpenCheck.rejected(DesktopOpenRejection.wrongExtension);
  }
  if (windows && _isReservedWindowsName(path.basename(raw))) {
    return const DesktopOpenCheck.rejected(DesktopOpenRejection.deviceName);
  }
  final fs = probe ?? const DesktopFileProbe();
  try {
    var type = await fs.type(raw, followLinks: false);
    // Windows reports every reparse point as a link when not following, and
    // OneDrive keeps a cloud reparse point on files it has downloaded. Only a
    // symlink or junction is a link here; any other reparse point is judged
    // by what it resolves to.
    if (windows &&
        type == FileSystemEntityType.link &&
        !await fs.isSymlinkOrJunction(raw)) {
      type = await fs.type(raw, followLinks: true);
    }
    if (type != FileSystemEntityType.file) {
      return const DesktopOpenCheck.rejected(
        DesktopOpenRejection.notRegularFile,
      );
    }
    if (await fs.length(raw) > maxBytes) {
      return const DesktopOpenCheck.rejected(DesktopOpenRejection.tooLarge);
    }
  } on FileSystemException {
    // diagnostics: silent — a file that cannot be stat'ed is refused like a missing one
    return const DesktopOpenCheck.rejected(DesktopOpenRejection.notRegularFile);
  }
  return DesktopOpenCheck.accepted(raw);
}

/// The file-system calls [checkDesktopOpenPath] makes, so a test can stand in
/// for Windows behaviour on any host.
class DesktopFileProbe {
  const DesktopFileProbe();

  Future<FileSystemEntityType> type(String path, {required bool followLinks}) =>
      FileSystemEntity.type(path, followLinks: followLinks);

  /// Whether [path] is a symlink or a junction. `Link.target` reads the link
  /// without following it, and on Windows it fails for any other reparse
  /// point (such as a OneDrive file).
  Future<bool> isSymlinkOrJunction(String path) async {
    try {
      await Link(path).target();
      return true;
    } on FileSystemException {
      // diagnostics: silent — not a symlink or junction; the caller follows it instead
      return false;
    }
  }

  Future<int> length(String path) => File(path).length();
}

final RegExp _twoLeadingSeparators = RegExp(r'^[\\/]{2}');
final RegExp _windowsDriveAbsolute = RegExp(r'^[A-Za-z]:[\\/]');

/// Device names Windows (10 and earlier) maps a file name to whatever its
/// extension: the part before the first dot, ignoring case and trailing
/// spaces and dots. Includes the superscript-digit ports Microsoft's naming
/// rules also reserve.
const Set<String> _reservedWindowsNames = {
  'CON', 'PRN', 'AUX', 'NUL', 'CONIN\$', 'CONOUT\$', //
  'COM0', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8',
  'COM9', 'LPT0', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7',
  'LPT8', 'LPT9', 'COM¹', 'COM²', 'COM³', 'LPT¹', 'LPT²', //
  'LPT³',
};

bool _isReservedWindowsName(String basename) {
  final stem = basename.split('.').first.replaceFirst(RegExp(r'[ .]+$'), '');
  return _reservedWindowsNames.contains(stem.toUpperCase());
}

/// The share file this launch was asked to open, from its command-line
/// [args], made absolute against this process's working directory. `null`
/// when no argument names a [kDesktopShareFileExtension] file, or off Windows
/// and Linux (macOS delivers files through its app delegate instead).
///
/// The `.desktop` launcher passes the file as `%f` and the Windows
/// association as `"%1"`, so the path is one argument. The result is not
/// checked: [checkDesktopOpenPath] does that wherever it ends up.
String? desktopOpenPathFromArgs(List<String> args, {bool? platformOpensArgs}) {
  final opens = platformOpensArgs ?? (Platform.isWindows || Platform.isLinux);
  if (!opens) return null;
  for (final arg in args) {
    if (arg.toLowerCase().endsWith(kDesktopShareFileExtension)) {
      return p.normalize(p.absolute(arg));
    }
  }
  return null;
}
