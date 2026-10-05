import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kIsWeb, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../diagnostics/error_log.dart';

/// File name of the desktop single-instance lock, kept inside the app's private
/// application-support directory (never a world-writable/predictable temp path).
const String kSingleInstanceLockFileName = 'single_instance.lock';

/// File name of the loopback port the first instance listens on for raise
/// requests, written beside [kSingleInstanceLockFileName].
const String kSingleInstancePortFileName = 'single_instance.port';

/// The only line the raise channel acts on. Anything else is ignored.
const String kRaiseRequestLine = 'raise';

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
  /// held by another live process. Throws (a [FileSystemException]) on any
  /// *other* fault — the directory/file can't be created or opened, or the lock
  /// failed for a reason other than genuine contention (e.g. a filesystem that
  /// doesn't support advisory locking) — which the guard treats as fail-open.
  Future<InstanceLockHandle?> tryAcquire(File lockFile);
}

/// POSIX `EACCES` (13): `fcntl`/`flock` reports this when the lock is held by
/// another process. The value is stable across POSIX platforms.
const int _eacces = 13;

/// `EAGAIN`/`EWOULDBLOCK` — the canonical "would block, lock is held" errno for
/// a non-blocking lock. Its numeric value is platform-specific: 11 on Linux,
/// 35 on macOS/BSD (Darwin).
const int _eagainLinux = 11;
const int _eagainDarwin = 35;

/// Windows lock-contention codes: `ERROR_SHARING_VIOLATION` (32) and
/// `ERROR_LOCK_VIOLATION` (33).
const int _errorSharingViolation = 32;
const int _errorLockViolation = 33;

/// Whether [osError] from a non-blocking [RandomAccessFile.lock] means the lock
/// is genuinely held by *another live process* (true contention → refuse the
/// second instance), as opposed to an unexpected fault (e.g. a filesystem that
/// doesn't support advisory locking, or an unusual I/O error) that must **fail
/// open** so we never wrongly refuse the only instance and brick launch.
///
/// When the code is absent or unrecognized we deliberately return `false`
/// (treat it as an unexpected fault → fail open): a false "already running"
/// that blocks the sole instance is the worst outcome.
bool isAdvisoryLockContention(OSError? osError) {
  final code = osError?.errorCode;
  if (code == null) return false;
  if (Platform.isWindows) {
    return code == _errorSharingViolation || code == _errorLockViolation;
  }
  // POSIX: EACCES is universal; EAGAIN/EWOULDBLOCK differs by platform.
  if (code == _eacces) return true;
  if (Platform.isMacOS) return code == _eagainDarwin;
  if (Platform.isLinux) return code == _eagainLinux;
  // Unknown/other platform: accept the common EAGAIN values so a genuine second
  // instance is still refused, but nothing else (anything unrecognized fails
  // open above).
  return code == _eagainLinux || code == _eagainDarwin;
}

/// Real [InstanceLockPrimitive] backed by `dart:io` OS advisory file locks
/// (`RandomAccessFile.lock`): `fcntl`/`flock` on POSIX, `LockFileEx` on Windows.
///
/// These locks are released automatically when the holding process dies, so a
/// crashed prior instance leaves no *live* lock — the leftover lock file is
/// inert and a fresh launch acquires normally. There is no PID-liveness check
/// or stale-marker cleanup to get wrong.
class AdvisoryFileLock implements InstanceLockPrimitive {
  const AdvisoryFileLock({this.lockOverride});

  /// Test seam: replaces the real [RandomAccessFile.lock] call so tests can
  /// simulate a specific lock failure (a genuine-contention errno vs. an
  /// unexpected fault) without a real second process. `null` in production.
  @visibleForTesting
  final Future<void> Function(RandomAccessFile raf)? lockOverride;

  Future<void> _lock(RandomAccessFile raf) =>
      lockOverride?.call(raf) ?? raf.lock(FileLock.exclusive);

