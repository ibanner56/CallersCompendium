/// The desktop OS-handoff seam for the assisted-download flow (ADR-002
/// "Stage 1.5"): given a **verified** local artifact, hand it to the operating
/// system so the *user* completes the install. It deliberately never replaces
/// the running binary in place — that is Stage 2 (Sparkle/WinSparkle), gated on
/// code-signing.
///
/// The default implementation shells out via `dart:io` `Process` (no new
/// dependency) and is the one place the flow touches the real OS, so it is kept
/// behind an injectable typedef: tests substitute a fake that records the
/// `(file, platform)` call without launching anything. Mobile platforms return
/// `false` — they never hand off; A11a's "open release page" link is their only
/// path.
library;

import 'dart:io';

import 'update_manifest.dart';

/// The injectable handoff seam. The [UpdateController] depends on this typedef
/// (default [handoffArtifactToOs]).
typedef ArtifactHandoff =
    Future<bool> Function(File file, UpdatePlatform platform);

/// Default [ArtifactHandoff]: opens/reveals the verified [file] per-platform so
/// the user finishes installing.
///
/// - **macOS** (`.dmg`/`.zip`): `open` the file (mounts the disk image / expands
///   the archive so the user can drag the app to Applications).
/// - **Windows**: launch an `.exe` installer directly (detached); otherwise
///   reveal the file in Explorer.
/// - **Linux**: mark an `.AppImage` executable, then reveal the containing
///   folder via `xdg-open` (a `.tar.gz` is just revealed).
/// - **Android/iOS**: no handoff — returns `false`.
///
/// Returns whether the handoff was initiated; any thrown [ProcessException]
/// (e.g. a missing `xdg-open`) is caught and reported as `false` so the caller
/// can fall back to the release-page link.
Future<bool> handoffArtifactToOs(File file, UpdatePlatform platform) async {
  try {
    switch (platform) {
      case UpdatePlatform.macos:
        final result = await Process.run('open', [file.path]);
        return result.exitCode == 0;
      case UpdatePlatform.windows:
        if (file.path.toLowerCase().endsWith('.exe')) {
          await Process.start(
            file.path,
            const [],
            mode: ProcessStartMode.detached,
          );
          return true;
        }
        await Process.start('explorer.exe', [
          '/select,${file.path}',
        ], mode: ProcessStartMode.detached);
        return true;
      case UpdatePlatform.linux:
        if (file.path.toLowerCase().endsWith('.appimage')) {
          await Process.run('chmod', ['+x', file.path]);
        }
        await Process.start('xdg-open', [
          file.parent.path,
        ], mode: ProcessStartMode.detached);
        return true;
      case UpdatePlatform.android:
      case UpdatePlatform.ios:
        return false;
    }
  } on ProcessException {
    return false;
  } on Object {
    return false;
  }
}
