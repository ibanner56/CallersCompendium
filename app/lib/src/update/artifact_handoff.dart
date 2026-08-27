/// The desktop OS-handoff seam for the assisted-download flow (ADR-002
/// "Stage 1.5"): given a **verified** local artifact, hand it to the operating
/// system so the *user* completes the install. It deliberately never replaces
/// the running binary in place — that is Stage 2 (Sparkle/WinSparkle), gated on
/// code-signing.
///
/// **Launch is gated on verification** (issue #431): the controller only calls
/// this after the manifest signature *and* the artifact sha256 have passed, and
/// the per-platform behavior distinguishes launch from reveal:
///
/// - **macOS** (signed + notarized): `open` the `.dmg`/`.zip` so it auto-mounts
///   / expands — [HandoffResult.launched].
/// - **Windows**: start the verified installer that the user explicitly
///   requested with "Download & install" — [HandoffResult.launched].
/// - **Linux** (OS-unsigned): **reveal** the verified installer in the file
///   manager and let the *user* run it. Linux `xdg-open`s the containing folder;
///   no `chmod +x` or direct `.AppImage` execution — [HandoffResult.revealed].
/// - **Android/iOS**: no handoff — [HandoffResult.failed].
///
/// The default implementation shells out via `dart:io` `Process` behind an
/// injectable [ProcessRunner] seam, so tests assert the exact command invoked
/// (and that each platform invokes only its documented command) without
/// launching anything real.
library;

import 'dart:io';

import 'update_manifest.dart';

/// The outcome of an OS-handoff attempt (issue #431). Distinguishes an
/// auto-launch from a reveal-only so the UI can instruct the user accurately.
enum HandoffResult {
  /// The artifact was opened/launched for the user (macOS `open`, Windows `.exe`).
  launched,

  /// The artifact was revealed in the file manager for the user to run
  /// manually (Linux — never auto-executed).
  revealed,

  /// No handoff happened: an unsupported platform (mobile) or the reveal/launch
  /// command could not be started.
  failed,
}

/// The injectable handoff seam. The [UpdateController] depends on this typedef
/// (default [handoffArtifactToOs]).
typedef ArtifactHandoff =
    Future<HandoffResult> Function(File file, UpdatePlatform platform);

/// An injectable process-launch seam so [handoffArtifactToOs] is unit-testable
/// without touching the real OS. [runToCompletion] mirrors `Process.run` (used
/// for the macOS `open`, whose exit code we check); [startDetached] mirrors
/// `Process.start(mode: detached)` (used to reveal a folder/file without
/// blocking). Both return whether the command was *initiated* successfully.
class ProcessRunner {
  const ProcessRunner();

  /// Runs [executable] with [arguments] to completion; returns `true` on a
  /// zero exit code. Any [ProcessException]/error (e.g. a missing executable)
  /// is caught and reported as `false` so callers get the documented
  /// fail-closed contract even outside a surrounding try/catch.
  Future<bool> runToCompletion(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await Process.run(executable, arguments);
      return result.exitCode == 0;
    } on Object {
      // diagnostics: silent — fail-closed per this method's documented
      // contract (see doc comment above); the boolean return already conveys
      // failure to the caller.
      return false;
    }
  }

  /// Starts [executable] with [arguments] detached (fire-and-forget); returns
  /// `true` only once the process has actually started. Any
  /// [ProcessException]/error is caught and reported as `false`.
  Future<bool> startDetached(String executable, List<String> arguments) async {
    try {
      await Process.start(
        executable,
        arguments,
        mode: ProcessStartMode.detached,
      );
      return true;
    } on Object {
      // diagnostics: silent — fail-closed per this method's documented
      // contract (see doc comment above); the boolean return already conveys
      // failure to the caller.
      return false;
    }
  }
}

/// Default [ArtifactHandoff]: opens (macOS), starts (Windows), or reveals (Linux) the
/// verified [file] per-platform so the user finishes installing. See the
/// library doc for the exact per-platform behavior. [runner] is injectable for
/// tests; production uses the real [ProcessRunner].
///
/// Never throws — any thrown [ProcessException] (e.g. a missing `xdg-open`) is
/// caught and reported as [HandoffResult.failed] so the caller can fall back to
/// the release-page link.
Future<HandoffResult> handoffArtifactToOs(
  File file,
  UpdatePlatform platform, {
  ProcessRunner runner = const ProcessRunner(),
}) async {
  try {
    switch (platform) {
      case UpdatePlatform.macos:
        // macOS ships signed + notarized, so auto-open is safe: the .dmg mounts
        // / the .zip expands and the user drags the app to Applications.
        final ok = await runner.runToCompletion('open', [file.path]);
        return ok ? HandoffResult.launched : HandoffResult.failed;
      case UpdatePlatform.windows:
        // Starting the installer is authorized by the user's explicit
        // "Download & install" action. The installer itself coordinates closing
        // any running instance before replacing the installed files.
        final ok = await runner.startDetached(file.path, const []);
        return ok ? HandoffResult.launched : HandoffResult.failed;
      case UpdatePlatform.linux:
        // OS-unsigned: never mark executable and never launch. Reveal the
        // containing folder so the user runs the installer themselves.
        final ok = await runner.startDetached('xdg-open', [file.parent.path]);
        return ok ? HandoffResult.revealed : HandoffResult.failed;
      case UpdatePlatform.android:
      case UpdatePlatform.ios:
        return HandoffResult.failed;
    }
  } on ProcessException {
    // diagnostics: silent — fail-closed; `HandoffResult.failed` already
    // conveys failure to the caller.
    return HandoffResult.failed;
  } on Object {
    // diagnostics: silent — fail-closed; `HandoffResult.failed` already
    // conveys failure to the caller.
    return HandoffResult.failed;
  }
}