  @override
  Future<InstanceLockHandle?> tryAcquire(File lockFile) async {
    // A create/open failure here (bad path, permissions) propagates to the
    // caller, which fails open — distinct from "lock held by another process",
    // handled below.
    await lockFile.parent.create(recursive: true);
    final raf = await lockFile.open(mode: FileMode.write);
    try {
      // Non-blocking exclusive lock: throws instead of waiting when the lock
      // can't be taken.
      await _lock(raf);
    } on FileSystemException catch (error) {
      // diagnostics: silent — lock acquisition failed; determines whether to return null (contention) or rethrow (unexpected fault).
      await raf.close();
      // Only *genuine contention* (the lock is held by another live process)
      // means a second instance is running → return null (alreadyRunning). Any
      // other lock failure — e.g. a filesystem that doesn't support advisory
      // locking, or an unclassifiable error — is an unexpected fault: rethrow
      // so the guard fails OPEN (SingleInstanceResult.unavailable) rather than
      // fail CLOSED (wrongly refusing the only instance and bricking launch).
      if (isAdvisoryLockContention(error.osError)) return null;
      rethrow;
    }
    return _RandomAccessFileLockHandle(raf);
  }
}

class _RandomAccessFileLockHandle implements InstanceLockHandle {
  _RandomAccessFileLockHandle(this._raf);

  // Holding this reference is what keeps the lock: an unreachable
  // RandomAccessFile is finalized, which closes its fd and releases the OS
  // lock. Production never calls [release], so a release (AOT) build would
  // otherwise tree-shake the field as write-only (see [DesktopSingleInstance]).
  @pragma('vm:entry-point')
  final RandomAccessFile _raf;
  bool _released = false;

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _raf.unlock();
    } on FileSystemException {
      // diagnostics: silent — best-effort: closing the handle (below)
      // releases the lock regardless.
    }
    await _raf.close();
  }
}

/// How a second launch asks the first instance to bring its window forward.
///
/// Abstracted like [InstanceLockPrimitive] so [handleSecondLaunch] is testable
/// without a real second process.
abstract class InstanceRaiseChannel {
  /// Starts listening in the first instance and records where in [lockDir].
  /// Calls [onRaise] each time a peer sends the raise request. Returns the
  /// bound port. May throw; the caller treats that as non-fatal.
  Future<int> listen(Directory lockDir, void Function() onRaise);

  /// Asks the running first instance (found via [lockDir]) to raise its window.
  /// Returns `false` on any failure (no port file, nothing listening, I/O
  /// error). Never throws.
  Future<bool> requestRaise(Directory lockDir);

  /// Stops listening and removes the port file if this channel wrote it.
  /// Idempotent; never throws.
  Future<void> close();
}

/// [InstanceRaiseChannel] over a loopback-only TCP socket (IPv4, ephemeral
/// port). The port is written to `<lockDir>/single_instance.port`.
///
/// This is not a general IPC surface: it binds `127.0.0.1`, reads at most one
/// short line per connection, acts only on the literal [kRaiseRequestLine],
/// and carries no payload or reply.
class LoopbackRaiseChannel implements InstanceRaiseChannel {
  LoopbackRaiseChannel({
    this.portFileName = kSingleInstancePortFileName,
    this.timeout = const Duration(seconds: 2),
  });

  final String portFileName;

  /// Bounds connect and read so a wedged peer can neither hang a second launch
  /// nor hold a connection in the first instance open indefinitely.
  final Duration timeout;

  /// Longest request line accepted before the connection is dropped.
  static const int _maxRequestBytes = 64;

  ServerSocket? _server;
  File? _portFile;
  int? _port;

  File _portFileIn(Directory dir) => File(p.join(dir.path, portFileName));

