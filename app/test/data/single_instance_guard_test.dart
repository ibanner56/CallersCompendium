import 'dart:io';

import 'package:compendium_app/src/data/single_instance_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A fake [InstanceLockHandle] that records whether it was released.
class _FakeHandle implements InstanceLockHandle {
  bool released = false;

  @override
  Future<void> release() async => released = true;
}

/// A fake [InstanceLockPrimitive] with a scripted outcome, so the guard's
/// decision logic is exercised without a real OS lock — a real advisory lock
/// can't be contended within one process on POSIX, so this stands in for
/// "another live process already holds it" and for an unexpected IO fault.
class _FakePrimitive implements InstanceLockPrimitive {
  _FakePrimitive.acquired() : _handle = _FakeHandle();
  _FakePrimitive.alreadyRunning() : _handle = null;
  _FakePrimitive.throwing() : _handle = null, _throw = true;

  final _FakeHandle? _handle;
  bool _throw = false;
  File? lastLockFile;

  @override
  Future<InstanceLockHandle?> tryAcquire(File lockFile) async {
    lastLockFile = lockFile;
    if (_throw) {
      throw const FileSystemException('injected IO fault');
    }
    return _handle;
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('single_instance_guard_');
  });

  tearDown(() async {
    // Release any process-wide lock a test acquired so the temp dir can be
    // deleted (an open, locked handle can block deletion on some platforms) and
    // so shared static state never leaks between tests.
    await DesktopSingleInstance.releaseHeld();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  DesktopSingleInstance guardWith({
    InstanceLockPrimitive primitive = const AdvisoryFileLock(),
  }) => DesktopSingleInstance(
    lockDirectoryProvider: () async => dir,
    primitive: primitive,
  );

  File lockFile() => File(p.join(dir.path, kSingleInstanceLockFileName));

  /// The errno/OS code the current platform reports for genuine lock
  /// contention (EAGAIN/EWOULDBLOCK; ERROR_LOCK_VIOLATION on Windows), so the
  /// contention tests stay portable across the CI matrix.
  int platformContentionCode() {
    if (Platform.isWindows) return 33; // ERROR_LOCK_VIOLATION
    if (Platform.isMacOS) return 35; // EAGAIN / EWOULDBLOCK (Darwin)
    return 11; // EAGAIN / EWOULDBLOCK (Linux)
  }

  /// A real [AdvisoryFileLock] whose lock call fails with [error], so the
  /// contention-vs-unexpected-fault classification is exercised end-to-end
  /// without a real second process.
  AdvisoryFileLock lockFailingWith(FileSystemException error) =>
      AdvisoryFileLock(lockOverride: (_) async => throw error);

  group('acquire (real advisory lock)', () {
    test('first acquire succeeds and creates the lock file', () async {
      final result = await guardWith().acquire();

      expect(result, SingleInstanceResult.acquired);
      expect(await lockFile().exists(), isTrue);
    });

    test('release frees the lock so a later acquire succeeds again', () async {
      expect(await guardWith().acquire(), SingleInstanceResult.acquired);

      // Releasing stands in for the OS releasing the lock at process exit.
      await DesktopSingleInstance.releaseHeld();

      expect(await guardWith().acquire(), SingleInstanceResult.acquired);
    });

    test(
      'a stale lock file left by a crashed instance does not block launch',
      () async {
        // Simulate a leftover lock file (with stale PID content) from a process
        // that died: the OS releases advisory locks on death, so only the inert
        // file remains. A fresh launch must still acquire.
        await lockFile().writeAsString('999999\n');

        final result = await guardWith().acquire();

        expect(result, SingleInstanceResult.acquired);
      },
    );
  });

  group('acquire (decision logic via fake primitive)', () {
    test('reports acquired when the primitive grants the lock', () async {
      final primitive = _FakePrimitive.acquired();

      final result = await guardWith(primitive: primitive).acquire();

      expect(result, SingleInstanceResult.acquired);
      // The lock is resolved inside the injected directory, never a shared
      // world-writable temp path.
      expect(
        primitive.lastLockFile!.path,
        p.join(dir.path, kSingleInstanceLockFileName),
      );
    });

    test(
      'reports alreadyRunning when another instance holds the lock',
      () async {
        final result = await guardWith(
          primitive: _FakePrimitive.alreadyRunning(),
        ).acquire();

        expect(result, SingleInstanceResult.alreadyRunning);
      },
    );

    test(
      'fails open (unavailable, no throw) on an unexpected IO fault',
      () async {
        final result = await guardWith(
          primitive: _FakePrimitive.throwing(),
        ).acquire();

        expect(result, SingleInstanceResult.unavailable);
      },
    );

    test('fails open when the lock directory cannot be resolved', () async {
      final guard = DesktopSingleInstance(
        lockDirectoryProvider: () async =>
            throw const FileSystemException('no support dir'),
      );

      expect(await guard.acquire(), SingleInstanceResult.unavailable);
    });
  });

  group('contention vs. unexpected lock failure (real AdvisoryFileLock)', () {
    test(
      'genuine OS contention maps to alreadyRunning (refuse 2nd instance)',
      () async {
        final guard = guardWith(
          primitive: lockFailingWith(
            FileSystemException(
              'resource temporarily unavailable',
              lockFile().path,
              OSError('EAGAIN', platformContentionCode()),
            ),
          ),
        );

        expect(await guard.acquire(), SingleInstanceResult.alreadyRunning);
      },
    );

    test('EACCES is treated as contention on POSIX', () async {
      // Skipped on Windows, where contention uses distinct codes (32/33).
      final primitive = lockFailingWith(
        FileSystemException(
          'permission denied',
          lockFile().path,
          const OSError('EACCES', 13),
        ),
      );

      expect(await primitive.tryAcquire(lockFile()), isNull);
    }, skip: Platform.isWindows);

    test(
      'a non-contention lock failure FAILS OPEN (unavailable), not closed',
      () async {
        // e.g. a filesystem that does not support advisory locking (ENOSYS 38):
        // must NOT be misread as "already running" (which would brick launch).
        final guard = guardWith(
          primitive: lockFailingWith(
            const FileSystemException(
              'function not implemented',
              '',
              OSError('ENOSYS', 38),
            ),
          ),
        );

        expect(await guard.acquire(), SingleInstanceResult.unavailable);
      },
    );

    test('a lock failure with no OSError fails open (rethrows)', () async {
      final primitive = lockFailingWith(
        const FileSystemException('opaque lock failure'),
      );

      await expectLater(
        primitive.tryAcquire(lockFile()),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('classifier: unrecognized errno is not contention', () {
      expect(isAdvisoryLockContention(const OSError('ENOSPC', 28)), isFalse);
      expect(isAdvisoryLockContention(null), isFalse);
      expect(
        isAdvisoryLockContention(OSError('EAGAIN', platformContentionCode())),
        isTrue,
      );
    });
  });
}
