import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// File name of the desktop single-instance lock, kept inside the app's private
/// application-support directory (never a world-writable/predictable temp path).
const String kSingleInstanceLockFileName = 'single_instance.lock';

/// Resolves the directory the single-instance lock lives in. Injectable so
/// tests can point the guard at a temp directory instead of the real
/// app-support location (which needs the `path_provider` platform channel,
/// unavailable under `flutter test`).
typedef LockDirectoryProvider = Future<Directory> Function();

/// A held OS lock. Releasing it — or the process exiting — frees the guard so a
/// later launch can acquire it. Production never needs to release explicitly
/// (the OS releases the advisory lock at process exit, including a crash); the
/// seam exists for tests and tidy shutdown.
abstract class InstanceLockHandle {
  /// Releases the underlying OS lock and closes the file handle. Idempotent.
  Future<void> release();
}

/// The OS lock primitive the guard builds on, abstracted so the guard's
/// decision logic is unit-testable with a fake.
///
/// This abstraction matters because a *real* advisory lock cannot be contended
/// within a single process on POSIX — `fcntl` locks are per-process, so a
/// second acquire in the same test process always succeeds. A fake primitive
/// therefore stands in for "another live process already holds it" so the
/// refused/second-instance path can be tested headlessly, with no real second
/// process or display.
abstract class InstanceLockPrimitive {
  /// Attempts to take an exclusive, non-blocking lock on [lockFile].
  ///
  /// Returns a handle when the lock is acquired, or `null` when it is already
  /// held by another live process. Throws (a [FileSystemException]) only on an
  /// unexpected IO fault — e.g. the directory can't be created or the file
  /// can't be opened — which the guard treats as fail-open.
  Future<InstanceLockHandle?> tryAcquire(File lockFile);
}

/// Real [InstanceLockPrimitive] backed by `dart:io` OS advisory file locks
/// (`RandomAccessFile.lock`): `fcntl`/`flock` on POSIX, `LockFileEx` on Windows.
///
/// These locks are released automatically when the holding process dies, so a
/// crashed prior instance leaves no *live* lock — the leftover lock file is
/// inert and a fresh launch acquires normally. There is no PID-liveness check
/// or stale-marker cleanup to get wrong.
class AdvisoryFileLock implements InstanceLockPrimitive {
  const AdvisoryFileLock();

  @override
  Future<InstanceLockHandle?> tryAcquire(File lockFile) async {
    // A create/open failure here (bad path, permissions) propagates to the
    // caller, which fails open — distinct from "lock held by another process",
    // handled below.
    await lockFile.parent.create(recursive: true);
    final raf = await lockFile.open(mode: FileMode.write);
    try {
      // Non-blocking exclusive lock: throws instead of waiting when another
      // live process already holds it. On the app's private support directory
      // (always a local filesystem) this is the "second instance" signal.
      await raf.lock(FileLock.exclusive);
    } on FileSystemException {
      await raf.close();
      return null;
    }
    return _RandomAccessFileLockHandle(raf);
  }
}

class _RandomAccessFileLockHandle implements InstanceLockHandle {
  _RandomAccessFileLockHandle(this._raf);

  final RandomAccessFile _raf;
  bool _released = false;

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _raf.unlock();
    } on FileSystemException {
      // Best-effort: closing the handle (below) releases the lock regardless.
    }
    await _raf.close();
  }
}

/// The outcome of a single-instance [DesktopSingleInstance.acquire] attempt.
enum SingleInstanceResult {
  /// This process took the lock; it is the sole instance. The lock is held for
  /// the process lifetime (see [DesktopSingleInstance]).
  acquired,

  /// Another live instance already holds the lock. The caller must not open the
  /// database; it should focus the existing window and/or exit.
  alreadyRunning,

  /// The guard could not run (an unexpected IO fault). The caller proceeds
  /// anyway (fail-open) — a false block is worse than the rare race, and the
  /// database open path remains a visible backstop.
  unavailable,
}

/// Desktop-only single-instance guard (issue #441).
///
/// Acquires an OS advisory exclusive lock on
/// `<applicationSupportDirectory>/single_instance.lock` at startup, **before**
/// the app opens the on-device database. If another live instance already holds
/// the lock, a second launch is refused so two processes can't race the
/// migration / derived-rebuild marker and trip `database is locked`.
///
/// This is intentionally desktop-only: [isSupportedPlatform] gates it to
/// Linux/macOS/Windows, so mobile (the OS already owns single-instance) and web
/// (no `dart:io`) are untouched. `main` calls it only on desktop, and the
/// headless test harness never runs `main`, so `flutter test` is unaffected.
/// The lock *directory* and lock *primitive* are both injectable so the
/// decision logic is unit-testable without a real window or second process.
class DesktopSingleInstance {
  DesktopSingleInstance({
    LockDirectoryProvider? lockDirectoryProvider,
    this.primitive = const AdvisoryFileLock(),
    this.lockFileName = kSingleInstanceLockFileName,
  }) : _lockDirectoryProvider =
           lockDirectoryProvider ?? getApplicationSupportDirectory;

  final LockDirectoryProvider _lockDirectoryProvider;
  final InstanceLockPrimitive primitive;
  final String lockFileName;

  /// Process-wide holder for the acquired lock, so the handle is never garbage
  /// collected and the lock stays held until the process exits (the OS then
  /// releases it).
  static InstanceLockHandle? _held;

  /// Whether the current platform gets the desktop single-instance guard.
  /// Desktop only; a no-op on mobile and web.
  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  /// Attempts to become the sole instance.
  ///
  /// On [SingleInstanceResult.acquired] the lock is retained process-wide. On
  /// [SingleInstanceResult.alreadyRunning] the caller must abort before opening
  /// the database. On [SingleInstanceResult.unavailable] the caller proceeds
  /// (fail-open). Never throws.
  Future<SingleInstanceResult> acquire() async {
    try {
      final dir = await _lockDirectoryProvider();
      final lockFile = File(p.join(dir.path, lockFileName));
      final handle = await primitive.tryAcquire(lockFile);
      if (handle == null) return SingleInstanceResult.alreadyRunning;
      _held = handle;
      return SingleInstanceResult.acquired;
    } catch (error, stackTrace) {
      // Fail-open: an unexpected IO fault must never permanently prevent launch
      // (e.g. a read-only or unusual support directory). Log it (like the other
      // startup best-effort paths) so it is diagnosable in the field.
      debugPrint(
        'Single-instance guard unavailable, failing open: $error\n$stackTrace',
      );
      return SingleInstanceResult.unavailable;
    }
  }

  /// Releases the process-wide lock if held. Production relies on the OS
  /// releasing the lock at process exit; this exists for tidy shutdown and for
  /// tests to reset the shared state between cases.
  static Future<void> releaseHeld() async {
    final held = _held;
    _held = null;
    await held?.release();
  }
}