  @override
  Future<int> listen(Directory lockDir, void Function() onRaise) async {
    await close();
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(
      (socket) => unawaited(_serve(socket, onRaise)),
      onError: (Object error, StackTrace stackTrace) {
        logCaughtErrorTypeOnly(
          error,
          stackTrace,
          source: 'single_instance_guard.raiseListener',
        );
      },
    );
    _port = server.port;
    final portFile = _portFileIn(lockDir);
    try {
      await portFile.parent.create(recursive: true);
      await portFile.writeAsString('${server.port}\n', flush: true);
    } catch (_) {
      // diagnostics: silent — rethrown below; the caller logs it once.
      await close();
      rethrow;
    }
    _portFile = portFile;
    return server.port;
  }

  Future<void> _serve(Socket socket, void Function() onRaise) async {
    try {
      final bytes = <int>[];
      var raise = false;
      await for (final chunk in socket.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > _maxRequestBytes) break;
        final newline = bytes.indexOf(0x0a);
        if (newline >= 0) {
          raise =
              latin1.decode(bytes.sublist(0, newline)).trim() ==
              kRaiseRequestLine;
          break;
        }
      }
      if (raise) onRaise();
    } catch (_) {
      // diagnostics: silent — a malformed, slow or reset peer is ignored; the
      // channel only ever acts on a well-formed raise line.
    } finally {
      socket.destroy();
    }
  }

  @override
  Future<bool> requestRaise(Directory lockDir) async {
    Socket? socket;
    try {
      final port = int.tryParse(
        (await _portFileIn(lockDir).readAsString()).trim(),
      );
      if (port == null || port < 1 || port > 65535) return false;
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: timeout,
      );
      socket.write('$kRaiseRequestLine\n');
      await socket.flush().timeout(timeout);
      await socket.close().timeout(timeout);
      return true;
    } catch (_) {
      // diagnostics: silent — no port file, a stale port, or a refused connect
      // all mean "could not raise"; the caller reports false on stderr.
      return false;
    } finally {
      socket?.destroy();
    }
  }

  @override
  Future<void> close() async {
    final server = _server;
    final portFile = _portFile;
    final port = _port;
    _server = null;
    _portFile = null;
    _port = null;
    try {
      await server?.close();
    } catch (_) {
      // diagnostics: silent — best-effort shutdown of a loopback listener.
    }
    if (portFile == null) return;
    try {
      // Only remove a file that still names our port; a newer instance may
      // have overwritten it after a crash/restart race.
      if (int.tryParse((await portFile.readAsString()).trim()) == port) {
        await portFile.delete();
      }
    } catch (_) {
      // diagnostics: silent — a leftover port file is harmless (requestRaise
      // fails to connect and the next instance overwrites it).
    }
  }
}

/// The outcome of a single-instance [DesktopSingleInstance.acquire] attempt.
enum SingleInstanceResult {
  /// This process took the lock; it is the sole instance. The lock is held for
  /// the process lifetime (see [DesktopSingleInstance]).
  acquired,

  /// Another live instance already holds the lock. The caller must not open the
  /// database; it asks that instance to raise its window and exits
  /// ([handleSecondLaunch]).
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
/// The first instance also listens on a loopback socket
/// ([InstanceRaiseChannel]) so a refused second launch can ask it to bring its
/// window forward instead of exiting silently ([handleSecondLaunch]).
///
/// This is intentionally desktop-only: [isSupportedPlatform] gates it to
/// Linux/macOS/Windows, so mobile (the OS already owns single-instance) and web
/// (no `dart:io`) are untouched. `main` calls it only on desktop, and the
/// headless test harness never runs `main`, so `flutter test` is unaffected.
/// The lock *directory*, lock *primitive* and raise *channel* are all
/// injectable so the decision logic is unit-testable without a real window or
/// second process.
class DesktopSingleInstance {
  DesktopSingleInstance({
    LockDirectoryProvider? lockDirectoryProvider,
    this.primitive = const AdvisoryFileLock(),
    this.lockFileName = kSingleInstanceLockFileName,
    InstanceRaiseChannel? raiseChannel,
  }) : raiseChannel = raiseChannel ?? _defaultRaiseChannel,
       _lockDirectoryProvider =
           lockDirectoryProvider ?? getApplicationSupportDirectory;

  final LockDirectoryProvider _lockDirectoryProvider;
  final InstanceLockPrimitive primitive;
  final String lockFileName;

  /// How a second launch reaches the first instance, and how the first listens.
  final InstanceRaiseChannel raiseChannel;

  /// Shared by every guard built with the default, so the listener started in
  /// the first instance is the one [releaseHeld] closes.
  static final InstanceRaiseChannel _defaultRaiseChannel =
      LoopbackRaiseChannel();

  /// Process-wide holder for the acquired lock, so the handle is never garbage
  /// collected and the lock stays held until the process exits (the OS then
  /// releases it).
  ///
  /// Only [releaseHeld] reads this, and only tests call that, so without the
  /// pragma a release (AOT) build removes the field as write-only. The handle
  /// is then collected about half a second after launch, its file is closed,
  /// the lock is released, and a second launch runs on the same database.
  /// `flutter test` (JIT) keeps the field, so only a release build shows it;
  /// `single_instance_guard_test.dart` pins the pragma here and on `_raf`.
  @pragma('vm:entry-point')
  static InstanceLockHandle? _held;

  /// Whether the current platform gets the desktop single-instance guard.
  /// Desktop only; a no-op on mobile and web.
  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  /// The directory holding the lock file (and the raise port file).
  Future<Directory> lockDirectory() => _lockDirectoryProvider();

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
      if (kDebugMode) {
        debugPrint(
          'Single-instance guard unavailable, failing open: $error\n$stackTrace',
        );
      }
      logCaughtError(
        error,
        stackTrace,
        source: 'single_instance_guard.acquire',
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
    await _defaultRaiseChannel.close();
    await held?.release();
  }
}

/// What `main` does after [handleSecondLaunch].
enum SecondLaunchOutcome {
  /// Continue starting the app (this process is the sole instance, or the guard
  /// was unavailable and failed open).
  proceed,

  /// Another instance is running; this process must exit before opening the
  /// database.
  exitNow,
}

/// The second-launch decision, extracted from `main` so it is testable.
///
/// Runs before `AppData` exists, so a refused launch never opens the database.
/// - `alreadyRunning`: asks the running instance to raise its window, writes
///   one line to [err] naming the outcome, returns [SecondLaunchOutcome.exitNow].
/// - `acquired`: starts the raise listener (calling [onRaise] on a request) and
///   returns [SecondLaunchOutcome.proceed]. A listener failure is logged and
///   non-fatal: the app just won't be raisable.
/// - `unavailable`: returns [SecondLaunchOutcome.proceed] (fail-open).
Future<SecondLaunchOutcome> handleSecondLaunch(
  DesktopSingleInstance guard, {
  required void Function() onRaise,
  IOSink? err,
}) async {
  final sink = err ?? stderr;
  final result = await guard.acquire();
  switch (result) {
    case SingleInstanceResult.alreadyRunning:
      var raised = false;
      try {
        raised = await guard.raiseChannel.requestRaise(
          await guard.lockDirectory(),
        );
      } catch (error, stackTrace) {
        logCaughtErrorTypeOnly(
          error,
          stackTrace,
          source: 'single_instance_guard.requestRaise',
        );
      }
      sink.writeln(
        raised
            ? "Caller's Compendium is already running; asked it to bring its "
                  'window forward. Exiting this second launch.'
            : "Caller's Compendium is already running, but its window could "
                  'not be reached. Exiting this second launch to protect the '
                  'database.',
      );
      return SecondLaunchOutcome.exitNow;
    case SingleInstanceResult.acquired:
      try {
        await guard.raiseChannel.listen(await guard.lockDirectory(), onRaise);
      } catch (error, stackTrace) {
        logCaughtErrorTypeOnly(
          error,
          stackTrace,
          source: 'single_instance_guard.listen',
        );
      }
      return SecondLaunchOutcome.proceed;
    case SingleInstanceResult.unavailable:
      return SecondLaunchOutcome.proceed;
  }
}
